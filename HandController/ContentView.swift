import SwiftUI

/// Main view that combines the camera preview, hand skeleton overlay, and gesture display.
struct ContentView: View {
    @StateObject private var viewModel = HandGestureViewModel()

    var body: some View {
        ZStack {
            // Camera feed
            CameraPreviewView(session: viewModel.cameraService.captureSession)
                .ignoresSafeArea()

            // Hand skeleton overlay
            GeometryReader { geo in
                HandOverlayView(
                    hands: viewModel.detectedHands,
                    viewSize: geo.size
                )
            }
            .ignoresSafeArea()

            // Gesture info panel
            VStack {
                // Top bar: FPS and hand count
                HStack {
                    Label("\(viewModel.fps) FPS", systemImage: "speedometer")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    Label("\(viewModel.detectedHands.count) hand(s)", systemImage: "hand.raised")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                // Bottom: detected gesture
                if viewModel.currentGesture != .unknown {
                    VStack(spacing: 8) {
                        Text(viewModel.currentGesture.emoji)
                            .font(.system(size: 64))

                        Text(viewModel.currentGesture.rawValue)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, 40)
                }
            }

            // Camera permission denied
            if !viewModel.cameraService.isCameraAuthorized {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Camera Access Required")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Please enable camera access in Settings to use hand gesture detection.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
