#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Rings

/// A flat-capped progress ring that starts at 12 o'clock and fills clockwise. `progress` is 0...1;
/// nil draws the bare track (the honest empty state — never a fabricated zero arc).
struct ProRing: View {
    var progress: Double?
    var color: Color
    var lineWidth: CGFloat
    var track: Color = ProPalette.ringTrack

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var target: Double { min(1, max(0, progress ?? 0)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .onAppear {
            if reduceMotion { shown = target } else { withAnimation(ProMotion.ringFill) { shown = target } }
        }
        .onChange(of: target) { _, new in
            if reduceMotion { shown = new } else { withAnimation(ProMotion.ringUpdate) { shown = new } }
        }
    }
}

/// A score read-out: the big number with an optional smaller trailing unit ("85" + "%").
struct ProScoreText: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat
    var color: Color = ProPalette.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.02) {
            Text(value)
                .font(ProFont.score(size))
            if let unit {
                Text(unit)
                    .font(ProFont.score(size * 0.52))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// One of the three home dials: a ring with the score inside and a tracked label underneath.
struct ProScoreDial: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String? = nil
    let progress: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProRing(progress: progress, color: color, lineWidth: ProMetrics.dialStroke)
                ProScoreText(value: value, unit: unit, size: 27)
                    .padding(.horizontal, 12)
            }
            .frame(width: ProMetrics.dialDiameter, height: ProMetrics.dialDiameter)
            HStack(spacing: 3) {
                Text(title).proLabel(11)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(ProPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// The large detail-screen gauge: ring, NOOP wordmark, score and label, with optional page dots.
struct ProHeroGauge: View {
    let value: String
    var unit: String? = nil
    let label: LocalizedStringKey
    let progress: Double?
    let color: Color
    var caption: String? = nil

    var body: some View {
        ZStack {
            ProRing(progress: progress, color: color, lineWidth: ProMetrics.heroStroke)
            VStack(spacing: 4) {
                NoopWordmark()
                    .padding(.bottom, 2)
                ProScoreText(value: value, unit: unit, size: 76)
                Text(label)
                    .proLabel(14)
                    .multilineTextAlignment(.center)
                if let caption {
                    Text(caption)
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textSecondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 36)
        }
        .frame(width: ProMetrics.heroDiameter, height: ProMetrics.heroDiameter)
        .accessibilityElement(children: .combine)
    }
}

/// The NOOP wordmark in the thin, wide-tracked style that sits inside every hero ring.
struct NoopWordmark: View {
    var color: Color = ProPalette.textSecondary
    var body: some View {
        Text(verbatim: "NOOP")
            .font(ProFont.wordmark)
            .tracking(ProTracking.wordmark)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// The standard flat card: near-black slate fill, 12pt corners, a faint hairline.
struct ProCard<Content: View>: View {
    var padding: CGFloat = ProMetrics.cardPadding
    var fill: Color = ProPalette.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ProMetrics.cardRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ProMetrics.cardRadius, style: .continuous)
                    .strokeBorder(ProPalette.hairline, lineWidth: 1)
            )
    }
}

/// The rounded card with a small upward notch at top-centre that points at the gauge above it.
struct ProNotchedCardShape: Shape {
    var cornerRadius: CGFloat = ProMetrics.detailCardRadius
    var notchWidth: CGFloat = 20
    var notchHeight: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + notchHeight
        let r = min(cornerRadius, (rect.maxY - top) / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: top))
        p.addLine(to: CGPoint(x: rect.midX - notchWidth / 2, y: top))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + notchWidth / 2, y: top))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: top), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: top + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: top),
                 tangent2End: CGPoint(x: rect.maxX, y: top), radius: r)
        p.closeSubpath()
        return p
    }
}

/// The detail card under a hero gauge: notched, with a top-lit gradient that fades into the canvas.
struct ProDetailCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.top, 9 + 4)
            .padding(.horizontal, ProMetrics.cardPadding)
            .padding(.bottom, ProMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ProNotchedCardShape()
                    .fill(LinearGradient(colors: [ProPalette.cardTop, ProPalette.cardBottom],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                ProNotchedCardShape()
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.0)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

// MARK: - Rows

/// How a value compares with the personal baseline. `better`/`worse` are judged in the metric's own
/// direction (a lower resting HR is better); `higher`/`lower` are for metrics with no good direction.
enum ProComparison: Equatable {
    case better(up: Bool)
    case worse(up: Bool)
    case higher
    case lower
    case same
    case unknown

    /// Classify `value` against `baseline`. `higherIsBetter` nil means the metric has no good direction.
    /// Within `tolerance` (relative) of the baseline counts as unchanged.
    static func classify(_ value: Double?, baseline: Double?, higherIsBetter: Bool?,
                         tolerance: Double = 0.03) -> ProComparison {
        guard let value, let baseline, baseline != 0 else { return .unknown }
        let delta = (value - baseline) / abs(baseline)
        if abs(delta) <= tolerance { return .same }
        let up = delta > 0
        guard let higherIsBetter else { return up ? .higher : .lower }
        return up == higherIsBetter ? .better(up: up) : .worse(up: up)
    }
}

/// The comparison glyph: a small solid triangle, or a dot when unchanged.
struct ProComparisonGlyph: View {
    let comparison: ProComparison

    var body: some View {
        switch comparison {
        case .better(let up): triangle(up: up, color: ProPalette.better)
        case .worse(let up): triangle(up: up, color: ProPalette.worse)
        case .higher: triangle(up: true, color: ProPalette.neutral)
        case .lower: triangle(up: false, color: ProPalette.neutral)
        case .same:
            Circle().fill(ProPalette.neutral).frame(width: 6, height: 6)
                .frame(width: 10)
        case .unknown:
            Color.clear.frame(width: 10, height: 6)
        }
    }

    private func triangle(up: Bool, color: Color) -> some View {
        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 10)
    }
}

/// Three-tier quality (Poor / Sufficient / Optimal) for a percentage-style metric.
enum ProTier: Int {
    case poor = 0, sufficient = 1, optimal = 2

    static func of(_ value: Double?, sufficientFrom: Double, optimalFrom: Double) -> ProTier? {
        guard let value else { return nil }
        if value >= optimalFrom { return .optimal }
        if value >= sufficientFrom { return .sufficient }
        return .poor
    }

    var color: Color {
        switch self {
        case .poor: return ProPalette.tierPoor
        case .sufficient: return ProPalette.tierSufficient
        case .optimal: return ProPalette.tierOptimal
        }
    }
}

/// The three short dashes beside a row value; the dash for the active tier is lit in its colour.
struct ProTierBar: View {
    let tier: ProTier?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(tier?.rawValue == i ? (tier?.color ?? ProPalette.tierIdle) : ProPalette.tierIdle)
                    .frame(width: 18, height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A detail row: line icon, tracked title, optional tier bar, value and comparison glyph.
struct ProMetricRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    var comparison: ProComparison? = nil
    /// Draws the three-dash tier bar; `tier` nil leaves every dash unlit (no value to judge).
    var showsTier = false
    var tier: ProTier? = nil
    var showsDivider = true
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ProPalette.icon)
                .frame(width: 22)
            Text(title)
                .proLabel(12)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            if showsTier {
                ProTierBar(tier: tier)
                    .padding(.trailing, 10)
            }
            Text(value)
                .font(ProFont.number(20))
                .foregroundStyle(ProPalette.textPrimary)
                .lineLimit(1)
            if let comparison {
                ProComparisonGlyph(comparison: comparison)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProPalette.textTertiary)
            }
        }
        .frame(minHeight: ProMetrics.rowHeight)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(ProPalette.divider).frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "▲▼ Today vs. prior 30 days" — the legend under a comparison list.
struct ProComparisonLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.up.fill").foregroundStyle(ProPalette.better)
                Image(systemName: "arrowtriangle.down.fill").foregroundStyle(ProPalette.worse)
            }
            .font(.system(size: 8, weight: .bold))
            Text("Today vs. prior 30 days")
                .font(ProFont.caption)
                .foregroundStyle(ProPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ProPalette.inset))
        .padding(.top, 12)
    }
}

/// "— Poor — Sufficient — Optimal" — the legend under a tiered list.
struct ProTierLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(ProPalette.tierPoor, "Poor")
            item(ProPalette.tierSufficient, "Sufficient")
            item(ProPalette.tierOptimal, "Optimal")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ProPalette.inset))
        .padding(.top, 12)
    }

    private func item(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title).font(ProFont.caption).foregroundStyle(ProPalette.textSecondary)
        }
    }
}

// MARK: - Insight

/// The summary card with the purple→teal hairline border and an optional tracked link underneath that
/// pushes `route` onto the enclosing navigation stack.
struct ProInsightCard<Route: Hashable>: View {
    let text: String
    var linkTitle: LocalizedStringKey? = nil
    var route: Route? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(ProFont.body)
                .foregroundStyle(ProPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let linkTitle, let route {
                NavigationLink(value: route) {
                    HStack(spacing: 8) {
                        Text(linkTitle).proLabel(12, color: ProPalette.link)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ProPalette.link)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ProMetrics.detailCardRadius, style: .continuous)
            .fill(ProPalette.insightFill))
        .overlay(
            RoundedRectangle(cornerRadius: ProMetrics.detailCardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [ProPalette.insightBorderStart, ProPalette.insightBorderEnd],
                                             startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
        )
    }
}

// MARK: - Headers

/// A section title row ("My Day", "Activities") with an optional trailing accessory.
struct ProSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(ProFont.sectionTitle)
                .foregroundStyle(ProPalette.textPrimary)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension ProSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// A small tracked overline above a card group ("HEART RATE", "LAST 7 DAYS").
struct ProOverline: View {
    let title: LocalizedStringKey
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title).proLabel(12, color: ProPalette.textSecondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(ProFont.caption)
                    .foregroundStyle(ProPalette.textTertiary)
            }
        }
    }
}

/// The centred tracked title used in a detail screen's navigation bar.
struct ProNavTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(ProFont.label(15))
                .tracking(ProTracking.title)
                .textCase(.uppercase)
                .foregroundStyle(ProPalette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(ProFont.caption)
                    .foregroundStyle(ProPalette.textSecondary)
            }
        }
    }
}

extension View {
    /// Detail-screen navigation chrome: transparent bar, chevron-only back button, centred tracked
    /// title and an optional info button. Keeps the system back swipe.
    func proDetailNavigation(title: String, subtitle: String? = nil,
                             onInfo: (() -> Void)? = nil) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ProNavTitle(title: title, subtitle: subtitle)
                }
                if let onInfo {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onInfo) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(ProPalette.textPrimary)
                        }
                        .accessibilityLabel(Text("About this score"))
                    }
                }
            }
            .tint(ProPalette.textPrimary)
    }
}

// MARK: - Empty state

/// An honest "nothing to show" card: what is missing and what produces it.
struct ProEmptyCard: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        ProCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(ProPalette.icon)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(ProFont.cardTitle)
                        .foregroundStyle(ProPalette.textPrimary)
                    Text(message)
                        .font(ProFont.subtitle)
                        .foregroundStyle(ProPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Segmented range picker

/// The pill segmented control used for chart ranges (1W / 1M / 3M …).
struct ProSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.0 == selection
                Button {
                    withAnimation(ProMotion.tab) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(ProFont.label(12))
                        .tracking(0.8)
                        .foregroundStyle(selected ? Color.black : ProPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Capsule().fill(selected ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(ProPalette.pill))
    }
}

// MARK: - Charts

/// One bar or point in a Pro chart.
struct ProChartPoint: Identifiable, Equatable {
    let id: String
    let label: String
    let value: Double?
    var color: Color? = nil
}

/// Vertical bars with rounded tops, value labels above and day labels below. Missing values leave
/// their slot empty rather than drawing a zero.
struct ProBarChart: View {
    let points: [ProChartPoint]
    var color: Color = ProPalette.strain
    var maxValue: Double? = nil
    var height: CGFloat = 150
    var valueFormat: (Double) -> String = { String(format: "%.0f", $0) }
    var showsValues = true
    var labelStride = 1

    var body: some View {
        let top = maxValue ?? max(1, points.compactMap(\.value).max() ?? 1)
        VStack(spacing: 6) {
            GeometryReader { geo in
                let count = max(points.count, 1)
                let slot = geo.size.width / CGFloat(count)
                let barWidth = max(3, min(26, slot * 0.58))
                let valueRoom: CGFloat = showsValues ? 18 : 0
                ZStack(alignment: .bottomLeading) {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle()
                            .fill(ProPalette.hairline)
                            .frame(height: 1)
                            .offset(y: -CGFloat(i) * (geo.size.height - valueRoom) / 3)
                    }
                    ForEach(Array(points.enumerated()), id: \.element.id) { idx, p in
                        if let v = p.value {
                            let h = max(2, CGFloat(min(v, top) / top) * (geo.size.height - valueRoom))
                            VStack(spacing: 4) {
                                if showsValues {
                                    Text(valueFormat(v))
                                        .font(ProFont.number(11, weight: .semibold))
                                        .foregroundStyle(ProPalette.textSecondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                UnevenRoundedRectangle(topLeadingRadius: min(4, barWidth / 2),
                                                       topTrailingRadius: min(4, barWidth / 2),
                                                       style: .continuous)
                                    .fill(p.color ?? color)
                                    .frame(width: barWidth, height: h)
                            }
                            .frame(width: slot)
                            .offset(x: CGFloat(idx) * slot)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            }
            .frame(height: height)
            HStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.element.id) { idx, p in
                    Text(idx % max(1, labelStride) == 0 ? p.label : "")
                        .font(ProFont.label(9))
                        .tracking(0.6)
                        .foregroundStyle(ProPalette.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        points.compactMap { p in p.value.map { "\(p.label) \(valueFormat($0))" } }.joined(separator: ", ")
    }
}

/// A line with point markers, a soft area fill and an optional dashed baseline. Gaps (nil values)
/// break the line instead of bridging them.
struct ProLineChart: View {
    let points: [ProChartPoint]
    var color: Color = ProPalette.sleep
    var baseline: Double? = nil
    var height: CGFloat = 150
    var valueFormat: (Double) -> String = { String(format: "%.0f", $0) }
    var labelStride = 1
    var showsMarkers = true

    var body: some View {
        let values = points.compactMap(\.value) + (baseline.map { [$0] } ?? [])
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, max(abs(hi) * 0.1, 1))
        let minV = lo - span * 0.18
        let maxV = hi + span * 0.25
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let count = max(points.count, 1)
                let step = w / CGFloat(count)
                let x: (Int) -> CGFloat = { CGFloat($0) * step + step / 2 }
                let y: (Double) -> CGFloat = { h - CGFloat(($0 - minV) / (maxV - minV)) * h }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(ProPalette.hairline).frame(height: 1)
                            .offset(y: CGFloat(i) * h / 3)
                    }
                    if let baseline {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y(baseline)))
                            p.addLine(to: CGPoint(x: w, y: y(baseline)))
                        }
                        .stroke(ProPalette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(segments(), id: \.self) { seg in
                        Path { p in
                            p.move(to: CGPoint(x: x(seg[0]), y: h))
                            for i in seg { p.addLine(to: CGPoint(x: x(i), y: y(points[i].value ?? 0))) }
                            p.addLine(to: CGPoint(x: x(seg[seg.count - 1]), y: h))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.0)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            for (n, i) in seg.enumerated() {
                                let pt = CGPoint(x: x(i), y: y(points[i].value ?? 0))
                                if n == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                            }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if showsMarkers {
                        ForEach(Array(points.enumerated()), id: \.element.id) { idx, p in
                            if let v = p.value {
                                Circle()
                                    .fill(p.color ?? color)
                                    .overlay(Circle().stroke(ProPalette.canvasMid, lineWidth: 1.5))
                                    .frame(width: 7, height: 7)
                                    .position(x: x(idx), y: y(v))
                            }
                        }
                    }
                    if let lastIdx = points.lastIndex(where: { $0.value != nil }),
                       let v = points[lastIdx].value {
                        Text(valueFormat(v))
                            .font(ProFont.number(12, weight: .semibold))
                            .foregroundStyle(ProPalette.textPrimary)
                            .fixedSize()
                            .position(x: min(max(x(lastIdx), 16), w - 16), y: max(y(v) - 14, 8))
                    }
                }
            }
            .frame(height: height)
            HStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.element.id) { idx, p in
                    Text(idx % max(1, labelStride) == 0 ? p.label : "")
                        .font(ProFont.label(9))
                        .tracking(0.6)
                        .foregroundStyle(ProPalette.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(points.compactMap { p in p.value.map { "\(p.label) \(valueFormat($0))" } }
            .joined(separator: ", ")))
    }

    /// Runs of consecutive non-nil indices.
    private func segments() -> [[Int]] {
        var out: [[Int]] = []
        var run: [Int] = []
        for (i, p) in points.enumerated() {
            if p.value != nil { run.append(i) } else if !run.isEmpty { out.append(run); run = [] }
        }
        if !run.isEmpty { out.append(run) }
        return out
    }
}

/// A day of heart rate: a smooth line over an area fill, with workout windows shaded behind it.
struct ProHeartRateChart: View {
    /// (unix seconds, bpm) in time order.
    let samples: [(ts: Int, bpm: Double)]
    let windowStart: Int
    let windowEnd: Int
    var highlights: [(start: Int, end: Int)] = []
    var color: Color = ProPalette.strain
    var height: CGFloat = 160

    var body: some View {
        let bpms = samples.map { $0.bpm }
        let lo = max(30, (bpms.min() ?? 50) - 8)
        let hi = max(lo + 20, (bpms.max() ?? 120) + 8)
        let span = Double(max(1, windowEnd - windowStart))
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let x: (Int) -> CGFloat = { CGFloat(Double($0 - windowStart) / span) * w }
                let y: (Double) -> CGFloat = { h - CGFloat(($0 - lo) / (hi - lo)) * h }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(ProPalette.hairline).frame(height: 1)
                            .offset(y: CGFloat(i) * h / 3)
                    }
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, hl in
                        let x0 = max(0, x(hl.start))
                        let x1 = min(w, x(hl.end))
                        if x1 > x0 {
                            Rectangle()
                                .fill(color.opacity(0.16))
                                .frame(width: x1 - x0, height: h)
                                .offset(x: x0)
                        }
                    }
                    ForEach(runs(), id: \.self) { run in
                        Path { p in
                            p.move(to: CGPoint(x: x(samples[run[0]].ts), y: h))
                            for i in run { p.addLine(to: CGPoint(x: x(samples[i].ts), y: y(samples[i].bpm))) }
                            p.addLine(to: CGPoint(x: x(samples[run[run.count - 1]].ts), y: h))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.0)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            for (n, i) in run.enumerated() {
                                let pt = CGPoint(x: x(samples[i].ts), y: y(samples[i].bpm))
                                if n == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                            }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                    VStack {
                        Text(verbatim: "\(Int(hi.rounded()))")
                        Spacer()
                        Text(verbatim: "\(Int(lo.rounded()))")
                    }
                    .font(ProFont.number(10, weight: .semibold))
                    .foregroundStyle(ProPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: height)
            HStack {
                Text(Self.clock(windowStart))
                Spacer()
                Text(Self.clock((windowStart + windowEnd) / 2))
                Spacer()
                Text(Self.clock(windowEnd))
            }
            .font(ProFont.label(9))
            .tracking(0.6)
            .foregroundStyle(ProPalette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate chart"))
    }

    /// Consecutive samples no more than 15 minutes apart draw as one line; a longer gap breaks it.
    private func runs() -> [[Int]] {
        var out: [[Int]] = []
        var run: [Int] = []
        for i in samples.indices {
            if let last = run.last, samples[i].ts - samples[last].ts > 900 {
                if run.count > 1 { out.append(run) }
                run = []
            }
            run.append(i)
        }
        if run.count > 1 { out.append(run) }
        return out
    }

    static func clock(_ ts: Int) -> String {
        clockFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("jm")
        return f
    }()
}

/// The night as four stage lanes (Awake / REM / Light / Deep), each interval a rounded block in its
/// stage colour, joined by faint risers, with onset and wake times underneath.
struct ProHypnogram: View {
    let intervals: [SleepInterval]
    let onset: Date
    var height: CGFloat = 150

    private let lanes: [SleepStage] = [.awake, .rem, .light, .deep]

    var body: some View {
        let total = max(1, intervals.map(\.end).max() ?? 1)
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lanes, id: \.self) { stage in
                        Text(stage.label)
                            .font(ProFont.label(9))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(ProPalette.textTertiary)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: 44, height: height)
                GeometryReader { geo in
                    let w = geo.size.width
                    let laneH = geo.size.height / CGFloat(lanes.count)
                    let blockH = laneH * 0.62
                    let laneY: (SleepStage) -> CGFloat = { stage in
                        CGFloat(lanes.firstIndex(of: stage) ?? 0) * laneH + laneH / 2
                    }
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<lanes.count, id: \.self) { i in
                            Rectangle().fill(ProPalette.hairline).frame(height: 1)
                                .offset(y: CGFloat(i) * laneH + laneH / 2)
                        }
                        Path { p in
                            for (i, iv) in intervals.enumerated() where i > 0 {
                                let prev = intervals[i - 1]
                                let xx = CGFloat(iv.start / total) * w
                                p.move(to: CGPoint(x: xx, y: laneY(prev.stage)))
                                p.addLine(to: CGPoint(x: xx, y: laneY(iv.stage)))
                            }
                        }
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        ForEach(intervals) { iv in
                            let x0 = CGFloat(iv.start / total) * w
                            let bw = max(1.5, CGFloat((iv.end - iv.start) / total) * w)
                            RoundedRectangle(cornerRadius: min(3, bw / 2), style: .continuous)
                                .fill(ProPalette.stage(iv.stage))
                                .frame(width: bw, height: blockH)
                                .offset(x: x0, y: laneY(iv.stage) - blockH / 2)
                        }
                    }
                }
                .frame(height: height)
            }
            HStack {
                Text(ProHeartRateChart.clock(Int(onset.timeIntervalSince1970)))
                Spacer()
                Text(ProHeartRateChart.clock(Int(onset.timeIntervalSince1970 + total)))
            }
            .font(ProFont.label(9))
            .tracking(0.6)
            .foregroundStyle(ProPalette.textTertiary)
            .padding(.leading, 54)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages timeline"))
    }
}

/// One stage row: swatch, name, duration, share bar and percentage.
struct ProStageRow: View {
    let stage: SleepStage
    let minutes: Double
    let total: Double
    var typicalMinutes: Double? = nil

    var body: some View {
        let share = total > 0 ? minutes / total : 0
        VStack(spacing: 8) {
            HStack {
                Circle().fill(ProPalette.stage(stage)).frame(width: 8, height: 8)
                Text(stage.label).proLabel(12)
                Spacer()
                Text(ProFormat.duration(minutes: minutes))
                    .font(ProFont.number(17))
                    .foregroundStyle(ProPalette.textPrimary)
                Text(verbatim: "\(Int((share * 100).rounded()))%")
                    .font(ProFont.number(13, weight: .semibold))
                    .foregroundStyle(ProPalette.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ProPalette.tierIdle)
                    Capsule().fill(ProPalette.stage(stage))
                        .frame(width: max(2, geo.size.width * CGFloat(min(1, share))))
                    if let typicalMinutes, total > 0 {
                        Rectangle().fill(Color.white.opacity(0.7))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * CGFloat(min(1, typicalMinutes / total)) - 1)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Formatting

enum ProFormat {
    /// "7:42" style hours:minutes.
    static func duration(minutes: Double) -> String {
        guard minutes.isFinite else { return "—" }
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// "85%" — a whole percentage with its sign, for use as a format argument.
    static func percentText(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    /// "420 kcal".
    static func kcal(_ v: Double) -> String {
        "\(integer(v)) kcal"
    }

    static func percent(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        return "\(Int(v.rounded()))"
    }

    static func integer(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        return Int(v.rounded()).formatted(.number.locale(AppLanguage.activeLocale))
    }

    static func decimal(_ v: Double?, digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return v.formatted(.number.precision(.fractionLength(digits)).locale(AppLanguage.activeLocale))
    }

    /// Short weekday initial label for a yyyy-MM-dd key ("M", "T", …).
    static func weekdayLetter(_ dayKey: String) -> String {
        guard let d = dayKeyParser.date(from: dayKey) else { return "" }
        return weekdayFormatter.string(from: d).uppercased()
    }

    /// "12" style day-of-month label.
    static func dayOfMonth(_ dayKey: String) -> String {
        guard let d = dayKeyParser.date(from: dayKey) else { return "" }
        return String(Calendar.current.component(.day, from: d))
    }

    /// "MON, NOV 3" style header for a yyyy-MM-dd key.
    static func longDay(_ dayKey: String) -> String {
        guard let d = dayKeyParser.date(from: dayKey) else { return dayKey }
        return longFormatter.string(from: d)
    }

    static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f
    }()
}
#endif
