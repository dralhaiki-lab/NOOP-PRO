#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Interface preference
//
// The performance-wearable interface ("Pro" layout) is the iPhone default. The classic NOOP shell —
// Liquid Today, the five native tabs, the More index — stays one switch away in the More tab and in
// Settings, so nothing the classic layout reaches is lost. The key is iOS-only on purpose: Android and
// macOS keep their own shells and never read it.
enum ProInterface {
    static let storageKey = "noop.proInterfaceEnabled"
    static let defaultEnabled = true
}

// MARK: - Design tokens
//
// Every colour, type role and dimension the Pro interface draws with lives here, so a screen never
// hardcodes one. Values were sampled from reference captures of the performance-wearable layout this
// shell follows (dark slate canvas, near-black cards, saturated score rings).

/// Colour tokens. The Pro interface is dark-only, so these are plain colours, not light/dark pairs.
enum ProPalette {
    // Canvas
    static let canvasTop = Color(hex: "#232C33")
    static let canvasMid = Color(hex: "#161B1F")
    static let canvasBottom = Color(hex: "#0E1215")
    static let canvasGlow = Color(hex: "#2E3C47")

    // Surfaces
    static let card = Color(hex: "#24292D")
    static let cardRaised = Color(hex: "#2B3035")
    static let cardTop = Color(hex: "#2A2D32")
    static let cardBottom = Color(hex: "#171C20")
    static let cardNotch = Color(hex: "#2D3135")
    static let inset = Color(hex: "#090C0D")
    static let pill = Color(hex: "#2D343A")
    static let insightFill = Color(hex: "#101518")
    static let hairline = Color.white.opacity(0.07)
    static let divider = Color(hex: "#30353A")
    static let tabBar = Color(hex: "#262D34")

    // Rings
    static let ringTrack = Color(hex: "#363D41")
    static let ringTrackDim = Color(hex: "#2C3337")
    static let ringSegment = Color(hex: "#595D60")

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#B3B6BA")
    static let textTertiary = Color(hex: "#7D8389")
    static let icon = Color(hex: "#909398")
    static let tabInactive = Color(hex: "#8A919B")
    static let link = Color(hex: "#7797DB")

    // Scores
    static let recoveryHigh = Color(hex: "#16EC06")
    static let recoveryMid = Color(hex: "#FFDE00")
    static let recoveryLow = Color(hex: "#FF0026")
    static let strain = Color(hex: "#0093E7")
    static let sleep = Color(hex: "#7BA1BB")
    static let stress = Color(hex: "#3DAF8D")

    // Comparison against the personal baseline
    static let better = Color(hex: "#10EFA9")
    static let worse = Color(hex: "#F3AC53")
    static let neutral = Color(hex: "#8E9399")

    // Three-tier quality scale (Poor / Sufficient / Optimal)
    static let tierPoor = Color(hex: "#F3AC53")
    static let tierSufficient = Color(hex: "#8E9296")
    static let tierOptimal = Color(hex: "#10EFA9")
    static let tierIdle = Color(hex: "#34383C")

    // Insight card border
    static let insightBorderStart = Color(hex: "#4B4677")
    static let insightBorderEnd = Color(hex: "#2A5C6E")

    // Sleep stages
    static let stageAwake = Color(hex: "#D3D7DB")
    static let stageLight = Color(hex: "#8FB0C9")
    static let stageDeep = Color(hex: "#5C6FE0")
    static let stageREM = Color(hex: "#A986F0")

    // Daily Outlook row
    static let outlookStart = Color(hex: "#48534F")
    static let outlookEnd = Color(hex: "#31414E")

    // Coach button
    static let coachTop = Color(hex: "#454A6E")
    static let coachBottom = Color(hex: "#20233A")

    /// Recovery band colour: 67–100 green, 34–66 yellow, 0–33 red.
    static func recovery(_ score: Double?) -> Color {
        guard let score else { return ringTrack }
        switch score {
        case 67...: return recoveryHigh
        case 34..<67: return recoveryMid
        default: return recoveryLow
        }
    }

    /// Heart-rate zone colours, Zone 1 (easy) → Zone 5 (max).
    static let zones: [Color] = [
        Color(hex: "#8E9399"), Color(hex: "#3FA9F5"), Color(hex: "#10EFA9"),
        Color(hex: "#F3AC53"), Color(hex: "#FF4B4B"),
    ]

    static func zone(_ number: Int) -> Color {
        zones[min(max(number, 1), zones.count) - 1]
    }

    static func stage(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return stageAwake
        case .light: return stageLight
        case .deep: return stageDeep
        case .rem: return stageREM
        }
    }
}

/// Type roles. Scores use a bold condensed grotesque; labels are small, heavy, tracked capitals;
/// prose is the system text face.
enum ProFont {
    static func score(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold).width(.condensed).monospacedDigit()
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
    static func label(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .bold) }
    static let wordmark = Font.system(size: 15, weight: .light).width(.expanded)
    static let body = Font.system(size: 16, weight: .regular)
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let sectionTitle = Font.system(size: 22, weight: .semibold)
    static let subtitle = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .medium)
    static let tab = Font.system(size: 10, weight: .medium)
}

/// Letter-spacing for the tracked-capital label style, per size.
enum ProTracking {
    static let label: CGFloat = 1.3
    static let title: CGFloat = 1.6
    static let wordmark: CGFloat = 5
}

/// Dimensions.
enum ProMetrics {
    static let page: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let detailCardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let section: CGFloat = 24
    static let gap: CGFloat = 12
    static let rowHeight: CGFloat = 52
    static let dialDiameter: CGFloat = 92
    static let dialStroke: CGFloat = 6.5
    static let heroDiameter: CGFloat = 252
    static let heroStroke: CGFloat = 16
    static let tabBarHeight: CGFloat = 62
    /// Extra bottom scroll room under a tab root's last card. The shell already reserves the floating
    /// bar's own height as safe area, so this is breathing room only.
    static let tabBarClearance: CGFloat = 28
    /// Safe-area reserve for the gym-session bar stacked above the tab bar (bar height + gap).
    static let liftBarReserve: CGFloat = 74
}

/// Motion.
enum ProMotion {
    static let ringFill = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 1.0)
    static let ringUpdate = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.6)
    static let tab = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
    static let press = Animation.easeOut(duration: 0.12)
}

// MARK: - Canvas

/// The full-bleed canvas behind every Pro screen: a slate gradient that settles to near-black, with a
/// faint cool glow in the top-left corner.
struct ProCanvas: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: ProPalette.canvasTop, location: 0),
                .init(color: ProPalette.canvasMid, location: 0.42),
                .init(color: ProPalette.canvasBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [ProPalette.canvasGlow.opacity(0.55), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Tracked-capital label styling (the small heavy caps used for every section and row title).
    func proLabel(_ size: CGFloat = 12, color: Color = ProPalette.textPrimary) -> some View {
        self.font(ProFont.label(size))
            .tracking(ProTracking.label)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// The standard Pro page chrome: canvas behind, dark colour scheme, no system bar background.
    func proPageChrome() -> some View {
        self.background(ProCanvas())
            .environment(\.colorScheme, .dark)
    }
}

/// Press feedback used by every tappable card: a quick dim + scale.
struct ProPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(ProMotion.press, value: configuration.isPressed)
    }
}
#endif
