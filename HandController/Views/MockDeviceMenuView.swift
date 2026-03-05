#if DEBUG
import MWDATMockDevice
import SwiftUI

struct MockDeviceMenuView: View {
    @State private var pairedDevices: [any MockDevice] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Paired Mock Devices") {
                    if pairedDevices.isEmpty {
                        Text("No mock devices paired")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(0..<pairedDevices.count, id: \.self) { index in
                            HStack {
                                Image(systemName: "eyeglasses")
                                Text("Mock Device \(index + 1)")
                                Spacer()
                                Button("Unpair") {
                                    let device = pairedDevices[index]
                                    MockDeviceKit.shared.unpairDevice(device)
                                    refreshDevices()
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section {
                    Button("Pair Mock Ray-Ban Meta") {
                        _ = MockDeviceKit.shared.pairRaybanMeta()
                        refreshDevices()
                    }
                }
            }
            .navigationTitle("Mock Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { refreshDevices() }
        }
    }

    private func refreshDevices() {
        pairedDevices = MockDeviceKit.shared.pairedDevices
    }
}
#endif
