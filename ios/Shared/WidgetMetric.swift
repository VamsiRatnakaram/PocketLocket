import Foundation
import AppIntents

/// Which fact a widget leads with.
///
/// Shared so the Settings picker, the widget's long-press menu, and the small
/// widget's cycle button all agree on the same three options and the same raw
/// values on disk.
enum WidgetMetric: String, Codable, CaseIterable, Identifiable, Sendable, AppEnum {
    case percent
    case remaining
    case safeToSpend

    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Metric")
    static var caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [
        .percent: "Percent spent",
        .remaining: "Amount left",
        .safeToSpend: "Safe to spend"
    ]

    var id: String { rawValue }

    /// The next metric in the cycle, wrapping back to the first.
    var next: WidgetMetric {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .percent }
        return all[(index + 1) % all.count]
    }

    var label: String {
        switch self {
        case .percent: return "Spent"
        case .remaining: return "Left"
        case .safeToSpend: return "Safe"
        }
    }

    /// The fuller wording a Settings picker needs; `label` is what a widget
    /// caption gets, where there are about four characters.
    var pickerLabel: String {
        switch self {
        case .percent: return "Percent spent"
        case .remaining: return "Amount left"
        case .safeToSpend: return "Safe to spend"
        }
    }

    /// Stored in the shared suite; `percent` needs no stored value, which keeps
    /// a first-run widget correct without the app having written anything yet.
    static let defaultsKey = "widgetMetric"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> WidgetMetric {
        guard let raw = defaults.string(forKey: defaultsKey),
              let metric = WidgetMetric(rawValue: raw) else { return .percent }
        return metric
    }

    static func save(_ metric: WidgetMetric, to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(metric.rawValue, forKey: defaultsKey)
    }
}
