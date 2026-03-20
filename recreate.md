# VibeMic Native macOS — Complete Project Recreation Instructions

## Project Description

VibeMic is a native macOS menu bar application built with Swift Package Manager (no Xcode project file). It records audio from the microphone, sends it to the OpenAI Whisper API for transcription, and either copies the transcribed text to the clipboard or auto-pastes it into the focused application (if Accessibility permission is granted). It supports optional AI paraphrasing and translation via OpenAI's chat completions API. The app uses a global hotkey (default: Ctrl+Option+V) registered via the Carbon API, a floating recording overlay, a history window, and a settings window. It requires macOS 13+.

---

## Directory Structure

```
vibemic-native-macos/
├── .env.example
├── .gitignore
├── Package.swift
└── VibeMic/
    ├── Resources/
    │   ├── Info.plist
    │   └── VibeMic.entitlements
    └── Sources/
        ├── main.swift
        ├── AppDelegate.swift
        ├── AudioRecorder.swift
        ├── ConfigManager.swift
        ├── FloatingPanel.swift
        ├── GlobalHotkey.swift
        ├── HistoryManager.swift
        ├── HistoryWindowController.swift
        ├── Logger.swift
        ├── RecordingOverlay.swift
        ├── SettingsWindowController.swift
        ├── TextPaster.swift
        └── WhisperTranscriber.swift
```

---

## File Contents

Create every file below exactly as shown. Do not truncate or omit any lines.

---

### `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeMic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VibeMic",
            path: "VibeMic/Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
```

---

### `VibeMic/Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>VibeMic</string>
	<key>CFBundleIdentifier</key>
	<string>com.vibemic.macos</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleName</key>
	<string>VibeMic</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSMicrophoneUsageDescription</key>
	<string>VibeMic needs microphone access to record your voice for transcription.</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>VibeMic uses Apple Events to paste transcribed text into your active application.</string>
</dict>
</plist>
```

---

### `VibeMic/Resources/VibeMic.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
</dict>
</plist>
```

---

### `VibeMic/Sources/main.swift`

```swift
import Cocoa
import Foundation

NSLog("[VibeMic] Starting...")
let app = NSApplication.shared
NSLog("[VibeMic] NSApplication created")
let delegate = AppDelegate()
app.delegate = delegate
NSLog("[VibeMic] Running event loop")
app.run()
```

---

### `VibeMic/Sources/AppDelegate.swift`

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder: AudioRecorder!
    private var transcriber: WhisperTranscriber!
    private var isTranscribing = false
    private var settingsWindow: SettingsWindowController?
    private var historyWindow: HistoryWindowController?
    private var hotkey: GlobalHotkey!
    private var overlay: RecordingOverlay!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSLog("[VibeMic] App launched")

        recorder = AudioRecorder()
        transcriber = WhisperTranscriber()
        overlay = RecordingOverlay(onStop: { [weak self] in self?.toggleRecording() })

        statusBar = StatusBarController(
            onRecord: { [weak self] in self?.toggleRecording() },
            onSettings: { [weak self] in self?.openSettings() },
            onHistory: { [weak self] in self?.openHistory() },
            onToggleParaphrase: { [weak self] in self?.toggleParaphrase() },
            isParaphraseEnabled: { ConfigManager.shared.config.paraphraseEnabled }
        )
        statusBar.show()

        // Global hotkey via Carbon API — no accessibility permission needed
        hotkey = GlobalHotkey(callback: { [weak self] in self?.toggleRecording() })
        let config = ConfigManager.shared.config
        hotkey.register(keyCode: UInt32(config.hotkeyKeyCode), modifiers: UInt32(config.hotkeyModifiers))

        if ConfigManager.shared.config.apiKey.isEmpty {
            sendNotification(title: "VibeMic", body: "No API key. Right-click menu bar icon → Settings.")
        }

        NSLog("[VibeMic] Ready — press Ctrl+Shift+V to record")
    }

    /// Re-register hotkey (called after settings change)
    func reregisterHotkey() {
        let config = ConfigManager.shared.config
        hotkey.register(keyCode: UInt32(config.hotkeyKeyCode), modifiers: UInt32(config.hotkeyModifiers))
    }

    // When user clicks Dock icon while app is running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.d("applicationShouldHandleReopen: hasVisibleWindows=\(flag)")
        if !flag {
            openSettings()
        }
        return true
    }

    // Dock right-click menu
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let recordItem = NSMenuItem(
            title: recorder.isRecording ? "Stop Recording" : "Record",
            action: #selector(dockRecord),
            keyEquivalent: ""
        )
        recordItem.image = NSImage(systemSymbolName: recorder.isRecording ? "stop.circle.fill" : "mic.fill", accessibilityDescription: nil)
        menu.addItem(recordItem)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "History", action: #selector(dockHistory), keyEquivalent: "")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(dockSettings), keyEquivalent: "")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let paraphraseItem = NSMenuItem(title: "Paraphrase", action: #selector(dockParaphrase), keyEquivalent: "")
        paraphraseItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        paraphraseItem.state = ConfigManager.shared.config.paraphraseEnabled ? .on : .off
        menu.addItem(paraphraseItem)

        return menu
    }

    @objc private func dockRecord() { toggleRecording() }
    @objc private func dockHistory() { openHistory() }
    @objc private func dockSettings() { openSettings() }
    @objc private func dockParaphrase() { toggleParaphrase() }

    // Keep running when all windows closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func toggleRecording() {
        Log.d("toggleRecording: isRecording=\(recorder.isRecording), isTranscribing=\(isTranscribing)")
        if isTranscribing {
            Log.d("Still transcribing, ignoring")
            return
        }
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Log.d("startRecording called")
        recorder.checkPermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                Log.d("Mic permission granted, starting...")
                do {
                    try self.recorder.start()
                    self.statusBar.setState(.recording)
                    self.overlay.show()
                    Log.d("Recording started OK")
                } catch {
                    Log.d("Recording FAILED: \(error)")
                    self.sendNotification(title: "VibeMic", body: "Mic error: \(error.localizedDescription)")
                }
            } else {
                Log.d("Mic permission DENIED")
                self.sendNotification(title: "VibeMic", body: "Microphone access denied. Go to System Settings → Privacy → Microphone.")
            }
        }
    }

    private func stopAndTranscribe() {
        Log.d("stopAndTranscribe called")
        guard let audioURL = recorder.stop() else {
            Log.d("No audio file returned from recorder")
            statusBar.setState(.idle)
            sendNotification(title: "VibeMic", body: "No audio recorded.")
            return
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        Log.d("Audio file: \(audioURL.path), size: \(size)")
        Log.d("API key loaded: \(ConfigManager.shared.config.apiKey.isEmpty ? "NO" : "YES")")
        isTranscribing = true
        statusBar.setState(.transcribing)
        overlay.updateState("Transcribing", color: NSColor.systemOrange)

        let config = ConfigManager.shared.config
        transcriber.transcribe(
            fileURL: audioURL,
            config: config,
            onStateChange: { [weak self] state in
                DispatchQueue.main.async {
                    if state == "paraphrasing" {
                        self?.statusBar.setState(.paraphrasing)
                        self?.overlay.updateState("Paraphrasing", color: NSColor.systemPurple)
                    }
                }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (text, original)):
                    if text.isEmpty {
                        self?.sendNotification(title: "VibeMic", body: "No speech detected.")
                    } else {
                        TextPaster.paste(text)
                        HistoryManager.shared.add(text: text, original: original)
                        let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
                        if TextPaster.hasAccessibilityPermission {
                            self?.sendNotification(title: "VibeMic", body: "Typed: \(preview)")
                        } else {
                            self?.sendNotification(title: "VibeMic", body: "Copied! Press ⌘V to paste. Enable auto-paste in Settings.")
                        }
                    }
                case .failure(let error):
                    self?.sendNotification(title: "VibeMic", body: "Error: \(error.localizedDescription)")
                }
                self?.isTranscribing = false
                self?.statusBar.setState(.idle)
                self?.overlay.hide()
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindowController()
        }
        historyWindow?.reload()
        historyWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleParaphrase() {
        var config = ConfigManager.shared.config
        config.paraphraseEnabled.toggle()
        ConfigManager.shared.save(config)
        sendNotification(
            title: "VibeMic",
            body: "Paraphrase \(config.paraphraseEnabled ? "enabled ✍️" : "disabled")"
        )
    }

    private func sendNotification(title: String, body: String) {
        let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escaped)\" with title \"\(escapedTitle)\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
```

---

### `VibeMic/Sources/AudioRecorder.swift`

```swift
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
```

---

### `VibeMic/Sources/ConfigManager.swift`

```swift
import Foundation
import AppKit

struct VibeMicConfig: Codable {
    var apiKey: String
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
         translateTo: String = "") {
        self.apiKey = apiKey; self.model = model; self.language = language
        self.prompt = prompt; self.temperature = temperature
        self.responseFormat = responseFormat; self.paraphraseEnabled = paraphraseEnabled
        self.paraphrasePrompt = paraphrasePrompt; self.paraphraseModel = paraphraseModel
        self.hotkeyKeyCode = hotkeyKeyCode; self.hotkeyModifiers = hotkeyModifiers
        self.translateTo = translateTo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
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
    }

    func save(_ newConfig: VibeMicConfig) {
        config = newConfig
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
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
```

---

### `VibeMic/Sources/FloatingPanel.swift`

```swift
import Cocoa

enum RecordingState {
    case idle
    case recording
    case transcribing
    case paraphrasing
}

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var recordMenuItem: NSMenuItem!
    private var paraphraseMenuItem: NSMenuItem!

    private var onRecord: () -> Void
    private var onSettings: () -> Void
    private var onHistory: () -> Void
    private var onToggleParaphrase: () -> Void
    private var isParaphraseEnabled: () -> Bool
    private(set) var currentState: RecordingState = .idle

    init(
        onRecord: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onHistory: @escaping () -> Void,
        onToggleParaphrase: @escaping () -> Void,
        isParaphraseEnabled: @escaping () -> Bool
    ) {
        self.onRecord = onRecord
        self.onSettings = onSettings
        self.onHistory = onHistory
        self.onToggleParaphrase = onToggleParaphrase
        self.isParaphraseEnabled = isParaphraseEnabled
        super.init()
        setupStatusBar()
    }

    private func setIcon(_ symbolName: String, template: Bool = true, tint: NSColor? = nil, title: String = "") {
        guard let button = statusItem.button else { return }
        if symbolName == "vibemic" {
            // Use custom menu bar icon from Resources
            if let img = loadMenuBarIcon() {
                img.isTemplate = true
                button.image = img
                button.contentTintColor = nil
            }
        } else if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VibeMic") {
            img.isTemplate = template
            button.image = img
            button.contentTintColor = tint
        }
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
    }

    private func loadMenuBarIcon() -> NSImage? {
        // Try to load from app bundle Resources
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        // Fallback: draw waveform programmatically
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let bars: [(x: CGFloat, h: CGFloat)] = [
                (2, 4), (5, 8), (8, 14), (11, 18), (14, 14), (17, 8), (20, 4)
            ]
            let barW: CGFloat = 2.0
            let cy = rect.height / 2
            NSColor.black.setFill()
            for bar in bars {
                let x = bar.x * rect.width / 22
                let h = bar.h * rect.height / 18
                let r = NSRect(x: x, y: cy - h/2, width: barW * rect.width / 22, height: h)
                NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        return img
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        statusItem.autosaveName = "com.vibemic.statusitem"

        setIcon("waveform")

        // Always use menu — most reliable approach for NSStatusItem
        menu = NSMenu()
        menu.delegate = self

        let headerItem = NSMenuItem(title: "VibeMic", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        recordMenuItem = NSMenuItem(title: "Record", action: #selector(recordClicked(_:)), keyEquivalent: "r")
        recordMenuItem.target = self
        recordMenuItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        menu.addItem(recordMenuItem)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "History", action: #selector(historyClicked(_:)), keyEquivalent: "h")
        historyItem.target = self
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsClicked(_:)), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        paraphraseMenuItem = NSMenuItem(title: "Paraphrase", action: #selector(paraphraseClicked(_:)), keyEquivalent: "p")
        paraphraseMenuItem.target = self
        paraphraseMenuItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(paraphraseMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VibeMic", action: #selector(quitClicked(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func show() {
        NSLog("[VibeMic] Status bar ready")
    }

    func setState(_ state: RecordingState) {
        currentState = state
        NSLog("[VibeMic] setState: \(state)")

        switch state {
        case .idle:
            statusItem.length = NSStatusItem.squareLength
            setIcon("waveform")
            recordMenuItem.title = "Record"
            recordMenuItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        case .recording:
            // No image — just bold red text so it's unmistakable
            statusItem.button?.image = nil
            statusItem.button?.title = "■ STOP"
            statusItem.button?.contentTintColor = .systemRed
            statusItem.button?.imagePosition = .noImage
            statusItem.length = NSStatusItem.variableLength
            recordMenuItem.title = "Stop Recording"
            recordMenuItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
        case .transcribing:
            statusItem.length = NSStatusItem.variableLength
            setIcon("ellipsis.circle.fill", template: false, tint: .systemOrange, title: "...")
            recordMenuItem.title = "Transcribing..."
            recordMenuItem.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: nil)
        case .paraphrasing:
            statusItem.length = NSStatusItem.variableLength
            setIcon("text.bubble.fill", template: false, tint: .systemPurple, title: "AI")
            recordMenuItem.title = "Paraphrasing..."
            recordMenuItem.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)
        }
    }

    @objc private func recordClicked(_ sender: Any) {
        NSLog("[VibeMic] recordClicked, state=\(currentState)")
        onRecord()
    }

    @objc private func settingsClicked(_ sender: Any) { onSettings() }
    @objc private func historyClicked(_ sender: Any) { onHistory() }
    @objc private func paraphraseClicked(_ sender: Any) { onToggleParaphrase() }
    @objc private func quitClicked(_ sender: Any) { NSApp.terminate(nil) }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        Log.d("menuNeedsUpdate: state=\(currentState)")
        paraphraseMenuItem.state = isParaphraseEnabled() ? .on : .off
        recordMenuItem.isEnabled = (currentState == .idle || currentState == .recording)

        // Force update title/image based on current state
        switch currentState {
        case .idle:
            recordMenuItem.title = "Record"
            recordMenuItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        case .recording:
            recordMenuItem.title = "Stop Recording"
            recordMenuItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
        default:
            break
        }
    }
}
```

---

### `VibeMic/Sources/GlobalHotkey.swift`

```swift
import Carbon
import Cocoa

/// Global hotkey using Carbon RegisterEventHotKey — no accessibility permission needed.
class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    deinit {
        unregister()
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(0x564D4943), id: 1) // "VMIC"

        // Install handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let myself = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                myself.callback()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handlerCallback, 1, &eventType, selfPtr, &eventHandler)

        // Convert NSEvent modifier flags to Carbon modifiers
        var carbonMods: UInt32 = 0
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { carbonMods |= UInt32(controlKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { carbonMods |= UInt32(optionKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { carbonMods |= UInt32(shiftKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { carbonMods |= UInt32(cmdKey) }

        let status = RegisterEventHotKey(keyCode, carbonMods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            Log.d("GlobalHotkey registered: keyCode=\(keyCode), mods=\(carbonMods)")
        } else {
            Log.d("GlobalHotkey registration FAILED: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
```

---

### `VibeMic/Sources/HistoryManager.swift`

```swift
import Foundation

struct TranscriptEntry: Codable {
    let text: String
    let timestamp: String
    let original: String?  // non-nil if paraphrased

    var isParaphrased: Bool { original != nil }
}

class HistoryManager {
    static let shared = HistoryManager()

    private let maxEntries = 200
    private let historyURL: URL
    private(set) var entries: [TranscriptEntry] = []

    private init() {
        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
        historyURL = appDir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: historyURL.path),
              let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func add(text: String, original: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let entry = TranscriptEntry(
            text: text,
            timestamp: formatter.string(from: Date()),
            original: original
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        entries.remove(at: index)
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: historyURL)
        }
    }
}
```

---

### `VibeMic/Sources/HistoryWindowController.swift`

```swift
import Cocoa

class HistoryWindowController: NSWindowController {
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var countLabel: NSTextField!
    private var emptyLabel: NSTextField!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.center()
        window.minSize = NSSize(width: 400, height: 300)
        window.isMovableByWindowBackground = true
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Header
        let header = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 44, width: contentView.bounds.width, height: 44))
        header.autoresizingMask = [.width, .minYMargin]

        countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.frame = NSRect(x: 20, y: 12, width: 200, height: 20)
        header.addSubview(countLabel)

        let clearButton = NSButton(title: "Clear All", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .inline
        clearButton.font = NSFont.systemFont(ofSize: 12)
        clearButton.frame = NSRect(x: contentView.bounds.width - 80, y: 12, width: 64, height: 22)
        clearButton.autoresizingMask = [.minXMargin]
        header.addSubview(clearButton)

        contentView.addSubview(header)

        // Stack view inside scroll view
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 1
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 44))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let clipView = scrollView.contentView
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        contentView.addSubview(scrollView)

        // Empty state
        emptyLabel = NSTextField(labelWithString: "No transcriptions yet")
        emptyLabel.font = NSFont.systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: contentView.bounds.height / 2 - 20, width: contentView.bounds.width, height: 30)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        emptyLabel.isHidden = true
        contentView.addSubview(emptyLabel)
    }

    func reload() {
        HistoryManager.shared.load()
        rebuildList()
    }

    private func rebuildList() {
        // Remove old views
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let entries = HistoryManager.shared.entries
        countLabel.stringValue = "\(entries.count) transcript\(entries.count == 1 ? "" : "s")"
        emptyLabel.isHidden = !entries.isEmpty

        for (index, entry) in entries.enumerated() {
            let row = makeEntryRow(entry: entry, index: index)
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }

    private func makeEntryRow(entry: TranscriptEntry, index: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true

        // Hover-like alternating bg
        if index % 2 == 0 {
            row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }

        let contentWidth = (window?.contentView?.bounds.width ?? 520) - 40

        // Timestamp
        let badge = entry.isParaphrased ? " · paraphrased" : ""
        let timeLabel = NSTextField(labelWithString: "\(entry.timestamp)\(badge)")
        timeLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 20, y: 0, width: contentWidth, height: 14)
        timeLabel.translatesAutoresizingMaskIntoConstraints = true

        // Main text
        let textLabel = NSTextField(wrappingLabelWithString: entry.text)
        textLabel.font = NSFont.systemFont(ofSize: 13)
        textLabel.maximumNumberOfLines = 3
        textLabel.frame = NSRect(x: 20, y: 16, width: contentWidth - 80, height: 40)
        textLabel.translatesAutoresizingMaskIntoConstraints = true

        // Original text if paraphrased
        var origLabel: NSTextField?
        if let original = entry.original {
            let ol = NSTextField(wrappingLabelWithString: "Original: \(original)")
            ol.font = NSFont.systemFont(ofSize: 11)
            ol.textColor = .secondaryLabelColor
            ol.maximumNumberOfLines = 2
            ol.frame = NSRect(x: 20, y: 58, width: contentWidth - 80, height: 30)
            ol.translatesAutoresizingMaskIntoConstraints = true
            origLabel = ol
        }

        let rowHeight: CGFloat = entry.isParaphrased ? 96 : 62

        // Copy button
        let copyBtn = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!, target: self, action: #selector(copyEntry(_:)))
        copyBtn.bezelStyle = .inline
        copyBtn.isBordered = false
        copyBtn.tag = index
        copyBtn.frame = NSRect(x: contentWidth - 24, y: (rowHeight - 20) / 2, width: 24, height: 20)
        copyBtn.toolTip = "Copy"

        // Delete button
        let delBtn = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!, target: self, action: #selector(deleteEntry(_:)))
        delBtn.bezelStyle = .inline
        delBtn.isBordered = false
        delBtn.tag = index
        delBtn.contentTintColor = .systemRed
        delBtn.frame = NSRect(x: contentWidth - 52, y: (rowHeight - 20) / 2, width: 24, height: 20)
        delBtn.toolTip = "Delete"

        row.addSubview(timeLabel)
        row.addSubview(textLabel)
        if let ol = origLabel { row.addSubview(ol) }
        row.addSubview(copyBtn)
        row.addSubview(delBtn)

        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        return row
    }

    @objc private func copyEntry(_ sender: NSButton) {
        let idx = sender.tag
        guard idx < HistoryManager.shared.entries.count else { return }
        let text = HistoryManager.shared.entries[idx].text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Flash feedback
        if let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) {
            sender.image = img
            sender.contentTintColor = .systemGreen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                sender.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                sender.contentTintColor = .labelColor
            }
        }
    }

    @objc private func deleteEntry(_ sender: NSButton) {
        let idx = sender.tag
        HistoryManager.shared.delete(at: idx)
        rebuildList()
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        guard let win = window else { return }
        alert.beginSheetModal(for: win) { response in
            if response == .alertFirstButtonReturn {
                HistoryManager.shared.clearAll()
                self.rebuildList()
            }
        }
    }
}
```

---

### `VibeMic/Sources/Logger.swift`

```swift
import Foundation

enum Log {
    private static let logURL: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibemic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func d(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("[VibeMic] \(message)")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    static var path: String { logURL.path }
}
```

---

### `VibeMic/Sources/RecordingOverlay.swift`

```swift
import Cocoa

class RecordingOverlay {
    private var panel: NSPanel?
    private var container: NSView?
    private var label: NSTextField?
    private var dot: NSView?
    private var stopBtn: NSButton?
    private var onStop: () -> Void
    private var pulseTimer: Timer?

    private let panelWidth: CGFloat = 140
    private let height: CGFloat = 44

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    func show() {
        guard panel == nil else { return }

        guard let screen = NSScreen.main else { return }
        let x = (screen.frame.width - panelWidth) / 2
        let y = screen.frame.height - height - 80

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true

        let c = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: height))
        c.wantsLayer = true
        c.layer?.cornerRadius = height / 2
        c.layer?.backgroundColor = NSColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 0.95).cgColor
        c.layer?.masksToBounds = true

        // Red dot
        let d = NSView(frame: NSRect(x: 14, y: 16, width: 12, height: 12))
        d.wantsLayer = true
        d.layer?.cornerRadius = 6
        d.layer?.backgroundColor = NSColor.white.cgColor
        c.addSubview(d)

        // Label
        let l = NSTextField(labelWithString: "REC")
        l.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        l.textColor = .white
        l.frame = NSRect(x: 32, y: 12, width: 44, height: 20)
        c.addSubview(l)

        // STOP button
        let btn = NSButton(title: "STOP", target: self, action: #selector(stopClicked(_:)))
        btn.bezelStyle = .rounded
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 12
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        btn.contentTintColor = .white
        btn.frame = NSRect(x: panelWidth - 60, y: 8, width: 50, height: 28)
        c.addSubview(btn)

        p.contentView = c
        p.orderFront(nil)

        self.panel = p
        self.container = c
        self.label = l
        self.dot = d
        self.stopBtn = btn

        // Pulse the dot
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                d.animator().alphaValue = 0.3
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.5
                    d.animator().alphaValue = 1.0
                }
            }
        }
    }

    func updateState(_ text: String, color: NSColor) {
        guard let panel = panel, let container = container, let label = label else { return }

        pulseTimer?.invalidate()
        pulseTimer = nil

        // Hide dot and stop button, expand label to full width
        dot?.isHidden = true
        stopBtn?.isHidden = true

        container.layer?.backgroundColor = color.cgColor
        label.stringValue = text
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 12, width: panelWidth, height: 20)
    }

    func hide() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        panel?.close()
        panel = nil
        container = nil
        label = nil
        dot = nil
        stopBtn = nil
    }

    @objc private func stopClicked(_ sender: Any) {
        onStop()
    }
}
```

---

### `VibeMic/Sources/SettingsWindowController.swift`

```swift
import Cocoa

class SettingsWindowController: NSWindowController {
    private var apiKeyField: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var languagePopup: NSPopUpButton!
    private var translatePopup: NSPopUpButton!
    private var promptField: NSTextField!
    private var temperatureSlider: NSSlider!
    private var temperatureLabel: NSTextField!
    private var hotkeyButton: NSButton!
    private var hotkeyKeyCode: UInt16 = 9
    private var hotkeyModifiers: UInt = 786432
    private var isCapturingHotkey = false
    private var hotkeyMonitor: Any?
    private var paraphraseToggle: NSSwitch!
    private var paraphraseModelPopup: NSPopUpButton!
    private var paraphrasePromptView: NSTextView!
    private var paraphraseDetailStack: NSStackView!
    private var accessibilityDot: NSView!
    private var accessibilityLabel: NSTextField!
    private var accessibilityButton: NSButton!
    private var accessibilityTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.center()
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
        setupUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        loadValues()
        updateAccessibilityStatus()
        startAccessibilityPolling()
        super.showWindow(sender)
    }

    override func close() {
        stopAccessibilityPolling()
        super.close()
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scroll = NSScrollView(frame: contentView.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 28, bottom: 28, right: 28)

        // ── General Card ──
        let generalCard = makeCard(title: "General")
        let generalStack = cardStack()

        generalStack.addArrangedSubview(makeRow("API Key", makeTextField(placeholder: "sk-proj-...", assign: &apiKeyField)))

        let modelRow = makePopup(items: VibeMicConfig.availableModels, assign: &modelPopup)
        generalStack.addArrangedSubview(makeRow("Model", modelRow))

        let langItems = VibeMicConfig.availableLanguages.map { $0.code.isEmpty ? $0.name : "\($0.name) (\($0.code))" }
        let langRow = makePopup(items: langItems, assign: &languagePopup)
        generalStack.addArrangedSubview(makeRow("Language", langRow))

        generalStack.addArrangedSubview(makeRow("Prompt", makeTextField(placeholder: "e.g. 廣東話、English", assign: &promptField)))

        // Temperature
        let tempStack = NSStackView()
        tempStack.orientation = .horizontal
        tempStack.spacing = 10
        temperatureSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(temperatureChanged))
        temperatureSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        temperatureLabel = NSTextField(labelWithString: "0.0")
        temperatureLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        temperatureLabel.textColor = .secondaryLabelColor
        tempStack.addArrangedSubview(temperatureSlider)
        tempStack.addArrangedSubview(temperatureLabel)
        generalStack.addArrangedSubview(makeRow("Temperature", tempStack))

        // Hotkey
        hotkeyButton = NSButton(title: "⌃⌥V", target: self, action: #selector(captureHotkey))
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        hotkeyButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let hotkeyRow = NSStackView()
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 8
        hotkeyRow.addArrangedSubview(hotkeyButton)
        let hotkeyHint = NSTextField(labelWithString: "Click to change")
        hotkeyHint.font = .systemFont(ofSize: 11)
        hotkeyHint.textColor = .tertiaryLabelColor
        hotkeyRow.addArrangedSubview(hotkeyHint)
        generalStack.addArrangedSubview(makeRow("Shortcut", hotkeyRow))

        generalCard.addArrangedSubview(generalStack)
        stack.addArrangedSubview(generalCard)
        generalCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        // ── Auto-Insert Card ──
        let autoCard = makeCard(title: "Auto-Insert")
        let autoStack = cardStack()

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 8

        accessibilityDot = NSView()
        accessibilityDot.wantsLayer = true
        accessibilityDot.layer?.cornerRadius = 5
        accessibilityDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        accessibilityDot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        accessibilityLabel = NSTextField(labelWithString: "")
        accessibilityLabel.font = .systemFont(ofSize: 12)

        statusRow.addArrangedSubview(accessibilityDot)
        statusRow.addArrangedSubview(accessibilityLabel)
        autoStack.addArrangedSubview(statusRow)

        let desc = NSTextField(wrappingLabelWithString: "Auto-insert types transcribed text directly into the focused input field. This requires macOS Accessibility permission.")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .tertiaryLabelColor
        autoStack.addArrangedSubview(desc)

        accessibilityButton = NSButton(title: "Setup Auto-Insert...", target: self, action: #selector(showAutoInsertGuide))
        accessibilityButton.bezelStyle = .rounded
        autoStack.addArrangedSubview(accessibilityButton)

        updateAccessibilityStatus()

        autoCard.addArrangedSubview(autoStack)
        stack.addArrangedSubview(autoCard)
        autoCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        // ── Paraphrase Card ──
        let paraCard = makeCard(title: "Paraphrase")
        let paraHeaderStack = NSStackView()
        paraHeaderStack.orientation = .horizontal

        let paraDesc = NSTextField(wrappingLabelWithString: "Rewrite transcription with AI before pasting")
        paraDesc.font = .systemFont(ofSize: 12)
        paraDesc.textColor = .secondaryLabelColor
        paraDesc.setContentHuggingPriority(.defaultLow, for: .horizontal)

        paraphraseToggle = NSSwitch()
        paraphraseToggle.target = self
        paraphraseToggle.action = #selector(paraphraseToggled)

        paraHeaderStack.addArrangedSubview(paraDesc)
        paraHeaderStack.addArrangedSubview(paraphraseToggle)
        paraCard.addArrangedSubview(paraHeaderStack)
        paraHeaderStack.widthAnchor.constraint(equalTo: paraCard.widthAnchor, constant: -32).isActive = true

        // Paraphrase details (hidden when off)
        paraphraseDetailStack = cardStack()
        let paraModelRow = makePopup(items: VibeMicConfig.paraphraseModels, assign: &paraphraseModelPopup)
        paraphraseDetailStack.addArrangedSubview(makeRow("Model", paraModelRow))

        let ppScroll = NSScrollView()
        ppScroll.hasVerticalScroller = true
        ppScroll.borderType = .noBorder
        ppScroll.wantsLayer = true
        ppScroll.layer?.cornerRadius = 8
        ppScroll.layer?.borderWidth = 1
        ppScroll.layer?.borderColor = NSColor.separatorColor.cgColor
        ppScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true

        paraphrasePromptView = NSTextView()
        paraphrasePromptView.isEditable = true
        paraphrasePromptView.isRichText = false
        paraphrasePromptView.font = .systemFont(ofSize: 12)
        paraphrasePromptView.textContainerInset = NSSize(width: 8, height: 8)
        paraphrasePromptView.textContainer?.widthTracksTextView = true
        paraphrasePromptView.autoresizingMask = [.width]
        ppScroll.documentView = paraphrasePromptView
        paraphraseDetailStack.addArrangedSubview(makeRow("System Prompt", ppScroll))

        // Translate to
        let transItems = VibeMicConfig.translateLanguages.map { $0.name }
        let transRow = makePopup(items: transItems, assign: &translatePopup)
        paraphraseDetailStack.addArrangedSubview(makeRow("Translate to", transRow))

        paraCard.addArrangedSubview(paraphraseDetailStack)
        stack.addArrangedSubview(paraCard)
        paraCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        // ── Buttons ──
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(spacer)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        buttonRow.addArrangedSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.bezelColor = .controlAccentColor
        buttonRow.addArrangedSubview(saveBtn)

        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        // Wrap in flipped view for top-to-bottom layout
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: flipped.topAnchor),
            stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
        ])

        scroll.documentView = flipped
        contentView.addSubview(scroll)

        // Size the flipped view to match scroll width
        NSLayoutConstraint.activate([
            flipped.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    // MARK: - Helpers

    private func makeCard(title: String) -> NSStackView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 12
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        card.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        card.addArrangedSubview(titleLabel)

        let sep = NSBox()
        sep.boxType = .separator
        card.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true

        return card
    }

    private func cardStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 14
        return s
    }

    private func makeRow(_ label: String, _ control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 4

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)

        // Make control fill width
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        return row
    }

    private func makeTextField(placeholder: String, assign field: inout NSTextField!) -> NSTextField {
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.bezelStyle = .roundedBezel
        tf.font = .systemFont(ofSize: 13)
        field = tf
        return tf
    }

    private func makePopup(items: [String], assign popup: inout NSPopUpButton!) -> NSPopUpButton {
        let p = NSPopUpButton()
        p.addItems(withTitles: items)
        popup = p
        return p
    }

    // MARK: - Load / Save

    private func loadValues() {
        let config = ConfigManager.shared.config
        apiKeyField.stringValue = config.apiKey

        if let idx = VibeMicConfig.availableModels.firstIndex(of: config.model) {
            modelPopup.selectItem(at: idx)
        }
        if let idx = VibeMicConfig.availableLanguages.firstIndex(where: { $0.code == config.language }) {
            languagePopup.selectItem(at: idx)
        }

        if let idx = VibeMicConfig.translateLanguages.firstIndex(where: { $0.code == config.translateTo }) {
            translatePopup.selectItem(at: idx)
        }

        promptField.stringValue = config.prompt
        temperatureSlider.doubleValue = config.temperature
        temperatureLabel.stringValue = String(format: "%.1f", config.temperature)
        paraphraseToggle.state = config.paraphraseEnabled ? .on : .off
        paraphraseDetailStack.isHidden = !config.paraphraseEnabled

        if let idx = VibeMicConfig.paraphraseModels.firstIndex(of: config.paraphraseModel) {
            paraphraseModelPopup.selectItem(at: idx)
        }
        paraphrasePromptView.string = config.paraphrasePrompt

        hotkeyKeyCode = config.hotkeyKeyCode
        hotkeyModifiers = config.hotkeyModifiers
        hotkeyButton.title = config.hotkeyDisplayString
    }

    // MARK: - Actions

    @objc private func temperatureChanged() {
        temperatureLabel.stringValue = String(format: "%.1f", temperatureSlider.doubleValue)
    }

    @objc private func paraphraseToggled() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            paraphraseDetailStack.animator().isHidden = paraphraseToggle.state != .on
        }
    }

    private func updateAccessibilityStatus() {
        let granted = AXIsProcessTrusted()
        if granted {
            accessibilityDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            accessibilityLabel.stringValue = "Enabled — transcriptions auto-paste into focused field"
            accessibilityLabel.textColor = .labelColor
            accessibilityButton.title = "✓ Permission Granted"
            accessibilityButton.isEnabled = false
        } else {
            accessibilityDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            accessibilityLabel.stringValue = "Disabled — transcriptions copied to clipboard only"
            accessibilityLabel.textColor = .secondaryLabelColor
            accessibilityButton.title = "Setup Auto-Insert..."
            accessibilityButton.isEnabled = true
        }
    }

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateAccessibilityStatus()
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    @objc private func showAutoInsertGuide() {
        let alert = NSAlert()
        alert.messageText = "Enable Auto-Insert"
        alert.informativeText = """
        To let VibeMic automatically type transcribed text into your focused input field:

        1. Click "Open Settings" below
        2. Find "VibeMic" in the list
           • If not there, click + and navigate to VibeMic.app
        3. Toggle it ON
        4. Restart VibeMic

        Without this, VibeMic will copy text to your clipboard — just press ⌘V to paste.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")

        if let win = window {
            alert.beginSheetModal(for: win) { response in
                if response == .alertFirstButtonReturn {
                    // Open Accessibility settings directly
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    @objc private func captureHotkey() {
        if isCapturingHotkey { stopCapturing(); return }
        isCapturingHotkey = true
        hotkeyButton.title = "Press keys..."
        hotkeyButton.contentTintColor = .systemRed

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !flags.isEmpty && flags != .shift {
                self.hotkeyKeyCode = event.keyCode
                self.hotkeyModifiers = flags.rawValue
                var display: [String] = []
                if flags.contains(.control) { display.append("⌃") }
                if flags.contains(.option) { display.append("⌥") }
                if flags.contains(.shift) { display.append("⇧") }
                if flags.contains(.command) { display.append("⌘") }
                display.append(VibeMicConfig.keyCodeToString(event.keyCode))
                self.hotkeyButton.title = display.joined()
                self.stopCapturing()
                return nil
            }
            return event
        }
    }

    private func stopCapturing() {
        isCapturingHotkey = false
        hotkeyButton.contentTintColor = nil
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m); hotkeyMonitor = nil }
    }

    @objc private func saveSettings() {
        let langIndex = languagePopup.indexOfSelectedItem
        let langCode = langIndex >= 0 ? VibeMicConfig.availableLanguages[langIndex].code : ""

        let newConfig = VibeMicConfig(
            apiKey: apiKeyField.stringValue.trimmingCharacters(in: .whitespaces),
            model: modelPopup.titleOfSelectedItem ?? "gpt-4o-transcribe",
            language: langCode,
            prompt: promptField.stringValue.trimmingCharacters(in: .whitespaces),
            temperature: round(temperatureSlider.doubleValue * 10) / 10,
            responseFormat: "json",
            paraphraseEnabled: paraphraseToggle.state == .on,
            paraphrasePrompt: paraphrasePromptView.string.trimmingCharacters(in: .whitespacesAndNewlines),
            paraphraseModel: paraphraseModelPopup.titleOfSelectedItem ?? "gpt-4o-mini",
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers,
            translateTo: {
                let idx = translatePopup.indexOfSelectedItem
                return idx >= 0 ? VibeMicConfig.translateLanguages[idx].code : ""
            }()
        )

        ConfigManager.shared.save(newConfig)

        // Re-register hotkey
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.reregisterHotkey()
        }

        close()
    }

    @objc private func cancelSettings() {
        stopCapturing()
        close()
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
```

---

### `VibeMic/Sources/TextPaster.swift`

```swift
import Cocoa
import Foundation

enum TextPaster {
    /// Check if we have accessibility permission
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func paste(_ text: String) {
        // Always copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.d("TextPaster: copied to clipboard, length=\(text.count)")

        if hasAccessibilityPermission {
            // Auto-paste via osascript
            usleep(300_000)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    Log.d("TextPaster: auto-pasted OK")
                } else {
                    Log.d("TextPaster: osascript failed")
                }
            } catch {
                Log.d("TextPaster: error: \(error)")
            }
        } else {
            Log.d("TextPaster: no accessibility permission, clipboard only")
        }
    }
}
```

---

### `VibeMic/Sources/WhisperTranscriber.swift`

```swift
import Foundation

class WhisperTranscriber {

    /// Transcribe audio, optionally paraphrase, then return the final text.
    func transcribe(
        fileURL: URL,
        config: VibeMicConfig,
        onStateChange: @escaping (String) -> Void,
        completion: @escaping (Result<(text: String, original: String?), Error>) -> Void
    ) {
        guard !config.apiKey.isEmpty else {
            completion(.failure(TranscriberError.noApiKey))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                Log.d("Calling Whisper API...")
                let transcript = try self.sendToWhisper(fileURL: fileURL, config: config)
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

        let (data, _) = try syncRequest(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriberError.invalidResponse
        }

        if let errorInfo = json["error"] as? [String: Any],
           let message = errorInfo["message"] as? String {
            throw TranscriberError.apiError(message)
        }

        guard let text = json["text"] as? String else {
            throw TranscriberError.invalidResponse
        }
        return text
    }

    private func paraphrase(text: String, config: VibeMicConfig) throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Prepend "Translate to X." to system prompt if set
        var systemPrompt = config.paraphrasePrompt
        if !config.translateTo.isEmpty {
            systemPrompt = "Translate the output to \(config.translateTo). \(systemPrompt)"
        }

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
        let (data, _) = try syncRequest(request)

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
        case noResponse
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "No API key. Right-click → Settings."
            case .noResponse: return "No response from API"
            case .invalidResponse: return "Invalid API response"
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
```

---

### `.gitignore`

```
.env
config.json
__pycache__/
*.pyc
```

---

### `.env.example`

```
# OpenAI API key (required)
OPENAI_API_KEY=sk-your-key-here

# Language hint for Whisper (optional — e.g., en, zh, ja, ko)
# VIBEMIC_LANGUAGE=en
```

---

## Build Instructions

### Prerequisites

- macOS 13.0 (Ventura) or later
- Swift 5.9+ (included with Xcode 15+)
- An OpenAI API key with access to the Whisper transcription API

### Build via Swift Package Manager (command line)

```bash
cd vibemic-native-macos
swift build -c release
```

The compiled binary will be at `.build/release/VibeMic`.

### Create a proper .app bundle

After building, wrap the binary in a macOS .app bundle so that Info.plist, entitlements, and microphone permissions work correctly:

```bash
APP_DIR="VibeMic.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy binary
cp .build/release/VibeMic "$APP_DIR/MacOS/VibeMic"

# Copy Info.plist
cp VibeMic/Resources/Info.plist "$APP_DIR/Info.plist"

# Copy entitlements (for reference; used during codesigning)
cp VibeMic/Resources/VibeMic.entitlements "$APP_DIR/Resources/"
```

### Codesign the app (required for microphone access)

```bash
codesign --force --deep --sign - \
  --entitlements VibeMic/Resources/VibeMic.entitlements \
  VibeMic.app
```

If you have a Developer ID, replace `-` with your signing identity.

---

## Post-Build Setup

### 1. Create `.env` file

Place a `.env` file **next to** the `VibeMic.app` bundle (in the same directory):

```bash
echo 'OPENAI_API_KEY=sk-your-actual-key-here' > .env
```

Alternatively, launch the app and enter the API key in Settings (right-click the menu bar icon).

### 2. Grant Microphone Permission

On first launch, macOS will prompt for microphone access. Click "Allow". If you accidentally denied it, go to **System Settings > Privacy & Security > Microphone** and enable VibeMic.

### 3. Grant Accessibility Permission (optional, for auto-paste)

To let VibeMic automatically type transcribed text into the focused input field (instead of just copying to clipboard):

1. Go to **System Settings > Privacy & Security > Accessibility**
2. Click the `+` button and add `VibeMic.app`
3. Toggle it ON
4. Restart VibeMic

Without this permission, VibeMic copies text to the clipboard and you press Cmd+V to paste.

### 4. Run the app

```bash
open VibeMic.app
```

Or double-click `VibeMic.app` in Finder.

### Default Hotkey

**Ctrl+Option+V** (⌃⌥V) — toggles recording on/off. Configurable in Settings.