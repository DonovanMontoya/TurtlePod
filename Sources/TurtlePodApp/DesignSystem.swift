import SwiftUI

// MARK: - Theme Definition

struct TurtleTheme {
    let name: String
    let colorScheme: ColorScheme

    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let backgroundCard: Color
    let backgroundElevated: Color

    let amber: Color
    let amberMuted: Color
    let amberGlow: Color

    let teal: Color
    let tealMuted: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    let destructive: Color
    let success: Color

    static let cardCornerRadius: CGFloat = 14
    static let artworkCornerRadius: CGFloat = 10
    static let miniPlayerCornerRadius: CGFloat = 16
}

// MARK: - Theme Variants

extension TurtleTheme {
    /// Warm dark — charcoal + honey gold + teal
    static let ember = TurtleTheme(
        name: "Ember",
        colorScheme: .dark,
        backgroundPrimary:   Color(red: 0.08, green: 0.07, blue: 0.06),
        backgroundSecondary: Color(red: 0.12, green: 0.11, blue: 0.09),
        backgroundCard:      Color(red: 0.15, green: 0.13, blue: 0.11),
        backgroundElevated:  Color(red: 0.18, green: 0.16, blue: 0.13),
        amber:               Color(red: 0.92, green: 0.72, blue: 0.26),
        amberMuted:          Color(red: 0.72, green: 0.55, blue: 0.20),
        amberGlow:           Color(red: 0.92, green: 0.72, blue: 0.26).opacity(0.15),
        teal:                Color(red: 0.35, green: 0.78, blue: 0.72),
        tealMuted:           Color(red: 0.25, green: 0.55, blue: 0.52),
        textPrimary:         Color(red: 0.93, green: 0.90, blue: 0.85),
        textSecondary:       Color(red: 0.62, green: 0.58, blue: 0.52),
        textTertiary:        Color(red: 0.42, green: 0.39, blue: 0.35),
        destructive:         Color(red: 0.85, green: 0.35, blue: 0.30),
        success:             Color(red: 0.45, green: 0.75, blue: 0.45)
    )

    /// Warm light — aged paper + burnt sienna + forest green
    static let parchment = TurtleTheme(
        name: "Parchment",
        colorScheme: .light,
        backgroundPrimary:   Color(red: 0.96, green: 0.93, blue: 0.87),
        backgroundSecondary: Color(red: 0.92, green: 0.88, blue: 0.82),
        backgroundCard:      Color(red: 0.99, green: 0.97, blue: 0.93),
        backgroundElevated:  Color(red: 0.88, green: 0.84, blue: 0.77),
        amber:               Color(red: 0.61, green: 0.27, blue: 0.13),
        amberMuted:          Color(red: 0.72, green: 0.42, blue: 0.28),
        amberGlow:           Color(red: 0.61, green: 0.27, blue: 0.13).opacity(0.12),
        teal:                Color(red: 0.22, green: 0.48, blue: 0.32),
        tealMuted:           Color(red: 0.30, green: 0.55, blue: 0.40),
        textPrimary:         Color(red: 0.17, green: 0.14, blue: 0.10),
        textSecondary:       Color(red: 0.42, green: 0.36, blue: 0.30),
        textTertiary:        Color(red: 0.62, green: 0.56, blue: 0.50),
        destructive:         Color(red: 0.72, green: 0.18, blue: 0.14),
        success:             Color(red: 0.22, green: 0.55, blue: 0.32)
    )

    /// Cool dark — deep navy + soft indigo + electric cyan
    static let midnight = TurtleTheme(
        name: "Midnight",
        colorScheme: .dark,
        backgroundPrimary:   Color(red: 0.04, green: 0.05, blue: 0.10),
        backgroundSecondary: Color(red: 0.07, green: 0.09, blue: 0.15),
        backgroundCard:      Color(red: 0.09, green: 0.11, blue: 0.18),
        backgroundElevated:  Color(red: 0.12, green: 0.15, blue: 0.24),
        amber:               Color(red: 0.55, green: 0.48, blue: 0.97),
        amberMuted:          Color(red: 0.42, green: 0.36, blue: 0.76),
        amberGlow:           Color(red: 0.55, green: 0.48, blue: 0.97).opacity(0.18),
        teal:                Color(red: 0.13, green: 0.83, blue: 0.93),
        tealMuted:           Color(red: 0.10, green: 0.60, blue: 0.70),
        textPrimary:         Color(red: 0.90, green: 0.92, blue: 0.97),
        textSecondary:       Color(red: 0.55, green: 0.60, blue: 0.72),
        textTertiary:        Color(red: 0.35, green: 0.38, blue: 0.50),
        destructive:         Color(red: 0.90, green: 0.35, blue: 0.42),
        success:             Color(red: 0.30, green: 0.82, blue: 0.60)
    )
}

// MARK: - App Theme Enum

enum AppTheme: String, CaseIterable {
    case ember     = "ember"
    case parchment = "parchment"
    case midnight  = "midnight"

    var theme: TurtleTheme {
        switch self {
        case .ember:     return .ember
        case .parchment: return .parchment
        case .midnight:  return .midnight
        }
    }
}

// MARK: - Environment

struct AppThemeKey: EnvironmentKey {
    static let defaultValue: TurtleTheme = .ember
}

extension EnvironmentValues {
    var appTheme: TurtleTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Shared Components

struct ArtworkView: View {
    @Environment(\.appTheme) private var theme
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                theme.backgroundElevated
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.3, weight: .light))
                    .foregroundStyle(theme.amberMuted.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: TurtleTheme.artworkCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TurtleTheme.artworkCornerRadius)
                .strokeBorder(theme.textPrimary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

struct AmberProgressBar: View {
    @Environment(\.appTheme) private var theme
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.backgroundElevated)
                    .frame(height: 4)
                Capsule()
                    .fill(LinearGradient(
                        colors: [theme.amberMuted, theme.amber],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: proxy.size.width * min(max(value, 0), 1), height: 4)
                    .shadow(color: theme.amberGlow, radius: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 4)
    }
}

// MARK: - View Modifiers

struct TurtleCardStyle: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(theme.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: TurtleTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TurtleTheme.cardCornerRadius)
                    .strokeBorder(theme.amberMuted.opacity(0.12), lineWidth: 0.5)
            )
    }
}

extension View {
    func turtleCard() -> some View {
        modifier(TurtleCardStyle())
    }

    func turtleNavBarBackground(_ theme: TurtleTheme) -> some View {
        #if os(iOS)
        self
            .toolbarBackground(theme.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }
}
