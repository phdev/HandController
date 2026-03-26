import Foundation

/// Observable log for wake-record network debugging. Visible in-app.
@MainActor
final class WakeRecordLog: ObservableObject {
    static let shared = WakeRecordLog()
    @Published var entries: [String] = []

    func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(ts)] \(message)"
        entries.append(entry)
        // Keep last 50 entries
        if entries.count > 50 { entries.removeFirst(entries.count - 50) }
        print("[WakeRecord] \(message)")
    }
}

/// REST API client for posting gesture events to the home-center dashboard.
///
/// Posts notifications to: POST /api/notifications
/// Docs: https://github.com/phdev/home-center
actor HomeCenterClient {
    static let defaultBaseURL = "https://home-center-api.phhowell.workers.dev"

    private let baseURL: String
    private var authToken: String?
    private let session: URLSession
    private let encoder = JSONEncoder()

    /// Minimum interval between sending the same gesture type to avoid flooding.
    private let throttleInterval: TimeInterval = 2.0
    private var lastSentTimes: [HandGesture: Date] = [:]

    var isEnabled: Bool = true

    init(baseURL: String = HomeCenterClient.defaultBaseURL, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken ?? Self.loadTokenFromSecrets()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    private static func loadTokenFromSecrets() -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return dict["HomeCenterAuthToken"] as? String
    }

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }

    /// Send a gesture event to home-center as a notification.
    /// Throttles per gesture type to avoid flooding the API.
    @discardableResult
    func sendGestureEvent(_ event: GestureEvent) async -> Bool {
        guard isEnabled else { return false }

        // Throttle: skip if we sent this gesture type recently
        if let lastSent = lastSentTimes[event.gesture],
           Date().timeIntervalSince(lastSent) < throttleInterval {
            return false
        }

        guard let url = URL(string: "\(baseURL)/api/notifications") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = event.homeCenterPayload
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                lastSentTimes[event.gesture] = Date()
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// Check connectivity to the home-center API.
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/health") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Wake Word Recording (Pi at http://homecenter.local:8765)

    static let piBaseURL = "http://homecenter.local:8765"

    struct WakeRecordStatus {
        var active: Bool
        var type: String
        var count: Int
        var totalPositive: Int
        var totalNegative: Int
    }

    /// Parse a Pi response into WakeRecordStatus.
    private func parseStatus(from data: Data) -> WakeRecordStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = json["active"] as? Bool,
              let type = json["type"] as? String,
              let count = json["count"] as? Int else { return nil }
        return WakeRecordStatus(
            active: active, type: type, count: count,
            totalPositive: json["totalPositive"] as? Int ?? 0,
            totalNegative: json["totalNegative"] as? Int ?? 0
        )
    }

    /// GET /status from the Pi.
    func getWakeRecordStatus() async -> WakeRecordStatus? {
        guard let url = URL(string: "\(Self.piBaseURL)/status") else { return nil }
        await WakeRecordLog.shared.log("GET \(url)")
        do {
            let (data, response) = try await session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            await WakeRecordLog.shared.log("GET /status → \(code) \(body)")
            guard code >= 200, code < 300 else { return nil }
            return parseStatus(from: data)
        } catch {
            await WakeRecordLog.shared.log("GET /status FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    /// POST to a Pi endpoint with optional JSON body. Returns parsed status.
    private func postPi(_ path: String, body: [String: String]? = nil) async -> WakeRecordStatus? {
        guard let url = URL(string: "\(Self.piBaseURL)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            request.httpBody = data
        }
        await WakeRecordLog.shared.log("POST \(url)")
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            await WakeRecordLog.shared.log("POST \(path) → \(code) \(body)")
            guard code >= 200, code < 300 else { return nil }
            return parseStatus(from: data)
        } catch {
            await WakeRecordLog.shared.log("POST \(path) FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    /// Toggle recording on/off on the Pi.
    func toggleWakeRecord(type: String) async -> WakeRecordStatus? {
        await postPi("/toggle", body: ["type": type])
    }

    /// Reset cumulative totals on the Pi.
    func resetWakeRecordTotals() async -> WakeRecordStatus? {
        await postPi("/reset")
    }

    /// Clear all recordings and delete saved audio files on the Pi.
    func clearRecordings() async -> WakeRecordStatus? {
        await postPi("/clear")
    }
}
