import SwiftUI

/// UI for recording wake word training samples via the Home Center worker API.
struct WakeRecordView: View {
    let client: HomeCenterClient
    @Environment(\.dismiss) private var dismiss

    @State private var isActive = false
    @State private var sampleType = "positive"
    @State private var totalPositive = 0
    @State private var totalNegative = 0
    @State private var pollTimer: Timer?
    @State private var isLoading = false
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                instructionsCard
                sampleTypePicker
                recordButton

                if isActive {
                    activeIndicator
                }

                totalsCard
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
            .alert("Clear All Recordings?", isPresented: $showClearConfirmation) {
                Button("Clear", role: .destructive) { clearRecordings() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will reset all counters and delete saved audio files on the Pi. This cannot be undone.")
            }
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
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            toggle()
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
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isActive)

            Text("Recording \(sampleType == "positive" ? "\"Hey Homer\"" : "negative") samples")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Totals Card

    private var totalsCard: some View {
        VStack(spacing: 12) {
            Text("Cumulative Totals")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                totalGauge(label: "Positive", count: totalPositive, color: .green)
                totalGauge(label: "Negative", count: totalNegative, color: .orange)
            }

            HStack(spacing: 16) {
                Button {
                    resetTotals()
                } label: {
                    Label("Reset Totals", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }

                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear Recordings", systemImage: "trash")
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func totalGauge(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(CGFloat(count) / 50.0, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.default, value: count)

                Text("\(count)/50")
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .frame(width: 60, height: 60)

            if count >= 50 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func applyStatus(_ status: HomeCenterClient.WakeRecordStatus) {
        isActive = status.active
        totalPositive = status.totalPositive
        totalNegative = status.totalNegative
        if isActive { startPolling() } else { stopPolling() }
    }

    private func toggle() {
        isLoading = true
        Task {
            if let status = await client.toggleWakeRecord(type: sampleType) {
                await MainActor.run {
                    applyStatus(status)
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func fetchStatus() {
        Task {
            if let status = await client.getWakeRecordStatus() {
                await MainActor.run { applyStatus(status) }
            }
        }
    }

    private func resetTotals() {
        Task {
            if let status = await client.resetWakeRecordTotals() {
                await MainActor.run { applyStatus(status) }
            }
        }
    }

    private func clearRecordings() {
        Task {
            if let status = await client.clearRecordings() {
                await MainActor.run { applyStatus(status) }
            }
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                if let status = await client.getWakeRecordStatus() {
                    await MainActor.run { applyStatus(status) }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
