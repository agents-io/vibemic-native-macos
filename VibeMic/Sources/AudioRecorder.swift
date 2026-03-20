import AVFoundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempURL: URL?
    private(set) var isRecording = false

    private var tempDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibemic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Check and request microphone permission before recording
    func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async { completion(true) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    func start() throws {
        Log.d("AudioRecorder.start()")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Log.d("Input format: \(format)")

        let url = tempDirectory.appendingPathComponent("recording.wav")
        try? FileManager.default.removeItem(at: url)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            Log.d("ERROR: Could not create output format")
            throw RecorderError.formatError
        }

        let file = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
        Log.d("Audio file created at: \(url.path)")

        guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
            Log.d("ERROR: Could not create converter")
            throw RecorderError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * outputFormat.sampleRate / format.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status != .error {
                try? file.write(from: convertedBuffer)
            }
        }

        try engine.start()
        Log.d("Engine started OK")

        self.audioEngine = engine
        self.audioFile = file
        self.tempURL = url
        self.isRecording = true
        Log.d("Recording started")
    }

    func stop() -> URL? {
        Log.d("AudioRecorder.stop() isRecording=\(isRecording)")
        guard isRecording else { return nil }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false

        guard let url = tempURL else {
            Log.d("No temp URL")
            return nil
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int
        else {
            Log.d("Could not get file attrs")
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        Log.d("Audio file size: \(size) bytes")

        guard size > 1000 else {
            Log.d("File too small, discarding")
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return url
    }

    enum RecorderError: LocalizedError {
        case formatError
        case converterError
        case noPermission

        var errorDescription: String? {
            switch self {
            case .formatError: return "Could not create audio format"
            case .converterError: return "Could not create audio converter"
            case .noPermission: return "Microphone permission denied. Go to System Settings → Privacy → Microphone."
            }
        }
    }
}
