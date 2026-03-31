import SwiftUI

/// Pre-streaming view with a start button, shown when registered but not yet streaming.
struct NonStreamView: View {
    @ObservedObject var streamVM: StreamViewModel
    @ObservedObject var wearablesVM: WearablesViewModel
    @State private var showWakeRecord = false
    @State private var showEnrollments = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "video.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Ready to Stream")
                    .font(.title2)
                    .fontWeight(.semibold)

                if streamVM.hasActiveDevice {
                    Label("Device connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Label("Waiting for device...", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            VStack(spacing: 12) {
                Button {
                    Task { await streamVM.startStreaming() }
                } label: {
                    Label("Start Hand Tracking", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)

                Button {
                    showWakeRecord = true
                } label: {
                    Label("Record Wake Word Samples", systemImage: "mic.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)

                Button {
                    showEnrollments = true
                } label: {
                    Label("Wake Word Training", systemImage: "waveform.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)

                Button {
                    wearablesVM.disconnectGlasses()
                } label: {
                    Text("Disconnect Glasses")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Text("Detected gestures:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Thumb Swipe (L/R/Up/Down) | Index Pinch | Middle Pinch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom)
        }
        .sheet(isPresented: $showWakeRecord) {
            WakeRecordView(client: streamVM.homeCenterClient)
        }
        .sheet(isPresented: $showEnrollments) {
            EnrollmentListView(client: streamVM.homeCenterClient)
        }
    }
}
