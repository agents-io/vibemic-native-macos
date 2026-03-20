import Foundation
import AppKit

struct VibeMicConfig: Codable {
    var apiKey: String
    var useProxy: Bool
    var proxyBaseURL: String
    var proxyToken: String
    var proxyEmail: String
    var developerMode: Bool
    var model: String
    var language: String
    var prompt: String
    var temperature: Double
    var responseFormat: String
    var paraphraseEnabled: Bool
    var paraphrasePrompt: String
    var paraphraseModel: String
    var hotkeyKeyCode: UInt16
    var hotkeyModifiers: UInt
    var translateTo: String  // language code, empty = no translation

    init(apiKey: String, model: String, language: String, prompt: String,
         temperature: Double, responseFormat: String, paraphraseEnabled: Bool,
         paraphrasePrompt: String, paraphraseModel: String,
         hotkeyKeyCode: UInt16 = 9, hotkeyModifiers: UInt = 786432,
         translateTo: String = "", useProxy: Bool = false,
         proxyBaseURL: String = VibeMicConfig.defaultProxyBaseURL,
         proxyToken: String = "", proxyEmail: String = "",
         developerMode: Bool = false) {
        self.apiKey = apiKey; self.model = model; self.language = language
        self.prompt = prompt; self.temperature = temperature
        self.responseFormat = responseFormat; self.paraphraseEnabled = paraphraseEnabled
        self.paraphrasePrompt = paraphrasePrompt; self.paraphraseModel = paraphraseModel
        self.hotkeyKeyCode = hotkeyKeyCode; self.hotkeyModifiers = hotkeyModifiers
        self.translateTo = translateTo
        self.useProxy = useProxy
        self.proxyBaseURL = proxyBaseURL
        self.proxyToken = proxyToken
        self.proxyEmail = proxyEmail
        self.developerMode = developerMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        useProxy = try c.decodeIfPresent(Bool.self, forKey: .useProxy) ?? false
        proxyBaseURL = try c.decodeIfPresent(String.self, forKey: .proxyBaseURL) ?? VibeMicConfig.defaultProxyBaseURL
        proxyToken = try c.decodeIfPresent(String.self, forKey: .proxyToken) ?? ""
        proxyEmail = try c.decodeIfPresent(String.self, forKey: .proxyEmail) ?? ""
        developerMode = try c.decodeIfPresent(Bool.self, forKey: .developerMode) ?? false
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "gpt-4o-transcribe"
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        responseFormat = try c.decodeIfPresent(String.self, forKey: .responseFormat) ?? "json"
        paraphraseEnabled = try c.decodeIfPresent(Bool.self, forKey: .paraphraseEnabled) ?? false
        paraphrasePrompt = try c.decodeIfPresent(String.self, forKey: .paraphrasePrompt) ?? VibeMicConfig.defaultParaphrasePrompt
        paraphraseModel = try c.decodeIfPresent(String.self, forKey: .paraphraseModel) ?? "gpt-4o-mini"
        hotkeyKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .hotkeyKeyCode) ?? 9
        hotkeyModifiers = try c.decodeIfPresent(UInt.self, forKey: .hotkeyModifiers) ?? 786432
        translateTo = try c.decodeIfPresent(String.self, forKey: .translateTo) ?? ""
    }

    static let defaultProxyBaseURL = "https://api.vibemic.app"

    static let translateLanguages: [(name: String, code: String)] = [
        ("None", ""),
        ("English", "English"),
        ("繁體中文", "Traditional Chinese"),
        ("简体中文", "Simplified Chinese"),
        ("日本語", "Japanese"),
        ("한국어", "Korean"),
        ("Français", "French"),
        ("Deutsch", "German"),
        ("Español", "Spanish"),
        ("Português", "Portuguese"),
        ("Italiano", "Italian"),
        ("Русский", "Russian"),
        ("العربية", "Arabic"),
        ("हिन्दी", "Hindi"),
        ("ภาษาไทย", "Thai"),
        ("Tiếng Việt", "Vietnamese"),
    ]

    static let defaultParaphrasePrompt = """
    Rewrite the following transcript into natural work chat / Slack language.
    It should read like a quick but clear engineer typist wrote it.
    Simple, everyday language — not corporate, not formal.
    Non-native English speaker in tech style.
    Preserve original meaning and technical accuracy.
    Same length or shorter. Fix rough language naturally.
    Preserve intent, uncertainty, directness, casual tone.
    No corporate phrases like "just a quick update", "for your reference", etc.
    """

    static let `default` = VibeMicConfig(
        apiKey: "",
        model: "gpt-4o-transcribe",
        language: "",
        prompt: "廣東話、English、普通話、日本語",
        temperature: 0,
        responseFormat: "json",
        paraphraseEnabled: false,
        paraphrasePrompt: defaultParaphrasePrompt,
        paraphraseModel: "gpt-4o-mini",
        hotkeyKeyCode: 9,       // V key
        hotkeyModifiers: 786432 // Ctrl+Option (⌃⌥)
    )

    /// Human-readable hotkey description
    var hotkeyDisplayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: hotkeyModifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'",
            40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "Space", 50: "`", 51: "⌫",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 111: "F12", 103: "F11",
            105: "F13", 107: "F14", 113: "F15",
            118: "F4", 120: "F2", 122: "F1",
            115: "Home", 116: "PgUp", 117: "⌦", 119: "End", 121: "PgDn",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    static let availableModels = [
        "whisper-1",
        "gpt-4o-transcribe",
        "gpt-4o-mini-transcribe",
    ]

    static let paraphraseModels = [
        "gpt-4o-mini",
        "gpt-4o",
        "gpt-4.1-mini",
        "gpt-4.1",
    ]

    static let availableLanguages: [(name: String, code: String)] = [
        ("Auto-detect", ""),
        ("English", "en"),
        ("廣東話 / Chinese", "zh"),
        ("日本語", "ja"),
        ("한국어", "ko"),
        ("Français", "fr"),
        ("Deutsch", "de"),
        ("Español", "es"),
        ("Português", "pt"),
        ("Italiano", "it"),
        ("Nederlands", "nl"),
        ("Polski", "pl"),
        ("Русский", "ru"),
        ("Türkçe", "tr"),
        ("العربية", "ar"),
        ("हिन्दी", "hi"),
        ("ภาษาไทย", "th"),
        ("Tiếng Việt", "vi"),
    ]
}

class ConfigManager {
    static let shared = ConfigManager()

    private let configURL: URL
    private let envURL: URL

    private(set) var config: VibeMicConfig

    private init() {
        // Bundle.main.bundleURL = VibeMic.app/
        // We want config next to the .app bundle, i.e. in its parent directory
        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()

        configURL = appDir.appendingPathComponent("config.json")
        envURL = appDir.appendingPathComponent(".env")

        Log.d("ConfigManager init: appDir=\(appDir.path)")
        Log.d("ConfigManager init: configURL=\(configURL.path)")
        Log.d("ConfigManager init: envURL=\(envURL.path)")

        config = VibeMicConfig.default
        load()
        print("[VibeMic] API key loaded: \(config.apiKey.isEmpty ? "NO" : "YES (\(config.apiKey.prefix(10))...)")")
    }

    func load() {
        Log.d("ConfigManager.load() configURL=\(configURL.path) exists=\(FileManager.default.fileExists(atPath: configURL.path))")
        Log.d("ConfigManager.load() envURL=\(envURL.path) exists=\(FileManager.default.fileExists(atPath: envURL.path))")

        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                Log.d("Config data read OK, \(data.count) bytes")
                let decoded = try JSONDecoder().decode(VibeMicConfig.self, from: data)
                config = decoded
                Log.d("Config decoded OK, apiKey=\(config.apiKey.isEmpty ? "empty" : "set (\(config.apiKey.prefix(10))...)")")
            } catch {
                Log.d("Config load FAILED: \(error)")
                // Fallback: try to parse as dictionary
                if let data = try? Data(contentsOf: configURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    Log.d("Config JSON keys: \(json.keys.sorted())")
                    if let key = json["apiKey"] as? String ?? json["api_key"] as? String {
                        config.apiKey = key
                        Log.d("Fallback apiKey loaded")
                    }
                }
            }
        }

        if config.apiKey.isEmpty {
            config.apiKey = loadEnvApiKey()
            Log.d("Loaded from .env: \(config.apiKey.isEmpty ? "empty" : "set")")
        }

        if config.apiKey.isEmpty, let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            config.apiKey = envKey
        }

        config = normalized(config)
    }

    func save(_ newConfig: VibeMicConfig) {
        config = normalized(newConfig, preserving: config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    private func normalized(_ input: VibeMicConfig, preserving current: VibeMicConfig? = nil) -> VibeMicConfig {
        var normalized = input

        if let current {
            if current.developerMode && !normalized.developerMode {
                normalized.developerMode = true
            }

            if normalized.proxyEmail.isEmpty,
               !current.proxyEmail.isEmpty,
               normalized.proxyToken == current.proxyToken {
                normalized.proxyEmail = current.proxyEmail
            }
        }

        normalized.proxyBaseURL = normalized.proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.proxyBaseURL.isEmpty {
            normalized.proxyBaseURL = VibeMicConfig.defaultProxyBaseURL
        }

        if !normalized.developerMode {
            normalized.useProxy = true
        }

        return normalized
    }

    private func loadEnvApiKey() -> String {
        guard FileManager.default.fileExists(atPath: envURL.path),
              let content = try? String(contentsOf: envURL, encoding: .utf8)
        else { return "" }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("OPENAI_API_KEY=") && !trimmed.hasPrefix("#") {
                let value = String(trimmed.dropFirst("OPENAI_API_KEY=".count))
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        return ""
    }
}
