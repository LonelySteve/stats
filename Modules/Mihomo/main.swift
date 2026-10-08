import Cocoa
import Kit

enum MihomoPreferences {
    static var showUsed: Bool {
        get { Store.shared.bool(key: "Mihomo_showUsed", defaultValue: false) }
        set { Store.shared.set(key: "Mihomo_showUsed", value: newValue) }
    }

    static var address: String {
        Store.shared.string(key: "Mihomo_address", defaultValue: MihomoAPI.defaultAddress)
    }

    static func displayName(_ provider: MihomoProvider) -> String {
        let name = Store.shared.string(key: "Mihomo_name_\(provider.name)", defaultValue: "")
        return name.isEmpty ? provider.name : name
    }

    static func selected(_ provider: MihomoProvider, in providers: [MihomoProvider]) -> Bool {
        Store.shared.bool(key: "Mihomo_selected_\(provider.name)",
                          defaultValue: provider.name == providers.first(where: { $0.subscriptionInfo != nil })?.name)
    }
}

public class Mihomo: Module {
    private let popupView = Popup(.mihomo)
    private let settingsView = Settings()
    private var reader: MihomoReader?
    private var providers: [MihomoProvider] = []

    public init() {
        super.init(moduleType: .mihomo, popup: self.popupView, settings: self.settingsView)
        self.reader = MihomoReader(.mihomo) { [weak self] value in
            guard let value else { return }
            self?.receive(value)
        }
        self.reader?.errorHandler = { [weak self] message in
            self?.popupView.showError(message)
            self?.updateWidgets(error: true)
        }
        self.settingsView.connectionCallback = { [weak self] in
            guard let self else { return }
            self.providers = []
            self.settingsView.update([])
            self.updateWidgets()
            self.popupView.update([])
            if self.enabled { self.reader?.refresh() }
        }
        self.settingsView.displayCallback = { [weak self] in
            guard let self else { return }
            self.updateWidgets()
            self.popupView.update(self.providers)
        }
        self.popupView.refreshCallback = { [weak self] in self?.reader?.refresh() }
        self.setReaders([self.reader])
    }

    private func receive(_ providers: [MihomoProvider]) {
        // Reader can restore entries cached by versions that included Compatible providers.
        let providers = providers.filter { $0.vehicleType != "Compatible" }
        self.providers = providers
        self.settingsView.update(providers)
        self.popupView.update(providers)
        self.updateWidgets()
    }

    private func updateWidgets(error: Bool = false) {
        let showUsed = MihomoPreferences.showUsed
        let values = self.providers.filter { MihomoPreferences.selected($0, in: self.providers) }.map { provider in
            let percentage = provider.subscriptionInfo?.menuBarPercentage(showUsed: showUsed)
            let value = error ? "!" : percentage.map { "\($0)%" } ?? "—"
            return Stack_t(key: provider.name, value: value, label: MihomoPreferences.displayName(provider))
        }
        self.menuBar.widgets.forEach { widget in
            (widget.item as? StackWidget)?.setValues(values)
        }
    }
}
