import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var session: WatchSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let running = session.snapshot.isClockedIn
                ? max(0, context.date.timeIntervalSince(session.snapshot.updatedAt))
                : 0
            VStack(spacing: 10) {
                HStack {
                    watchMetric("TODAY", session.snapshot.todaySeconds + running)
                    Spacer()
                    watchMetric("WEEK", session.snapshot.weekSeconds + running)
                }
                Button(action: session.toggle) {
                    ZStack {
                        Capsule()
                            .fill(session.snapshot.isClockedIn ? Color(red: 0.95, green: 0.42, blue: 0.36) : Color(red: 0.30, green: 0.76, blue: 0.56))
                        if session.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Label(
                                session.snapshot.isClockedIn ? "Leave" : "Enter",
                                systemImage: session.snapshot.isClockedIn ? "arrow.down.right" : "arrow.up.right"
                            )
                            .font(.headline)
                            .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 52)
                .disabled(session.isBusy)
                Text(session.snapshot.isClockedIn ? "You’re clocked in" : "Ready when you are")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .alert("Yucca", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK") { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "Unknown error")
            }
        }
    }

    private func watchMetric(_ title: String, _ seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            Text(DurationText.compact(seconds))
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(DurationText.spoken(seconds))")
    }
}
