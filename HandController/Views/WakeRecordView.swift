import SwiftUI

/// UI for recording wake word training samples via the Home Center worker API.
struct WakeRecordView: View {
    let client: HomeCenterClient
    @Environment(\.dismiss) private var dismiss

    @State private var isActive = false
    @State private var sampleType = "positive"
    @State private var clipCount = 0
    @State private var pollTimer: Timer?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                instructionsCard

                sampleTypePicker

                recordButton

                if isActive {
                    activeIndicator
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Wake Word Samples")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { fetchStatus() }
            .onDisappear { stopPolling() }
        }
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How it works", systemImage: "info.circle")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Say **\"Hey Homer\"** clearly toward the Pi. A beep confirms each saved sample. Aim for **30\u{2013}50 samples**.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("For negative samples, say anything *other* than \"Hey Homer\" so the model learns what to ignore.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sample Type Picker

    private var sampleTypePicker: some View {
        VStack(spacing: 8) {
            Text("Sample Type")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Sample Type", selection: $sampleType) {
                Text("Positive").tag("positive")
                Text("Negative").tag("negative")
            }
            .pickerStyle(.segmented)
            .onChange(of: sampleType) { _, newValue in
                Task {
                    _ = await client.setWakeRecordType(newValue)
                }
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)
                        .shadow(color: isActive ? .red.opacity(0.4) : .clear, radius: 12)

                    Image(systemName: isActive ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                Text(isActive ? "Stop Recording" : "Start Recording")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Active Indicator

    private var activeIndicator: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(isActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isActive)

                Text("Recording \(sampleType == "positive" ? "\"Hey Homer\"" : "negative") samples")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Text("\(clipCount) clip\(clipCount == 1 ? "" : "s") saved")
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: clipCount)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func toggleRecording() {
        isLoading = true
        Task {
            let ok = await client.toggleWakeRecord(type: sampleType)
            if ok {
                // Fetch fresh status to confirm
                if let status = await client.getWakeRecordStatus() {
                    await MainActor.run {
                        isActive = status.active
                        clipCount = status.count
                        sampleType = status.type
                        isLoading = false
                        if isActive { startPolling() } else { stopPolling() }
                    }
                } else {
                    await MainActor.run {
                        isActive.toggle()
                        isLoading = false
                        if isActive { startPolling() } else { stopPolling() }
                    }
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func fetchStatus() {
        Task {
            if let status = await client.getWakeRecordStatus() {
                await MainActor.run {
                    isActive = status.active
                    clipCount = status.count
                    sampleType = status.type
                    if isActive { startPolling() }
                }
            }
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                if let status = await client.getWakeRecordStatus() {
                    await MainActor.run {
                        clipCount = status.count
                        isActive = status.active
                        if !status.active { stopPolling() }
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
