import SwiftUI

/// The tab formerly known as "Save" — now hosts a segmented picker between the
/// new **Analysis** (trend-mining) view and the original **Save** content
/// (AI Q&A + savings suggestions + subscriptions).
struct AnalysisRootView: View {
    enum Segment: Hashable { case analysis, save }

    @State private var segment: Segment = .analysis
    @State private var hasLoadedSave = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnalysisView(isActive: segment == .analysis)
                    .opacity(segment == .analysis ? 1 : 0)
                    .allowsHitTesting(segment == .analysis)
                    .accessibilityHidden(segment != .analysis)

                // Create Save lazily so opening Analysis does not start two
                // data pipelines, then keep it mounted. A switch no longer
                // discards its scroll position, typed question, or AI answer.
                if hasLoadedSave {
                    SuggestionsView(isActive: segment == .save)
                        .opacity(segment == .save ? 1 : 0)
                        .allowsHitTesting(segment == .save)
                        .accessibilityHidden(segment != .save)
                }
            }
            .navigationTitle(segment == .analysis ? "Analysis" : "Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The control stays in one physical location without consuming
                // a permanent content row. Because it belongs to this root
                // destination, it also disappears on merchant/category detail
                // screens instead of offering a context-breaking tab switch.
                ToolbarItem(placement: .principal) {
                    AnalysisSegmentPicker(segment: segmentBinding)
                        .frame(width: 190)
                }
                if segment == .save {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SubscriptionsView()
                        } label: {
                            Label("Subscriptions", systemImage: "repeat")
                        }
                    }
                }
            }
        }
    }

    private var segmentBinding: Binding<Segment> {
        Binding(
            get: { segment },
            set: { newValue in
                if newValue == .save { hasLoadedSave = true }
                segment = newValue
            }
        )
    }
}

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
