import Foundation

class WhisperTranscriber {

    /// Transcribe audio, optionally paraphrase, then return the final text.
    func transcribe(
        fileURL: URL,
        config: VibeMicConfig,
        onStateChange: @escaping (String) -> Void,
        completion: @escaping (Result<(text: String, original: String?), Error>) -> Void
    ) {
        if config.useProxy {
            guard !config.proxyToken.isEmpty else {
                completion(.failure(TranscriberError.notLoggedIn))
                return
            }
        } else {
            guard !config.apiKey.isEmpty else {
                completion(.failure(TranscriberError.noApiKey))
                return
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let transcript = try config.useProxy
                    ? self.sendToProxyTranscription(fileURL: fileURL, config: config)
                    : self.sendToWhisper(fileURL: fileURL, config: config)
                Log.d("Whisper returned: \(transcript.prefix(100))")
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    completion(.success((text: "", original: nil)))
                    return
                }

                if config.paraphraseEnabled {
                    DispatchQueue.main.async { onStateChange("paraphrasing") }
                    do {
                        let paraphrased = try self.paraphrase(text: trimmed, config: config)
                        completion(.success((text: paraphrased, original: trimmed)))
                    } catch {
                        // Fallback to original transcript on paraphrase failure
                        completion(.success((text: trimmed, original: nil)))
                    }
                } else {
                    completion(.success((text: trimmed, original: nil)))
                }
            } catch {
                Log.d("Whisper error: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func sendToWhisper(fileURL: URL, config: VibeMicConfig) throws -> String {
        Log.d("Calling Whisper API...")
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: fileURL)
        body.appendMultipart(boundary: boundary, name: "file", filename: "recording.wav", mimeType: "audio/wav", data: audioData)
        body.appendMultipart(boundary: boundary, name: "model", value: config.model)

        if !config.language.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language", value: config.language)
        }
        if !config.prompt.isEmpty {
            body.appendMultipart(boundary: boundary, name: "prompt", value: config.prompt)
        }
        if config.temperature > 0 {
            body.appendMultipart(boundary: boundary, name: "temperature", value: String(config.temperature))
        }
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try syncRequest(request)
        try validateResponse(data: data, response: response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriberError.invalidResponse
        }

        guard let text = json["text"] as? String else {
            throw TranscriberError.invalidResponse
        }
        return text
    }

    private func sendToProxyTranscription(fileURL: URL, config: VibeMicConfig) throws -> String {
        Log.d("Calling proxy transcription API...")
        let url = try proxyURL(baseURL: config.proxyBaseURL, path: "/api/transcribe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.proxyToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: fileURL)
        body.appendMultipart(boundary: boundary, name: "file", filename: "recording.wav", mimeType: "audio/wav", data: audioData)
        if !config.language.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language", value: config.language)
        }
        if !config.prompt.isEmpty {
            body.appendMultipart(boundary: boundary, name: "prompt", value: config.prompt)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try syncRequest(request)
        try validateResponse(data: data, response: response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw TranscriberError.invalidResponse
        }

        return text
    }

    private func paraphrase(text: String, config: VibeMicConfig) throws -> String {
        if config.useProxy {
            return try proxyParaphrase(text: text, config: config)
        }
        return try directParaphrase(text: text, config: config)
    }

    private func directParaphrase(text: String, config: VibeMicConfig) throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let systemPrompt = paraphrasePrompt(for: config)

        let payload: [String: Any] = [
            "model": config.paraphraseModel,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ]
        ]
        Log.d("Paraphrase system prompt: \(systemPrompt.prefix(100))")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try syncRequest(request)
        try validateResponse(data: data, response: response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw TranscriberError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func proxyParaphrase(text: String, config: VibeMicConfig) throws -> String {
        let url = try proxyURL(baseURL: config.proxyBaseURL, path: "/api/paraphrase")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.proxyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let payload: [String: Any] = [
            "text": text,
            "prompt": paraphrasePrompt(for: config),
            "model": "gpt-4o-mini",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try syncRequest(request)
        try validateResponse(data: data, response: response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["text"] as? String
        else {
            throw TranscriberError.invalidResponse
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func paraphrasePrompt(for config: VibeMicConfig) -> String {
        if config.translateTo.isEmpty {
            return config.paraphrasePrompt
        }
        return "Translate the output to \(config.translateTo). \(config.paraphrasePrompt)"
    }

    private func proxyURL(baseURL: String, path: String) throws -> URL {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            normalized = VibeMicConfig.defaultProxyBaseURL
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        guard let url = URL(string: normalized + path) else {
            throw TranscriberError.invalidProxyURL
        }
        return url
    }

    private func validateResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let message = errorMessage(from: data) {
                throw TranscriberError.apiError(message)
            }
            throw TranscriberError.apiError("Request failed (\(http.statusCode))")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let errorInfo = json["error"] as? [String: Any],
           let message = errorInfo["message"] as? String {
            return message
        }
        if let errorMessage = json["error"] as? String {
            return errorMessage
        }
        if let message = json["message"] as? String {
            return message
        }
        return nil
    }

    private func syncRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
        var responseData: Data?
        var responseResp: URLResponse?
        var responseError: Error?

        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseResp = response
            responseError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = responseError { throw error }
        guard let data = responseData, let resp = responseResp else {
            throw TranscriberError.noResponse
        }
        return (data, resp)
    }

    enum TranscriberError: LocalizedError {
        case noApiKey
        case notLoggedIn
        case noResponse
        case invalidResponse
        case invalidProxyURL
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "No API key. Right-click → Settings."
            case .notLoggedIn: return "Not logged in. Open Settings and sign in."
            case .noResponse: return "No response from API"
            case .invalidResponse: return "Invalid API response"
            case .invalidProxyURL: return "Invalid server URL"
            case .apiError(let msg): return msg
            }
        }
    }
}

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
