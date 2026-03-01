import Vision
import CoreMedia
import UIKit

/// Processes camera frames using Vision's VNDetectHumanHandPoseRequest to detect hand landmarks.
final class HandPoseDetector {
    private let request = VNDetectHumanHandPoseRequest()
    private let gestureClassifier = GestureClassifier()

    init() {
        request.maximumHandCount = 2
    }

    /// Processes a sample buffer and returns detected hands with their gestures.
    func detectHands(in sampleBuffer: CMSampleBuffer) -> [DetectedHand] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return []
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else {
            return []
        }

        return observations.compactMap { observation in
            parseObservation(observation)
        }
    }

    private func parseObservation(_ observation: VNHumanHandPoseObservation) -> DetectedHand? {
        let allJoints: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]

        for jointName in allJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.3 else {
                continue
            }
            // Vision coordinates: origin at bottom-left, y goes up.
            // Convert to UIKit coordinates: origin at top-left, y goes down.
            joints[jointName] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }

        guard joints.count >= 10 else { return nil }

        let gesture = gestureClassifier.classify(joints: joints)
        let avgConfidence = observation.confidence

        return DetectedHand(joints: joints, gesture: gesture, confidence: avgConfidence)
    }
}
