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
            // The picker is handed to the child rather than stacked above it so
            // it rides at the top of the child's *scroll content*. Stacked
            // above, it stayed on screen forever, eating a row of height on a
            // tab that is mostly a long scroll -- and sat on bare background
            // with nothing marking where it ended.
            switch segment {
            case .analysis: AnalysisView(segmentPicker: picker)
            case .save: SuggestionsView(segmentPicker: picker)
            }
        }
    }

    private var picker: AnalysisSegmentPicker { AnalysisSegmentPicker(segment: $segment) }
}

/// Concrete (rather than a generic header parameter) so the children can hold
/// it in a plain optional stored property.
struct AnalysisSegmentPicker: View {
    @Binding var segment: AnalysisRootView.Segment

    var body: some View {
        Picker("View", selection: $segment) {
            Text("Analysis").tag(AnalysisRootView.Segment.analysis)
            Text("Save").tag(AnalysisRootView.Segment.save)
        }
        .pickerStyle(.segmented)
    }
}
