import SwiftUI

@main
struct YuccaWatchApp: App {
    @StateObject private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(session)
        }
    }
}

