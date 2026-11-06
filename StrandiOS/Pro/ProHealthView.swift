#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Trend metrics

/// The metrics the Health tab trends. Each maps to the stored daily column it reads, its catalog key
/// (for the full source-aware detail screen) and how it is drawn.
enum ProTrendMetric: String, Hashable, CaseIterable, Identifiable {
    case recovery, hrv, restingHR, respiratory, strain, sleepPerformance, sleepHours, steps, calories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: return String(localized: "Recovery")
        case .hrv: return String(localized: "Heart Rate Variability")
        case .restingHR: return String(localized: "Resting Heart Rate")
        case .respiratory: return String(localized: "Respiratory Rate")
        case .strain: return String(localized: "Strain")
        case .sleepPerformance: return String(localized: "Sleep Performance")
        case .sleepHours: return String(localized: "Hours of Sleep")
        case .steps: return String(localized: "Steps")
        case .calories: return String(localized: "Calories")
        }
    }

    var icon: String {
        switch self {
        case .recovery: return "bolt.heart"
        case .hrv: return "waveform.path.ecg"
        case .restingHR: return "heart"
        case .respiratory: return "lungs"
        case .strain: return "flame"
        case .sleepPerformance: return "moon.zzz"
        case .sleepHours: return "bed.double"
        case .steps: return "shoeprints.fill"
        case .calories: return "bolt"
        }
    }

    var color: Color {
        switch self {
        case .recovery: return ProPalette.recoveryHigh
        case .hrv: return ProPalette.better
        case .restingHR: return ProPalette.recoveryLow
        case .respiratory: return ProPalette.link
        case .strain, .steps, .calories: return ProPalette.strain
        case .sleepPerformance, .sleepHours: return ProPalette.sleep
        }
    }

    /// The `MetricCatalog` key behind the full detail screen.
    var catalogKey: String {
        switch self {
        case .recovery: return "recovery"
        case .hrv: return "hrv"
        case .restingHR: return "rhr"
        case .respiratory: return "resp_rate"
        case .strain: return "strain"
        case .sleepPerformance: return "sleep_performance"
        case .sleepHours: return "sleep_total_min"
        case .steps: return "steps"
        case .calories: return "energy_kcal"
        }
    }

    var unit: String {
        switch self {
        case .recovery, .sleepPerformance: return "%"
        case .hrv: return "ms"
        case .restingHR: return "bpm"
        case .respiratory: return "rpm"
        case .strain, .steps, .sleepHours: return ""
        case .calories: return "kcal"
        }
    }

    var higherIsBetter: Bool? {
        switch self {
        case .recovery, .hrv, .sleepPerformance, .sleepHours, .steps: return true
        case .restingHR: return false
        case .respiratory, .strain, .calories: return nil
        }
    }

    /// Bars for daily totals and scores, a line for physiological signals.
    var drawsBars: Bool {
        switch self {
        case .recovery, .strain, .sleepHours, .steps, .calories: return true
        case .hrv, .restingHR, .respiratory, .sleepPerformance: return false
        }
    }

    /// The day's value from its stored row. Sleep performance reads its own series instead.
    func value(_ d: DailyMetric) -> Double? {
        switch self {
        case .recovery: return d.recovery
        case .hrv: return d.avgHrv
        case .restingHR: return d.restingHr.map(Double.init)
        case .respiratory: return d.respRateBpm
        case .strain: return d.strain
        case .sleepPerformance: return nil
        case .sleepHours: return d.totalSleepMin
        case .steps: return d.steps.map(Double.init)
        case .calories: return d.activeKcalEst
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .recovery, .sleepPerformance: return "\(Int(v.rounded()))%"
        case .strain: return ProScores.effortText(v)
        case .sleepHours: return ProFormat.duration(minutes: v)
        case .respiratory: return ProFormat.decimal(v)
        case .hrv, .restingHR, .steps, .calories: return ProFormat.integer(v)
        }
    }

    func points(rows: [DailyMetric], sleepPerformance: [String: Double], endKey: String, days: Int) -> [ProChartPoint] {
        let barColor: ((Double) -> Color)? = self == .recovery ? { ProPalette.recovery($0) } : nil
        if self == .sleepPerformance {
            return ProHistory.points(sleepPerformance, endKey: endKey, days: days)
        }
        return ProHistory.points(rows, endKey: endKey, days: days, value: { self.value($0) }, color: barColor)
    }
}

/// Health-tab range: 1 week to 6 months.
enum ProLongRange: Int, Hashable {
    case week = 7, month = 30, quarter = 90, half = 180
    static let options: [(ProLongRange, String)] = [(.week, "1W"), (.month, "1M"), (.quarter, "3M"), (.half, "6M")]
}

// MARK: - Health tab

/// The Health tab: the body-age hero, the vital-sign monitor, and a trend card per metric.
struct ProHealthView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @State private var range: ProLongRange = .month
    @State private var sleepPerformance: [String: Double] = [:]
    @State private var fitnessAge: (day: String, value: Double)?
    @State private var vo2max: Double?
    @State private var vitality: Double?
    @State private var readings: [BodyVitalReading] = []

    private static let topID = "proHealth.top"
    private var todayKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    ProNavTitle(title: String(localized: "Health"),
                                subtitle: String(localized: "Long-term trends from your own data"))
                        .padding(.top, 10)
                    ageHero
                        .padding(.top, 20)
                    monitor
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, ProMetrics.section)
                    trends
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, ProMetrics.section)
                    explore
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, ProMetrics.section)
                }
                .padding(.bottom, ProMetrics.tabBarClearance)
            }
            .refreshable { await repo.refresh(); await load() }
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .proPageChrome()
        .task(id: repo.refreshSeq) { await load() }
    }

    private func load() async {
        async let perfA = repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        async let fitA = repo.exploreSeries(key: "fitness_age", source: "my-whoop")
        async let vo2A = repo.exploreSeries(key: "vo2max_est", source: "my-whoop")
        async let vitA = repo.exploreSeries(key: "vitality", source: "my-whoop")
        let perf = await perfA
        sleepPerformance = Dictionary(perf.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        fitnessAge = (await fitA).last.map { (day: $0.day, value: $0.value) }
        vo2max = (await vo2A).last?.value
        vitality = (await vitA).last?.value
        readings = BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows,
                                           temperatureUnit: ProScores.temperatureUnit(),
                                           skinTempPreferred: ProScores.skinTempPreference())
    }

    // MARK: Age hero

    private var ageHero: some View {
        VStack(spacing: 18) {
            ZStack {
                ProParticleSphere(color: ProPalette.better)
                    .frame(width: 250, height: 250)
                VStack(spacing: 6) {
                    Text(fitnessAge.map { ProFormat.decimal($0.value) } ?? "—")
                        .font(ProFont.score(60))
                        .foregroundStyle(ProPalette.textPrimary)
                    Text("Fitness Age").proLabel(14)
                    if let delta = ageDelta {
                        Text(delta >= 0 ? String(localized: "\(ProFormat.decimal(delta)) years younger")
                                        : String(localized: "\(ProFormat.decimal(-delta)) years older"))
                            .font(ProFont.label(13))
                            .foregroundStyle(delta >= 0 ? ProPalette.better : ProPalette.worse)
                    } else if fitnessAge == nil {
                        Text("Builds from your heart-rate history")
                            .font(ProFont.caption)
                            .foregroundStyle(ProPalette.textSecondary)
                    }
                }
            }
            HStack(spacing: ProMetrics.gap) {
                heroStat("VO₂ Max", vo2max.map { ProFormat.decimal($0) } ?? "—", route: .metric("vo2max_est"))
                heroStat("Vitality", vitality.map { ProFormat.integer($0) } ?? "—", route: .metric("vitality"))
                heroStat("Fitness Age", fitnessAge.map { ProFormat.decimal($0.value) } ?? "—", route: .metric("fitness_age"))
            }
            .padding(.horizontal, ProMetrics.page)
        }
    }

    /// Chronological age minus fitness age (positive = younger), when both are known.
    private var ageDelta: Double? {
        guard let fit = fitnessAge?.value, profile.age > 0 else { return nil }
        return Double(profile.age) - fit
    }

    private func heroStat(_ title: LocalizedStringKey, _ value: String, route: TabRoute) -> some View {
        NavigationLink(value: route) {
            ProCard(padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).proLabel(10, color: ProPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(value)
                        .font(ProFont.number(20))
                        .foregroundStyle(ProPalette.textPrimary)
                }
            }
        }
        .buttonStyle(ProPressStyle())
    }

    // MARK: Monitor

    private var monitor: some View {
        let withData = readings.filter { $0.banding.band != .noData }
        let inRange = withData.filter { $0.banding.band == .inRange }.count
        return VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader(title: "Health Monitor") {
                NavigationLink(value: TabRoute.health) {
                    HStack(spacing: 4) {
                        Text("Details").proLabel(11, color: ProPalette.link)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ProPalette.link)
                    }
                }
                .buttonStyle(.plain)
            }
            ProCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: withData.isEmpty ? "minus.circle" : (inRange == withData.count
                                                                               ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
                            .font(.system(size: 22))
                            .foregroundStyle(withData.isEmpty ? ProPalette.neutral
                                             : (inRange == withData.count ? ProPalette.better : ProPalette.worse))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(withData.isEmpty ? String(localized: "No vitals yet")
                                 : (inRange == withData.count ? String(localized: "All metrics within range")
                                    : String(localized: "\(withData.count - inRange) outside your range")))
                                .font(ProFont.cardTitle)
                                .foregroundStyle(ProPalette.textPrimary)
                            Text(withData.isEmpty ? String(localized: "Sync overnight data to start the monitor.")
                                 : String(localized: "\(inRange)/\(withData.count) metrics in your typical range"))
                                .font(ProFont.caption)
                                .foregroundStyle(ProPalette.textSecondary)
                        }
                    }
                    if !readings.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            ForEach(readings) { r in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(r.banding.band == .inRange ? ProPalette.better
                                              : (r.banding.band == .outOfRange ? ProPalette.worse : ProPalette.ringTrack))
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.label).proLabel(9, color: ProPalette.textSecondary)
                                            .lineLimit(1)
                                        Text(r.formattedValue ?? "—")
                                            .font(ProFont.number(15))
                                            .foregroundStyle(ProPalette.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Trends

    private var trends: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader("Trends")
            ProSegmented(options: ProLongRange.options, selection: $range)
            ForEach(ProTrendMetric.allCases) { metric in
                NavigationLink(value: ProRoute.trend(metric)) {
                    trendCard(metric)
                }
                .buttonStyle(ProPressStyle())
            }
        }
    }

    private func trendCard(_ metric: ProTrendMetric) -> some View {
        let points = metric.points(rows: repo.days, sleepPerformance: sleepPerformance,
                                   endKey: todayKey, days: range.rawValue)
        let avg = ProHistory.average(points)
        let firstHalf = ProHistory.average(Array(points.prefix(points.count / 2)))
        let secondHalf = ProHistory.average(Array(points.suffix(points.count - points.count / 2)))
        return ProCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: metric.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(metric.color)
                        .frame(width: 22)
                    Text(metric.title).proLabel(12)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text(avg.map { metric.format($0) } ?? "—")
                        .font(ProFont.number(20))
                        .foregroundStyle(ProPalette.textPrimary)
                    ProComparisonGlyph(comparison: ProComparison.classify(secondHalf, baseline: firstHalf,
                                                                          higherIsBetter: metric.higherIsBetter))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ProPalette.textTertiary)
                }
                if points.contains(where: { $0.value != nil }) {
                    if metric.drawsBars {
                        ProBarChart(points: points, color: metric.color, height: 70, showsValues: false,
                                    labelStride: ProHistory.stride(for: range.rawValue))
                    } else {
                        ProLineChart(points: points, color: metric.color, height: 70,
                                     valueFormat: { metric.format($0) },
                                     labelStride: ProHistory.stride(for: range.rawValue),
                                     showsMarkers: range == .week)
                    }
                } else {
                    Text("No data in this period")
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textTertiary)
                }
                Text(String(localized: "Average over \(range.rawValue) days"))
                    .font(ProFont.caption)
                    .foregroundStyle(ProPalette.textTertiary)
            }
        }
    }

    // MARK: Explore

    private var explore: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader("Explore")
            ProCard(padding: 0) {
                VStack(spacing: 0) {
                    exploreRow("All Metrics", "square.grid.2x2", .metricExplorer)
                    exploreRow("Stress", "bolt.heart", .stress)
                    exploreRow("Body & Vitals", "heart.text.square", .health)
                    exploreRow("Full-Day Heart Rate", "waveform.path.ecg", .fullDayChart)
                    exploreRow("Data Sources", "externaldrive", .dataSources, last: true)
                }
            }
        }
    }

    private func exploreRow(_ title: LocalizedStringKey, _ icon: String, _ route: TabRoute, last: Bool = false) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(ProPalette.icon)
                    .frame(width: 24)
                Text(title)
                    .font(ProFont.body)
                    .foregroundStyle(ProPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(ProPalette.divider).frame(height: 1).padding(.leading, 52) }
            }
        }
        .buttonStyle(ProPressStyle())
    }
}

/// A glowing disc of seeded particles, densest at the rim — the backdrop for the age hero. The seed is
/// fixed, so the pattern is stable across redraws.
struct ProParticleSphere: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [Color.black.opacity(0.9), color.opacity(0.18), color.opacity(0.42)]),
                                               center: c, startRadius: radius * 0.35, endRadius: radius))
                var rng = ProSeededRandom(seed: 0x5EED)
                for _ in 0..<520 {
                    let angle = rng.next() * 2 * .pi + t * 0.04
                    let r = radius * (0.42 + 0.58 * pow(rng.next(), 0.45))
                    let p = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                    let dot = 0.8 + rng.next() * 2.6
                    let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 1.3 + rng.next() * 20))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)),
                             with: .color(color.opacity(twinkle * (r / radius))))
                }
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius + 1, y: c.y - radius + 1,
                                                  width: radius * 2 - 2, height: radius * 2 - 2)),
                           with: .color(color.opacity(0.55)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A tiny deterministic generator (SplitMix64) so the particle layout never shifts between frames.
struct ProSeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}

// MARK: - Trend detail

/// One metric over a chosen range: average, low/high, the chart and the daily values, with a link to
/// the full source-aware metric screen.
struct ProTrendDetailView: View {
    let metric: ProTrendMetric
    @EnvironmentObject private var repo: Repository
    @State private var range: ProLongRange = .month
    @State private var sleepPerformance: [String: Double] = [:]

    private var endKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }

    var body: some View {
        let points = metric.points(rows: repo.days, sleepPerformance: sleepPerformance, endKey: endKey, days: range.rawValue)
        let values = points.compactMap(\.value)
        return ProDetailScaffold(title: metric.title) {
            VStack(spacing: 6) {
                Text("Average").proLabel(11, color: ProPalette.textSecondary)
                Text(ProHistory.average(points).map { metric.format($0) } ?? "—")
                    .font(ProFont.score(56))
                    .foregroundStyle(ProPalette.textPrimary)
                if !metric.unit.isEmpty {
                    Text(verbatim: metric.unit)
                        .font(ProFont.label(12))
                        .foregroundStyle(ProPalette.textSecondary)
                }
            }
            .padding(.top, 12)
            ProSegmented(options: ProLongRange.options, selection: $range)
                .padding(.top, 20)
            ProCard {
                if values.isEmpty {
                    Text("No data in this period")
                        .font(ProFont.subtitle)
                        .foregroundStyle(ProPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if metric.drawsBars {
                    ProBarChart(points: points, color: metric.color, height: 190,
                                valueFormat: { metric.format($0) }, showsValues: range == .week,
                                labelStride: ProHistory.stride(for: range.rawValue))
                } else {
                    ProLineChart(points: points, color: metric.color, baseline: ProHistory.average(points),
                                 height: 190, valueFormat: { metric.format($0) },
                                 labelStride: ProHistory.stride(for: range.rawValue), showsMarkers: range == .week)
                }
            }
            .padding(.top, ProMetrics.gap)
            HStack(spacing: ProMetrics.gap) {
                stat("Low", values.min())
                stat("High", values.max())
                stat("Days", values.isEmpty ? nil : Double(values.count), plain: true)
            }
            .padding(.top, ProMetrics.gap)
            dailyList(points)
                .padding(.top, ProMetrics.section)
            NavigationLink(value: TabRoute.metric(metric.catalogKey)) {
                HStack(spacing: 8) {
                    Text("Sources & full history").proLabel(12, color: ProPalette.link)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ProPalette.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, ProMetrics.section)
        }
        .task(id: repo.refreshSeq) {
            guard metric == .sleepPerformance else { return }
            let perf = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
            sleepPerformance = Dictionary(perf.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        }
    }

    private func stat(_ title: LocalizedStringKey, _ v: Double?, plain: Bool = false) -> some View {
        ProCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).proLabel(10, color: ProPalette.textSecondary)
                Text(v.map { plain ? ProFormat.integer($0) : metric.format($0) } ?? "—")
                    .font(ProFont.number(19))
                    .foregroundStyle(ProPalette.textPrimary)
            }
        }
    }

    private func dailyList(_ points: [ProChartPoint]) -> some View {
        let recent = points.filter { $0.value != nil }.suffix(14).reversed()
        return VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Recent Days")
            ProCard(padding: 0) {
                VStack(spacing: 0) {
                    if recent.isEmpty {
                        Text("No data in this period")
                            .font(ProFont.subtitle)
                            .foregroundStyle(ProPalette.textTertiary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(recent)) { p in
                        HStack {
                            Text(ProFormat.longDay(p.id))
                                .font(ProFont.body)
                                .foregroundStyle(ProPalette.textSecondary)
                            Spacer()
                            Text(p.value.map { metric.format($0) } ?? "—")
                                .font(ProFont.number(17))
                                .foregroundStyle(ProPalette.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(ProPalette.divider).frame(height: 1).padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }
}
#endif
