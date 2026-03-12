import SwiftUI

/// Debug panel showing gesture event log and home-center integration settings.
struct DebugPanelView: View {
    @ObservedObject var streamVM: StreamViewModel
    @State private var homeCenterEnabled = true
    @State private var homeCenterToken = ""
    @State private var healthStatus: HealthStatus = .unknown
    @State private var showWakeRecord = false
    @Environment(\.dismiss) private var dismiss

    enum HealthStatus {
        case unknown, checking, healthy, unhealthy
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                homeCenterSection
                toolsSection
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

    // MARK: - Tools Section

    private var toolsSection: some View {
        Section("Tools") {
            Button {
                showWakeRecord = true
            } label: {
                Label("Record Wake Word Samples", systemImage: "mic.badge.plus")
            }
            .sheet(isPresented: $showWakeRecord) {
                WakeRecordView(client: streamVM.homeCenterClient)
            }
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
