#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Everything the Pro screens show for one selected day. Resolved once per load in `ProDayStore`,
/// through the SAME Repository reads and pure resolvers the Today screens use (`ChargeDisplay`,
/// `TodayView.freshRestScore`, `StrainScorer.effectiveEffort`, the per-field vital carries,
/// `SleepModel`), so Home, a detail screen and the classic Today read one number for one fact.
struct ProDaySnapshot {
    var dayKey: String = ""
    var isToday = true
    var day: DailyMetric?

    // Scores
    var charge: LiquidTodayView.ChargeDisplay = .noData
    /// Effort on NOOP's stored 0–100 axis (the display scale is applied at render).
    var strain: Double?
    var sleepPerformance: Double?

    // Recovery inputs, today-first with the prior-night carry, and their prior-30-day means
    var hrv: Double?
    var hrvBaseline: Double?
    var restingHR: Double?
    var restingHRBaseline: Double?
    var respiratory: Double?
    var respiratoryBaseline: Double?
    var sleepPerformanceBaseline: Double?

    // Activity
    var steps: Double?
    var stepsBaseline: Double?
    var calories: Double?
    var caloriesBaseline: Double?
    /// Minutes in heart-rate zones 1…5 over the day window, nil when the window holds no heart rate.
    var zoneMinutes: [Double]?
    var heartRate: [(ts: Int, bpm: Double)] = []
    var windowStart = 0
    var windowEnd = 0
    /// The day's workouts, newest first.
    var workouts: [WorkoutRow] = []

    // Sleep
    var night: Night?
    var sleepIntervals: [SleepInterval] = []
    var sleepNeedMin: Double?
    var hoursVsNeeded: Double?
    var sleepEfficiency: Double?
    var sleepConsistency: Double?
    var restorative: Double?
    var sleepDebtMin: Double?
    var typicalDeepMin: Double?
    var typicalRemMin: Double?
    var typicalLightMin: Double?

    // Monitors
    var stress: Double?
    var vitalReadings: [BodyVitalReading] = []

    /// Daily rows for the trailing 30 calendar days ending on the selected day, oldest → newest.
    var history: [DailyMetric] = []
    /// Sleep performance by day key (the same `sleep_performance` series the Sleep dial reads).
    var sleepPerformanceByDay: [String: Double] = [:]

    var recoveryPct: Double? { charge.pct }

    var vitalsInRange: Int { vitalReadings.filter { $0.banding.band == .inRange }.count }
    var vitalsWithData: Int { vitalReadings.filter { $0.banding.band != .noData }.count }
    var vitalsOutOfRange: [BodyVitalReading] { vitalReadings.filter { $0.banding.band == .outOfRange } }

    /// Minutes in zones 1–3 and 4–5.
    var lowZoneMinutes: Double? { zoneMinutes.map { $0.prefix(3).reduce(0, +) } }
    var highZoneMinutes: Double? { zoneMinutes.map { $0.suffix(2).reduce(0, +) } }
}

/// Loads `ProDaySnapshot` for a day offset (0 = today). One store is owned by the Home tab and handed
/// to the Recovery / Strain / Sleep screens it pushes, so all four always describe the same day.
@MainActor
final class ProDayStore: ObservableObject {
    @Published private(set) var snapshot = ProDaySnapshot()
    @Published private(set) var loaded = false
    @Published var dayOffset = 0

    private var generation = 0

    /// Whole-history sleep reads, kept until the Repository next refreshes.
    private struct SleepCache {
        let seq: Int
        let sessions: [CachedSleepSession]
        let habitual: Int?
        let motion: [Int: [Double]]
    }
    private var sleepCache: SleepCache?

    /// The logical day the offset points at.
    var selectedLogicalDay: Date {
        let base = Repository.logicalDay(Date())
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: base) ?? base
    }

    /// Whole days from today back to the earliest banked day (how far back navigation may go).
    func maxOffset(repo: Repository) -> Int {
        TodayView.maxDayOffset(earliestDayKey: repo.freshness.earliestDay,
                               todayKey: Repository.logicalDayKey(Date()))
    }

    /// "TODAY" / "YESTERDAY" / "MON, NOV 3".
    var dayTitle: String {
        switch dayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default:
            return selectedLogicalDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()
                .locale(AppLanguage.activeLocale))
        }
    }

    func step(by delta: Int, repo: Repository) {
        let next = TodayView.clampedDayOffset(current: dayOffset, delta: delta, maxOffset: maxOffset(repo: repo))
        guard next != dayOffset else { return }
        dayOffset = next
    }

    func load(repo: Repository, profile: ProfileStore,
              temperatureUnit: TemperatureUnit, skinTempPreferred: SkinTempDisplay.Kind) async {
        generation += 1
        let gen = generation
        let offset = dayOffset
        let isToday = offset == 0
        let cal = Calendar.current
        let logical = selectedLogicalDay
        let selectedKey: String = {
            if isToday, let key = repo.today?.day { return key }
            return Repository.localDayKey(logical)
        }()

        var s = ProDaySnapshot()
        s.isToday = isToday
        let day: DailyMetric? = isToday
            ? (repo.today ?? repo.days.last(where: { $0.day == selectedKey }))
            : repo.days.last(where: { $0.day == selectedKey })
        s.day = day
        let tkey = day?.day ?? selectedKey
        s.dayKey = tkey

        // Charge — the same calibration gate, carry selection and truth table as Liquid Today.
        let calNights = isToday
            ? RecoveryScorer.calibrationNights(nightlyHrv: repo.chargeBaselines?.hrvHistory.values ?? [],
                                               dayKeys: repo.chargeBaselines?.hrvHistory.dayKeys ?? [],
                                               hasRecovery: day?.recovery != nil)
            : nil
        let priorScored = TodayView.lastScoredRecoveryDay(days: repo.days, selectedDayKey: tkey, isToday: isToday,
                                                          todayScored: day?.recovery != nil,
                                                          isCalibrating: calNights != nil)
        s.charge = LiquidTodayView.ChargeDisplay.resolve(todayRecovery: day?.recovery, priorScored: priorScored,
                                                         calibrationNights: calNights, todayKey: tkey)

        // Vitals: today's own value first, then the per-field prior-night carry (today only).
        let hrvDay = isToday ? Repository.lastHrvDay(days: repo.days, todayKey: tkey) : nil
        let rhrDay = isToday ? Repository.lastRestingHrDay(days: repo.days, todayKey: tkey) : nil
        let respDay = isToday ? Repository.lastRespDay(days: repo.days, todayKey: tkey) : nil
        s.hrv = day?.avgHrv ?? hrvDay?.avgHrv
        s.restingHR = (day?.restingHr ?? rhrDay?.restingHr).map(Double.init)
        s.respiratory = day?.respRateBpm ?? respDay?.respRateBpm
        let vitalsKey = day?.avgHrv != nil ? tkey : (hrvDay?.day ?? tkey)
        s.hrvBaseline = Self.baseline(repo.days, before: vitalsKey) { $0.avgHrv }
        s.restingHRBaseline = Self.baseline(repo.days, before: tkey) { $0.restingHr.map(Double.init) }
        s.respiratoryBaseline = Self.baseline(repo.days, before: tkey) { $0.respRateBpm }

        // History window (30 calendar days ending on the selected day).
        let historyCutoff = Repository.localDayKey(cal.date(byAdding: .day, value: -29, to: logical) ?? logical)
        s.history = repo.days.filter { $0.day >= historyCutoff && $0.day <= tkey }

        // The day window the Effort and heart-rate reads cover: the detected sleep onset when the
        // day-cycle mode says so, else calendar midnight → now (today) or the whole day (past).
        let dayStart = cal.startOfDay(for: logical)
        let calendarFrom = Int(dayStart.timeIntervalSince1970)
        let calendarTo: Int = isToday
            ? Int(Date().timeIntervalSince1970)
            : Int((cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970)
        let nextDayKey = Repository.localDayKey(cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart)
        let cycleMode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey))
        let markers = cycleMode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop") : []
        let from = markers.last(where: { $0.day == selectedKey }).map { Int($0.value) } ?? calendarFrom
        let toExclusive = markers.last(where: { $0.day == nextDayKey }).map { Int($0.value) } ?? calendarTo
        let to = max(from, toExclusive - 1)
        s.windowStart = from
        s.windowEnd = max(to, from + 1)

        // The window's heart rate, read whole: an EXPLICIT limit, because the 8000-row default is
        // chart-sized and `ORDER BY ts ASC LIMIT` would drop the newest hours of a full day.
        let dayHr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        let zoneSet = profile.hrZoneSet

        // Effort: the live in-progress score for today when it beats the stored row (#1001).
        var liveStrain: Double?
        if isToday {
            let maxHR = profile.effortHRmax
            let restHR = day?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
            let method = PuffinExperiment.effortMethod
            let sex = profile.sex
            liveStrain = await Task.detached(priority: .utility) {
                StrainScorer.strain(dayHr, maxHR: maxHR, restingHR: restHR, method: method, sex: sex)
            }.value
        }
        s.strain = StrainScorer.effectiveEffort(live: liveStrain, stored: day?.strain)

        // Time in zones over the same samples, with the profile's display zones.
        s.zoneMinutes = await Task.detached(priority: .utility) { () -> [Double]? in
            guard !dayHr.isEmpty else { return nil }
            let minutes = HRZones.timeInZone(dayHr, zoneSet: zoneSet).seconds.map { $0 / 60.0 }
            return minutes.contains(where: { $0 > 0 }) ? minutes : nil
        }.value

        async let restA = repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        async let stepsA = repo.exploreSeries(key: "steps_est", source: "my-whoop")
        async let stressA = repo.series(key: "stress", source: "my-whoop")
        async let appleA = repo.appleDailyRows()
        async let hrA = repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
        async let wkA = repo.workoutRows()

        // Sleep performance — today's own score, else last night's while it is still fresh (#977).
        let restSeries = await restA
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        s.sleepPerformanceByDay = restByDay
        s.sleepPerformance = TodayView.freshRestScore(todayValue: restByDay[selectedKey], lastDay: restSeries.last?.day,
                                                      lastValue: restSeries.last?.value, isTodaySelected: isToday,
                                                      todayKey: selectedKey)
        let restCutoff = Repository.localDayKey(cal.date(byAdding: .day, value: -30, to: logical) ?? logical)
        let priorRest = restSeries.filter { $0.day < tkey && $0.day >= restCutoff }.map(\.value)
        s.sleepPerformanceBaseline = priorRest.isEmpty ? nil : priorRest.reduce(0, +) / Double(priorRest.count)

        // Steps: measured strap count, then imported Apple Health, then the motion estimate (#377).
        let apple = await appleA
        let stepsSeries = await stepsA
        let stepsByDay = Dictionary(stepsSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let importedSteps = apple.filter { $0.day == selectedKey }.compactMap { $0.steps }.max()
        let stepsEst = stepsByDay[selectedKey] ?? (isToday ? stepsSeries.last?.value : nil)
        s.steps = day?.steps.map(Double.init) ?? importedSteps.map(Double.init) ?? stepsEst
        s.stepsBaseline = Self.baseline(repo.days, before: tkey) { $0.steps.map(Double.init) }

        // Calories: imported active energy first, else the on-device HR estimate (#616).
        let importedKcal = apple.filter { $0.day == selectedKey }.compactMap { $0.activeKcal }.max()
        s.calories = importedKcal ?? day?.activeKcalEst
        s.caloriesBaseline = Self.baseline(repo.days, before: tkey) { $0.activeKcalEst }

        let buckets = await hrA
        s.heartRate = buckets.map { (ts: $0.ts, bpm: $0.bpm) }
        s.workouts = (await wkA).filter { $0.startTs >= from && $0.startTs < to }
            .sorted { $0.startTs > $1.startTs }

        // Stress (0–3), computed off the main actor exactly as Today does.
        let storedStress = await stressA
        let daysSnapshot = repo.days
        if isToday {
            s.stress = await Task.detached(priority: .utility) {
                StressModel(days: daysSnapshot, stored: storedStress)?.score
            }.value
        } else {
            s.stress = storedStress.last(where: { $0.day == tkey })?.value
        }

        // Health monitor: the same banded vital readings the Health screen draws.
        s.vitalReadings = BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows,
                                                  temperatureUnit: temperatureUnit,
                                                  skinTempPreferred: skinTempPreferred)

        // Sleep: the night that ends on the selected day, merged by the Sleep tab's own pipeline. The
        // whole-history session/motion reads are cached per Repository refresh, so stepping between
        // days on Home does not re-read them.
        if sleepCache?.seq != repo.refreshSeq {
            let sessions = await repo.allSleepSessions()
            let habitual = await repo.habitualMidsleepSec()
            let motion = await repo.sessionMotions(sessions: sessions)
            sleepCache = SleepCache(seq: repo.refreshSeq, sessions: sessions, habitual: habitual, motion: motion)
        }
        let sessions = sleepCache?.sessions ?? []
        let habitual = sleepCache?.habitual
        let motion = sleepCache?.motion ?? [:]
        let navSessions = sessions.isEmpty ? repo.sleeps : sessions
        let groups = SleepModel.navDays(navSessions: navSessions)
        func endKey(_ group: [CachedSleepSession]) -> String? {
            group.last.map { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) }
        }
        // Exact wake-day match; on today, also accept a night that ended on the local calendar day
        // (the pre-04:00 window where the logical day still points at yesterday).
        let localToday = Repository.localDayKey(Date())
        let groupIndex = groups.firstIndex(where: { endKey($0) == tkey })
            ?? (isToday ? groups.firstIndex(where: { endKey($0) == localToday }) : nil)
        if let idx = groupIndex,
           let night = SleepModel.decodedNight(at: idx, navDays: groups, habitualMidsleepSec: habitual,
                                               motionByStart: motion) {
            s.night = night
            s.sleepIntervals = night.intervals
        }
        let fallbackNeed = SleepModel.sleepNeedMin(days: repo.days)
        let need = repo.importedSleep[tkey]?.needMin ?? fallbackNeed
        s.sleepNeedMin = need
        if let asleep = day?.totalSleepMin, asleep > 0, need > 0 { s.hoursVsNeeded = asleep / need * 100 }
        if let e = day?.efficiency { s.sleepEfficiency = e <= 1.0 ? e * 100 : e }
        if let deep = day?.deepMin, let rem = day?.remMin, let asleep = day?.totalSleepMin, asleep > 0 {
            s.restorative = (deep + rem) / asleep * 100
        }
        if let imported = repo.importedSleep[tkey]?.consistencyPct {
            s.sleepConsistency = imported
        } else if isToday {
            s.sleepConsistency = SleepModel.consistencySeries(days: repo.days, sleeps: repo.sleeps,
                                                              importedSleep: repo.importedSleep).latest
        }
        let napCredit = SleepModel.napSleepMinutesByDay(navDays: groups, habitualMidsleepSec: habitual)
        let debt = SleepModel.sleepDebtSeries(days: repo.days.filter { $0.day <= tkey },
                                              importedSleep: repo.importedSleep, napSleepMinByDay: napCredit)
        s.sleepDebtMin = debt.latest
        s.typicalDeepMin = SleepModel.typicalStageMin(days: repo.days, \.deepMin)
        s.typicalRemMin = SleepModel.typicalStageMin(days: repo.days, \.remMin)
        s.typicalLightMin = SleepModel.typicalStageMin(days: repo.days, \.lightMin)

        guard gen == generation else { return }
        snapshot = s
        loaded = true
    }

    /// Mean of `value` over the 30 calendar days strictly before `key`, or nil with no data.
    static func baseline(_ rows: [DailyMetric], before key: String, days: Int = 30,
                         _ value: (DailyMetric) -> Double?) -> Double? {
        guard let date = ProFormat.dayKeyParser.date(from: key),
              let start = Calendar.current.date(byAdding: .day, value: -days, to: date) else { return nil }
        let cutoff = ProFormat.dayKeyParser.string(from: start)
        let values = rows.filter { $0.day < key && $0.day >= cutoff }.compactMap(value).filter { $0.isFinite }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Shared display helpers

/// Score formatting shared by every Pro screen, so the dial, the hero and any row agree.
enum ProScores {
    /// Effort on the user's chosen display scale (0–100 or 0–21).
    static func effortText(_ stored: Double?) -> String {
        guard let stored else { return "—" }
        return UnitFormatter.effortDisplay(stored, scale: effortScale)
    }

    static var effortScale: EffortScale {
        UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
    }

    /// Ring fill for a stored 0–100 Effort.
    static func effortProgress(_ stored: Double?) -> Double? {
        stored.map { min(1, max(0, $0 / StrainScorer.maxStrain)) }
    }

    static func temperatureUnit() -> TemperatureUnit {
        let d = UserDefaults.standard
        let system = UnitSystem(rawValue: d.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        return UnitPrefs.resolveTemperature(system: system, override: d.string(forKey: UnitPrefs.temperatureKey) ?? "")
    }

    static func skinTempPreference() -> SkinTempDisplay.Kind {
        SkinTempDisplay.Kind(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.skinTempDisplayKey) ?? "")
            ?? .absolute
    }

    /// Recovery band copy.
    static func recoveryBand(_ pct: Double?) -> String? {
        guard let pct else { return nil }
        switch pct {
        case 67...: return String(localized: "Green recovery")
        case 34..<67: return String(localized: "Yellow recovery")
        default: return String(localized: "Red recovery")
        }
    }

    /// Effort band copy on the 0–21 equivalent axis (light / moderate / strenuous / all out).
    static func effortBand(_ stored: Double?) -> String? {
        guard let stored else { return nil }
        let whoopScale = stored * 0.21
        switch whoopScale {
        case ..<10: return String(localized: "Light")
        case ..<14: return String(localized: "Moderate")
        case ..<18: return String(localized: "Strenuous")
        default: return String(localized: "All out")
        }
    }
}
#endif
