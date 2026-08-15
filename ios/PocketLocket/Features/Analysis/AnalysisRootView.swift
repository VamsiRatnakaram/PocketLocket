import SwiftUI

/// One Analysis home. Analysis remains the primary surface and Savings Plan is
/// a normal drill-down alongside merchant and category details.
struct AnalysisRootView: View {
    @State private var showSavingsPlan = false

    var body: some View {
        NavigationStack {
            AnalysisView { showSavingsPlan = true }
                .navigationTitle("Analysis")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showSavingsPlan) {
                    SuggestionsView()
                }
            }
    }
}
