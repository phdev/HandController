import CoreMedia
import MWDATCore
import MWDATCamera
import SwiftUI
import Vision

/// Coordinates DAT SDK streaming with Vision hand pose detection and gesture classification.
@MainActor
final class StreamViewModel: ObservableObject {
    // MARK: - Published State

    @Published var currentFrame: UIImage?
    @Published var detectedHands: [DetectedHand] = []
    @Published var leftHandGesture: HandGesture = .none
    @Published var rightHandGesture: HandGesture = .none
    @Published var gestureEvents: [GestureEvent] = []
    @Published var streamingStatus: StreamingStatus = .stopped
    @Published var hasActiveDevice: Bool = false
    @Published var fps: Int = 0
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    enum StreamingStatus: String {
        case streaming = "Streaming"
        case waiting = "Waiting"
        case stopped = "Stopped"
    }

    var isStreaming: Bool { streamingStatus != .stopped }

    // MARK: - Services

    private let handPoseDetector = HandPoseDetector(maxHands: 2)
    private let gestureClassifier = GestureClassifier()
    let homeCenterClient: HomeCenterClient

    // MARK: - DAT SDK

    private var streamSession: StreamSession
    private let wearables: WearablesInterface
    private let deviceSelector: AutoDeviceSelector

    // MARK: - Listener Tokens

    private var stateToken: AnyListenerToken?
    private var frameToken: AnyListenerToken?
    private var errorToken: AnyListenerToken?
    private var deviceMonitorTask: Task<Void, Never>?

    // MARK: - Frame Processing

    private let processingQueue = DispatchQueue(label: "com.handcontroller.processing", qos: .userInitiated)
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    /// Atomic flag for frame skipping — accessed from processingQueue only.
    private nonisolated(unsafe) var _isProcessingFrame = false

    /// Maximum number of gesture events to keep in the debug log.
    private let maxEventHistory = 50

    // MARK: - Init

    init(wearables: WearablesInterface, homeCenterClient: HomeCenterClient = HomeCenterClient()) {
        self.wearables = wearables
        self.homeCenterClient = homeCenterClient
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        // Lower resolution + frame rate = less Bluetooth bandwidth pressure,
        // fewer ABR compression artifacts, and higher per-frame quality.
        let config = StreamSessionConfig(
            videoCodec: VideoCodec.raw,
            resolution: StreamingResolution.low,
            frameRate: 7
        )
        self.streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

        setupListeners()
    }

    // MARK: - Setup

    private func setupListeners() {
        // Monitor device availability
        deviceMonitorTask = Task { @MainActor in
            for await device in deviceSelector.activeDeviceStream() {
                self.hasActiveDevice = device != nil
            }
        }

        // Stream state changes
        stateToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleStateChange(state)
            }
        }

        // Video frames → hand detection pipeline
        frameToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            guard let self else { return }

            // Skip entire frame (including UIImage conversion) if still processing previous
            guard !self._isProcessingFrame else { return }
            self._isProcessingFrame = true

            let sampleBuffer = videoFrame.sampleBuffer
            let displayImage = videoFrame.makeUIImage()

            self.processingQueue.async { [weak self] in
                guard let self else { return }

                var hands: [DetectedHand] = []
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    hands = self.handPoseDetector.detectHands(in: pixelBuffer)
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self._isProcessingFrame = false
                    if let displayImage {
                        self.currentFrame = displayImage
                    }
                    self.updateFPS()
                    self.detectedHands = hands
                    self.classifyGestures(for: hands)
                }
            }
        }

        // Streaming errors
        errorToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleStreamError(error)
            }
        }
    }

    // MARK: - Streaming Control

    func startStreaming() async {
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            if status == .granted {
                await streamSession.start()
                return
            }
            let requestResult = try await wearables.requestPermission(.camera)
            if requestResult == .granted {
                await streamSession.start()
            } else {
                showError("Camera permission denied.")
            }
        } catch {
            showError("Permission error: \(error.localizedDescription)")
        }
    }

    func stopStreaming() async {
        await streamSession.stop()
        gestureClassifier.reset()
    }

    // MARK: - Gesture Classification

    /// How long a detected gesture chip stays visible on the HUD.
    private let gestureDisplayDuration: TimeInterval = 1.5
    private var leftGestureClearTask: Task<Void, Never>?
    private var rightGestureClearTask: Task<Void, Never>?

    private func classifyGestures(for hands: [DetectedHand]) {
        for hand in hands {
            let gesture = gestureClassifier.classify(hand: hand)

            if gesture != .none {
                switch hand.chirality {
                case .left:
                    leftHandGesture = gesture
                    leftGestureClearTask?.cancel()
                    leftGestureClearTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(gestureDisplayDuration))
                        if !Task.isCancelled { leftHandGesture = .none }
                    }
                case .right:
                    rightHandGesture = gesture
                    rightGestureClearTask?.cancel()
                    rightGestureClearTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(gestureDisplayDuration))
                        if !Task.isCancelled { rightHandGesture = .none }
                    }
                case .unknown: break
                }

                let event = GestureEvent(
                    gesture: gesture,
                    hand: hand.chirality.rawValue,
                    confidence: hand.confidence
                )
                addEvent(event)
            }
        }

        // Clear gesture for hands no longer detected
        if !hands.contains(where: { $0.chirality == .left }) {
            leftGestureClearTask?.cancel()
            leftHandGesture = .none
        }
        if !hands.contains(where: { $0.chirality == .right }) {
            rightGestureClearTask?.cancel()
            rightHandGesture = .none
        }
    }

    private func addEvent(_ event: GestureEvent) {
        gestureEvents.insert(event, at: 0)
        if gestureEvents.count > maxEventHistory {
            gestureEvents = Array(gestureEvents.prefix(maxEventHistory))
        }

        // Send to home-center
        Task {
            await homeCenterClient.sendGestureEvent(event)
        }
    }

    // MARK: - Helpers

    private func handleStateChange(_ state: StreamSessionState) {
        switch state {
        case .stopped:
            currentFrame = nil
            streamingStatus = .stopped
        case .waitingForDevice, .starting, .stopping, .paused:
            streamingStatus = .waiting
        case .streaming:
            streamingStatus = .streaming
        }
    }

    private func handleStreamError(_ error: StreamSessionError) {
        let message: String
        switch error {
        case .deviceNotFound: message = "Device not found. Check connection."
        case .deviceNotConnected: message = "Device disconnected."
        case .timeout: message = "Connection timed out."
        case .videoStreamingError: message = "Video streaming failed."
        case .permissionDenied: message = "Camera permission denied."
        case .hingesClosed: message = "Glasses hinges closed. Open them to resume."
        default: message = "Streaming error occurred."
        }
        showError(message)
    }

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func dismissError() {
        showError = false
        errorMessage = ""
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

    func clearEvents() {
        gestureEvents.removeAll()
    }
}
