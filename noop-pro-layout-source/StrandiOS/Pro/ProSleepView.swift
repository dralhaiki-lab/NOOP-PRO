#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Sleep deep-dive: performance ring, the four tiered sleep factors, a plain summary, the night's
/// duration against need, the stage timeline, the stage split against typical and the trend.
struct ProSleepView: View {
    @ObservedObject var store: ProDayStore
    @EnvironmentObject private var repo: Repository

    @State private var guide: ScoreSection?
    @State private var range: ProRange = .week

    private var snap: ProDaySnapshot { store.snapshot }
    private var endKey: String { snap.dayKey.isEmpty ? Repository.logicalDayKey(Date()) : snap.dayKey }

    // Tier edges (Poor / Sufficient / Optimal) for each factor.
    private var hoursTier: ProTier? { ProTier.of(snap.hoursVsNeeded, sufficientFrom: 70, optimalFrom: 85) }
    private var consistencyTier: ProTier? { ProTier.of(snap.sleepConsistency, sufficientFrom: 70, optimalFrom: 80) }
    private var efficiencyTier: ProTier? { ProTier.of(snap.sleepEfficiency, sufficientFrom: 80, optimalFrom: 90) }
    private var restorativeTier: ProTier? { ProTier.of(snap.restorative, sufficientFrom: 30, optimalFrom: 40) }

    var body: some View {
        ProDetailScaffold(title: store.dayTitle, onInfo: { guide = .rest }) {
            ProHeroGauge(value: ProFormat.percent(snap.sleepPerformance),
                         unit: snap.sleepPerformance == nil ? nil : "%",
                         label: "Sleep\nPerformance",
                         progress: snap.sleepPerformance.map { $0 / 100 },
                         color: ProPalette.sleep,
                         caption: snap.sleepPerformance == nil ? String(localized: "No sleep scored") : nil)
                .padding(.top, 8)
            ProDetailCard {
                VStack(spacing: 0) {
                    ProMetricRow(icon: "clock", title: "Hours vs. Needed", value: pct(snap.hoursVsNeeded),
                                 showsTier: true, tier: hoursTier)
                    ProMetricRow(icon: "calendar", title: "Sleep Consistency", value: pct(snap.sleepConsistency),
                                 showsTier: true, tier: consistencyTier)
                    ProMetricRow(icon: "bed.double", title: "Sleep Efficiency", value: pct(snap.sleepEfficiency),
                                 showsTier: true, tier: efficiencyTier)
                    ProMetricRow(icon: "sparkles", title: "Restorative Sleep", value: pct(snap.restorative),
                                 showsTier: true, tier: restorativeTier, showsDivider: false)
                    ProTierLegend()
                }
            }
            .padding(.top, 22)
            ProInsightCard(text: insightText, linkTitle: "Dive into my sleep", route: TabRoute.sleep)
                .padding(.top, ProMetrics.gap)

            durationSection
                .padding(.top, ProMetrics.section)
            stagesSection
                .padding(.top, ProMetrics.section)

            let hours = ProHistory.points(repo.days, endKey: endKey, days: range.rawValue,
                                          value: { $0.totalSleepMin.map { $0 / 60 } })
            ProTrendCard(title: "Hours of Sleep", range: $range,
                         average: ProHistory.average(hours).map { String(localized: "Avg \(ProFormat.duration(minutes: $0 * 60))") }) {
                ProBarChart(points: hours, color: ProPalette.sleep,
                            maxValue: max(10, (snap.sleepNeedMin ?? 480) / 60 * 1.25), height: 150,
                            valueFormat: { ProFormat.duration(minutes: $0 * 60) },
                            showsValues: range == .week, labelStride: ProHistory.stride(for: range.rawValue))
            }
            .padding(.top, ProMetrics.section)

            let perf = ProHistory.points(snap.sleepPerformanceByDay, endKey: endKey, days: range.rawValue)
            VStack(alignment: .leading, spacing: ProMetrics.gap) {
                ProOverline(title: "Sleep Performance",
                            trailing: ProHistory.average(perf).map { String(localized: "Avg \(ProFormat.percentText($0))") })
                ProCard {
                    ProLineChart(points: perf, color: ProPalette.sleep, baseline: snap.sleepPerformanceBaseline,
                                 height: 130, valueFormat: { "\(Int($0.rounded()))%" },
                                 labelStride: ProHistory.stride(for: range.rawValue))
                }
            }
            .padding(.top, ProMetrics.section)
        }
        .sheet(item: $guide) { section in
            NavigationStack { ScoringGuideView(initialSection: section, onClose: { guide = nil }) }
        }
    }

    private func pct(_ v: Double?) -> String {
        v.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    /// Names the overall band and, when one factor is short of optimal, the weakest of them.
    private var insightText: String {
        guard let perf = snap.sleepPerformance else {
            return String(localized: "Sleep performance compares the sleep you got with the sleep your body needed. Wear your strap overnight to score it.")
        }
        let factors: [(String, Double?, ProTier?)] = [
            (String(localized: "Hours vs. Needed"), snap.hoursVsNeeded, hoursTier),
            (String(localized: "Sleep Consistency"), snap.sleepConsistency, consistencyTier),
            (String(localized: "Sleep Efficiency"), snap.sleepEfficiency, efficiencyTier),
            (String(localized: "Restorative Sleep"), snap.restorative, restorativeTier),
        ]
        let weakest = factors
            .filter { $0.2 != nil && $0.2 != .optimal }
            .min { ($0.2?.rawValue ?? 0, $0.1 ?? 0) < ($1.2?.rawValue ?? 0, $1.1 ?? 0) }
        switch perf {
        case 85...:
            return String(localized: "Your Sleep Performance is optimal. Keep the routine that got you here.")
        case 70..<85:
            if let weakest {
                return String(localized: "Your Sleep Performance is sufficient, but there's room to improve. \(weakest.0) could use attention to help you get to optimal sleep.")
            }
            return String(localized: "Your Sleep Performance is sufficient, but there's room to improve.")
        default:
            if let weakest {
                return String(localized: "Your Sleep Performance is poor. \(weakest.0) held it back the most last night.")
            }
            return String(localized: "Your Sleep Performance is poor. An earlier, more regular bedtime is the quickest lever.")
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Sleep Duration",
                        trailing: snap.night.map { "\($0.onsetText) – \($0.wakeText)" })
            ProCard {
                VStack(spacing: 16) {
                    HStack(alignment: .top) {
                        figure("Hours of Sleep", snap.day?.totalSleepMin ?? snap.night?.stages.asleep)
                        Spacer()
                        figure("Sleep Needed", snap.sleepNeedMin)
                        Spacer()
                        figure("Time in Bed", snap.night?.timeInBed)
                    }
                    if let asleep = snap.day?.totalSleepMin ?? snap.night?.stages.asleep, let need = snap.sleepNeedMin, need > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ProPalette.tierIdle)
                                Capsule().fill(ProPalette.sleep)
                                    .frame(width: geo.size.width * CGFloat(min(1, asleep / need)))
                            }
                        }
                        .frame(height: 8)
                    }
                    if let debt = snap.sleepDebtMin, debt > 0 {
                        HStack {
                            Text("Sleep debt").proLabel(11, color: ProPalette.textSecondary)
                            Spacer()
                            Text(ProFormat.duration(minutes: debt))
                                .font(ProFont.number(15))
                                .foregroundStyle(ProPalette.worse)
                        }
                    }
                }
            }
        }
    }

    private func figure(_ title: LocalizedStringKey, _ minutes: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).proLabel(10, color: ProPalette.textSecondary)
            Text(minutes.map { ProFormat.duration(minutes: $0) } ?? "—")
                .font(ProFont.number(24))
                .foregroundStyle(ProPalette.textPrimary)
        }
    }

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Sleep Stages")
            if let night = snap.night, night.stages.total > 0, !snap.sleepIntervals.isEmpty {
                ProCard {
                    VStack(alignment: .leading, spacing: 18) {
                        ProHypnogram(intervals: snap.sleepIntervals, onset: night.onsetDate, height: 140)
                        if night.realSegments == nil || (night.realSegments?.count ?? 0) < 2 {
                            Text("Stage order is reconstructed from the night's totals; the export carries no per-minute timeline.")
                                .font(ProFont.caption)
                                .foregroundStyle(ProPalette.textTertiary)
                        }
                        VStack(spacing: 4) {
                            ProStageRow(stage: .awake, minutes: night.stages.awake, total: night.stages.total)
                            ProStageRow(stage: .light, minutes: night.stages.light, total: night.stages.total,
                                        typicalMinutes: snap.typicalLightMin)
                            ProStageRow(stage: .deep, minutes: night.stages.deep, total: night.stages.total,
                                        typicalMinutes: snap.typicalDeepMin)
                            ProStageRow(stage: .rem, minutes: night.stages.rem, total: night.stages.total,
                                        typicalMinutes: snap.typicalRemMin)
                        }
                        HStack(spacing: 6) {
                            Rectangle().fill(Color.white.opacity(0.7)).frame(width: 2, height: 10)
                            Text("Your typical share")
                                .font(ProFont.caption)
                                .foregroundStyle(ProPalette.textTertiary)
                        }
                    }
                }
            } else {
                ProEmptyCard(icon: "moon.zzz", title: "No sleep stages",
                             message: "Stages appear once a night ending on this day has been synced and scored.")
            }
        }
    }
}
#endif
