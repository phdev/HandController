import Vision
import CoreGraphics

/// Classifies hand gestures using joint positions and temporal tracking.
///
/// Detects:
/// - Index finger + thumb pinch (spatial proximity)
/// - Middle finger + thumb pinch (spatial proximity)
/// - Wave left/right/up/down (tracked wrist movement over time)
final class GestureClassifier {
    private let pinchThreshold: CGFloat = 0.06
    private let waveMinDisplacement: CGFloat = 0.10
    private let waveWindowSize = 8
    private let waveDirectionRatio: CGFloat = 1.5

    // Thumb swipe detection parameters
    private let thumbSwipeMinDisplacement: CGFloat = 0.08
    private let thumbSwipeWindowSize = 6
    private let thumbSwipeDirectionRatio: CGFloat = 1.8

    // Track middleMCP positions per hand for wave detection.
    // Using middleMCP instead of wrist because the glasses camera often can't see the wrist.
    // Key is chirality string ("Left" or "Right").
    private var wristHistory: [String: [(position: CGPoint, time: CFAbsoluteTime)]] = [:]
    private var lastWaveTime: [String: CFAbsoluteTime] = [:]
    private let waveCooldown: CFAbsoluteTime = 1.0

    // Track thumb tip positions per hand for thumb swipe detection.
    private var thumbHistory: [String: [(position: CGPoint, time: CFAbsoluteTime)]] = [:]
    private var lastThumbSwipeTime: [String: CFAbsoluteTime] = [:]
    private let thumbSwipeCooldown: CFAbsoluteTime = 1.0

    /// Classify the gesture for a single detected hand.
    func classify(hand: DetectedHand) -> HandGesture {
        let joints = hand.joints
        let handKey = hand.chirality.rawValue

        // Check pinch gestures first (instantaneous, no temporal tracking needed)
        if let pinch = detectPinch(joints: joints) {
            return pinch
        }

        // Track thumb tip for swipe detection
        if let thumbTip = joints[.thumbTip] {
            trackThumb(position: thumbTip, handKey: handKey)

            if let swipe = detectThumbSwipe(handKey: handKey) {
                return swipe
            }
        }

        // Track middleMCP for wave detection (wrist is often out of frame on glasses camera)
        if let trackingJoint = joints[.middleMCP] ?? joints[.wrist] {
            trackWrist(position: trackingJoint, handKey: handKey)

            if let wave = detectWave(handKey: handKey) {
                return wave
            }
        }

        return .none
    }

    /// Reset tracking state (e.g., when streaming stops).
    func reset() {
        wristHistory.removeAll()
        lastWaveTime.removeAll()
        thumbHistory.removeAll()
        lastThumbSwipeTime.removeAll()
    }

    // MARK: - Pinch Detection

    private func detectPinch(joints: [VNHumanHandPoseObservation.JointName: CGPoint]) -> HandGesture? {
        guard let thumbTip = joints[.thumbTip] else { return nil }

        // Index-thumb pinch: thumb tip close to index tip
        if let indexTip = joints[.indexTip] {
            let dist = distance(thumbTip, indexTip)
            if dist < pinchThreshold {
                return .indexThumbPinch
            }
        }

        // Middle-thumb pinch: thumb tip close to middle tip
        if let middleTip = joints[.middleTip] {
            let dist = distance(thumbTip, middleTip)
            if dist < pinchThreshold {
                return .middleThumbPinch
            }
        }

        return nil
    }

    // MARK: - Wave Detection

    private func trackWrist(position: CGPoint, handKey: String) {
        let now = CFAbsoluteTimeGetCurrent()
        var history = wristHistory[handKey] ?? []
        history.append((position: position, time: now))

        // Keep only recent entries (last ~0.5 seconds at 24fps ≈ 12 frames)
        let cutoff = now - 0.6
        history = history.filter { $0.time > cutoff }

        // Cap at max window size
        if history.count > waveWindowSize * 2 {
            history = Array(history.suffix(waveWindowSize * 2))
        }

        wristHistory[handKey] = history
    }

    private func detectWave(handKey: String) -> HandGesture? {
        guard let history = wristHistory[handKey],
              history.count >= waveWindowSize else {
            return nil
        }

        // Cooldown: don't fire waves too frequently
        let now = CFAbsoluteTimeGetCurrent()
        if let lastWave = lastWaveTime[handKey], now - lastWave < waveCooldown {
            return nil
        }

        // Calculate total displacement from first to last tracked position
        let first = history.first!.position
        let last = history.last!.position
        let dx = last.x - first.x
        let dy = last.y - first.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        // Need significant displacement in one dominant axis
        let totalDisplacement = max(absDx, absDy)

        // DEBUG: log wrist displacement every ~0.5s to diagnose wave detection
        let debugKey = "waveDebug_\(handKey)"
        let lastDebug = lastWaveTime[debugKey] ?? 0
        if now - lastDebug > 0.5 {
            lastWaveTime[debugKey] = now
            print("[Wave] \(handKey) pts=\(history.count) dx=\(String(format: "%.3f", dx)) dy=\(String(format: "%.3f", dy)) disp=\(String(format: "%.3f", totalDisplacement)) need=\(String(format: "%.3f", waveMinDisplacement))")
        }

        guard totalDisplacement > waveMinDisplacement else { return nil }

        // One axis must dominate to distinguish direction
        let gesture: HandGesture
        if absDx > absDy * waveDirectionRatio {
            gesture = dx > 0 ? .waveRight : .waveLeft
        } else if absDy > absDx * waveDirectionRatio {
            // In screen coords: y increases downward
            gesture = dy > 0 ? .waveDown : .waveUp
        } else {
            print("[Wave] \(handKey) REJECTED: ratio too close dx=\(String(format: "%.3f", absDx)) dy=\(String(format: "%.3f", absDy)) ratio=\(String(format: "%.2f", waveDirectionRatio))")
            return nil
        }

        // Consume the wave: clear history and set cooldown
        lastWaveTime[handKey] = now
        wristHistory[handKey] = []

        print("[Wave] \(handKey) DETECTED: \(gesture.rawValue)")
        return gesture
    }

    // MARK: - Thumb Swipe Detection

    private func trackThumb(position: CGPoint, handKey: String) {
        let now = CFAbsoluteTimeGetCurrent()
        var history = thumbHistory[handKey] ?? []
        history.append((position: position, time: now))

        let cutoff = now - 0.5
        history = history.filter { $0.time > cutoff }

        if history.count > thumbSwipeWindowSize * 2 {
            history = Array(history.suffix(thumbSwipeWindowSize * 2))
        }

        thumbHistory[handKey] = history
    }

    private func detectThumbSwipe(handKey: String) -> HandGesture? {
        guard let history = thumbHistory[handKey],
              history.count >= thumbSwipeWindowSize else {
            return nil
        }

        let now = CFAbsoluteTimeGetCurrent()
        if let lastSwipe = lastThumbSwipeTime[handKey], now - lastSwipe < thumbSwipeCooldown {
            return nil
        }

        let first = history.first!.position
        let last = history.last!.position
        let dx = last.x - first.x
        let dy = last.y - first.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        let totalDisplacement = max(absDx, absDy)
        guard totalDisplacement > thumbSwipeMinDisplacement else { return nil }

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
