import AVFoundation
import UIKit

/// Manages the AVCaptureSession for real-time camera input.
final class CameraService: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.handcontroller.camera")

    var onFrameCaptured: ((CMSampleBuffer) -> Void)?

    @Published var isCameraAuthorized = false
    @Published var isRunning = false

    override init() {
        super.init()
    }

    func requestAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.isCameraAuthorized = true }
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.isCameraAuthorized = granted }
                if granted { self.configureSession() }
            }
        default:
            DispatchQueue.main.async { self.isCameraAuthorized = false }
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.handcontroller.videoOutput"))

            guard self.captureSession.canAddOutput(output) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addOutput(output)

            if let connection = output.connection(with: .video) {
                connection.videoOrientation = .portrait
            }

            self.captureSession.commitConfiguration()
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onFrameCaptured?(sampleBuffer)
    }
}
