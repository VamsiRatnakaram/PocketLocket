import SwiftUI

/// Covers the UI with a branded blur whenever the app isn't active, so balances
/// don't show up in the app switcher or over-the-shoulder while backgrounded.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                Text("PocketLocket")
                    .font(.title2.bold())
            }
        }
        .ignoresSafeArea()
    }
}
