import Foundation
import WatchConnectivity

@MainActor
final class WatchSession: NSObject, ObservableObject, @preconcurrency WCSessionDelegate {
    @Published private(set) var snapshot = DashboardSnapshot.empty
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "snapshot"),
           let cached = try? JSONDecoder().decode(DashboardSnapshot.self, from: data) {
            snapshot = cached
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func toggle() {
        guard WCSession.default.isReachable else {
            errorMessage = "Open Yucca on your iPhone, then try again."
            return
        }
        isBusy = true
        WCSession.default.sendMessage(["command": "toggle"], replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.isBusy = false
                if let data = reply["snapshot"] as? Data { self?.apply(data) }
                else { self?.errorMessage = reply["error"] as? String ?? "The iPhone did not reply." }
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isBusy = false
                self?.errorMessage = error.localizedDescription
            }
        })
    }

    private func apply(_ data: Data) {
        guard let value = try? JSONDecoder().decode(DashboardSnapshot.self, from: data) else { return }
        snapshot = value
        UserDefaults.standard.set(data, forKey: "snapshot")
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) { }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        apply(data)
    }
}
