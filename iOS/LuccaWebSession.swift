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
    private let logger = Logger(subsystem: "de.ndurner.yucca", category: "Lucca")
    @Published private(set) var snapshot = DashboardSnapshot.empty
    @Published private(set) var isSignedIn = false
    @Published private(set) var isBusy = false
    @Published private(set) var userName = ""
    @Published var errorMessage: String?
    @Published var isShowingLogin = false

    let webView: WKWebView
    private(set) var tenantHost: String
    private var currentUser: LuccaUser?
    private var refreshTask: Task<Void, Never>?

    override init() {
        tenantHost = UserDefaults.standard.string(forKey: "tenantHost") ?? ""
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
            snapshot = TimesheetMath.snapshot(entries: entries)
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
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let user: LuccaUser
            if let currentUser { user = currentUser }
            else { user = try await fetchCurrentUser() }
            let entries = try await fetchWeekEntries(ownerId: user.id)
            if let active = TimesheetMath.activeEntry(in: entries) {
                try await leave(active: active, ownerId: user.id)
            } else {
                try await enter(ownerId: user.id)
            }
            let updated = try await fetchWeekEntries(ownerId: user.id)
            snapshot = TimesheetMath.snapshot(entries: updated)
            isSignedIn = true
            errorMessage = nil
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
        webView.loadHTMLString("", baseURL: nil)
    }

    func forgetTenant() {
        signOut()
        tenantHost = ""
        UserDefaults.standard.removeObject(forKey: "tenantHost")
    }

    private func enter(ownerId: Int) async throws {
        let now = Date()
        let payload: [String: Any] = [
            "ownerId": ownerId,
            "unit": 2,
            "startsAt": LuccaDateCodec.string(from: now),
            "duration": "00:00:00",
            "creationSource": 4,
            "axisSections": []
        ]
        do {
            _ = try await request(path: "/api/v3/timeentries", method: "POST", json: payload)
        } catch let error as LuccaServiceError where error.message.contains("creationSource") {
            var compatiblePayload = payload
            compatiblePayload["creationSource"] = 2
            _ = try await request(path: "/api/v3/timeentries", method: "POST", json: compatiblePayload)
        }
    }

    private func leave(active: TimeEntry, ownerId: Int) async throws {
        guard let start = active.startsAtDate(), Calendar.current.isDateInToday(start) else {
            throw LuccaServiceError(message: "Only an entry started today can be stopped.")
        }
        let payload: [String: Any] = [
            "ownerId": ownerId,
            "unit": 2,
            "startsAt": active.startsAt,
            "duration": TimesheetMath.luccaDuration(from: Date().timeIntervalSince(start)),
            "creationSource": active.creationSource ?? 4,
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

    private func fetchWeekEntries(ownerId: Int) async throws -> [TimeEntry] {
        let week = TimesheetMath.weekInterval(containing: .now)
        let dayAfterToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        let end = min(week.end, dayAfterToday)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = .current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents()
        components.path = "/api/v3/timeentries"
        components.queryItems = [
            URLQueryItem(name: "ownerId", value: String(ownerId)),
            URLQueryItem(name: "startsAt", value: "between,\(dateFormatter.string(from: week.start)),\(dateFormatter.string(from: end))"),
            URLQueryItem(name: "paging", value: "0,1000")
        ]
        let data = try await request(path: components.string ?? "/api/v3/timeentries")
        let root = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = root as? [String: Any] else { return [] }
        let dataObject = dictionary["data"] as? [String: Any] ?? dictionary
        let rawItems = dataObject["items"] as? [[String: Any]] ?? []
        return rawItems.compactMap { item in
            guard let id = Self.integer(item["id"]),
                  let startsAt = item["startsAt"] as? String
            else {
                logger.warning("Skipping a Lucca entry without an id or start time")
                return nil
            }
            return TimeEntry(
                id: id,
                ownerId: Self.integer(item["ownerId"]) ?? ownerId,
                unit: Self.integer(item["unit"]) ?? 2,
                startsAt: startsAt,
                duration: item["duration"] as? String ?? "00:00:00",
                endsAt: item["endsAt"] as? String,
                archivedAt: item["archivedAt"] as? String,
                creationSource: Self.integer(item["creationSource"])
            )
        }
    }

    private func request(path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
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
