import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, @preconcurrency WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    weak var lucca: LuccaWebSession?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func publish(snapshot: DashboardSnapshot) {
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) { }

    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["command"] as? String == "toggle", let lucca else {
            replyHandler(["error": "Open Yucca on the iPhone to sign in."])
            return
        }
        Task {
            await lucca.toggleClock()
            if let error = lucca.errorMessage { replyHandler(["error": error]) }
            else if let data = try? JSONEncoder().encode(lucca.snapshot) { replyHandler(["snapshot": data]) }
            else { replyHandler(["error": "Could not update the watch."]) }
        }
    }
}
