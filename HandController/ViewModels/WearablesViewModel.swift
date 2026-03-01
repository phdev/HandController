import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

/// Manages DAT SDK device registration and discovery.
@MainActor
final class WearablesViewModel: ObservableObject {
    @Published var devices: [DeviceIdentifier]
    @Published var registrationState: RegistrationState
    @Published var hasMockDevice: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    let wearables: WearablesInterface

    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.devices = wearables.devices
        self.registrationState = wearables.registrationState

        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                self.registrationState = state
            }
        }

        deviceStreamTask = Task {
            for await devices in wearables.devicesStream() {
                self.devices = devices
                #if DEBUG
                self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
                #endif
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
    }

    var isRegistered: Bool {
        registrationState == .registered || hasMockDevice
    }

    func connectGlasses() {
        guard registrationState != .registering else { return }
        Task {
            do {
                try await wearables.startRegistration()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func disconnectGlasses() {
        Task {
            do {
                try await wearables.startUnregistration()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }
}
