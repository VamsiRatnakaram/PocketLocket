import SwiftUI

/// The tab formerly known as "Save" — now hosts a segmented picker between the
/// new **Analysis** (trend-mining) view and the original **Save** content
/// (AI Q&A + savings suggestions + subscriptions), mirroring Home's
/// Month/Year picker pattern.
struct AnalysisRootView: View {
    enum Segment: Hashable { case analysis, save }

    @State private var segment: Segment = .analysis

    var body: some View {
        // The stack lives here rather than in each child so the segmented
        // picker is part of the *root* screen. It used to sit outside the
        // children's own stacks, which pinned it above every pushed
        // drill-down -- offering to switch to Save from inside a category
        // detail, and stealing a row of height from every pushed screen.
        NavigationStack {
            Group {
                switch segment {
                case .analysis: AnalysisView()
                case .save: SuggestionsView()
                }
            }
            // A safe-area inset rather than a VStack row: stacked above the
            // content, the picker sat on bare background with nothing marking
            // where it ended, so scrolling ran the content straight into it.
            // As an inset it stays pinned, the content scrolls *under* it, and
            // it carries the same material and hairline as a toolbar.
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("View", selection: $segment) {
                    Text("Analysis").tag(Segment.analysis)
                    Text("Save").tag(Segment.save)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }
}
