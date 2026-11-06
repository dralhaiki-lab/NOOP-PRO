#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Strain deep-dive: day-strain ring, time in heart-rate zones, workout time, steps and calories
/// against the prior 30 days, the day's heart-rate trace, its activities, the zone split and the trend.
struct ProStrainView: View {
    @ObservedObject var store: ProDayStore
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var guide: ScoreSection?
    @State private var range: ProRange = .week

    private var snap: ProDaySnapshot { store.snapshot }
    private var endKey: String { snap.dayKey.isEmpty ? Repository.logicalDayKey(Date()) : snap.dayKey }

    var body: some View {
        ProDetailScaffold(title: store.dayTitle, onInfo: { guide = .effort }) {
            ProHeroGauge(value: ProScores.effortText(snap.strain), label: "Day Strain",
                         progress: ProScores.effortProgress(snap.strain), color: ProPalette.strain,
                         caption: snap.strain == nil ? String(localized: "Not enough heart rate yet")
                                                     : ProScores.effortBand(snap.strain))
                .padding(.top, 8)
                .id(effortScaleRaw)
            ProDetailCard {
                VStack(spacing: 0) {
                    ProMetricRow(icon: "heart", title: "Heart Rate Zones 1-3",
                                 value: snap.lowZoneMinutes.map { ProFormat.duration(minutes: $0) } ?? "—")
                    ProMetricRow(icon: "heart.fill", title: "Heart Rate Zones 4-5",
                                 value: snap.highZoneMinutes.map { ProFormat.duration(minutes: $0) } ?? "—")
                    ProMetricRow(icon: "figure.strengthtraining.traditional", title: "Workout Time",
                                 value: workoutMinutes.map { ProFormat.duration(minutes: $0) } ?? "—")
                    ProMetricRow(icon: "shoeprints.fill", title: "Steps", value: ProFormat.integer(snap.steps),
                                 comparison: ProComparison.classify(snap.steps, baseline: snap.stepsBaseline,
                                                                    higherIsBetter: true))
                    ProMetricRow(icon: "flame", title: "Calories", value: ProFormat.integer(snap.calories),
                                 comparison: ProComparison.classify(snap.calories, baseline: snap.caloriesBaseline,
                                                                    higherIsBetter: nil),
                                 showsDivider: false)
                    ProComparisonLegend()
                }
            }
            .padding(.top, 22)
            ProInsightCard(text: insightText, linkTitle: "Explore my strain", route: TabRoute.metric("strain"))
                .padding(.top, ProMetrics.gap)

            heartRateSection
                .padding(.top, ProMetrics.section)
            activitiesSection
                .padding(.top, ProMetrics.section)
            zonesSection
                .padding(.top, ProMetrics.section)

            let points = ProHistory.points(repo.days, endKey: endKey, days: range.rawValue,
                                           value: { $0.strain }, color: { _ in ProPalette.strain })
            ProTrendCard(title: "Strain Trend", range: $range,
                         average: ProHistory.average(points).map { String(localized: "Avg \(ProScores.effortText($0))") }) {
                ProBarChart(points: points, color: ProPalette.strain, maxValue: StrainScorer.maxStrain,
                            height: 150, valueFormat: { ProScores.effortText($0) },
                            showsValues: range == .week, labelStride: ProHistory.stride(for: range.rawValue))
            }
            .padding(.top, ProMetrics.section)
        }
        .sheet(item: $guide) { section in
            NavigationStack { ScoringGuideView(initialSection: section, onClose: { guide = nil }) }
        }
    }

    /// Total recorded workout duration for the day, nil with no workouts.
    private var workoutMinutes: Double? {
        let durations = snap.workouts.compactMap { w -> Double? in
            if let d = w.durationS { return d / 60 }
            return w.endTs > w.startTs ? Double(w.endTs - w.startTs) / 60 : nil
        }
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }

    /// The band sentence, with band edges printed on the user's own Effort scale.
    private var insightText: String {
        guard let strain = snap.strain else {
            return String(localized: "Strain builds from the time your heart rate spends above rest. Wear your strap through the day to see it climb.")
        }
        let whoopScale = strain * 0.21
        func edge(_ v: Double) -> String { ProScores.effortText(v / 0.21) }
        switch whoopScale {
        case ..<10:
            return String(localized: "Strain below \(edge(10)) is considered light, meaning your cardiovascular system has had an easy day so far.")
        case ..<14:
            return String(localized: "Strain between \(edge(10)) and \(edge(13.9)) is considered moderate, meaning your cardiovascular system has been steadily active.")
        case ..<18:
            return String(localized: "Strain between \(edge(14)) and \(edge(17.9)) is considered strenuous, meaning your cardiovascular system has been working hard.")
        default:
            return String(localized: "Strain of \(edge(18)) or more is considered all out, meaning your cardiovascular system has been pushed to its limit.")
        }
    }

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Heart Rate")
            ProCard {
                if snap.heartRate.count > 1 {
                    ProHeartRateChart(samples: snap.heartRate, windowStart: snap.windowStart, windowEnd: snap.windowEnd,
                                      highlights: snap.workouts.map { (start: $0.startTs, end: $0.endTs) },
                                      color: ProPalette.strain, height: 150)
                } else {
                    Text("No heart rate recorded for this day yet.")
                        .font(ProFont.subtitle)
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Activities", trailing: snap.workouts.isEmpty ? nil
                        : String(localized: "\(snap.workouts.count) recorded"))
            if snap.workouts.isEmpty {
                ProEmptyCard(icon: "figure.run", title: "No activities",
                             message: "Workouts you record or that NOOP detects for this day appear here.")
            } else {
                ProCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(snap.workouts.enumerated()), id: \.offset) { idx, w in
                            NavigationLink(value: ProRoute.workout(startTs: w.startTs, sport: w.sport)) {
                                workoutRow(w, last: idx == snap.workouts.count - 1)
                            }
                            .buttonStyle(ProPressStyle())
                        }
                    }
                }
            }
        }
    }

    private func workoutRow(_ w: WorkoutRow, last: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sportSymbol(w.sport))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ProPalette.strain)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ProPalette.strain.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutSource.displaySport(w.sport)).proLabel(13)
                    .lineLimit(1)
                Text("\(ProHeartRateChart.clock(w.startTs)) – \(ProHeartRateChart.clock(w.endTs))")
                    .font(ProFont.caption)
                    .foregroundStyle(ProPalette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProScores.effortText(w.strain))
                    .font(ProFont.number(19))
                    .foregroundStyle(ProPalette.textPrimary)
                if let hr = w.avgHr {
                    Text(verbatim: "\(hr) bpm")
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ProPalette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(ProPalette.divider).frame(height: 1).padding(.leading, 66) }
        }
        .contentShape(Rectangle())
    }

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Heart Rate Zones")
            ProCard {
                if let minutes = snap.zoneMinutes {
                    let top = max(1, minutes.max() ?? 1)
                    VStack(spacing: 10) {
                        ForEach(Array(minutes.enumerated().reversed()), id: \.offset) { idx, m in
                            HStack(spacing: 10) {
                                Text(verbatim: "Z\(idx + 1)")
                                    .font(ProFont.label(11))
                                    .foregroundStyle(ProPalette.textSecondary)
                                    .frame(width: 24, alignment: .leading)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(ProPalette.tierIdle)
                                        Capsule().fill(ProPalette.zone(idx + 1))
                                            .frame(width: max(m > 0 ? 4 : 0, geo.size.width * CGFloat(m / top)))
                                    }
                                }
                                .frame(height: 8)
                                Text(ProFormat.duration(minutes: m))
                                    .font(ProFont.number(14, weight: .semibold))
                                    .foregroundStyle(ProPalette.textPrimary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    Text("No heart rate in this window to split into zones.")
                        .font(ProFont.subtitle)
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
        }
    }
}
#endif
