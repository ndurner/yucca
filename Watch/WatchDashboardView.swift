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
                        Circle()
                            .fill(session.snapshot.isClockedIn ? leaveGradient : enterGradient)
                        if session.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: session.snapshot.isClockedIn ? "arrow.down.right" : "arrow.up.right")
                                Text(session.snapshot.isClockedIn ? "Leave" : "Enter")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 130, height: 130)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
                .accessibilityLabel(session.snapshot.isClockedIn ? "Leave work" : "Enter work")
                if session.isBusy {
                    Text("Syncing with Lucca…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if session.snapshot.isClockedIn {
                    Text("You’re clocked in")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

    private var enterGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.88, blue: 0.30),
                Color(red: 0.96, green: 0.60, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var leaveGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.42, blue: 0.38),
                Color(red: 0.78, green: 0.10, blue: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
