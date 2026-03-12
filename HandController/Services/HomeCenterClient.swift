import Foundation

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

    // MARK: - Wake Word Recording

    struct WakeRecordStatus {
        var active: Bool
        var type: String
        var count: Int
    }

    /// Toggle wake word recording on/off.
    func toggleWakeRecord(type: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/wake-record") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: String] = ["action": "toggle", "type": type]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    /// Get current wake word recording status.
    func getWakeRecordStatus() async -> WakeRecordStatus? {
        guard let url = URL(string: "\(baseURL)/api/wake-record") else { return nil }
        var request = URLRequest(url: url)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let active = json["active"] as? Bool,
                  let type = json["type"] as? String,
                  let count = json["count"] as? Int else { return nil }
            return WakeRecordStatus(active: active, type: type, count: count)
        } catch {
            return nil
        }
    }

    /// Switch the sample type (positive/negative).
    func setWakeRecordType(_ type: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/wake-record") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: String] = ["action": "set_type", "type": type]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}
