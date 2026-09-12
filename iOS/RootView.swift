import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: LuccaWebSession

    var body: some View {
        Group {
            if !session.hasTenant {
                TenantSetupView()
            } else if !session.isSignedIn {
                SignedOutView()
            } else {
                DashboardView()
            }
        }
        .tint(YuccaTheme.ink)
        .sheet(isPresented: $session.isShowingLogin) {
            NavigationStack {
                LuccaWebView(webView: session.webView)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Sign in to Lucca")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                session.isShowingLogin = false
                                Task { await session.refresh() }
                            }
                        }
                    }
            }
        }
    }
}

enum YuccaTheme {
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.15)
    static let mint = Color(red: 0.69, green: 0.93, blue: 0.80)
    static let warm = Color(red: 0.98, green: 0.95, blue: 0.89)
    static let coral = Color(red: 0.95, green: 0.42, blue: 0.36)
}

struct TenantSetupView: View {
    @EnvironmentObject private var session: LuccaWebSession
    @State private var tenant = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [YuccaTheme.warm, YuccaTheme.mint.opacity(0.65)], startPoint: .top, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 26) {
                Spacer()
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 44, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Yucca")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("A calmer way to clock in.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR LUCCA DOMAIN")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                    TextField("company.ilucca.net", text: $tenant)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .submitLabel(.continue)
                        .onSubmit(connect)
                }
                if let error = session.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button(action: connect) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(YuccaTheme.ink, in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)
                }
                .disabled(tenant.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .frame(maxWidth: 520)
            .padding(28)
        }
        .onAppear { focused = true }
    }

    private func connect() {
        do { try session.configureTenant(tenant) }
        catch { session.errorMessage = error.localizedDescription }
    }
}

struct SignedOutView: View {
    @EnvironmentObject private var session: LuccaWebSession

    var body: some View {
        ZStack {
            YuccaTheme.warm.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "person.crop.circle.badge.key")
                    .font(.system(size: 54))
                Text("Connect to Lucca")
                    .font(.largeTitle.bold())
                Text("Sign in on Lucca’s page. Your company’s SSO flow will open automatically when configured.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
                Button("Sign in") { session.beginSignIn() }
                    .buttonStyle(YuccaPrimaryButtonStyle(color: YuccaTheme.ink))
                    .frame(maxWidth: 360)
                if session.isBusy { ProgressView() }
                if let error = session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                Button("Use a different domain", role: .destructive) { session.forgetTenant() }
                    .font(.footnote)
            }
            .padding(28)
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var session: LuccaWebSession

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: session.snapshot.isClockedIn
                        ? [YuccaTheme.ink, Color(red: 0.12, green: 0.27, blue: 0.23)]
                        : [YuccaTheme.warm, Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let running = session.snapshot.isClockedIn
                        ? max(0, context.date.timeIntervalSince(session.snapshot.updatedAt))
                        : 0
                    VStack(spacing: 28) {
                        header
                        HStack(spacing: 14) {
                            TimeCard(
                                label: "TODAY",
                                seconds: session.snapshot.todaySeconds + running,
                                dark: session.snapshot.isClockedIn
                            )
                            TimeCard(
                                label: "THIS WEEK",
                                seconds: session.snapshot.weekSeconds + running,
                                dark: session.snapshot.isClockedIn
                            )
                        }
                        Spacer(minLength: 10)
                        ClockButton(
                            isClockedIn: session.snapshot.isClockedIn,
                            isBusy: session.isBusy
                        ) {
                            Task { await session.toggleClock() }
                        }
                        if session.snapshot.isClockedIn, let start = session.snapshot.activeStart {
                            Text("Entered at \(start.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                        } else {
                            Text("Ready when you are")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await session.refresh() } }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { session.signOut() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(session.snapshot.isClockedIn ? .white : YuccaTheme.ink)
                    }
                }
            }
            .refreshable { await session.refresh() }
            .alert("Couldn’t update Lucca", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.snapshot.isClockedIn ? .white.opacity(0.65) : .secondary)
                Text(session.userName.isEmpty ? "Today" : "Hello, \(session.userName.split(separator: " ").first ?? "")")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(session.snapshot.isClockedIn ? .white : YuccaTheme.ink)
            }
            Spacer()
            Circle()
                .fill(session.snapshot.isClockedIn ? YuccaTheme.mint : Color.green)
                .frame(width: 11, height: 11)
                .shadow(color: .black.opacity(0.15), radius: 4)
                .accessibilityLabel(session.snapshot.isClockedIn ? "Clocked in" : "Clocked out")
        }
    }
}

private struct TimeCard: View {
    let label: String
    let seconds: TimeInterval
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(label).font(.caption2.bold()).tracking(1.1)
                .foregroundStyle(dark ? .white.opacity(0.58) : .secondary)
            Text(DurationText.compact(seconds))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(dark ? .white : YuccaTheme.ink)
            Text("hours")
                .font(.caption)
                .foregroundStyle(dark ? .white.opacity(0.55) : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(19)
        .background(dark ? Color.white.opacity(0.09) : Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(dark ? 0.12 : 0.7)))
    }
}

private struct ClockButton: View {
    let isClockedIn: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isClockedIn ? YuccaTheme.coral : YuccaTheme.ink)
                    .shadow(color: (isClockedIn ? YuccaTheme.coral : YuccaTheme.ink).opacity(0.34), radius: 28, y: 14)
                if isBusy {
                    ProgressView().tint(.white).scaleEffect(1.25)
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: isClockedIn ? "arrow.down.right" : "arrow.up.right")
                            .font(.title2.bold())
                        Text(isClockedIn ? "Leave" : "Enter")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(width: 184, height: 184)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isClockedIn ? "Leave work" : "Enter work")
    }
}

private struct YuccaPrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(.white)
    }
}
