import SwiftUI

/// Pre-connection view shown when glasses are not yet registered.
struct ConnectionView: View {
    @ObservedObject var viewModel: WearablesViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "eyeglasses")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("HandController")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Connect your Meta Ray-Ban glasses to detect hand gestures in real-time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 16) {
                statusBadge

                Button {
                    viewModel.connectGlasses()
                } label: {
                    HStack {
                        if viewModel.registrationState == .registering {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.registrationState == .registering ? "Connecting..." : "Connect Glasses")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.registrationState == .registering)
                .padding(.horizontal, 40)
            }

            Spacer()

            Text("Requires Meta AI app and Developer Mode enabled")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch viewModel.registrationState {
        case .registered: return .green
        case .registering: return .orange
        default: return .gray
        }
    }

    private var statusText: String {
        switch viewModel.registrationState {
        case .registered: return "Registered"
        case .registering: return "Registering..."
        default: return "Not Connected"
        }
    }
}
