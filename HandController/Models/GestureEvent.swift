import Foundation

/// A gesture event that can be displayed in debug UI and sent to home-center.
struct GestureEvent: Identifiable, Codable {
    let id: String
    let gesture: HandGesture
    let hand: String
    let timestamp: Date
    let confidence: Float

    init(gesture: HandGesture, hand: String, confidence: Float) {
        self.id = "gesture_\(UUID().uuidString.prefix(8).lowercased())"
        self.gesture = gesture
        self.hand = hand
        self.timestamp = Date()
        self.confidence = confidence
    }

    /// Format as a home-center notification payload.
    var homeCenterPayload: [String: Any] {
        [
            "id": id,
            "type": "gesture",
            "category": "activities",
            "icon": gesture.emoji,
            "title": "\(hand) Hand: \(gesture.rawValue)",
            "from": "HandController",
            "timestamp": Int(timestamp.timeIntervalSince1970 * 1000)
        ]
    }
}

/// Protocol for consuming gesture events (used by home-center integration and other consumers).
protocol GestureEventDelegate: AnyObject {
    func didDetectGesture(_ event: GestureEvent)
}
