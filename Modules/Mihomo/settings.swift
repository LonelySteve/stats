import Cocoa
import Security
import Kit

final class Settings: NSStackView, Settings_v, NSTextFieldDelegate {
    var connectionCallback: (() -> Void)?
    var displayCallback: (() -> Void)?
    var intervalCallback: ((Int) -> Void)?
    private let address = NSTextField()
    private let secret = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let scroll = ScrollableStackView()
    private var providerList: NSStackView { self.scroll.stackView }

    init() {
        super.init(frame: .zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin
        self.address.stringValue = MihomoPreferences.address
        do {
            self.secret.stringValue = try MihomoKeychain.read()
        } catch {
            self.status.stringValue = localizedString(error.localizedDescription)
        }
        self.address.widthAnchor.constraint(equalToConstant: 250).isActive = true
        self.secret.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let save = NSButton(title: localizedString("Save"), target: self, action: #selector(self.saveConnection))
        let read = NSButton(title: localizedString("Read secret"), target: self, action: #selector(self.readSecret))
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("API address"), component: self.address),
            PreferencesRow("Secret", component: self.secret),
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: [
                    KeyValue_t(key: "60", value: "1 minute"),
                    KeyValue_t(key: "300", value: "5 minutes"),
                    KeyValue_t(key: "600", value: "10 minutes"),
                    KeyValue_t(key: "900", value: "15 minutes"),
                    KeyValue_t(key: "1800", value: "30 minutes"),
                    KeyValue_t(key: "3600", value: "Every hour")
                ],
                selected: "\(MihomoPreferences.updateInterval)"
            )),
            PreferencesRow(localizedString("Invert display (show used quota)"), component: switchView(
                action: #selector(self.toggleUsage), state: MihomoPreferences.showUsed
            )),
            PreferencesRow(component: NSStackView(views: [read, save]))
        ]))
        self.status.textColor = .secondaryLabelColor
        self.addArrangedSubview(self.status)
        self.addArrangedSubview(NSTextField(wrappingLabelWithString: localizedString("Select providers and edit their display names")))
        self.providerList.orientation = .vertical
        self.providerList.alignment = .leading
        self.providerList.spacing = 6
        self.addArrangedSubview(self.scroll)
        NSLayoutConstraint.activate([
            self.scroll.heightAnchor.constraint(equalToConstant: 260),
            self.scroll.widthAnchor.constraint(equalTo: self.widthAnchor)
        ])
        self.update([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(widgets: [widget_t]) {}

    func update(_ providers: [MihomoProvider]) {
        self.providerList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if providers.isEmpty {
            self.providerList.addArrangedSubview(NSTextField(labelWithString: localizedString("Enable Mihomo to load providers")))
        }
        for provider in providers {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(self.toggleProvider))
            checkbox.identifier = NSUserInterfaceItemIdentifier(provider.name)
            checkbox.state = MihomoPreferences.selected(provider, in: providers) ? .on : .off
            let name = NSTextField()
            name.stringValue = MihomoPreferences.displayName(provider)
            name.placeholderString = provider.name
            name.toolTip = provider.name
            name.identifier = NSUserInterfaceItemIdentifier(provider.name)
            name.delegate = self
            let row = NSStackView(views: [checkbox, name])
            row.orientation = .horizontal
            self.providerList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: self.providerList.widthAnchor).isActive = true
        }
    }

    @objc private func changeUpdateInterval(_ sender: NSPopUpButton) {
        guard let key = sender.selectedItem?.representedObject as? String, let value = Int(key) else { return }
        MihomoPreferences.updateInterval = value
        self.intervalCallback?(value)
    }

    @objc private func toggleUsage(_ sender: NSControl) {
        MihomoPreferences.showUsed = controlState(sender)
        self.displayCallback?()
    }

    @objc private func readSecret() {
        do {
            self.secret.stringValue = try MihomoKeychain.read(allowInteraction: true)
            self.status.stringValue = localizedString("Secret loaded")
            self.connectionCallback?()
        } catch {
            self.status.stringValue = localizedString(error.localizedDescription)
        }
    }

    @objc private func saveConnection() {
        let address = self.address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try MihomoAPI.request(address: address, secret: self.secret.stringValue)
            // A blank field after denied access must not erase the stored secret.
            if self.secret.stringValue.isEmpty { _ = try MihomoKeychain.read() }
            let status = MihomoKeychain.write(self.secret.stringValue)
            guard status == errSecSuccess else {
                self.status.stringValue = localizedString("Could not save secret to Keychain") + " (\(status))"
                return
            }
            Store.shared.set(key: "Mihomo_address", value: address)
            self.status.stringValue = localizedString("Saved")
            self.connectionCallback?()
        } catch {
            self.status.stringValue = localizedString(error.localizedDescription)
        }
    }

    @objc private func toggleProvider(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        Store.shared.set(key: "Mihomo_selected_\(name)", value: sender.state == .on)
        self.displayCallback?()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let name = field.identifier?.rawValue else { return }
        let alias = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Store.shared.set(key: "Mihomo_name_\(name)", value: alias == name ? "" : alias)
        if alias.isEmpty { field.stringValue = name }
        self.displayCallback?()
    }
}
