import Cocoa
import Kit

final class Popup: PopupWrapper {
    var refreshCallback: (() -> Void)?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let scroll = ScrollableStackView()
    private var list: NSStackView { self.scroll.stackView }
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    override init(_ module: ModuleType, frame: NSRect) {
        super.init(module, frame: frame)
        self.orientation = .vertical
        self.spacing = Constants.Popup.spacing
        let refresh = NSButton(title: localizedString("Refresh"), target: self, action: #selector(self.refresh))
        let header = NSStackView(views: [self.status, refresh])
        header.orientation = .horizontal
        self.status.font = NSFont.systemFont(ofSize: 10)
        self.status.textColor = .secondaryLabelColor
        self.addArrangedSubview(header)
        self.list.orientation = .vertical
        self.list.alignment = .leading
        self.list.spacing = 8
        self.addArrangedSubview(self.scroll)
        header.widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        self.scroll.widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        self.scroll.heightAnchor.constraint(equalToConstant: 390).isActive = true
        self.update([])
    }

    convenience init(_ module: ModuleType) {
        self.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 420))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showError(_ message: String) {
        self.status.stringValue = localizedString(message)
        self.status.textColor = .systemRed
    }

    func update(_ providers: [MihomoProvider]) {
        self.list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        self.status.textColor = .secondaryLabelColor
        self.status.stringValue = providers.isEmpty ? localizedString("No providers") :
            "\(providers.count) " + localizedString("providers")
        for provider in providers {
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 3
            let title = NSTextField(labelWithString: MihomoPreferences.displayName(provider))
            title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            title.lineBreakMode = .byTruncatingMiddle
            title.toolTip = provider.name
            row.addArrangedSubview(title)
            row.addArrangedSubview(self.detail("\(provider.vehicleType) · \(provider.proxyCount) " + localizedString("proxies")))
            if let info = provider.subscriptionInfo {
                let total = info.total > 0 ? Self.bytes(info.total) : localizedString("Unknown")
                row.addArrangedSubview(self.detail(localizedString("Used") + ": \(Self.bytes(info.used)) / \(total)"))
                row.addArrangedSubview(self.detail("↑ \(Self.bytes(info.upload))  ↓ \(Self.bytes(info.download))"))
                let expiration = info.expirationDate.map(self.dateFormatter.string) ?? localizedString("Not provided")
                row.addArrangedSubview(self.detail(localizedString("Expires") + ": " + expiration))
            } else {
                row.addArrangedSubview(self.detail(localizedString("No subscription usage information")))
            }
            self.list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: self.list.widthAnchor).isActive = true
            title.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            let separator = NSBox()
            separator.boxType = .separator
            self.list.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: self.list.widthAnchor).isActive = true
        }
    }

    private func detail(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 10)
        field.textColor = .secondaryLabelColor
        return field
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }

    @objc private func refresh() { self.refreshCallback?() }
}
