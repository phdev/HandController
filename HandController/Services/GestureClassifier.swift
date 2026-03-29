import Vision
import CoreGraphics

/// Classifies hand gestures using joint positions and temporal tracking.
///
/// Detects:
/// - Index finger + thumb pinch (spatial proximity)
/// - Middle finger + thumb pinch (spatial proximity)
/// - Thumb swipe left/right/up/down (relative thumb-to-knuckle offset change over time)
final class GestureClassifier {
    private let pinchThreshold: CGFloat = 0.06

    // Thumb swipe: track the relative offset of thumbTip from indexMCP over time.
    // This is immune to overall hand movement — only the thumb's motion relative
    // to the hand matters. Detect when the offset changes significantly.
    private let swipeMinDelta: CGFloat = 0.06
    private let swipeDirectionRatio: CGFloat = 1.5
    private let swipeCooldown: CFAbsoluteTime = 1.0
    private let swipeWindowSeconds: CFAbsoluteTime = 0.5
    private var offsetHistory: [String: [(offset: CGPoint, time: CFAbsoluteTime)]] = [:]
    private var lastSwipeTime: [String: CFAbsoluteTime] = [:]

    /// Classify the gesture for a single detected hand.
    func classify(hand: DetectedHand) -> HandGesture {
        let joints = hand.joints
        let handKey = hand.chirality.rawValue
        let now = CFAbsoluteTimeGetCurrent()

        // Always track thumb offset every frame
        if let thumbTip = joints[.thumbTip], let indexMCP = joints[.indexMCP] {
            let offset = CGPoint(x: thumbTip.x - indexMCP.x, y: thumbTip.y - indexMCP.y)
            appendOffset(offset, handKey: handKey, now: now)
        }

        // 1. Pinch (instantaneous)
        if let pinch = detectPinch(joints: joints) {
            // Clear swipe history so pinch motion doesn't trigger a false swipe
            offsetHistory[handKey] = []
            return pinch
        }

        // 2. Thumb swipe (relative offset change)
        if let swipe = detectThumbSwipe(handKey: handKey, now: now) {
            return swipe
        }

        return .none
    }

    /// Reset tracking state (e.g., when streaming stops).
    func reset() {
        offsetHistory.removeAll()
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

    // MARK: - Thumb Swipe Detection (relative offset tracking)

    private func appendOffset(_ offset: CGPoint, handKey: String, now: CFAbsoluteTime) {
        var history = offsetHistory[handKey] ?? []
        history.append((offset: offset, time: now))
        history = history.filter { now - $0.time < swipeWindowSeconds }
        offsetHistory[handKey] = history
    }

    private func detectThumbSwipe(handKey: String, now: CFAbsoluteTime) -> HandGesture? {
        guard let history = offsetHistory[handKey], history.count >= 3 else { return nil }

        if let last = lastSwipeTime[handKey], now - last < swipeCooldown { return nil }

        // Compare earliest and latest offset in the window
        let first = history.first!.offset
        let last = history.last!.offset
        let dx = last.x - first.x  // how much thumb moved relative to knuckle (x)
        let dy = last.y - first.y  // how much thumb moved relative to knuckle (y)
        let absDx = abs(dx)
        let absDy = abs(dy)
        let disp = max(absDx, absDy)

        guard disp > swipeMinDelta else { return nil }

        let gesture: HandGesture
        if absDx > absDy * swipeDirectionRatio {
            gesture = dx > 0 ? .thumbSwipeRight : .thumbSwipeLeft
        } else if absDy > absDx * swipeDirectionRatio {
            gesture = dy > 0 ? .thumbSwipeDown : .thumbSwipeUp
        } else {
            return nil
        }

        lastSwipeTime[handKey] = now
        offsetHistory[handKey] = []
        print("[ThumbSwipe] \(handKey) DETECTED: \(gesture.rawValue) dx=\(String(format: "%.3f", dx)) dy=\(String(format: "%.3f", dy))")
        return gesture
    }

    // MARK: - Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
