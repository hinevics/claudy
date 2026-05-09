import Foundation

enum BottomPanelSessionFilter: String, CaseIterable, Identifiable {
    case all
    case activeOnly
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:        "All Sessions"
        case .activeOnly: "Active Only"
        case .none:       "Hidden"
        }
    }
}

enum BottomPanelSettingsKeys {
    static let enabled = "bottomPanel.enabled"
    static let sessionFilter = "bottomPanel.sessionFilter"
    static let rowLimit = "bottomPanel.rowLimit"
    static let opacity = "bottomPanel.opacity"
    static let hideOnFullScreen = "bottomPanel.hideOnFullScreen"

    static let defaultEnabled: Bool = true
    static let defaultRowLimit: Int = 5
    static let defaultOpacity: Double = 1.0
    static let defaultHideOnFullScreen: Bool = true
    static let defaultSessionFilter: BottomPanelSessionFilter = .all

    static let rowLimitRange: ClosedRange<Int> = 1...10
    static let opacityRange: ClosedRange<Double> = 0.3...1.0
}
