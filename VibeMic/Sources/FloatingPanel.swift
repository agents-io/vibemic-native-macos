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
