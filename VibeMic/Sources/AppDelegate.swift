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

        if !config.useProxy && config.apiKey.isEmpty {
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
        let currentConfig = ConfigManager.shared.config
        Log.d("Transcription mode: \(currentConfig.useProxy ? "proxy" : "direct")")
        isTranscribing = true
        statusBar.setState(.transcribing)
        overlay.updateState("Transcribing", color: NSColor.systemOrange)

        transcriber.transcribe(
            fileURL: audioURL,
            config: currentConfig,
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
