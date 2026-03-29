import Vision
import CoreGraphics

/// Classifies hand gestures using joint positions and temporal tracking.
///
/// Detects:
/// - Index finger + thumb pinch (spatial proximity)
/// - Middle finger + thumb pinch (spatial proximity)
/// - Thumb swipe left/right/up/down (thumb tip crosses over index knuckle)
final class GestureClassifier {
    private let pinchThreshold: CGFloat = 0.06

    // Thumb swipe: detect when thumb tip crosses the index knuckle (indexMCP).
    // Track which side of the knuckle the thumb is on each frame.
    // When it crosses from one side to the other, that's a swipe.
    private let thumbSwipeCooldown: CFAbsoluteTime = 1.0
    private var lastThumbSide: [String: ThumbSide] = [:]
    private var lastSwipeTime: [String: CFAbsoluteTime] = [:]

    private struct ThumbSide {
        var xSide: Int  // -1 = left of indexMCP, +1 = right
        var ySide: Int  // -1 = above indexMCP, +1 = below (screen coords: y down)
    }

    /// Classify the gesture for a single detected hand.
    func classify(hand: DetectedHand) -> HandGesture {
        let joints = hand.joints
        let handKey = hand.chirality.rawValue

        // 1. Pinch (instantaneous)
        if let pinch = detectPinch(joints: joints) {
            return pinch
        }

        // 2. Thumb swipe (thumb tip crosses index knuckle)
        if let swipe = detectThumbSwipe(joints: joints, handKey: handKey) {
            return swipe
        }

        return .none
    }

    /// Reset tracking state (e.g., when streaming stops).
    func reset() {
        lastThumbSide.removeAll()
        lastSwipeTime.removeAll()
    }

    // MARK: - Pinch Detection

    private func detectPinch(joints: [VNHumanHandPoseObservation.JointName: CGPoint]) -> HandGesture? {
        guard let thumbTip = joints[.thumbTip] else { return nil }

        if let indexTip = joints[.indexTip], distance(thumbTip, indexTip) < pinchThreshold {
            return .indexThumbPinch
        }
        if let middleTip = joints[.middleTip], distance(thumbTip, middleTip) < pinchThreshold {
            return .middleThumbPinch
        }
        return nil
    }

    // MARK: - Thumb Swipe Detection (crossing-based)

    private func detectThumbSwipe(joints: [VNHumanHandPoseObservation.JointName: CGPoint], handKey: String) -> HandGesture? {
        guard let thumbTip = joints[.thumbTip],
              let indexMCP = joints[.indexMCP] else { return nil }

        // Ignore if thumb is too close to indexMCP (near pinch territory — noisy)
        guard distance(thumbTip, indexMCP) > 0.03 else { return nil }

        let now = CFAbsoluteTimeGetCurrent()
        let currentX = thumbTip.x < indexMCP.x ? -1 : 1
        let currentY = thumbTip.y < indexMCP.y ? -1 : 1
        let current = ThumbSide(xSide: currentX, ySide: currentY)

        guard let prev = lastThumbSide[handKey] else {
            // First frame — just record the side
            lastThumbSide[handKey] = current
            return nil
        }

        lastThumbSide[handKey] = current

        // Cooldown
        if let last = lastSwipeTime[handKey], now - last < thumbSwipeCooldown {
            return nil
        }

        // Check for a crossing
        let gesture: HandGesture?
        if prev.xSide != current.xSide {
            // Horizontal crossing
            gesture = current.xSide > 0 ? .thumbSwipeRight : .thumbSwipeLeft
        } else if prev.ySide != current.ySide {
            // Vertical crossing
            gesture = current.ySide > 0 ? .thumbSwipeDown : .thumbSwipeUp
        } else {
            gesture = nil
        }

        if gesture != nil {
            lastSwipeTime[handKey] = now
            print("[ThumbSwipe] \(handKey) DETECTED: \(gesture!.rawValue) thumb=(\(String(format: "%.3f", thumbTip.x)),\(String(format: "%.3f", thumbTip.y))) indexMCP=(\(String(format: "%.3f", indexMCP.x)),\(String(format: "%.3f", indexMCP.y)))")
        }

        return gesture
    }

    // MARK: - Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
