import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
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
        WCSession.default.sendMessage(
            ["command": "toggle"],
            replyHandler: receiveReply,
            errorHandler: receiveError
        )
    }

    nonisolated private func receiveReply(_ reply: [String: Any]) {
        let snapshotData = reply["snapshot"] as? Data
        let message = reply["error"] as? String ?? "The iPhone did not reply."
        Task { @MainActor [weak self] in
            self?.isBusy = false
            if let snapshotData { self?.apply(snapshotData) }
            else { self?.errorMessage = message }
        }
    }

    nonisolated private func receiveError(_ error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.isBusy = false
            self?.errorMessage = message
        }
    }

    private func apply(_ data: Data) {
        guard let value = try? JSONDecoder().decode(DashboardSnapshot.self, from: data) else { return }
        snapshot = value
        UserDefaults.standard.set(data, forKey: "snapshot")
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) { }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor [weak self] in
            self?.apply(data)
        }
    }
}
