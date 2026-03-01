import SwiftUI
import Combine

/// ViewModel that coordinates the camera service and hand pose detector,
/// publishing detected hands and gesture information for the UI.
@MainActor
final class HandGestureViewModel: ObservableObject {
    @Published var detectedHands: [DetectedHand] = []
    @Published var currentGesture: HandGesture = .unknown
    @Published var fps: Int = 0

    let cameraService = CameraService()
    private let handPoseDetector = HandPoseDetector()

    private var frameCount = 0
    private var lastFPSUpdate = Date()

    func start() {
        cameraService.onFrameCaptured = { [weak self] sampleBuffer in
            guard let self else { return }
            let hands = self.handPoseDetector.detectHands(in: sampleBuffer)

            Task { @MainActor in
                self.detectedHands = hands
                self.currentGesture = hands.first?.gesture ?? .unknown
                self.updateFPS()
            }
        }
        cameraService.requestAuthorization()
        cameraService.start()
    }

    func stop() {
        cameraService.stop()
    }

    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            fps = Int(Double(frameCount) / elapsed)
            frameCount = 0
            lastFPSUpdate = now
        }
    }
}
