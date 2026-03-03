import Foundation

/// A section on the Family TV Dashboard that can be navigated via hand gestures.
struct DashboardSection: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    /// Whether this section has a corresponding full screen view that can be opened.
    let hasFullScreenView: Bool

    /// The default sections displayed on the Family TV Dashboard.
    static let defaultSections: [DashboardSection] = [
        DashboardSection(id: "calendar", title: "Calendar", icon: "calendar", hasFullScreenView: true),
        DashboardSection(id: "photos", title: "Photos", icon: "photo.on.rectangle", hasFullScreenView: true),
        DashboardSection(id: "weather", title: "Weather", icon: "cloud.sun", hasFullScreenView: true),
        DashboardSection(id: "clock", title: "Clock", icon: "clock", hasFullScreenView: false),
        DashboardSection(id: "news", title: "News", icon: "newspaper", hasFullScreenView: true),
        DashboardSection(id: "music", title: "Music", icon: "music.note", hasFullScreenView: true)
    ]
}

/// Navigation actions sent to the Home Center API to control the TV Dashboard.
enum DashboardAction: String, Codable {
    case selectSection = "select_section"
    case openFullscreen = "open_fullscreen"
    case closeFullscreen = "close_fullscreen"
    case powerOn = "power_on"
}
