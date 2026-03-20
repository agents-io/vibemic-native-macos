import Cocoa

private struct UserUsageSummary {
    let email: String?
    let plan: String
    let usedMinutes: Double
    let totalMinutes: Double?
}

class UserSettingsWindowController: NSWindowController {
    private let onOpenDeveloperMode: () -> Void

    private var proxyEmailField: NSTextField!
    private var proxyPasswordField: NSSecureTextField!
    private var signInButton: NSButton!
    private var createAccountButton: NSButton!
    private var proxyStatusLabel: NSTextField!
    private var accountDetailStack: NSStackView!
    private var planBadge: NSTextField!
    private var usageProgressBar: NSProgressIndicator!
    private var usageLabel: NSTextField!
    private var upgradeButton: NSButton!
    private var languagePopup: NSPopUpButton!
    private var translatePopup: NSPopUpButton!
    private var paraphraseToggle: NSButton!
    private var hotkeyButton: NSButton!
    private var hotkeyKeyCode: UInt16 = 9
    private var hotkeyModifiers: UInt = 786432
    private var isCapturingHotkey = false
    private var hotkeyMonitor: Any?
    private var accessibilityDot: NSView!
    private var accessibilityLabel: NSTextField!
    private var accessibilityButton: NSButton!
    private var accessibilityTimer: Timer?
    private var proxyToken = ""
    private var signedInEmail = ""
    private var isAuthenticating = false
    private var isFetchingUsage = false
    private var isOpeningCheckout = false

    init(onOpenDeveloperMode: @escaping () -> Void) {
        self.onOpenDeveloperMode = onOpenDeveloperMode

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 760),
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
        refreshUsageIfNeeded()
        super.showWindow(sender)
    }

    override func close() {
        stopAccessibilityPolling()
        stopCapturing()
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

        // ── Account Card ──
        let accountCard = makeCard(title: "Account")
        let accountStack = cardStack()

        accountStack.addArrangedSubview(makeRow("Email", makeTextField(placeholder: "you@example.com", assign: &proxyEmailField)))
        accountStack.addArrangedSubview(makeRow("Password", makeSecureField(assign: &proxyPasswordField)))

        let authButtons = NSStackView()
        authButtons.orientation = .horizontal
        authButtons.spacing = 10

        signInButton = NSButton(title: "Sign In", target: self, action: #selector(signIn))
        signInButton.bezelStyle = .rounded

        createAccountButton = NSButton(title: "Create Account", target: self, action: #selector(createAccount))
        createAccountButton.bezelStyle = .rounded

        authButtons.addArrangedSubview(signInButton)
        authButtons.addArrangedSubview(createAccountButton)
        accountStack.addArrangedSubview(authButtons)

        proxyStatusLabel = NSTextField(labelWithString: "Not signed in")
        proxyStatusLabel.font = .systemFont(ofSize: 12)
        proxyStatusLabel.textColor = .secondaryLabelColor
        accountStack.addArrangedSubview(proxyStatusLabel)

        accountDetailStack = cardStack()

        let planRow = NSStackView()
        planRow.orientation = .horizontal
        planRow.spacing = 8

        let planLabel = NSTextField(labelWithString: "Plan")
        planLabel.font = .systemFont(ofSize: 11, weight: .medium)
        planLabel.textColor = .secondaryLabelColor
        planLabel.setContentHuggingPriority(.required, for: .horizontal)

        planBadge = NSTextField(labelWithString: "Free")
        planBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        planBadge.alignment = .center
        planBadge.wantsLayer = true
        planBadge.layer?.cornerRadius = 10
        planBadge.layer?.borderWidth = 0.5
        planBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        planBadge.heightAnchor.constraint(equalToConstant: 22).isActive = true
        updatePlanBadge("Free")

        planRow.addArrangedSubview(planLabel)
        planRow.addArrangedSubview(planBadge)
        accountDetailStack.addArrangedSubview(planRow)

        let usageStack = NSStackView()
        usageStack.orientation = .vertical
        usageStack.alignment = .leading
        usageStack.spacing = 6

        usageProgressBar = NSProgressIndicator()
        usageProgressBar.isIndeterminate = false
        usageProgressBar.minValue = 0
        usageProgressBar.maxValue = 1
        usageProgressBar.doubleValue = 0
        usageProgressBar.controlSize = .small
        usageProgressBar.style = .bar
        usageProgressBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        usageLabel = NSTextField(labelWithString: "Loading usage…")
        usageLabel.font = .systemFont(ofSize: 12)
        usageLabel.textColor = .secondaryLabelColor

        usageStack.addArrangedSubview(usageProgressBar)
        usageStack.addArrangedSubview(usageLabel)
        accountDetailStack.addArrangedSubview(makeRow("Usage", usageStack))

        upgradeButton = NSButton(title: "Upgrade to Pro", target: self, action: #selector(openUpgradeCheckout))
        upgradeButton.bezelStyle = .rounded
        accountDetailStack.addArrangedSubview(upgradeButton)

        accountCard.addArrangedSubview(accountStack)
        accountCard.addArrangedSubview(accountDetailStack)
        stack.addArrangedSubview(accountCard)
        accountCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        // ── Preferences Card ──
        let preferencesCard = makeCard(title: "Preferences")
        let preferencesStack = cardStack()

        let langItems = VibeMicConfig.availableLanguages.map { $0.code.isEmpty ? $0.name : "\($0.name) (\($0.code))" }
        preferencesStack.addArrangedSubview(makeRow("Language", makePopup(items: langItems, assign: &languagePopup)))

        let transItems = VibeMicConfig.translateLanguages.map { $0.name }
        preferencesStack.addArrangedSubview(makeRow("Translate to", makePopup(items: transItems, assign: &translatePopup)))

        paraphraseToggle = NSButton(checkboxWithTitle: "Clean up my speech", target: nil, action: nil)
        preferencesStack.addArrangedSubview(paraphraseToggle)

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
        preferencesStack.addArrangedSubview(makeRow("Shortcut", hotkeyRow))

        preferencesCard.addArrangedSubview(preferencesStack)
        stack.addArrangedSubview(preferencesCard)
        preferencesCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

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

        autoCard.addArrangedSubview(autoStack)
        stack.addArrangedSubview(autoCard)
        autoCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        // ── About Card ──
        let aboutCard = makeCard(title: "About")
        let aboutStack = cardStack()

        let versionLabel = NSTextField(labelWithString: "VibeMic v1.0")
        versionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        aboutStack.addArrangedSubview(versionLabel)

        let developerModeButton = NSButton(title: "Hold ⌥ (Option) and click this text to enter Developer Mode", target: self, action: #selector(openDeveloperModeFromSecret))
        developerModeButton.isBordered = false
        developerModeButton.bezelStyle = .inline
        developerModeButton.font = .systemFont(ofSize: 11)
        developerModeButton.contentTintColor = .tertiaryLabelColor
        developerModeButton.toolTip = "Option-click to open developer settings"
        aboutStack.addArrangedSubview(developerModeButton)

        aboutCard.addArrangedSubview(aboutStack)
        stack.addArrangedSubview(aboutCard)
        aboutCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

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

    private func makeSecureField(assign field: inout NSSecureTextField!) -> NSSecureTextField {
        let tf = NSSecureTextField()
        tf.placeholderString = "Password"
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

    private func updatePlanBadge(_ plan: String) {
        let normalized = normalizedPlanName(plan)
        let color: NSColor
        switch normalized {
        case "Pro":
            color = .systemBlue
        case "Unlimited":
            color = .systemOrange
        default:
            color = .systemGray
        }

        planBadge.stringValue = normalized
        planBadge.textColor = color
        planBadge.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        planBadge.layer?.borderColor = color.withAlphaComponent(0.25).cgColor
    }

    private func normalizedPlanName(_ plan: String) -> String {
        let raw = plan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "pro":
            return "Pro"
        case "unlimited":
            return "Unlimited"
        case "":
            return "Free"
        default:
            return raw.capitalized
        }
    }

    private func updateAccountStatus(isError: Bool = false, message: String? = nil) {
        proxyStatusLabel.toolTip = message

        if let message {
            proxyStatusLabel.stringValue = message
            proxyStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
            return
        }

        if proxyToken.isEmpty {
            proxyStatusLabel.stringValue = "Not signed in"
            proxyStatusLabel.textColor = .secondaryLabelColor
            return
        }

        if signedInEmail.isEmpty {
            proxyStatusLabel.stringValue = "Signed in"
        } else {
            proxyStatusLabel.stringValue = "Signed in as \(signedInEmail)"
        }
        proxyStatusLabel.textColor = .systemGreen
    }

    private func updateSignedInUI() {
        let signedIn = !proxyToken.isEmpty
        accountDetailStack.isHidden = !signedIn

        if !signedIn {
            usageProgressBar.maxValue = 1
            usageProgressBar.doubleValue = 0
            usageLabel.stringValue = "Sign in to see usage."
        }

        updateAccountStatus()
        updateAuthControls()
    }

    private func updateAuthControls(activeAction: String? = nil) {
        signInButton.isEnabled = !isAuthenticating
        createAccountButton.isEnabled = !isAuthenticating
        signInButton.title = activeAction == "signin" ? "Signing In..." : "Sign In"
        createAccountButton.title = activeAction == "create" ? "Creating..." : "Create Account"
        upgradeButton.isEnabled = !proxyToken.isEmpty && !isOpeningCheckout && !isAuthenticating
        upgradeButton.title = isOpeningCheckout ? "Opening..." : "Upgrade to Pro"
    }

    private func formatMinutes(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    private func updateUsageSummary(_ summary: UserUsageSummary) {
        if let email = summary.email, !email.isEmpty {
            signedInEmail = email
            proxyEmailField.stringValue = email
        }

        updatePlanBadge(summary.plan)

        let used = max(summary.usedMinutes, 0)
        if let total = summary.totalMinutes, total > 0 {
            usageProgressBar.maxValue = total
            usageProgressBar.doubleValue = min(used, total)
            usageLabel.stringValue = "\(formatMinutes(used)) min / \(formatMinutes(total)) min used"
        } else {
            usageProgressBar.maxValue = max(used, 1)
            usageProgressBar.doubleValue = min(used, usageProgressBar.maxValue)
            usageLabel.stringValue = "\(formatMinutes(used)) min used"
        }

        updateAccountStatus()
    }

    private func proxyURL(path: String) -> URL? {
        URL(string: VibeMicConfig.defaultProxyBaseURL + path)
    }

    private func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func errorMessage(from data: Data) -> String? {
        guard let json = jsonObject(from: data) else { return nil }

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

    private func stringValue(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func numberValue(in json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double { return value }
            if let value = json[key] as? Int { return Double(value) }
            if let value = json[key] as? NSNumber { return value.doubleValue }
            if let value = json[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    private func parseUsageSummary(from data: Data) -> UserUsageSummary? {
        guard let json = jsonObject(from: data) else { return nil }

        let user = json["user"] as? [String: Any] ?? [:]
        let account = json["account"] as? [String: Any] ?? [:]
        let usage = json["usage"] as? [String: Any] ?? [:]
        let subscription = json["subscription"] as? [String: Any] ?? [:]
        let limits = json["limits"] as? [String: Any] ?? [:]

        let email = stringValue(in: json, keys: ["email"])
            ?? stringValue(in: user, keys: ["email"])
            ?? stringValue(in: account, keys: ["email"])

        let plan = stringValue(in: json, keys: ["plan", "tier"])
            ?? stringValue(in: subscription, keys: ["plan", "tier", "name"])
            ?? "Free"

        let used = numberValue(in: json, keys: ["used_minutes", "usedMinutes", "minutes_used", "usage_minutes"])
            ?? numberValue(in: usage, keys: ["used_minutes", "usedMinutes", "minutes_used", "current_period_minutes_used", "minutes"])
            ?? 0

        let total = numberValue(in: json, keys: ["total_minutes", "limit_minutes", "included_minutes", "minutes_limit"])
            ?? numberValue(in: usage, keys: ["total_minutes", "limit_minutes", "included_minutes", "minutes_limit"])
            ?? numberValue(in: subscription, keys: ["included_minutes", "limit_minutes", "minutes_limit"])
            ?? numberValue(in: limits, keys: ["minutes", "monthly_minutes", "included_minutes"])

        return UserUsageSummary(email: email, plan: plan, usedMinutes: used, totalMinutes: total)
    }

    private func checkoutURL(from data: Data) -> URL? {
        guard let json = jsonObject(from: data) else { return nil }
        let nested = json["data"] as? [String: Any] ?? [:]

        let urlString = stringValue(in: json, keys: ["url", "checkout_url", "checkoutUrl"])
            ?? stringValue(in: nested, keys: ["url", "checkout_url", "checkoutUrl"])

        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url
    }

    private func accessToken(from data: Data) -> String? {
        guard let json = jsonObject(from: data) else { return nil }
        return stringValue(in: json, keys: ["access_token", "accessToken", "token"])
    }

    private func persistProxySession(token: String, email: String) {
        proxyToken = token
        signedInEmail = email

        var config = ConfigManager.shared.config
        config.useProxy = true
        config.proxyBaseURL = VibeMicConfig.defaultProxyBaseURL
        config.proxyToken = token
        config.proxyEmail = email
        ConfigManager.shared.save(config)
    }

    private func clearProxySession() {
        proxyToken = ""
        signedInEmail = ""

        var config = ConfigManager.shared.config
        config.useProxy = true
        config.proxyBaseURL = VibeMicConfig.defaultProxyBaseURL
        config.proxyToken = ""
        config.proxyEmail = ""
        ConfigManager.shared.save(config)
    }

    // MARK: - Load / Save

    private func loadValues() {
        let config = ConfigManager.shared.config

        proxyEmailField.stringValue = config.proxyEmail
        proxyPasswordField.stringValue = ""
        proxyToken = config.proxyToken
        signedInEmail = config.proxyEmail

        if let idx = VibeMicConfig.availableLanguages.firstIndex(where: { $0.code == config.language }) {
            languagePopup.selectItem(at: idx)
        }

        if let idx = VibeMicConfig.translateLanguages.firstIndex(where: { $0.code == config.translateTo }) {
            translatePopup.selectItem(at: idx)
        }

        paraphraseToggle.state = config.paraphraseEnabled ? .on : .off
        hotkeyKeyCode = config.hotkeyKeyCode
        hotkeyModifiers = config.hotkeyModifiers
        hotkeyButton.title = config.hotkeyDisplayString

        if proxyToken.isEmpty {
            updatePlanBadge("Free")
        } else {
            updatePlanBadge("Free")
            usageProgressBar.maxValue = 1
            usageProgressBar.doubleValue = 0
            usageLabel.stringValue = "Loading usage…"
        }

        updateSignedInUI()
    }

    // MARK: - Account Actions

    @objc private func signIn() {
        authenticate(path: "/auth/login", action: "signin")
    }

    @objc private func createAccount() {
        authenticate(path: "/auth/register", action: "create")
    }

    private func authenticate(path: String, action: String) {
        let email = proxyEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = proxyPasswordField.stringValue

        guard !email.isEmpty, !password.isEmpty else {
            updateAccountStatus(isError: true, message: "Enter email and password.")
            return
        }

        guard let url = proxyURL(path: path) else {
            updateAccountStatus(isError: true, message: "Invalid server URL.")
            return
        }

        isAuthenticating = true
        updateAuthControls(activeAction: action)
        updateAccountStatus(message: action == "create" ? "Creating account..." : "Signing in...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isAuthenticating = false
                self.updateAuthControls()

                if let error = error {
                    self.updateAccountStatus(isError: true, message: error.localizedDescription)
                    return
                }

                guard let data = data else {
                    self.updateAccountStatus(isError: true, message: "No response from server.")
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(statusCode) else {
                    self.updateAccountStatus(isError: true, message: self.errorMessage(from: data) ?? "Authentication failed.")
                    return
                }

                guard let accessToken = self.accessToken(from: data), !accessToken.isEmpty else {
                    self.updateAccountStatus(isError: true, message: "Invalid authentication response.")
                    return
                }

                self.proxyPasswordField.stringValue = ""
                self.persistProxySession(token: accessToken, email: email)
                self.updateSignedInUI()
                self.refreshUsageIfNeeded(force: true)
            }
        }.resume()
    }

    private func refreshUsageIfNeeded(force: Bool = false) {
        guard !proxyToken.isEmpty else {
            updateSignedInUI()
            return
        }
        guard force || !isFetchingUsage else { return }
        guard let url = proxyURL(path: "/api/usage") else { return }

        isFetchingUsage = true
        usageLabel.stringValue = "Loading usage…"

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(proxyToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingUsage = false

                if let error = error {
                    self.usageLabel.stringValue = "Could not load usage."
                    self.proxyStatusLabel.toolTip = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self.usageLabel.stringValue = "Could not load usage."
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(statusCode) else {
                    if statusCode == 401 || statusCode == 403 {
                        self.clearProxySession()
                        self.updateSignedInUI()
                        self.updateAccountStatus(isError: true, message: self.errorMessage(from: data) ?? "Session expired. Sign in again.")
                        return
                    }

                    self.usageLabel.stringValue = self.errorMessage(from: data) ?? "Could not load usage."
                    return
                }

                guard let summary = self.parseUsageSummary(from: data) else {
                    self.usageLabel.stringValue = "Could not load usage."
                    return
                }

                self.updateUsageSummary(summary)

                if let email = summary.email,
                   !email.isEmpty,
                   email != ConfigManager.shared.config.proxyEmail {
                    var config = ConfigManager.shared.config
                    config.proxyEmail = email
                    ConfigManager.shared.save(config)
                }
            }
        }.resume()
    }

    @objc private func openUpgradeCheckout() {
        guard !proxyToken.isEmpty else {
            updateAccountStatus(isError: true, message: "Sign in to upgrade.")
            return
        }
        guard let url = proxyURL(path: "/api/subscribe") else { return }

        isOpeningCheckout = true
        updateAuthControls()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(proxyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["plan": "pro"])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isOpeningCheckout = false
                self.updateAuthControls()

                if let error = error {
                    self.updateAccountStatus(isError: true, message: error.localizedDescription)
                    return
                }

                guard let data = data else {
                    self.updateAccountStatus(isError: true, message: "No response from server.")
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(statusCode) else {
                    self.updateAccountStatus(isError: true, message: self.errorMessage(from: data) ?? "Could not open checkout.")
                    return
                }

                guard let checkoutURL = self.checkoutURL(from: data) else {
                    self.updateAccountStatus(isError: true, message: "Invalid checkout response.")
                    return
                }

                self.openInSafari(checkoutURL)
            }
        }.resume()
    }

    private func openInSafari(_ url: URL) {
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: safariURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
            return
        }

        NSWorkspace.shared.open(url)
    }

    // MARK: - Accessibility

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
                if response == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Hotkey

    @objc private func captureHotkey() {
        if isCapturingHotkey {
            stopCapturing()
            return
        }

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
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }

    // MARK: - Window Actions

    @objc private func openDeveloperModeFromSecret() {
        guard NSApp.currentEvent?.modifierFlags.contains(.option) == true else { return }
        onOpenDeveloperMode()
        close()
    }

    @objc private func saveSettings() {
        var config = ConfigManager.shared.config

        let langIndex = languagePopup.indexOfSelectedItem
        config.language = langIndex >= 0 ? VibeMicConfig.availableLanguages[langIndex].code : ""

        let translateIndex = translatePopup.indexOfSelectedItem
        config.translateTo = translateIndex >= 0 ? VibeMicConfig.translateLanguages[translateIndex].code : ""

        config.paraphraseEnabled = paraphraseToggle.state == .on
        config.hotkeyKeyCode = hotkeyKeyCode
        config.hotkeyModifiers = hotkeyModifiers
        config.useProxy = true
        config.proxyBaseURL = VibeMicConfig.defaultProxyBaseURL
        config.proxyToken = proxyToken
        config.proxyEmail = proxyEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        ConfigManager.shared.save(config)

        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.reregisterHotkey()
        }

        close()
    }

    @objc private func cancelSettings() {
        close()
    }
}
