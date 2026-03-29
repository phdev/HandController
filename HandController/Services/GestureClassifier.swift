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
    // The thumb must be at least `swipeDeadZone` away from the knuckle on a given
    // axis before we commit to a side. This prevents jitter near the boundary.
    private let thumbSwipeCooldown: CFAbsoluteTime = 1.0
    private let swipeDeadZone: CGFloat = 0.03  // must be this far from knuckle to commit
    private var committedSide: [String: ThumbSide] = [:]
    private var lastSwipeTime: [String: CFAbsoluteTime] = [:]

    private struct ThumbSide: Equatable {
        var xSide: Int  // -1 = left of indexMCP, 0 = in dead zone, +1 = right
        var ySide: Int  // -1 = above indexMCP, 0 = in dead zone, +1 = below
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
        committedSide.removeAll()
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

        let now = CFAbsoluteTimeGetCurrent()
        let dx = thumbTip.x - indexMCP.x
        let dy = thumbTip.y - indexMCP.y

        // Compute current side per axis (0 = in dead zone, won't trigger a crossing)
        let currentX: Int = abs(dx) > swipeDeadZone ? (dx > 0 ? 1 : -1) : 0
        let currentY: Int = abs(dy) > swipeDeadZone ? (dy > 0 ? 1 : -1) : 0

        guard let prev = committedSide[handKey] else {
            committedSide[handKey] = ThumbSide(xSide: currentX, ySide: currentY)
            return nil
        }

        // Only update committed side when thumb is outside dead zone on that axis
        var updated = prev
        if currentX != 0 { updated.xSide = currentX }
        if currentY != 0 { updated.ySide = currentY }
        committedSide[handKey] = updated

        // Cooldown
        if let last = lastSwipeTime[handKey], now - last < thumbSwipeCooldown {
            return nil
        }

        // Detect crossing: prev committed side must be nonzero and different from current
        let xCrossed = prev.xSide != 0 && currentX != 0 && prev.xSide != currentX
        let yCrossed = prev.ySide != 0 && currentY != 0 && prev.ySide != currentY

        let gesture: HandGesture?
        if xCrossed && yCrossed {
            // Both axes crossed — pick the one with larger offset (more intentional)
            if abs(dx) > abs(dy) {
                gesture = currentX > 0 ? .thumbSwipeRight : .thumbSwipeLeft
            } else {
                gesture = currentY > 0 ? .thumbSwipeDown : .thumbSwipeUp
            }
        } else if xCrossed {
            gesture = currentX > 0 ? .thumbSwipeRight : .thumbSwipeLeft
        } else if yCrossed {
            gesture = currentY > 0 ? .thumbSwipeDown : .thumbSwipeUp
        } else {
            return nil
        }

        lastSwipeTime[handKey] = now
        print("[ThumbSwipe] \(handKey) DETECTED: \(gesture!.rawValue) dx=\(String(format: "%.3f", dx)) dy=\(String(format: "%.3f", dy))")
        return gesture
    }

    // MARK: - Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
