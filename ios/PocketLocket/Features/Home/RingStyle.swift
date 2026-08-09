import Foundation

/// The three selectable ring styles for the Home screen.
enum RingStyle: String, CaseIterable, Identifiable {
    case donut
    case progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .donut: return "Donut"
        case .progress: return "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .donut: return "chart.pie.fill"
        case .progress: return "circle.dashed"
        }
    }
}
