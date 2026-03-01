import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct HandControllerApp: App {
    private let wearables: WearablesInterface
    @StateObject private var wearablesVM: WearablesViewModel
    @StateObject private var streamVM: StreamViewModel

    #if DEBUG
    @State private var showMockDeviceMenu = false
    #endif

    init() {
        do {
            try Wearables.configure()
        } catch {
            #if DEBUG
            NSLog("[HandController] Failed to configure Wearables SDK: \(error)")
            #endif
        }

        let wearables = Wearables.shared
        self.wearables = wearables
        self._wearablesVM = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
        self._streamVM = StateObject(wrappedValue: StreamViewModel(wearables: wearables))
    }

    var body: some Scene {
        WindowGroup {
            mainContent
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Handle Meta AI app OAuth callback
                    Task {
                        try? await Wearables.handleUrl(url)
                    }
                }
                .alert("Error", isPresented: $wearablesVM.showError) {
                    Button("OK") { wearablesVM.dismissError() }
                } message: {
                    Text(wearablesVM.errorMessage)
                }
                #if DEBUG
                .overlay(alignment: .bottomLeading) {
                    Button {
                        showMockDeviceMenu = true
                    } label: {
                        Image(systemName: "ant.fill")
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding()
                }
                .sheet(isPresented: $showMockDeviceMenu) {
                    MockDeviceKitView(
                        viewModel: MockDeviceKitView.ViewModel(mockDeviceKit: MockDeviceKit.shared)
                    )
                }
                #endif
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if wearablesVM.isRegistered {
            if streamVM.isStreaming {
                StreamingView(streamVM: streamVM, wearablesVM: wearablesVM)
            } else {
                NonStreamView(streamVM: streamVM, wearablesVM: wearablesVM)
            }
        } else {
            ConnectionView(viewModel: wearablesVM)
        }
    }
}
