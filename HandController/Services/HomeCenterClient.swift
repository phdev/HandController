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

    var isEnabled: Bool = false

    init(baseURL: String = HomeCenterClient.defaultBaseURL, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
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
}
