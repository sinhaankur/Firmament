//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import SwiftUI
import UIKit

/// The single source of truth for Firmament's look. Every screen draws from
/// these tokens so the app feels like one considered thing rather than a dozen
/// views that each invented their own spacing, radii, and colours.
///
/// © Ankur Sinha.
enum Theme {
    // MARK: - Colour
    /// The one accent — a calm sky-cyan. (Replaces the mix of `.cyan` and a
    /// hand-rolled blue that had drifted across the app.)
    static let accent = Color(red: 0.36, green: 0.72, blue: 1.0)
    static let accentDim = accent.opacity(0.6)
    static let warning = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let good = Color(red: 0.35, green: 0.9, blue: 0.55)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)

    // MARK: - Corner radii (one small scale)
    enum Radius {
        static let chip: CGFloat = 12
        static let panel: CGFloat = 18
        static let sheet: CGFloat = 24
    }

    // MARK: - Panel fill (one glassy background everywhere)
    static let panelOpacity: Double = 0.5
    static let chipFill = Color.white.opacity(0.08)
    static let chipFillActive = Color.white.opacity(0.18)
    static let hairline = Color.white.opacity(0.14)

    // MARK: - Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
    }

    // MARK: - Motion
    static let ease = Animation.easeInOut(duration: 0.22)

    // MARK: - Haptics (that pro tactile feel)
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

extension View {
    /// A consistent dark glass panel (rounded rect, hairline border).
    func panel(radius: CGFloat = Theme.Radius.panel) -> some View {
        self
            .background(.black.opacity(Theme.panelOpacity),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1))
    }

    /// A consistent pill chip; `active` swaps to the accent-tinted state.
    func chip(active: Bool = false) -> some View {
        self
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(active ? Theme.chipFillActive : Theme.chipFill, in: Capsule())
            .overlay(Capsule().stroke(active ? Theme.accent : .clear, lineWidth: 1.5))
    }

    /// A round icon-button background used in the top bar.
    func iconButton() -> some View {
        self
            .padding(8)
            .background(.black.opacity(0.35), in: Circle())
    }
}
