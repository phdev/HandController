import Vision
import CoreGraphics

/// Classifies hand gestures using joint positions and temporal tracking.
///
/// Detects:
/// - Index finger + thumb pinch (spatial proximity)
/// - Middle finger + thumb pinch (spatial proximity)
/// - Thumb swipe left/right/up/down (tracked thumb tip movement)
final class GestureClassifier {
    private let pinchThreshold: CGFloat = 0.06

    // Thumb swipe detection
    private let thumbSwipeMinDisplacement: CGFloat = 0.08
    private let thumbSwipeDirectionRatio: CGFloat = 1.8
    private let thumbSwipeCooldown: CFAbsoluteTime = 1.0
    private var thumbHistory: [String: [(position: CGPoint, time: CFAbsoluteTime)]] = [:]
    private var lastThumbSwipeTime: [String: CFAbsoluteTime] = [:]

    /// Classify the gesture for a single detected hand.
    func classify(hand: DetectedHand) -> HandGesture {
        let joints = hand.joints
        let handKey = hand.chirality.rawValue
        let now = CFAbsoluteTimeGetCurrent()

        // Track thumb every frame
        if let thumbTip = joints[.thumbTip] {
            appendThumb(thumbTip, handKey: handKey, now: now)
        }

        // 1. Pinch (instantaneous)
        if let pinch = detectPinch(joints: joints) {
            return pinch
        }

        // 2. Thumb swipe (temporal)
        if let swipe = detectThumbSwipe(handKey: handKey, now: now) {
            return swipe
        }

        return .none
    }

    /// Reset tracking state (e.g., when streaming stops).
    func reset() {
        thumbHistory.removeAll()
        lastThumbSwipeTime.removeAll()
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

    // MARK: - Thumb Swipe Detection

    private func appendThumb(_ position: CGPoint, handKey: String, now: CFAbsoluteTime) {
        var history = thumbHistory[handKey] ?? []
        history.append((position: position, time: now))
        history = history.filter { now - $0.time < 0.5 }
        thumbHistory[handKey] = history
    }

    private func detectThumbSwipe(handKey: String, now: CFAbsoluteTime) -> HandGesture? {
        guard let history = thumbHistory[handKey], history.count >= 6 else { return nil }

        if let last = lastThumbSwipeTime[handKey], now - last < thumbSwipeCooldown { return nil }

        let first = history.first!.position
        let last = history.last!.position
        let dx = last.x - first.x
        let dy = last.y - first.y
        let absDx = abs(dx)
        let absDy = abs(dy)
        let disp = max(absDx, absDy)

        guard disp > thumbSwipeMinDisplacement else { return nil }

        let gesture: HandGesture
        if absDx > absDy * thumbSwipeDirectionRatio {
            gesture = dx > 0 ? .thumbSwipeRight : .thumbSwipeLeft
        } else if absDy > absDx * thumbSwipeDirectionRatio {
            gesture = dy > 0 ? .thumbSwipeDown : .thumbSwipeUp
        } else {
            return nil
        }

        lastThumbSwipeTime[handKey] = now
        thumbHistory[handKey] = []
        return gesture
    }

    // MARK: - Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
