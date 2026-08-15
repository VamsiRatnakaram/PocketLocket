import Foundation

/// How far back the Analysis tab looks when mining trends.
enum AnalysisTimeRange: String, CaseIterable, Identifiable {
    case oneMonth, threeMonths, sixMonths, twelveMonths, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .twelveMonths: return "12M"
        case .all: return "All"
        }
    }

    /// Earliest date to include, or `nil` for all-time.
    func cutoff(from reference: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: reference)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: reference)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: reference)
        case .twelveMonths: return calendar.date(byAdding: .month, value: -12, to: reference)
        case .all: return nil
        }
    }
}
