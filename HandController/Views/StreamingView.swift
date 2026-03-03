import SwiftUI

/// Main streaming view: camera feed + hand skeleton overlay + gesture indicators + dashboard selector.
struct StreamingView: View {
    @ObservedObject var streamVM: StreamViewModel
    @ObservedObject var wearablesVM: WearablesViewModel
    @State private var showDebugPanel = false

    private var dashboard: TVDashboardController {
        streamVM.dashboardController
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera feed
            if let frame = streamVM.currentFrame {
                GeometryReader { geo in
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay {
                            // Hand skeleton overlay
                            HandOverlayView(hands: streamVM.detectedHands)
                        }
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(streamVM.streamingStatus.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // HUD overlay
            VStack {
                topBar

                // Dashboard section selector (visible when connected and TV is on)
                if dashboard.isConnected && dashboard.isTVOn {
                    dashboardSelector
                }

                Spacer()
                gestureIndicators
                bottomControls
            }
        }
        .sheet(isPresented: $showDebugPanel) {
            DebugPanelView(streamVM: streamVM)
        }
        .alert("Error", isPresented: $streamVM.showError) {
            Button("OK") { streamVM.dismissError() }
        } message: {
            Text(streamVM.errorMessage)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // FPS counter
            Label("\(streamVM.fps) FPS", systemImage: "speedometer")
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Dashboard connection indicator
            if dashboard.isConnected {
                dashboardStatusBadge
            }

            // Hands detected
            Label("\(streamVM.detectedHands.count)", systemImage: "hand.raised.fill")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

            // Debug button
            Button {
                showDebugPanel = true
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Dashboard Status Badge

    private var dashboardStatusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: dashboard.isTVOn ? "tv.fill" : "tv")
                .font(.caption2)
            if dashboard.isFullScreen {
                Text("Full Screen")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            dashboard.isTVOn ? Color.green.opacity(0.3) : Color.gray.opacity(0.3),
            in: Capsule()
        )
    }

    // MARK: - Dashboard Section Selector

    private var dashboardSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(dashboard.sections.enumerated()), id: \.element.id) { index, section in
                        let isSelected = index == dashboard.selectedIndex
                        let baseLineWidth: CGFloat = 1.5
                        let lineWidth = isSelected ? baseLineWidth * 4 : baseLineWidth

                        HStack(spacing: 6) {
                            Image(systemName: section.icon)
                                .font(.caption2)
                            Text(section.title)
                                .font(.caption)
                                .fontWeight(isSelected ? .bold : .regular)
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? Color.blue.opacity(0.3) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? Color.blue : Color.white.opacity(0.2),
                                    lineWidth: lineWidth
                                )
                        )
                        .id(section.id)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: dashboard.selectedIndex)
            .onChange(of: dashboard.selectedIndex) { _, newIndex in
                if newIndex < dashboard.sections.count {
                    withAnimation {
                        proxy.scrollTo(dashboard.sections[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Gesture Indicators

    @ViewBuilder
    private var gestureIndicators: some View {
        HStack(spacing: 20) {
            if streamVM.leftHandGesture != .none {
                gestureChip(gesture: streamVM.leftHandGesture, hand: "L")
            }
            if streamVM.rightHandGesture != .none {
                gestureChip(gesture: streamVM.rightHandGesture, hand: "R")
            }
        }
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: streamVM.leftHandGesture)
        .animation(.easeInOut(duration: 0.2), value: streamVM.rightHandGesture)
    }

    private func gestureChip(gesture: HandGesture, hand: String) -> some View {
        HStack(spacing: 8) {
            Text(gesture.emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(gesture.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text("\(hand) Hand")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 16) {
            Button {
                Task { await streamVM.stopStreaming() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.8), in: Capsule())
                    .foregroundStyle(.white)
            }

            Button {
                wearablesVM.disconnectGlasses()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.bottom, 30)
    }
}
