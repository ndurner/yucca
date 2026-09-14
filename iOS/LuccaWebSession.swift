import Foundation
import OSLog
import SwiftUI
import WebKit

struct LuccaServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct BridgeResponse: Decodable {
    let ok: Bool
    let status: Int
    let body: String
}

@MainActor
final class LuccaWebSession: NSObject, ObservableObject {
    private static let pendingStartKey = "pendingClockInStart"
    private static let pendingEntryIDKey = "pendingClockInEntryID"
    private static let pendingBaselineKey = "pendingClockInBaselineSeconds"
    private static let recentlyCompletedEntryIDKey = "recentlyCompletedSentinelEntryID"
    private static let recentlyCompletedAtKey = "recentlyCompletedSentinelAt"
    private let logger = Logger(subsystem: "de.ndurner.yucca", category: "Lucca")
    @Published private(set) var snapshot = DashboardSnapshot.empty
    @Published private(set) var isSignedIn = false
    @Published private(set) var isBusy = false
    @Published private(set) var userName = ""
    @Published private(set) var confirmationMessage: String?
    @Published var errorMessage: String?
    @Published var isShowingLogin = false

    let webView: WKWebView
    private(set) var tenantHost: String
    private var currentUser: LuccaUser?
    private var pendingStart: Date?
    private var pendingEntryID: Int?
    private var pendingBaselineSeconds: TimeInterval?
    private var refreshTask: Task<Void, Never>?

    override init() {
        tenantHost = UserDefaults.standard.string(forKey: "tenantHost") ?? ""
        pendingStart = UserDefaults.standard.object(forKey: Self.pendingStartKey) as? Date
        let storedEntryID = UserDefaults.standard.integer(forKey: Self.pendingEntryIDKey)
        pendingEntryID = storedEntryID > 0 ? storedEntryID : nil
        pendingBaselineSeconds = UserDefaults.standard.object(forKey: Self.pendingBaselineKey) as? TimeInterval
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    deinit { refreshTask?.cancel() }

    var hasTenant: Bool { !tenantHost.isEmpty }

    func configureTenant(_ input: String) throws {
        let host = try Self.normalizedHost(input)
        guard host != tenantHost else {
            isShowingLogin = true
            loadLoginIfNeeded()
            return
        }

        tenantHost = host
        UserDefaults.standard.set(host, forKey: "tenantHost")
        isSignedIn = false
        currentUser = nil
        snapshot = .empty
        isShowingLogin = true
        loadTenantRoot()
    }

    func beginSignIn() {
        errorMessage = nil
        isShowingLogin = true
        loadLoginIfNeeded()
    }

    func loadTenantRoot() {
        guard let url = tenantURL(path: "/") else { return }
        webView.load(URLRequest(url: url))
    }

    func loadLoginIfNeeded() {
        guard hasTenant else { return }
        if webView.url?.host != tenantHost { loadTenantRoot() }
    }

    func refresh() async {
        guard hasTenant, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let user = try await fetchCurrentUser()
            currentUser = user
            userName = user.displayName
            let entries = try await fetchWeekEntries(ownerId: user.id)
            reconcilePendingClockIn(with: entries)
            snapshot = dashboardSnapshot(entries: entries, ownerId: user.id)
            isSignedIn = true
            errorMessage = nil
            logger.info("Lucca session ready with \(entries.count, privacy: .public) entries")
            #if DEBUG
            print("YUCCA_DIAGNOSTIC session-ready entries=\(entries.count)")
            #endif
        } catch {
            handle(error)
        }
    }

    func toggleClock() async {
        #if DEBUG
        print("YUCCA_DIAGNOSTIC toggle-requested busy=\(isBusy)")
        #endif
        guard !isBusy else {
            errorMessage = "Yucca is still syncing with Lucca. Please try again."
            return
        }
        isBusy = true
        confirmationMessage = nil
        defer { isBusy = false }
        do {
            let user: LuccaUser
            if let currentUser { user = currentUser }
            else { user = try await fetchCurrentUser() }
            let hadPendingAtTap = pendingStartForToday() != nil
            let entries = try await fetchWeekEntries(ownerId: user.id)
            reconcilePendingClockIn(with: entries)
            if hadPendingAtTap, pendingStartForToday() == nil {
                snapshot = dashboardSnapshot(entries: entries, ownerId: user.id)
                isSignedIn = true
                errorMessage = nil
                confirmationMessage = "Clock-in was updated in Lucca"
                return
            }
            let serverActive = TimesheetMath.activeEntry(in: entries)
            let localStart = pendingStartForToday()
            let wasClockedIn = serverActive != nil || localStart != nil
            if let localStart {
                let now = Date()
                let pendingID = pendingEntryID
                if let conflict = overlappingEntry(
                    in: entries,
                    startsAt: localStart,
                    endsAt: now,
                    excludingID: pendingID
                ) {
                    let time = conflict.startsAtDate()?.formatted(date: .omitted, time: .shortened) ?? "today"
                    throw LuccaServiceError(message: "A Lucca entry starting at \(time) overlaps this clock-in. Adjust or remove that entry before clocking out.")
                }
                if let pendingID, let placeholder = entries.first(where: { $0.id == pendingID }) {
                    try await updateEntry(placeholder, ownerId: user.id, startsAt: localStart)
                    markSentinelCompleted(pendingID)
                } else {
                    try await createCompletedEntry(ownerId: user.id, startsAt: localStart)
                }
                clearPendingStart()
            } else if let active = serverActive {
                try await leave(active: active, ownerId: user.id)
            } else {
                let start = Date()
                let entryID = try await createPlaceholderEntry(ownerId: user.id, startsAt: start)
                savePendingStart(start, entryID: entryID, baselineSeconds: 60)
            }
            let updated = wasClockedIn ? try await fetchWeekEntries(ownerId: user.id) : entries
            snapshot = dashboardSnapshot(entries: updated, ownerId: user.id)
            isSignedIn = true
            errorMessage = nil
            confirmationMessage = wasClockedIn ? "Clocked out successfully" : "Clock-in saved on this iPhone"
            #if DEBUG
            print("YUCCA_DIAGNOSTIC toggle-succeeded action=\(wasClockedIn ? "leave" : "enter") entries=\(updated.count)")
            #endif
        } catch {
            handle(error)
        }
    }

    func signOut() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { }
        isSignedIn = false
        currentUser = nil
        userName = ""
        snapshot = .empty
        errorMessage = nil
        confirmationMessage = nil
        clearPendingStart()
        webView.loadHTMLString("", baseURL: nil)
    }

    func forgetTenant() {
        signOut()
        tenantHost = ""
        UserDefaults.standard.removeObject(forKey: "tenantHost")
    }

    private func createCompletedEntry(ownerId: Int, startsAt: Date) async throws {
        let payload: [String: Any] = [
            "ownerId": ownerId,
            "unit": 2,
            "startsAt": LuccaDateCodec.string(from: startsAt),
            "duration": TimesheetMath.luccaDuration(from: Date().timeIntervalSince(startsAt)),
            "creationSource": 2,
            "axisSections": []
        ]
        _ = try await request(path: "/api/v3/timeentries", method: "POST", json: payload)
    }

    private func createPlaceholderEntry(ownerId: Int, startsAt: Date) async throws -> Int {
        var payload: [String: Any] = [
            "ownerId": ownerId,
            "unit": 2,
            "startsAt": LuccaDateCodec.string(from: startsAt),
            "duration": "00:01:00",
            "creationSource": 4,
            "axisSections": []
        ]
        let data: Data
        do {
            data = try await request(path: "/api/v3/timeentries", method: "POST", json: payload)
        } catch let error as LuccaServiceError where error.message.contains("creationSource") {
            payload["creationSource"] = 2
            data = try await request(path: "/api/v3/timeentries", method: "POST", json: payload)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let entry = Self.unwrapDataObject(object), let id = Self.integer(entry["id"]) else {
            throw LuccaServiceError(message: "Lucca created an entry but did not return its identifier.")
        }
        return id
    }

    private func leave(active: TimeEntry, ownerId: Int) async throws {
        guard let start = active.startsAtDate(), Calendar.current.isDateInToday(start) else {
            throw LuccaServiceError(message: "Only an entry started today can be stopped.")
        }
        try await updateEntry(active, ownerId: ownerId, startsAt: start)
    }

    private func updateEntry(_ active: TimeEntry, ownerId: Int, startsAt start: Date) async throws {
        let payload: [String: Any] = [
            "ownerId": ownerId,
            "unit": 2,
            "startsAt": LuccaDateCodec.string(from: start),
            "duration": TimesheetMath.luccaDuration(from: Date().timeIntervalSince(start)),
            "creationSource": active.creationSource ?? 2,
            "axisSections": []
        ]
        _ = try await request(path: "/api/v3/timeentries/\(active.id)", method: "PUT", json: payload)
    }

    private func fetchCurrentUser() async throws -> LuccaUser {
        let data = try await request(path: "/api/v3/users/me?fields=id,firstName,lastName")
        let object = try JSONSerialization.jsonObject(with: data)
        guard let userObject = Self.unwrapDataObject(object),
              let id = Self.integer(userObject["id"])
        else { throw LuccaServiceError(message: "Lucca did not return the signed-in user.") }
        return LuccaUser(
            id: id,
            firstName: userObject["firstName"] as? String,
            lastName: userObject["lastName"] as? String
        )
    }

    private func dashboardSnapshot(entries: [TimeEntry], ownerId: Int) -> DashboardSnapshot {
        guard let start = pendingStartForToday() else {
            return TimesheetMath.snapshot(entries: entries)
        }
        let visibleEntries = entries.filter { $0.id != pendingEntryID }
        let pendingEntry = TimeEntry(
            id: Int.min,
            ownerId: ownerId,
            unit: 2,
            startsAt: LuccaDateCodec.string(from: start),
            duration: "00:00:00",
            endsAt: nil,
            archivedAt: nil,
            creationSource: 2
        )
        return TimesheetMath.snapshot(entries: visibleEntries + [pendingEntry])
    }

    private func pendingStartForToday() -> Date? {
        guard let pendingStart else { return nil }
        guard Calendar.current.isDateInToday(pendingStart) else {
            clearPendingStart()
            return nil
        }
        return pendingStart
    }

    private func savePendingStart(_ date: Date, entryID: Int?, baselineSeconds: TimeInterval?) {
        pendingStart = date
        pendingEntryID = entryID
        pendingBaselineSeconds = baselineSeconds
        UserDefaults.standard.set(date, forKey: Self.pendingStartKey)
        if let entryID {
            UserDefaults.standard.set(entryID, forKey: Self.pendingEntryIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingEntryIDKey)
        }
        if let baselineSeconds {
            UserDefaults.standard.set(baselineSeconds, forKey: Self.pendingBaselineKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingBaselineKey)
        }
    }

    private func clearPendingStart() {
        pendingStart = nil
        pendingEntryID = nil
        pendingBaselineSeconds = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingStartKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingEntryIDKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingBaselineKey)
    }

    private func reconcilePendingClockIn(with entries: [TimeEntry]) {
        guard let localStart = pendingStartForToday() else {
            recoverOrphanedPlaceholder(from: entries)
            return
        }

        if let pendingEntryID {
            guard let serverEntry = entries.first(where: { $0.id == pendingEntryID }) else {
                // Give a newly-created Lucca row a short consistency window.
                if Date().timeIntervalSince(localStart) > 120 {
                    clearPendingStart()
                    confirmationMessage = "Clock-in was removed in Lucca"
                }
                return
            }

            if let baseline = pendingBaselineSeconds,
               abs(serverEntry.durationSeconds - baseline) > 1 {
                clearPendingStart()
                confirmationMessage = "Clock-in was updated in Lucca"
                return
            }

            if pendingBaselineSeconds == nil {
                pendingBaselineSeconds = serverEntry.durationSeconds
                UserDefaults.standard.set(serverEntry.durationSeconds, forKey: Self.pendingBaselineKey)
            }
            if let serverStart = serverEntry.startsAtDate(),
               abs(serverStart.timeIntervalSince(localStart)) > 1 {
                savePendingStart(
                    serverStart,
                    entryID: pendingEntryID,
                    baselineSeconds: serverEntry.durationSeconds
                )
            }
            return
        }

        // Migrate a clock-in made by an older Yucca build by adopting one nearby
        // Lucca row. Keeping the local start avoids silently changing elapsed time.
        let candidates = entries.filter { entry in
            guard let serverStart = entry.startsAtDate(), Calendar.current.isDateInToday(serverStart) else {
                return false
            }
            return abs(serverStart.timeIntervalSince(localStart)) <= 10 * 60
        }
        guard candidates.count == 1, let candidate = candidates.first else { return }
        savePendingStart(
            localStart,
            entryID: candidate.id,
            baselineSeconds: candidate.durationSeconds
        )
        #if DEBUG
        print("YUCCA_DIAGNOSTIC adopted-entry id=\(candidate.id) baseline=\(candidate.durationSeconds)")
        #endif
    }

    private func recoverOrphanedPlaceholder(from entries: [TimeEntry]) {
        let now = Date()
        let recentlyCompletedID: Int? = {
            let completedAt = UserDefaults.standard.object(forKey: Self.recentlyCompletedAtKey) as? Date
            guard let completedAt, now.timeIntervalSince(completedAt) <= 10 * 60 else { return nil }
            let value = UserDefaults.standard.integer(forKey: Self.recentlyCompletedEntryIDKey)
            return value > 0 ? value : nil
        }()
        let candidates = entries.filter { entry in
            guard entry.id != recentlyCompletedID,
                  abs(entry.durationSeconds - 60) <= 1,
                  let start = entry.startsAtDate(),
                  Calendar.current.isDateInToday(start)
            else { return false }
            return start <= now
        }

        let clockCandidates = candidates.filter { $0.creationSource == 4 }
        if clockCandidates.count == 1, let candidate = clockCandidates.first {
            savePendingStart(candidate.startsAtDate()!, entryID: candidate.id, baselineSeconds: 60)
            confirmationMessage = "Clock-in adopted from Lucca"
            return
        }

        // A unique one-minute row created in the web app is the shared sentinel.
        guard candidates.count == 1, let candidate = candidates.first,
              let start = candidate.startsAtDate()
        else { return }
        savePendingStart(start, entryID: candidate.id, baselineSeconds: 60)
        confirmationMessage = "Clock-in adopted from Lucca"
        #if DEBUG
        print("YUCCA_DIAGNOSTIC recovered-placeholder id=\(candidate.id)")
        #endif
    }

    private func markSentinelCompleted(_ entryID: Int) {
        UserDefaults.standard.set(entryID, forKey: Self.recentlyCompletedEntryIDKey)
        UserDefaults.standard.set(Date(), forKey: Self.recentlyCompletedAtKey)
    }

    private func overlappingEntry(
        in entries: [TimeEntry],
        startsAt: Date,
        endsAt: Date,
        excludingID: Int?
    ) -> TimeEntry? {
        entries.first { entry in
            guard entry.id != excludingID,
                  entry.archivedAt == nil,
                  entry.durationSeconds > 0,
                  let entryStart = entry.startsAtDate()
            else { return false }
            let entryEnd = entryStart.addingTimeInterval(entry.durationSeconds)
            return entryStart < endsAt && entryEnd > startsAt
        }
    }

    private func fetchWeekEntries(ownerId: Int) async throws -> [TimeEntry] {
        let week = TimesheetMath.weekInterval(containing: .now)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = .current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents()
        components.path = "/timmi-timesheet/services/timesheet-days/details"
        components.queryItems = [
            URLQueryItem(name: "ownerId", value: String(ownerId)),
            URLQueryItem(name: "from", value: dateFormatter.string(from: week.start)),
            URLQueryItem(name: "until", value: dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: week.end)!))
        ]
        let data = try await request(path: components.string ?? "/timmi-timesheet/services/timesheet-days/details")
        let root = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = root as? [String: Any] else { return [] }
        let rawItems = dictionary["items"] as? [[String: Any]] ?? []
        return rawItems.compactMap { item in
            guard item["type"] as? String == "timeEntry" else { return nil }
            guard let id = Self.integer(item["id"]),
                  let startsAt = item["startsAt"] as? String
            else {
                logger.warning("Skipping a Lucca entry without an id or start time")
                return nil
            }
            let durationObject = item["duration"] as? [String: Any]
            let durationSeconds = Self.durationSeconds(durationObject)
            return TimeEntry(
                id: id,
                ownerId: Self.integer(item["ownerId"]) ?? ownerId,
                unit: Self.timeEntryUnit(item["unit"]),
                startsAt: startsAt,
                duration: TimesheetMath.luccaDuration(from: durationSeconds),
                endsAt: item["endsAt"] as? String,
                archivedAt: nil,
                creationSource: Self.creationSource(item["creationSource"])
            )
        }
    }

    private func request(path: String, method: String = "GET", json: Any? = nil) async throws -> Data {
        let body = try json.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
        let script = """
        const options = {
          method: method,
          credentials: 'include',
          headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' }
        };
        const csrf = document.cookie.split('; ')
          .find(value => value.startsWith('XSRF-TOKEN='))
          ?.split('=').slice(1).join('=');
        if (csrf) options.headers['X-XSRF-TOKEN'] = decodeURIComponent(csrf);
        if (body !== null) options.body = body;
        const response = await fetch(path, options);
        const text = await response.text();
        return JSON.stringify({ ok: response.ok, status: response.status, body: text });
        """
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: ["path": path, "method": method, "body": body ?? NSNull()],
            in: nil,
            contentWorld: .page
        )
        guard let encoded = value as? String,
              let response = try? JSONDecoder().decode(BridgeResponse.self, from: Data(encoded.utf8))
        else { throw LuccaServiceError(message: "The Lucca page returned an unreadable response.") }
        logger.info("Lucca \(method, privacy: .public) \(path, privacy: .public) returned \(response.status, privacy: .public)")
        #if DEBUG
        print("YUCCA_DIAGNOSTIC request method=\(method) path=\(path) status=\(response.status) ok=\(response.ok)")
        #endif
        guard response.ok else {
            let detail = Self.serverMessage(from: response.body)
            throw LuccaServiceError(message: "Lucca returned \(response.status)\(detail.map { ": \($0)" } ?? "").")
        }
        return Data(response.body.utf8)
    }

    private func tenantURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = tenantHost
        components.path = path
        return components.url
    }

    private func handle(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        logger.error("Lucca refresh failed: \(String(reflecting: error), privacy: .public)")
        #if DEBUG
        print("YUCCA_DIAGNOSTIC refresh-failed \(String(reflecting: error))")
        #endif
        errorMessage = message
        if message.contains("401") || message.contains("403") || message.contains("signed-in user") {
            isSignedIn = false
            isShowingLogin = true
        }
    }

    private static func normalizedHost(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              let host = components.host,
              host.hasSuffix(".ilucca.net") || host.hasSuffix(".ilucca-test.net") || host.hasSuffix(".lucca.net")
        else {
            throw LuccaServiceError(message: "Enter a Lucca host such as company.ilucca.net.")
        }
        return host
    }

    private static func unwrapDataObject(_ object: Any) -> [String: Any]? {
        guard let dictionary = object as? [String: Any] else { return nil }
        let data = dictionary["data"] as? [String: Any] ?? dictionary
        if let first = (data["items"] as? [[String: Any]])?.first { return first }
        return data
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func durationSeconds(_ object: [String: Any]?) -> TimeInterval {
        guard let object,
              let number = object["value"] as? NSNumber
        else { return 0 }
        switch object["unit"] as? String {
        case "day": return number.doubleValue * 86_400
        case "minute": return number.doubleValue * 60
        case "second": return number.doubleValue
        default: return number.doubleValue * 3_600
        }
    }

    private static func timeEntryUnit(_ value: Any?) -> Int {
        if let integer = integer(value) { return integer }
        switch value as? String {
        case "day": return 0
        case "hour": return 1
        default: return 2
        }
    }

    private static func creationSource(_ value: Any?) -> Int? {
        if let integer = integer(value) { return integer }
        switch value as? String {
        case "automatic": return 0
        case "quickFill": return 1
        case "manual": return 2
        case "import": return 3
        case "clock": return 4
        default: return nil
        }
    }

    private static func serverMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return body.isEmpty ? nil : String(body.prefix(180)) }
        return object["Message"] as? String
            ?? object["message"] as? String
            ?? object["error"] as? String
    }
}

extension LuccaWebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host == tenantHost,
              webView.url?.path.contains("/identity/login") != true
        else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()
            if self?.isSignedIn == true { self?.isShowingLogin = false }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        errorMessage = error.localizedDescription
    }
}

struct LuccaWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
