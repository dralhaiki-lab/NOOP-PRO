#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Activity tab: this week's strain, shortcuts into recording, and the activity history grouped
/// by day. Rows open the existing workout detail screen.
struct ProActivityView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var workouts: [WorkoutRow] = []
    @State private var loaded = false

    private static let topID = "proActivity.top"
    private var todayKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    ProNavTitle(title: String(localized: "Activity"),
                                subtitle: String(localized: "Workouts, strain and recording"))
                        .padding(.top, 10)
                    weekSummary
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, 20)
                    shortcuts
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, ProMetrics.section)
                    history
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
        workouts = (await repo.workoutRows()).sorted { $0.startTs > $1.startTs }
        loaded = true
    }

    // MARK: Week

    private var weekSummary: some View {
        let points = ProHistory.points(repo.days, endKey: todayKey, days: 7, value: { $0.strain },
                                       color: { _ in ProPalette.strain })
        let weekStart = Int((Calendar.current.date(byAdding: .day, value: -6,
                                                   to: Calendar.current.startOfDay(for: Date())) ?? Date())
            .timeIntervalSince1970)
        let weekWorkouts = workouts.filter { $0.startTs >= weekStart }
        let minutes = weekWorkouts.compactMap { $0.durationS }.reduce(0, +) / 60
        return VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProOverline(title: "Last 7 Days")
            ProCard {
                VStack(spacing: 16) {
                    HStack(alignment: .top) {
                        summaryFigure("Avg Strain", ProHistory.average(points).map { ProScores.effortText($0) } ?? "—")
                        Spacer()
                        summaryFigure("Activities", "\(weekWorkouts.count)")
                        Spacer()
                        summaryFigure("Active Time", minutes > 0 ? ProFormat.duration(minutes: minutes) : "—")
                    }
                    ProBarChart(points: points, color: ProPalette.strain, maxValue: StrainScorer.maxStrain,
                                height: 120, valueFormat: { ProScores.effortText($0) })
                        .id(effortScaleRaw)
                }
            }
        }
    }

    private func summaryFigure(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).proLabel(10, color: ProPalette.textSecondary)
            Text(value)
                .font(ProFont.number(24))
                .foregroundStyle(ProPalette.textPrimary)
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader("Start")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: ProMetrics.gap),
                                GridItem(.flexible(), spacing: ProMetrics.gap)], spacing: ProMetrics.gap) {
                shortcut("Workouts", "figure.run", .workouts)
                shortcut("Live Heart Rate", "waveform.path.ecg", .live)
                shortcut("Lift Log", "dumbbell.fill", .liftLog)
                shortcut("Intervals", "timer", .intervals)
                shortcut("Breathe", "wind", .breathe)
                shortcut("Alarms", "alarm.fill", .alarms)
            }
        }
    }

    private func shortcut(_ title: LocalizedStringKey, _ icon: String, _ screen: ProScreen) -> some View {
        NavigationLink(value: ProRoute.screen(screen)) {
            ProCard(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ProPalette.strain)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ProPalette.strain.opacity(0.16)))
                    Text(title)
                        .font(ProFont.bodyEmphasis)
                        .foregroundStyle(ProPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(ProPressStyle())
    }

    // MARK: History

    private var groupedHistory: [(day: String, rows: [WorkoutRow])] {
        let recent = workouts.prefix(60)
        var order: [String] = []
        var groups: [String: [WorkoutRow]] = [:]
        for w in recent {
            let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(w.startTs)))
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(w)
        }
        return order.map { (day: $0, rows: groups[$0] ?? []) }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader(title: "History") {
                NavigationLink(value: ProRoute.allWorkouts) {
                    HStack(spacing: 4) {
                        Text("All").proLabel(11, color: ProPalette.link)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ProPalette.link)
                    }
                }
                .buttonStyle(.plain)
            }
            if loaded && workouts.isEmpty {
                ProEmptyCard(icon: "figure.run", title: "No activities yet",
                             message: "Record a workout or let NOOP detect one from your heart rate.")
            }
            ForEach(groupedHistory, id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ProFormat.longDay(group.day)).proLabel(11, color: ProPalette.textSecondary)
                    ProCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.offset) { idx, w in
                                NavigationLink(value: ProRoute.workout(startTs: w.startTs, sport: w.sport)) {
                                    row(w, last: idx == group.rows.count - 1)
                                }
                                .buttonStyle(ProPressStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ w: WorkoutRow, last: Bool) -> some View {
        HStack(spacing: 12) {
            Text(ProScores.effortText(w.strain))
                .font(ProFont.number(15))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 50, height: 38)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ProPalette.strain))
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutSource.displaySport(w.sport)).proLabel(13)
                    .lineLimit(1)
                Text("\(ProHeartRateChart.clock(w.startTs)) – \(ProHeartRateChart.clock(w.endTs))")
                    .font(ProFont.caption)
                    .foregroundStyle(ProPalette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let d = w.durationS {
                    Text(ProFormat.duration(minutes: d / 60))
                        .font(ProFont.number(15))
                        .foregroundStyle(ProPalette.textPrimary)
                }
                if let kcal = w.energyKcal {
                    Text(verbatim: ProFormat.kcal(kcal))
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ProPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(ProPalette.divider).frame(height: 1).padding(.leading, 76) }
        }
        .contentShape(Rectangle())
    }
}
#endif
