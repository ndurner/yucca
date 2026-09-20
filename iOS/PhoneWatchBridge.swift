// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Nils Durner
//
// This file is part of Yucca.
//
// Yucca is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Yucca is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Yucca. If not, see <https://www.gnu.org/licenses/>.

import Foundation
@preconcurrency import WatchConnectivity

private final class WatchReply: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func send(error: String) {
        handler(["error": error])
    }

    func send(snapshot: Data) {
        handler(["snapshot": snapshot])
    }
}

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    weak var lucca: LuccaWebSession?
    private var latestSnapshotData: Data?

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
        latestSnapshotData = data
        publishLatestSnapshotIfActivated()
    }

    private func publishLatestSnapshotIfActivated() {
        guard WCSession.default.activationState == .activated,
              let latestSnapshotData
        else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": latestSnapshotData])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            self?.publishLatestSnapshotIfActivated()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["command"] as? String == "toggle" else {
            replyHandler(["error": "Open Yucca on the iPhone to sign in."])
            return
        }

        let reply = WatchReply(replyHandler)
        Task { @MainActor [weak self] in
            guard let lucca = self?.lucca else {
                reply.send(error: "Open Yucca on the iPhone to sign in.")
                return
            }
            await lucca.toggleClockWhenReady()
            if let error = lucca.errorMessage { reply.send(error: error) }
            else if let data = try? JSONEncoder().encode(lucca.snapshot) { reply.send(snapshot: data) }
            else { reply.send(error: "Could not update the watch.") }
        }
    }
}
