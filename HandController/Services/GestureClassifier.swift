import Vision
import CoreGraphics

/// Classifies hand gestures using joint positions and temporal tracking.
///
/// Detects:
/// - Index finger + thumb pinch (spatial proximity)
/// - Middle finger + thumb pinch (spatial proximity)
/// - Thumb swipe left/right/up/down (tracked thumb tip movement)
/// - Wave left/right/up/down (centroid of all joints — immune to pinch/finger noise)
final class GestureClassifier {
    private let pinchThreshold: CGFloat = 0.06

    // Wave detection: track centroid of ALL visible joints.
    // Pinch moves fingers toward each other — centroid barely shifts.
    // Wave translates the whole hand — centroid moves a lot.
    private let waveMinDisplacement: CGFloat = 0.20
    private let waveDirectionRatio: CGFloat = 1.5
    private let waveCooldown: CFAbsoluteTime = 1.5
    private let waveWindowSeconds: CFAbsoluteTime = 0.6
    private var centroidHistory: [String: [(position: CGPoint, time: CFAbsoluteTime)]] = [:]
    private var lastWaveTime: [String: CFAbsoluteTime] = [:]

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

        // Always track centroid and thumb every frame
        trackCentroid(joints: joints, handKey: handKey, now: now)
        if let thumbTip = joints[.thumbTip] {
            appendThumb(thumbTip, handKey: handKey, now: now)
        }

        // 1. Pinch (instantaneous) — clear wave history to prevent false waves
        if let pinch = detectPinch(joints: joints) {
            centroidHistory[handKey] = []
            return pinch
        }

        // 2. Thumb swipe (temporal)
        if let swipe = detectThumbSwipe(handKey: handKey, now: now) {
            return swipe
        }

        // 3. Wave (temporal, centroid-based)
        if let wave = detectWave(handKey: handKey, now: now) {
            return wave
        }

        return .none
    }

    /// Reset tracking state (e.g., when streaming stops).
    func reset() {
        centroidHistory.removeAll()
        lastWaveTime.removeAll()
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

    // MARK: - Wave Detection (centroid-based)

    private func trackCentroid(joints: [VNHumanHandPoseObservation.JointName: CGPoint], handKey: String, now: CFAbsoluteTime) {
        guard !joints.isEmpty else { return }

        // Average of ALL visible joint positions
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for point in joints.values {
            sumX += point.x
            sumY += point.y
        }
        let count = CGFloat(joints.count)
        let centroid = CGPoint(x: sumX / count, y: sumY / count)

        var history = centroidHistory[handKey] ?? []
        history.append((position: centroid, time: now))
        // Keep only the wave window
        history = history.filter { now - $0.time < waveWindowSeconds }
        centroidHistory[handKey] = history
    }

    private func detectWave(handKey: String, now: CFAbsoluteTime) -> HandGesture? {
        guard let history = centroidHistory[handKey], history.count >= 4 else { return nil }

        if let last = lastWaveTime[handKey], now - last < waveCooldown { return nil }

        // Need at least 0.2s of data to avoid jitter
        let timeSpan = history.last!.time - history.first!.time
        guard timeSpan >= 0.2 else { return nil }

        let first = history.first!.position
        let last = history.last!.position
        let dx = last.x - first.x
        let dy = last.y - first.y
        let absDx = abs(dx)
        let absDy = abs(dy)
        let disp = max(absDx, absDy)

        guard disp > waveMinDisplacement else { return nil }

        let gesture: HandGesture
        if absDx > absDy * waveDirectionRatio {
            gesture = dx > 0 ? .waveRight : .waveLeft
        } else if absDy > absDx * waveDirectionRatio {
            gesture = dy > 0 ? .waveDown : .waveUp
        } else {
            return nil
        }

        lastWaveTime[handKey] = now
        centroidHistory[handKey] = []
        print("[Wave] \(handKey) DETECTED: \(gesture.rawValue) dx=\(String(format: "%.3f", dx)) dy=\(String(format: "%.3f", dy)) span=\(String(format: "%.2f", timeSpan))s")
        return gesture
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
