import SwiftUI

/// Guides the user through enrolling a new wake word on the Pi.
struct EnrollmentFlowView: View {
    let client: HomeCenterClient
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedPage = "dashboard"
    @State private var phase: Phase = .setup
    @State private var enrollmentState = ""
    @State private var elapsed: Double = 0
    @State private var bufferSeconds: Double = 0
    @State private var pollTimer: Timer?
    @State private var isLoading = false
    @State private var showTimeout = false

    private let pages = ["dashboard", "calendar", "weather", "photos"]

    enum Phase {
        case setup, recording, success
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch phase {
                case .setup:
                    setupView
                case .recording:
                    recordingView
                case .success:
                    successView
                }
            }
            .padding()
            .navigationTitle("New Wake Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        cancelAndDismiss()
                    }
                }
            }
            .onDisappear { stopPolling() }
        }
    }

    // MARK: - Setup Phase

    private var setupView: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("How it works", systemImage: "info.circle")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("The Pi's microphone will listen for a wake word. Say it clearly, and the Pi will auto-stop after 1.5s of silence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Olivia", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Target Page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Target Page", selection: $selectedPage) {
                    ForEach(pages, id: \.self) { page in
                        Text(page.capitalized).tag(page)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            Button {
                startRecording()
            } label: {
                Label("Start Recording", systemImage: "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .overlay {
                if isLoading { ProgressView() }
            }
        }
    }

    // MARK: - Recording Phase

    private var recordingView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Pulsing mic
            ZStack {
                Circle()
                    .fill(micColor.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .scaleEffect(enrollmentState == "recording" ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: enrollmentState)

                Circle()
                    .fill(micColor)
                    .frame(width: 80, height: 80)

                if enrollmentState == "processing" {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }

            Text(statusMessage)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            if enrollmentState == "recording" && bufferSeconds > 0 {
                Text(String(format: "%.1fs captured", bufferSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if showTimeout {
                VStack(spacing: 12) {
                    Text("No speech detected after 10 seconds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Button("Try Again") {
                            showTimeout = false
                            startRecording()
                        }
                        .buttonStyle(.bordered)

                        Button("Cancel") {
                            cancelAndDismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }

            Spacer()

            if !showTimeout && enrollmentState != "processing" {
                Button(role: .destructive) {
                    cancelAndDismiss()
                } label: {
                    Text("Cancel Recording")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Success Phase

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Wake Word Enrolled!")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text(name)
                    .font(.headline)
                Text("will navigate to **\(selectedPage)**")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                dismiss()
            }
        }
    }

    // MARK: - Helpers

    private var micColor: Color {
        switch enrollmentState {
        case "waiting": return .orange
        case "recording": return .red
        case "processing": return .blue
        default: return .gray
        }
    }

    private var statusMessage: String {
        switch enrollmentState {
        case "waiting": return "Listening...\nSay your wake word"
        case "recording": return "Heard you! Keep going..."
        case "processing": return "Processing your wake word..."
        default: return "Starting..."
        }
    }

    // MARK: - Actions

    private func startRecording() {
        isLoading = true
        showTimeout = false
        Task {
            let ok = await client.startEnrollment(
                name: name.trimmingCharacters(in: .whitespaces),
                action: "navigate",
                target: selectedPage
            )
            await MainActor.run {
                isLoading = false
                if ok {
                    phase = .recording
                    enrollmentState = "waiting"
                    startPolling()
                }
            }
        }
    }

    private func startPolling() {
        stopPolling()
        let startTime = Date()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task {
                if let status = await client.getEnrollmentStatus() {
                    await MainActor.run {
                        let prevState = enrollmentState
                        enrollmentState = status.state
                        elapsed = status.elapsed
                        bufferSeconds = status.bufferSeconds

                        // Completed: was non-idle, now idle
                        if prevState != "idle" && prevState != "" && status.state == "idle" {
                            stopPolling()
                            phase = .success
                            return
                        }

                        // Timeout: stuck in waiting for 10s
                        if status.state == "waiting" && Date().timeIntervalSince(startTime) > 10 {
                            stopPolling()
                            showTimeout = true
                        }
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func cancelAndDismiss() {
        stopPolling()
        Task {
            _ = await client.stopEnrollment()
            await MainActor.run { dismiss() }
        }
    }
}
