import SwiftUI

enum LiquidGlassButtonEmphasis {
    case standard
    case prominent
}

/// Compatibility shims for the iOS 26 control and navigation layer.
///
/// These APIs intentionally don't offer a general-purpose "glass card": content
/// surfaces should stay in the content layer instead of competing with the
/// system's glass navigation.
extension View {
    func liquidGlassContainer(spacing: CGFloat? = nil) -> some View {
        modifier(LiquidGlassContainer(spacing: spacing))
    }

    func liquidGlassCircleControl() -> some View {
        modifier(LiquidGlassCircleControl())
    }

    @ViewBuilder
    func liquidGlassButtonStyle(_ emphasis: LiquidGlassButtonEmphasis = .standard) -> some View {
        if #available(iOS 26.0, *) {
            switch emphasis {
            case .standard:
                buttonStyle(.glass)
            case .prominent:
                buttonStyle(.glassProminent)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func adaptiveProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func liquidGlassPressableButtonStyle(fallbackScale: CGFloat = 0.96) -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.plain)
        } else {
            buttonStyle(PressableStyle(scale: fallbackScale))
        }
    }

    @ViewBuilder
    func liquidGlassTabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    @ViewBuilder
    func adaptiveSafeAreaBar<Bar: View>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Bar
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: edge, alignment: alignment, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
        }
    }

    @ViewBuilder
    func legacyBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            background(.bar)
        }
    }

    @ViewBuilder
    func legacyTopDivider() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    func platformPresentationCornerRadius(_ legacyRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationCornerRadius(legacyRadius)
        }
    }
}

private struct LiquidGlassContainer: ViewModifier {
    let spacing: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private struct LiquidGlassCircleControl: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
        }
    }
}
