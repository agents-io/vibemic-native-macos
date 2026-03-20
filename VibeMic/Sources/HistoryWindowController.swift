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
