import Vision
import UIKit

/// Processes images using Vision's VNDetectHumanHandPoseRequest to detect hand landmarks.
/// Supports both CMSampleBuffer (from DAT SDK raw frames) and UIImage input.
final class HandPoseDetector {
    private let request: VNDetectHumanHandPoseRequest
    private let processingQueue = DispatchQueue(label: "com.handcontroller.handpose", qos: .userInitiated)

    init(maxHands: Int = 2) {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maxHands
    }

    /// Detect hands from a UIImage (from DAT SDK's VideoFrame.makeUIImage()).
    func detectHands(in image: UIImage) -> [DetectedHand] {
        guard let cgImage = image.cgImage else { return [] }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        return performDetection(with: handler)
    }

    /// Detect hands from a CVPixelBuffer (from DAT SDK's VideoFrame.sampleBuffer).
    func detectHands(in pixelBuffer: CVPixelBuffer) -> [DetectedHand] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        return performDetection(with: handler)
    }

    private func performDetection(with handler: VNImageRequestHandler) -> [DetectedHand] {
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.enumerated().compactMap { index, observation in
            parseObservation(observation, index: index)
        }
    }

    private func parseObservation(_ observation: VNHumanHandPoseObservation, index: Int) -> DetectedHand? {
        var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]

        for jointName in HandSkeleton.allJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.3 else {
                continue
            }
            // Vision: origin at bottom-left, y up. Convert to top-left, y down.
            joints[jointName] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }

        guard joints.count >= 10 else { return nil }

        // Determine chirality from observation if available (iOS 17+),
        // otherwise infer from wrist position (left side of image = right hand from camera POV).
        let chirality: DetectedHand.Chirality
        if #available(iOS 17.0, *) {
            switch observation.chirality {
            case .left: chirality = .left
            case .right: chirality = .right
            default: chirality = index == 0 ? .left : .right
            }
        } else {
            if let wrist = joints[.wrist] {
                chirality = wrist.x < 0.5 ? .right : .left
            } else {
                chirality = .unknown
            }
        }

        return DetectedHand(
            chirality: chirality,
            joints: joints,
            confidence: observation.confidence
        )
    }
}
