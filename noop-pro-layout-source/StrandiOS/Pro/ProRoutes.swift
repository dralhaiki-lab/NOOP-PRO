#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Value routes for every push that leaves a Pro tab root, so re-tapping the active tab can pop the
/// bound `NavigationPath` back to the root (the #135/#198 convention the classic shell follows).
enum ProRoute: Hashable {
    case recovery
    case strain
    case sleep
    case workout(startTs: Int, sport: String)
    case trend(ProTrendMetric)
    case intelligence
    case settings
    case allWorkouts
    case screen(ProScreen)
}

/// Every existing NOOP screen the Pro tabs link to. These keep their own design; the Pro shell only
/// changes how they are reached, so no feature is lost by switching layouts.
enum ProScreen: String, Hashable, CaseIterable {
    case insightsHub, intelligence, insights, explore, compare
    case live, workouts, liftLog, health, labBook, stress, breathe, intervals, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport, noopLimitations
    case devices, alarms, automations, testCentre, siriShortcuts, powerSaving, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .insightsHub:     InsightsHubView()
        case .intelligence:    IntelligenceView()
        case .insights:        InsightsView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .live:            LiveView()
        case .workouts:        WorkoutsView()
        case .liftLog:         LiftLogView()
        case .health:          HealthView()
        case .labBook:         LabBookView()
        case .stress:          StressView()
        case .breathe:         BreathingView()
        case .intervals:       IntervalTimerView()
        case .rhythm:          RhythmHost()
        case .fusedRecord:     FusedRecordHost()
        case .appleHealth:     AppleHealthView()
        case .miBand:          XiaomiBandView()
        case .dataSources:     DataSourcesView()
        case .backupSync:      BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .noopLimitations: NoopLimitationsView()
        case .devices:         DevicesView()
        case .alarms:          SmartAlarmView()
        case .automations:     AutomationsView()
        case .testCentre:      TestCentreView()
        case .siriShortcuts:   SiriShortcutsSettingsView()
        case .powerSaving:     PowerSavingView()
        case .settings:        SettingsView()
        }
    }
}

extension View {
    /// Registers the Pro destinations on a tab's stack. Register exactly once per stack, beside
    /// `tabRouteDestinations()` (a double registration double-pushes, #38).
    func proRouteDestinations(store: ProDayStore) -> some View {
        navigationDestination(for: ProRoute.self) { route in
            switch route {
            case .recovery: ProRecoveryView(store: store)
            case .strain: ProStrainView(store: store)
            case .sleep: ProSleepView(store: store)
            case .workout(let startTs, let sport): ProWorkoutHost(store: store, startTs: startTs, sport: sport)
            case .trend(let metric): ProTrendDetailView(metric: metric)
            case .intelligence:
                IntelligenceView()
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .toolbarBackground(.hidden, for: .navigationBar)
            case .settings:
                SettingsView()
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .toolbarBackground(.hidden, for: .navigationBar)
            case .allWorkouts:
                WorkoutsView()
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .toolbarBackground(.hidden, for: .navigationBar)
            case .screen(let screen):
                // The same per-screen wrapper the classic More index applies (#1027): a hidden bar
                // background keeps each screen's own full-bleed backdrop edge to edge.
                screen.destination
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }
}

/// Resolves a workout route to its row and shows the existing workout detail screen. The row comes
/// from the day snapshot when it is there, else from the full workout list, so a route can never
/// dead-end on a day change.
struct ProWorkoutHost: View {
    @ObservedObject var store: ProDayStore
    let startTs: Int
    let sport: String

    @EnvironmentObject private var repo: Repository
    @State private var row: WorkoutRow?
    @State private var looked = false

    var body: some View {
        Group {
            if let row {
                WorkoutDetailView(row: row)
            } else if looked {
                ProEmptyCard(icon: "figure.run", title: "Workout not found",
                             message: "This workout is no longer in your history.")
                    .padding(ProMetrics.page)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .proPageChrome()
            } else {
                ProgressView().tint(ProPalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .proPageChrome()
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if let hit = store.snapshot.workouts.first(where: { $0.startTs == startTs && $0.sport == sport }) {
                row = hit
            } else {
                row = await repo.workoutRows().first(where: { $0.startTs == startTs && $0.sport == sport })
            }
            looked = true
        }
    }
}
#endif
