import SwiftUI

/// Liquid Glass with a floor for older systems.
///
/// The app still deploys to iOS 17, and `glassEffect` is iOS 26+, so every use
/// needs a fallback. Doing that inline at each call site means an `if
/// #available` wrapped around a `background` in half a dozen places, which is
/// where inconsistencies creep in -- one surface gets the glass, the next keeps
/// a flat fill, and they sit next to each other looking unrelated.
///
/// So the choice is made once, here.
extension View {
    /// A raised content surface: cards, panels, anything that should read as
    /// floating above the background.
    ///
    /// On iOS 26 this is Liquid Glass. Below that it falls back to the flat
    /// `secondarySystemBackground` fill these surfaces already used, so the
    /// pre-26 appearance is unchanged rather than approximated.
    func glassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }

    /// Groups nearby glass surfaces so the system renders and blends them in
    /// one pass. Apple's guidance is that ungrouped glass effects sitting close
    /// together each get their own sampling pass, which is exactly the shape of
    /// a scrolling list of cards.
    func glassSurfaceGroup() -> some View {
        modifier(GlassSurfaceGroup())
    }
}

struct GlassSurfaceGroup: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(Color(.secondarySystemBackground), in: shape)
        }
    }
}
