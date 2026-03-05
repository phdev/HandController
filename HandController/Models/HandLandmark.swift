import Foundation
import Vision

// MARK: - Detected Hand

struct DetectedHand: Identifiable {
    let id = UUID()
    let chirality: Chirality
    let joints: [VNHumanHandPoseObservation.JointName: CGPoint]
    let confidence: Float

    enum Chirality: String {
        case left = "Left"
        case right = "Right"
        case unknown = "Unknown"
    }
}

// MARK: - Gesture Types

enum HandGesture: String, CaseIterable, Codable {
    case waveLeft = "Wave Left"
    case waveRight = "Wave Right"
    case waveUp = "Wave Up"
    case waveDown = "Wave Down"
    case thumbSwipeLeft = "Thumb Swipe Left"
    case thumbSwipeRight = "Thumb Swipe Right"
    case thumbSwipeUp = "Thumb Swipe Up"
    case thumbSwipeDown = "Thumb Swipe Down"
    case indexThumbPinch = "Index-Thumb Pinch"
    case middleThumbPinch = "Middle-Thumb Pinch"
    case none = "None"

    var icon: String {
        switch self {
        case .waveLeft: return "hand.point.left.fill"
        case .waveRight: return "hand.point.right.fill"
        case .waveUp: return "hand.point.up.fill"
        case .waveDown: return "hand.point.down.fill"
        case .thumbSwipeLeft: return "hand.thumbsdown.fill"
        case .thumbSwipeRight: return "hand.thumbsup.fill"
        case .thumbSwipeUp: return "hand.thumbsup.fill"
        case .thumbSwipeDown: return "hand.thumbsdown.fill"
        case .indexThumbPinch: return "hand.pinch"
        case .middleThumbPinch: return "hand.pinch"
        case .none: return "hand.raised"
        }
    }

    var emoji: String {
        switch self {
        case .waveLeft: return "👈"
        case .waveRight: return "👉"
        case .waveUp: return "👆"
        case .waveDown: return "👇"
        case .thumbSwipeLeft: return "👈"
        case .thumbSwipeRight: return "👉"
        case .thumbSwipeUp: return "👍"
        case .thumbSwipeDown: return "👎"
        case .indexThumbPinch: return "🤏"
        case .middleThumbPinch: return "🤌"
        case .none: return "✋"
        }
    }

    var color: String {
        switch self {
        case .waveLeft: return "#FF6B6B"
        case .waveRight: return "#4ECDC4"
        case .waveUp: return "#45B7D1"
        case .waveDown: return "#96CEB4"
        case .thumbSwipeLeft: return "#E74C3C"
        case .thumbSwipeRight: return "#2ECC71"
        case .thumbSwipeUp: return "#3498DB"
        case .thumbSwipeDown: return "#E67E22"
        case .indexThumbPinch: return "#FFEAA7"
        case .middleThumbPinch: return "#DDA0DD"
        case .none: return "#999999"
        }
    }
}

// MARK: - Bone Connections

struct HandSkeleton {
    static let boneConnections: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
        // Thumb
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        // Index
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        // Middle
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        // Ring
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        // Little
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        // Palm
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP),
        (.thumbCMC, .indexMCP)
    ]

    static let allJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]
}
