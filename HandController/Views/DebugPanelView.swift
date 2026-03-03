import SwiftUI

/// Debug panel showing gesture event log and home-center integration settings.
struct DebugPanelView: View {
    @ObservedObject var streamVM: StreamViewModel
    @State private var homeCenterEnabled = false
    @State private var homeCenterToken = ""
    @State private var healthStatus: HealthStatus = .unknown
    @Environment(\.dismiss) private var dismiss

    enum HealthStatus {
        case unknown, checking, healthy, unhealthy
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                homeCenterSection
                tvDashboardSection
                gestureEventSection
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Streaming", value: streamVM.streamingStatus.rawValue)
            LabeledContent("FPS", value: "\(streamVM.fps)")
            LabeledContent("Hands Detected", value: "\(streamVM.detectedHands.count)")

            if streamVM.leftHandGesture != .none {
                LabeledContent("Left Hand") {
                    HStack {
                        Text(streamVM.leftHandGesture.emoji)
                        Text(streamVM.leftHandGesture.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if streamVM.rightHandGesture != .none {
                LabeledContent("Right Hand") {
                    HStack {
                        Text(streamVM.rightHandGesture.emoji)
                        Text(streamVM.rightHandGesture.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Home Center Section

    private var homeCenterSection: some View {
        Section("Home Center Integration") {
            Toggle("Send Events", isOn: $homeCenterEnabled)
                .onChange(of: homeCenterEnabled) { _, newValue in
                    Task { await streamVM.homeCenterClient.setEnabled(newValue) }
                }

            if homeCenterEnabled {
                HStack {
                    SecureField("Auth Token", text: $homeCenterToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Button("Set") {
                        Task { await streamVM.homeCenterClient.setAuthToken(homeCenterToken) }
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Text("API Health")
                    Spacer()
                    switch healthStatus {
                    case .unknown:
                        Text("Not checked")
                            .foregroundStyle(.secondary)
                    case .checking:
                        ProgressView()
                    case .healthy:
                        Label("OK", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .unhealthy:
                        Label("Unreachable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Button("Check Connection") {
                    healthStatus = .checking
                    Task {
                        let ok = await streamVM.homeCenterClient.healthCheck()
                        healthStatus = ok ? .healthy : .unhealthy
                    }
                }
            }

            Text("Events are sent to home-center as notifications via REST API.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - TV Dashboard Section

    private var tvDashboardSection: some View {
        Section("TV Dashboard Control") {
            Toggle("Dashboard Connected", isOn: Binding(
                get: { streamVM.dashboardController.isConnected },
                set: { streamVM.dashboardController.isConnected = $0 }
            ))

            if streamVM.dashboardController.isConnected {
                Toggle("TV Power", isOn: Binding(
                    get: { streamVM.dashboardController.isTVOn },
                    set: { streamVM.dashboardController.isTVOn = $0 }
                ))

                if streamVM.dashboardController.isTVOn {
                    LabeledContent("Selected Section") {
                        Text(streamVM.dashboardController.selectedSection?.title ?? "None")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Full Screen") {
                        Text(streamVM.dashboardController.isFullScreen ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Enable to control the Family TV Dashboard via hand gestures. Wave left/right to navigate sections, index pinch to open, middle pinch to go back or power on.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Event Log Section

    private var gestureEventSection: some View {
        Section {
            if streamVM.gestureEvents.isEmpty {
                Text("No gesture events yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(streamVM.gestureEvents) { event in
                    eventRow(event)
                }
            }
        } header: {
            HStack {
                Text("Gesture Events (\(streamVM.gestureEvents.count))")
                Spacer()
                if !streamVM.gestureEvents.isEmpty {
                    Button("Clear") {
                        streamVM.clearEvents()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func eventRow(_ event: GestureEvent) -> some View {
        HStack(spacing: 12) {
            Text(event.gesture.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.gesture.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(event.hand)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                    Text(event.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(String(format: "%.0f%%", event.confidence * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
