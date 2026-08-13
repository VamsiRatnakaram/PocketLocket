import SwiftUI

/// The tab formerly known as "Save" — now hosts a segmented picker between the
/// new **Analysis** (trend-mining) view and the original **Save** content
/// (AI Q&A + savings suggestions + subscriptions), mirroring Home's
/// Month/Year picker pattern.
struct AnalysisRootView: View {
    enum Segment: Hashable { case analysis, save }

    @State private var segment: Segment = .analysis

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $segment) {
                Text("Analysis").tag(Segment.analysis)
                Text("Save").tag(Segment.save)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            switch segment {
            case .analysis: AnalysisView()
            case .save: SuggestionsView()
            }
        }
    }
}
