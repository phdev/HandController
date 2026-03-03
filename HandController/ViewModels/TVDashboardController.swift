import Foundation

/// Manages the TV Dashboard navigation state and translates hand gestures into
/// dashboard navigation commands sent to the Home Center API.
///
/// Gesture mappings:
/// - Wave left/right: Move selector between dashboard sections
/// - Index + thumb pinch: Open full screen view of selected section (if available)
/// - Middle + thumb pinch: Go back to dashboard from full screen, or turn on TV if off
@MainActor
final class TVDashboardController: ObservableObject {
    // MARK: - Published State

    @Published var sections: [DashboardSection] = DashboardSection.defaultSections
    @Published var selectedIndex: Int = 0
    @Published var isFullScreen: Bool = false
    @Published var isTVOn: Bool = false
    @Published var isConnected: Bool = false

    /// The currently selected section.
    var selectedSection: DashboardSection? {
        guard selectedIndex >= 0, selectedIndex < sections.count else { return nil }
        return sections[selectedIndex]
    }

    // MARK: - Dependencies

    private let homeCenterClient: HomeCenterClient

    // MARK: - Init

    init(homeCenterClient: HomeCenterClient) {
        self.homeCenterClient = homeCenterClient
    }

    // MARK: - Gesture Handling

    /// Process a detected gesture and perform the corresponding dashboard action.
    /// Returns true if the gesture was consumed by a navigation action.
    @discardableResult
    func handleGesture(_ gesture: HandGesture) -> Bool {
        guard isConnected else { return false }

        switch gesture {
        case .waveLeft:
            return moveSelectorBackward()
        case .waveRight:
            return moveSelectorForward()
        case .indexThumbPinch:
            return openFullScreen()
        case .middleThumbPinch:
            return handleMiddlePinch()
        case .waveUp, .waveDown, .none:
            return false
        }
    }

    // MARK: - Navigation Actions

    /// Move the selector to the previous section (wraps around).
    private func moveSelectorBackward() -> Bool {
        guard !isFullScreen, isTVOn else { return false }

        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = sections.count - 1
        }

        sendNavigationCommand(.selectSection, sectionId: selectedSection?.id)
        return true
    }

    /// Move the selector to the next section (wraps around).
    private func moveSelectorForward() -> Bool {
        guard !isFullScreen, isTVOn else { return false }

        if selectedIndex < sections.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0
        }

        sendNavigationCommand(.selectSection, sectionId: selectedSection?.id)
        return true
    }

    /// Open the full screen view of the currently selected section.
    private func openFullScreen() -> Bool {
        guard isTVOn, !isFullScreen else { return false }
        guard let section = selectedSection, section.hasFullScreenView else { return false }

        isFullScreen = true
        sendNavigationCommand(.openFullscreen, sectionId: section.id)
        return true
    }

    /// Middle + thumb pinch: go back from full screen, or turn on TV if off.
    private func handleMiddlePinch() -> Bool {
        if !isTVOn {
            isTVOn = true
            sendNavigationCommand(.powerOn)
            return true
        }

        if isFullScreen {
            isFullScreen = false
            sendNavigationCommand(.closeFullscreen, sectionId: selectedSection?.id)
            return true
        }

        return false
    }

    // MARK: - Home Center API

    private func sendNavigationCommand(_ action: DashboardAction, sectionId: String? = nil) {
        Task {
            await homeCenterClient.sendNavigationCommand(
                action: action,
                sectionId: sectionId,
                selectedIndex: selectedIndex
            )
        }
    }
}
