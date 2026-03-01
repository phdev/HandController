import Foundation
import Vision

/// Represents a detected hand with all joint positions and the recognized gesture.
struct DetectedHand: Identifiable {
    let id = UUID()
    let joints: [VNHumanHandPoseObservation.JointName: CGPoint]
    let gesture: HandGesture
    let confidence: Float
}

/// Supported hand gestures that the classifier can recognize.
enum HandGesture: String, CaseIterable {
    case openHand = "Open Hand"
    case fist = "Fist"
    case thumbsUp = "Thumbs Up"
    case thumbsDown = "Thumbs Down"
    case peace = "Peace"
    case pointingUp = "Pointing Up"
    case pinch = "Pinch"
    case unknown = "Unknown"

    var emoji: String {
        switch self {
        case .openHand: return "🖐"
        case .fist: return "✊"
        case .thumbsUp: return "👍"
        case .thumbsDown: return "👎"
        case .peace: return "✌️"
        case .pointingUp: return "☝️"
        case .pinch: return "🤏"
        case .unknown: return "❓"
        }
    }
}
