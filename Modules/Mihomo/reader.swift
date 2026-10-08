import Foundation
import Kit

final class MihomoReader: Reader<[MihomoProvider]> {
    var errorHandler: ((String) -> Void)?
    private var task: Task<Void, Never>?

    override func setup() {
        self.defaultInterval = MihomoAPI.defaultInterval
    }

    override func read() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, self.task == nil else { return }
            let address = MihomoPreferences.address
            self.task = Task { @MainActor [weak self] in
                do {
                    let secret = try MihomoKeychain.read()
                    let providers = try await MihomoAPI.fetch(address: address, secret: secret)
                    guard !Task.isCancelled, let self else { return }
                    self.task = nil
                    self.callback(providers)
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.task = nil
                    self.errorHandler?(error.localizedDescription)
                }
            }
        }
    }

    func refresh() {
        self.task?.cancel()
        self.task = nil
        self.read()
    }

    override func stop() {
        super.stop()
        DispatchQueue.main.async { [weak self] in
            self?.task?.cancel()
            self?.task = nil
        }
    }

    override func terminate() {
        self.stop()
    }
}
