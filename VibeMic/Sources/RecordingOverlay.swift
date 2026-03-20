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
