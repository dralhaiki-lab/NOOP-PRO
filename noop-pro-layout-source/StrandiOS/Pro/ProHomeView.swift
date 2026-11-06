#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import OuraProtocol

/// The Pro Home tab: day selector, the Sleep / Recovery / Strain dials, today's read-out, the health
/// and stress monitors, the day's activities, key statistics and the heart-rate trace. Every number
/// comes from `ProDayStore`, which resolves it through the same paths as the classic Today screen.
struct ProHomeView: View {
    @ObservedObject var store: ProDayStore
    /// Opens Live Session (the shell owns the cover so a deep link can open it too).
    var startLiveSession: (() -> Void)? = nil

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    /// Live Sessions beta gate — the same key the Settings toggle and classic Today read.
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true

    @State private var showDayPicker = false
    @State private var activitiesExpanded = false

    private static let topID = "proHome.top"

    private var snap: ProDaySnapshot { store.snapshot }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    header
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, 6)
                    NoopWordmark(color: ProPalette.textPrimary.opacity(0.85))
                        .padding(.top, 18)
                    dials
                        .padding(.top, 16)
                        .padding(.horizontal, 8)
                    VStack(spacing: ProMetrics.gap) {
                        outlookCard
                        monitors
                    }
                    .padding(.horizontal, ProMetrics.page)
                    .padding(.top, 26)
                    myDay
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, 30)
                    keyStatistics
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, 30)
                    heartRateCard
                        .padding(.horizontal, ProMetrics.page)
                        .padding(.top, 30)
                }
                .padding(.bottom, ProMetrics.tabBarClearance)
            }
            .refreshable {
                if ble.state.historyReady { ble.syncNow() }
                await repo.refresh()
                await reload()
            }
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .simultaneousGesture(daySwipe)
        .proPageChrome()
        .task(id: "\(repo.refreshSeq)-\(store.dayOffset)-\(dayCycleModeRaw)") { await reload() }
        .sheet(isPresented: $showDayPicker) { dayPicker }
    }

    private func reload() async {
        await store.load(repo: repo, profile: profile,
                         temperatureUnit: ProScores.temperatureUnit(),
                         skinTempPreferred: ProScores.skinTempPreference())
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            HStack {
                NavigationLink(value: ProRoute.settings) {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: 30)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(ProPressStyle())
                .accessibilityLabel(Text("Profile and settings"))
                Spacer()
                ProBatteryButton()
            }
            dayNavigator
        }
        .frame(height: 40)
    }

    private var dayNavigator: some View {
        HStack(spacing: 6) {
            Button { withAnimation(ProMotion.tab) { store.step(by: 1, repo: repo) } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(store.dayOffset < store.maxOffset(repo: repo)
                                     ? ProPalette.textPrimary : ProPalette.textTertiary)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous day"))
            Button { showDayPicker = true } label: {
                Text(store.dayTitle)
                    .font(ProFont.label(12))
                    .tracking(ProTracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(ProPalette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(ProPressStyle())
            .accessibilityHint(Text("Choose a day"))
            Button { withAnimation(ProMotion.tab) { store.step(by: -1, repo: repo) } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(store.dayOffset > 0 ? ProPalette.textPrimary : ProPalette.textTertiary)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.dayOffset == 0)
            .accessibilityLabel(Text("Next day"))
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(ProPalette.pill))
    }

    private var dayPicker: some View {
        let binding = Binding<Date>(
            get: { store.selectedLogicalDay },
            set: { picked in
                store.dayOffset = TodayView.pickedDayOffset(pickedDate: picked,
                                                            anchorLogicalDay: Repository.logicalDay(Date()))
                showDayPicker = false
            })
        let today = Repository.logicalDay(Date())
        let earliest = Calendar.current.date(byAdding: .day, value: -store.maxOffset(repo: repo), to: today) ?? today
        return NavigationStack {
            DatePicker("", selection: binding, in: earliest...today, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(ProPalette.recoveryHigh)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .proPageChrome()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDayPicker = false }
                            .foregroundStyle(ProPalette.textPrimary)
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > abs(dy) * 1.6, abs(dx) > 60 else { return }
                withAnimation(ProMotion.tab) { store.step(by: TodayView.daySwipeDelta(dx: dx), repo: repo) }
            }
    }

    // MARK: Dials

    private var dials: some View {
        HStack(alignment: .top, spacing: 0) {
            NavigationLink(value: ProRoute.sleep) {
                ProScoreDial(title: "Sleep", value: ProFormat.percent(snap.sleepPerformance),
                             unit: snap.sleepPerformance == nil ? nil : "%",
                             progress: snap.sleepPerformance.map { $0 / 100 }, color: ProPalette.sleep)
            }
            .buttonStyle(ProPressStyle())
            NavigationLink(value: ProRoute.recovery) {
                ProScoreDial(title: "Recovery", value: ProFormat.percent(snap.recoveryPct),
                             unit: snap.recoveryPct == nil ? nil : "%",
                             progress: snap.recoveryPct.map { $0 / 100 },
                             color: ProPalette.recovery(snap.recoveryPct))
            }
            .buttonStyle(ProPressStyle())
            NavigationLink(value: ProRoute.strain) {
                ProScoreDial(title: "Strain", value: ProScores.effortText(snap.strain),
                             progress: ProScores.effortProgress(snap.strain), color: ProPalette.strain)
            }
            .buttonStyle(ProPressStyle())
        }
        .id(effortScaleRaw)
    }

    // MARK: Outlook

    private var outlook: (title: String, body: String) {
        switch snap.charge {
        case .scored(let pct):
            return Self.outlookCopy(pct: pct, carriedCaption: nil)
        case .carried(let pct, let caption):
            return Self.outlookCopy(pct: pct, carriedCaption: caption)
        case .calibrating:
            return (String(localized: "Learning your baseline"),
                    snap.charge.calibrationDetail ?? String(localized: "Keep wearing your strap overnight."))
        case .noData:
            return (String(localized: "No recovery yet"),
                    String(localized: "Wear your strap overnight and sync to score your recovery."))
        }
    }

    static func outlookCopy(pct: Double, carriedCaption: String?) -> (title: String, body: String) {
        let p = ProFormat.percentText(pct)
        var result: (title: String, body: String)
        switch pct {
        case 67...:
            result = (String(localized: "Ready to perform"),
                      String(localized: "Your recovery is in the green at \(p). Your body is signaling it can take on significant exertion today."))
        case 34..<67:
            result = (String(localized: "Maintain today"),
                      String(localized: "Your recovery is in the yellow at \(p). Your body is maintaining, so moderate exertion suits today."))
        default:
            result = (String(localized: "Prioritize rest"),
                      String(localized: "Your recovery is in the red at \(p). Your body is signaling it needs rest, so keep exertion light today."))
        }
        if let carriedCaption { result.body += " " + carriedCaption }
        return result
    }

    private var outlookCard: some View {
        let copy = outlook
        return NavigationLink(value: ProRoute.recovery) {
            ProCard {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(copy.title)
                            .font(ProFont.cardTitle)
                            .foregroundStyle(ProPalette.textPrimary)
                        Text(copy.body)
                            .font(ProFont.subtitle)
                            .foregroundStyle(ProPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(ProPalette.recovery(snap.recoveryPct))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
        }
        .buttonStyle(ProPressStyle())
    }

    // MARK: Monitors

    private var monitors: some View {
        HStack(spacing: ProMetrics.gap) {
            NavigationLink(value: TabRoute.health) {
                monitorCard(title: "Health Monitor") {
                    let total = snap.vitalsWithData
                    let inRange = snap.vitalsInRange
                    let ok = total > 0 && inRange == total
                    HStack(spacing: 10) {
                        badge(color: total == 0 ? ProPalette.neutral : (ok ? ProPalette.stress : ProPalette.worse)) {
                            Image(systemName: total == 0 ? "minus" : (ok ? "checkmark" : "exclamationmark"))
                                .font(.system(size: 11, weight: .heavy))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(total == 0 ? String(localized: "No data")
                                 : (ok ? String(localized: "Within range") : String(localized: "Out of range")))
                                .proLabel(10, color: total == 0 ? ProPalette.textTertiary
                                          : (ok ? ProPalette.stress : ProPalette.worse))
                            Text(total == 0 ? String(localized: "Sync to check")
                                 : String(localized: "\(inRange)/\(total) Metrics"))
                                .font(ProFont.caption)
                                .foregroundStyle(ProPalette.textSecondary)
                        }
                    }
                }
            }
            .buttonStyle(ProPressStyle())
            NavigationLink(value: TabRoute.stress) {
                monitorCard(title: "Stress Monitor") {
                    HStack(spacing: 10) {
                        badge(color: stressColor) {
                            Text(snap.stress.map { ProFormat.decimal($0) } ?? "—")
                                .font(ProFont.number(12))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(snap.stress.map { StressBand(score: $0).title } ?? String(localized: "No data"))
                                .proLabel(10, color: snap.stress == nil ? ProPalette.textTertiary : stressColor)
                            Text(snap.isToday ? String(localized: "Today") : ProFormat.longDay(snap.dayKey))
                                .font(ProFont.caption)
                                .foregroundStyle(ProPalette.textSecondary)
                        }
                    }
                }
            }
            .buttonStyle(ProPressStyle())
        }
    }

    private var stressColor: Color {
        guard let s = snap.stress else { return ProPalette.neutral }
        switch StressBand(score: s) {
        case .low: return ProPalette.stress
        case .medium: return ProPalette.recoveryMid
        case .high: return ProPalette.worse
        }
    }

    private func monitorCard<C: View>(title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        ProCard(padding: 14, fill: ProPalette.cardRaised) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    Text(title).proLabel(11)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(ProPalette.textSecondary)
                }
                content()
            }
        }
    }

    private func badge<C: View>(color: Color, @ViewBuilder content: () -> C) -> some View {
        content()
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16)))
    }

    // MARK: My Day

    private var myDay: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader(title: "My Day") {
                Button { router.quickActionsRequested = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
                }
                .buttonStyle(ProPressStyle())
                .accessibilityLabel(Text("Quick actions"))
            }
            NavigationLink(value: ProRoute.intelligence) {
                HStack {
                    Text("Daily Outlook")
                        .font(ProFont.bodyEmphasis)
                        .foregroundStyle(ProPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ProPalette.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: ProMetrics.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [ProPalette.outlookStart, ProPalette.outlookEnd],
                                             startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(ProPressStyle())
            if liveSessionsBeta, store.dayOffset == 0, let startLiveSession {
                Button(action: startLiveSession) {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ProPalette.better)
                        Text("Start session")
                            .font(ProFont.bodyEmphasis)
                            .foregroundStyle(ProPalette.textPrimary)
                        Text("Beta")
                            .proLabel(9, color: ProPalette.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(ProPalette.inset))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ProPalette.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: ProMetrics.cardRadius, style: .continuous)
                        .fill(ProPalette.card))
                    .overlay(RoundedRectangle(cornerRadius: ProMetrics.cardRadius, style: .continuous)
                        .strokeBorder(ProPalette.hairline, lineWidth: 1))
                }
                .buttonStyle(ProPressStyle())
            }
            activitiesCard
        }
    }

    private var activitiesCard: some View {
        ProCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Activities").proLabel(12)
                    Spacer()
                    NavigationLink(value: ProRoute.allWorkouts) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ProPalette.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("All workouts"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                let rows = activityRows
                if rows.isEmpty {
                    Text("No activities recorded for this day.")
                        .font(ProFont.subtitle)
                        .foregroundStyle(ProPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            NavigationLink(value: row.route) { activityRow(row) }
                                .buttonStyle(ProPressStyle())
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private struct ActivityRowModel: Identifiable {
        let id: String
        let badge: String
        let badgeColor: Color
        let title: String
        let subtitle: String
        let time: String
        let route: ProRoute
    }

    private var activityRows: [ActivityRowModel] {
        var rows: [ActivityRowModel] = []
        if let night = snap.night, night.stages.asleep > 0 {
            rows.append(ActivityRowModel(
                id: "sleep-\(night.session.startTs)",
                badge: snap.sleepPerformance.map { "\(Int($0.rounded()))%" } ?? ProFormat.duration(minutes: night.stages.asleep),
                badgeColor: ProPalette.sleep,
                title: String(localized: "Sleep"),
                subtitle: ProFormat.duration(minutes: night.stages.asleep),
                time: "\(night.onsetText) – \(night.wakeText)",
                route: .sleep))
        }
        for w in snap.workouts {
            let start = ProHeartRateChart.clock(w.startTs), end = ProHeartRateChart.clock(w.endTs)
            rows.append(ActivityRowModel(
                id: "wk-\(w.startTs)-\(w.sport)",
                badge: ProScores.effortText(w.strain),
                badgeColor: ProPalette.strain,
                title: WorkoutSource.displaySport(w.sport),
                subtitle: w.durationS.map { ProFormat.duration(minutes: $0 / 60) } ?? "",
                time: "\(start) – \(end)",
                route: .workout(startTs: w.startTs, sport: w.sport)))
        }
        return rows
    }

    private func activityRow(_ row: ActivityRowModel) -> some View {
        HStack(spacing: 12) {
            Text(row.badge)
                .font(ProFont.number(15))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 54, height: 40)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(row.badgeColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).proLabel(13)
                    .lineLimit(1)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(row.time)
                .font(ProFont.caption)
                .foregroundStyle(ProPalette.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ProPalette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Key statistics

    private var keyStatistics: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader("Key Statistics")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: ProMetrics.gap),
                                GridItem(.flexible(), spacing: ProMetrics.gap)],
                      spacing: ProMetrics.gap) {
                statTile("HRV", value: ProFormat.integer(snap.hrv), unit: "ms",
                         baseline: snap.hrvBaseline, current: snap.hrv, higherIsBetter: true,
                         route: .trend(.hrv))
                statTile("Resting HR", value: ProFormat.integer(snap.restingHR), unit: "bpm",
                         baseline: snap.restingHRBaseline, current: snap.restingHR, higherIsBetter: false,
                         route: .trend(.restingHR))
                statTile("Steps", value: ProFormat.integer(snap.steps), unit: nil,
                         baseline: snap.stepsBaseline, current: snap.steps, higherIsBetter: true,
                         route: .trend(.steps))
                statTile("Calories", value: ProFormat.integer(snap.calories), unit: "kcal",
                         baseline: snap.caloriesBaseline, current: snap.calories, higherIsBetter: nil,
                         route: .trend(.calories))
                statTile("Respiratory Rate", value: ProFormat.decimal(snap.respiratory), unit: "rpm",
                         baseline: snap.respiratoryBaseline, current: snap.respiratory, higherIsBetter: nil,
                         route: .trend(.respiratory))
                statTile("Hours of Sleep",
                         value: snap.day?.totalSleepMin.map { ProFormat.duration(minutes: $0) } ?? "—",
                         unit: nil,
                         baseline: ProDayStore.baseline(repo.days, before: snap.dayKey) { $0.totalSleepMin },
                         current: snap.day?.totalSleepMin, higherIsBetter: true,
                         route: .trend(.sleepHours))
            }
        }
    }

    private func statTile(_ title: LocalizedStringKey, value: String, unit: String?,
                          baseline: Double?, current: Double?, higherIsBetter: Bool?,
                          route: ProRoute) -> some View {
        NavigationLink(value: route) {
            ProCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).proLabel(10, color: ProPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(ProFont.number(26))
                            .foregroundStyle(ProPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let unit, current != nil {
                            Text(verbatim: unit)
                                .font(ProFont.caption)
                                .foregroundStyle(ProPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        ProComparisonGlyph(comparison: ProComparison.classify(current, baseline: baseline,
                                                                              higherIsBetter: higherIsBetter))
                    }
                    Text(baseline.map { String(localized: "30-day avg \(ProFormat.decimal($0, digits: $0 >= 100 ? 0 : 1))") }
                         ?? String(localized: "No baseline yet"))
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(ProPressStyle())
    }

    // MARK: Heart rate

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: ProMetrics.gap) {
            ProSectionHeader(title: "Heart Rate") {
                NavigationLink(value: TabRoute.fullDayChart) {
                    HStack(spacing: 4) {
                        Text("Full day").proLabel(11, color: ProPalette.link)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ProPalette.link)
                    }
                }
                .buttonStyle(.plain)
            }
            ProCard {
                if snap.heartRate.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 18) {
                            hrFigure("Average", snap.heartRate.map { $0.bpm }.reduce(0, +) / Double(snap.heartRate.count))
                            hrFigure("Max", snap.heartRate.map { $0.bpm }.max())
                            hrFigure("Min", snap.heartRate.map { $0.bpm }.min())
                        }
                        ProHeartRateChart(samples: snap.heartRate, windowStart: snap.windowStart,
                                          windowEnd: snap.windowEnd,
                                          highlights: snap.workouts.map { (start: $0.startTs, end: $0.endTs) },
                                          color: ProPalette.recoveryLow.opacity(0.9), height: 130)
                    }
                } else {
                    Text("No heart rate recorded for this day yet.")
                        .font(ProFont.subtitle)
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
        }
    }

    private func hrFigure(_ title: LocalizedStringKey, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).proLabel(10, color: ProPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ProFormat.integer(value))
                    .font(ProFont.number(20))
                    .foregroundStyle(ProPalette.textPrimary)
                Text(verbatim: "bpm")
                    .font(ProFont.caption)
                    .foregroundStyle(ProPalette.textSecondary)
            }
        }
    }
}

/// The strap battery read-out in the Home header. Observes `LiveState` on its own so the ~1 Hz live
/// heart-rate updates never re-render the whole Home tab. Tap → Devices.
struct ProBatteryButton: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter

    private var display: LiquidTodayView.StrapBatteryDisplay {
        .resolve(activeIsWhoop: live.activeIsWhoop, connected: live.connected,
                 batteryPct: live.batteryPct, charging: live.charging,
                 ringPct: live.ouraBatteryPct, ringCharging: live.ouraWearState == .charging)
    }

    var body: some View {
        Button { router.requestedDestination = .devices } label: {
            HStack(spacing: 4) {
                switch display {
                case .charge(let pct, let charging, _):
                    if charging || live.backfilling {
                        Image(systemName: live.backfilling ? "arrow.triangle.2.circlepath" : "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text(verbatim: "\(Int(pct.rounded()))%")
                        .font(ProFont.number(13, weight: .semibold))
                case .pending(let charging):
                    if charging { Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold)) }
                    Text(verbatim: "—")
                        .font(ProFont.number(13, weight: .semibold))
                case .offline:
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 11, weight: .semibold))
                case .notActiveDevice:
                    EmptyView()
                }
                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 18, weight: .regular))
            }
            .foregroundStyle(ProPalette.textSecondary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProPressStyle())
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        switch display {
        case .charge(let pct, let charging, _):
            return charging ? String(localized: "Strap battery \(Int(pct.rounded())) percent, charging")
                            : String(localized: "Strap battery \(Int(pct.rounded())) percent")
        case .pending: return String(localized: "Strap battery reading pending")
        case .offline: return String(localized: "Strap not connected")
        case .notActiveDevice: return String(localized: "Devices")
        }
    }
}
#endif
