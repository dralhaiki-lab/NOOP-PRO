#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Shared detail scaffolding

/// The scroll page every score deep-dive sits in: canvas, transparent bar with a centred day title
/// and an info button, generous bottom room (the tab bar is hidden on pushed screens).
struct ProDetailScaffold<Content: View>: View {
    let title: String
    var onInfo: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) { content }
                .padding(.horizontal, ProMetrics.page)
                .padding(.top, 8)
                .padding(.bottom, 48)
        }
        .proPageChrome()
        .proDetailNavigation(title: title, onInfo: onInfo)
    }
}

/// Day-series helpers for the trend charts.
enum ProHistory {
    /// One point per calendar day for the `days` days ending on `endKey`, oldest → newest. Days with
    /// no row (or no value) stay nil so the chart leaves a gap instead of drawing a zero.
    static func points(_ rows: [DailyMetric], endKey: String, days: Int,
                       value: (DailyMetric) -> Double?,
                       color: ((Double) -> Color)? = nil) -> [ProChartPoint] {
        let byDay = Dictionary(rows.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return dayKeys(endKey: endKey, days: days).map { key in
            let v = byDay[key].flatMap(value)
            return ProChartPoint(id: key, label: label(key, days: days), value: v,
                                 color: v.flatMap { color?($0) })
        }
    }

    /// Same, from a day-keyed dictionary.
    static func points(_ byDay: [String: Double], endKey: String, days: Int,
                       color: ((Double) -> Color)? = nil) -> [ProChartPoint] {
        dayKeys(endKey: endKey, days: days).map { key in
            let v = byDay[key]
            return ProChartPoint(id: key, label: label(key, days: days), value: v,
                                 color: v.flatMap { color?($0) })
        }
    }

    static func dayKeys(endKey: String, days: Int) -> [String] {
        guard let end = ProFormat.dayKeyParser.date(from: endKey) else { return [] }
        return (0..<max(1, days)).reversed().compactMap { back in
            Calendar.current.date(byAdding: .day, value: -back, to: end).map { ProFormat.dayKeyParser.string(from: $0) }
        }
    }

    static func label(_ key: String, days: Int) -> String {
        days <= 7 ? ProFormat.weekdayLetter(key) : ProFormat.dayOfMonth(key)
    }

    static func stride(for days: Int) -> Int { days <= 7 ? 1 : (days <= 31 ? 5 : 15) }

    static func average(_ points: [ProChartPoint]) -> Double? {
        let v = points.compactMap(\.value)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}

/// 7-day / 30-day range for the deep-dive charts.
enum ProRange: Int, Hashable {
    case week = 7
    case month = 30

    static let options: [(ProRange, String)] = [(.week, "7D"), (.month, "30D")]
}

/// A titled trend card with a 7D / 30D switch and its period average.
struct ProTrendCard<Chart: View>: View {
    let title: LocalizedStringKey
    @Binding var range: ProRange
    let average: String?
    @ViewBuilder var chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).proLabel(12, color: ProPalette.textSecondary)
                Spacer()
                if let average {
                    Text(average)
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
            ProCard {
                VStack(spacing: 14) {
                    ProSegmented(options: ProRange.options, selection: $range)
                    chart
                }
            }
        }
    }
}

// MARK: - Recovery

/// The Recovery deep-dive: hero ring, the four recovery inputs against the prior 30 days, a plain
/// summary, trends and the full vital-sign check.
struct ProRecoveryView: View {
    @ObservedObject var store: ProDayStore
    @EnvironmentObject private var repo: Repository

    @State private var guide: ScoreSection?
    @State private var range: ProRange = .week

    private var snap: ProDaySnapshot { store.snapshot }

    var body: some View {
        ProDetailScaffold(title: store.dayTitle, onInfo: { guide = .charge }) {
            ProHeroGauge(value: ProFormat.percent(snap.recoveryPct),
                         unit: snap.recoveryPct == nil ? nil : "%",
                         label: "Recovery",
                         progress: snap.recoveryPct.map { $0 / 100 },
                         color: ProPalette.recovery(snap.recoveryPct),
                         caption: heroCaption)
                .padding(.top, 8)
            ProDetailCard {
                VStack(spacing: 0) {
                    ProMetricRow(icon: "waveform.path.ecg", title: "Heart Rate Variability",
                                 value: ProFormat.integer(snap.hrv), comparison: hrvComparison)
                    ProMetricRow(icon: "heart", title: "Resting Heart Rate",
                                 value: ProFormat.integer(snap.restingHR), comparison: rhrComparison)
                    ProMetricRow(icon: "lungs", title: "Respiratory Rate",
                                 value: ProFormat.decimal(snap.respiratory), comparison: respComparison)
                    ProMetricRow(icon: "moon.zzz", title: "Sleep Performance",
                                 value: snap.sleepPerformance.map { "\(Int($0.rounded()))%" } ?? "—",
                                 comparison: sleepComparison, showsDivider: false)
                    ProComparisonLegend()
                }
            }
            .padding(.top, 22)
            ProInsightCard(text: insightText, linkTitle: "Break down my recovery",
                           route: TabRoute.metric("recovery"))
                .padding(.top, ProMetrics.gap)

            let points = ProHistory.points(repo.days, endKey: snap.dayKey.isEmpty ? Repository.logicalDayKey(Date()) : snap.dayKey,
                                           days: range.rawValue, value: { $0.recovery },
                                           color: { ProPalette.recovery($0) })
            ProTrendCard(title: "Recovery Trend", range: $range,
                         average: ProHistory.average(points).map { String(localized: "Avg \(ProFormat.percentText($0))") }) {
                ProBarChart(points: points, maxValue: 100, height: 150,
                            valueFormat: { "\(Int($0.rounded()))" },
                            showsValues: range == .week, labelStride: ProHistory.stride(for: range.rawValue))
            }
            .padding(.top, ProMetrics.section)

            let hrvPoints = ProHistory.points(repo.days, endKey: snap.dayKey.isEmpty ? Repository.logicalDayKey(Date()) : snap.dayKey,
                                              days: range.rawValue, value: { $0.avgHrv })
            VStack(alignment: .leading, spacing: ProMetrics.gap) {
                ProOverline(title: "Heart Rate Variability",
                            trailing: snap.hrvBaseline.map { String(localized: "30-day avg \(Int($0.rounded())) ms") })
                ProCard {
                    ProLineChart(points: hrvPoints, color: ProPalette.recoveryHigh, baseline: snap.hrvBaseline,
                                 height: 130, valueFormat: { "\(Int($0.rounded()))" },
                                 labelStride: ProHistory.stride(for: range.rawValue))
                }
            }
            .padding(.top, ProMetrics.section)

            let rhrPoints = ProHistory.points(repo.days, endKey: snap.dayKey.isEmpty ? Repository.logicalDayKey(Date()) : snap.dayKey,
                                              days: range.rawValue, value: { $0.restingHr.map(Double.init) })
            VStack(alignment: .leading, spacing: ProMetrics.gap) {
                ProOverline(title: "Resting Heart Rate",
                            trailing: snap.restingHRBaseline.map { String(localized: "30-day avg \(Int($0.rounded())) bpm") })
                ProCard {
                    ProLineChart(points: rhrPoints, color: ProPalette.recoveryLow, baseline: snap.restingHRBaseline,
                                 height: 130, valueFormat: { "\(Int($0.rounded()))" },
                                 labelStride: ProHistory.stride(for: range.rawValue))
                }
            }
            .padding(.top, ProMetrics.section)

            vitalsSection
                .padding(.top, ProMetrics.section)
        }
        .sheet(item: $guide) { section in
            NavigationStack { ScoringGuideView(initialSection: section, onClose: { guide = nil }) }
        }
    }

    private var heroCaption: String? {
        switch snap.charge {
        case .carried(_, let caption): return caption
        case .calibrating: return snap.charge.calibrationDetail
        case .noData: return String(localized: "No recovery scored")
        case .scored(let pct): return ProScores.recoveryBand(pct)
        }
    }

    private var hrvComparison: ProComparison {
        ProComparison.classify(snap.hrv, baseline: snap.hrvBaseline, higherIsBetter: true)
    }
    private var rhrComparison: ProComparison {
        ProComparison.classify(snap.restingHR, baseline: snap.restingHRBaseline, higherIsBetter: false)
    }
    private var respComparison: ProComparison {
        ProComparison.classify(snap.respiratory, baseline: snap.respiratoryBaseline, higherIsBetter: nil)
    }
    private var sleepComparison: ProComparison {
        ProComparison.classify(snap.sleepPerformance, baseline: snap.sleepPerformanceBaseline, higherIsBetter: true)
    }

    /// One plain sentence naming which inputs moved against the prior 30 days, and which way the
    /// recovery landed. Built only from the comparisons shown above it.
    private var insightText: String {
        guard let pct = snap.recoveryPct else {
            return String(localized: "Recovery is scored from your overnight HRV, resting heart rate, respiratory rate and sleep. Wear your strap to bed and sync in the morning.")
        }
        let named: [(String, ProComparison)] = [
            (String(localized: "HRV"), hrvComparison),
            (String(localized: "resting heart rate"), rhrComparison),
            (String(localized: "respiratory rate"), respComparison),
            (String(localized: "sleep performance"), sleepComparison),
        ]
        let good = named.filter { if case .better = $0.1 { return true } else { return false } }.map { $0.0 }
        let bad = named.filter { if case .worse = $0.1 { return true } else { return false } }.map { $0.0 }
        let band = pct >= 67 ? String(localized: "a higher recovery") : (pct >= 34 ? String(localized: "a moderate recovery") : String(localized: "a lower recovery"))
        let list = ListFormatter.localizedString(byJoining: good)
        let badList = ListFormatter.localizedString(byJoining: bad)
        if !good.isEmpty && bad.isEmpty {
            return String(localized: "Your \(list) improved against your prior 30 days, resulting in \(band) today.")
        }
        if good.isEmpty && !bad.isEmpty {
            return String(localized: "Your \(badList) moved the wrong way against your prior 30 days, resulting in \(band) today.")
        }
        if !good.isEmpty && !bad.isEmpty {
            return String(localized: "Your \(list) improved while your \(badList) moved the wrong way, resulting in \(band) today.")
        }
        return String(localized: "Your recovery inputs are all close to your prior 30 days, resulting in \(band) today.")
    }

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Health Monitor",
                        trailing: snap.vitalsWithData > 0
                            ? String(localized: "\(snap.vitalsInRange)/\(snap.vitalsWithData) within range") : nil)
            ProCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(snap.vitalReadings.enumerated()), id: \.element.id) { idx, reading in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(dotColor(reading.banding.band))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reading.label).proLabel(12)
                                Text(reading.stateCaption)
                                    .font(ProFont.caption)
                                    .foregroundStyle(ProPalette.textTertiary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Text(reading.formattedValue ?? "—")
                                .font(ProFont.number(17))
                                .foregroundStyle(ProPalette.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            if idx < snap.vitalReadings.count - 1 {
                                Rectangle().fill(ProPalette.divider).frame(height: 1).padding(.leading, 36)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dotColor(_ band: VitalBands.Band) -> Color {
        switch band {
        case .inRange: return ProPalette.better
        case .outOfRange: return ProPalette.worse
        case .noData: return ProPalette.ringTrack
        }
    }
}
#endif
