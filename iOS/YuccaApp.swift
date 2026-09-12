import SwiftUI

@main
struct YuccaApp: App {
    @StateObject private var session = LuccaWebSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    if session.hasTenant {
                        session.loadTenantRoot()
                    }
                }
        }
    }
}
