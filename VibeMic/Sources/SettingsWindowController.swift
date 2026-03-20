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
