import SwiftUI

@main
struct YuccaApp: App {
    @StateObject private var session = LuccaWebSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .onReceive(session.$snapshot) { snapshot in
                    PhoneWatchBridge.shared.publish(snapshot: snapshot)
                }
                .task {
                    PhoneWatchBridge.shared.lucca = session
                    if session.hasTenant {
                        session.loadTenantRoot()
                    }
                }
        }
    }
}
