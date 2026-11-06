#if os(iOS)
import SwiftUI
import StrandDesign

/// The Pro More tab: profile header, the layout switch, and every NOOP screen grouped the way the
/// classic More index groups them — nothing the classic layout reaches is missing here.
struct ProMoreView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @AppStorage(ProInterface.storageKey) private var proInterface = ProInterface.defaultEnabled

    @State private var deviceName: String?

    private static let topID = "proMore.top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: ProMetrics.section) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    ProNavTitle(title: String(localized: "More"))
                        .frame(maxWidth: .infinity)
                    profileHeader
                    layoutSwitch
                    group("Device") {
                        row("Devices", "applewatch.side.right", .devices)
                        row("Power Saving", "battery.25", .powerSaving)
                        row("Alarms", "alarm.fill", .alarms, last: true)
                    }
                    group("Insights") {
                        row("What Moves You", "wand.and.sparkles", .insightsHub)
                        row("Intelligence", "brain.head.profile", .intelligence)
                        row("Journal & Insights", "lightbulb.fill", .insights)
                        row("Lab Book", "books.vertical.fill", .labBook)
                        row("Explore", "square.grid.2x2.fill", .explore)
                        row("Compare", "rectangle.split.2x1.fill", .compare, last: true)
                    }
                    group("Body") {
                        row("Live", "waveform.path.ecg", .live)
                        row("Workouts", "figure.run", .workouts)
                        row("Lift Log", "dumbbell.fill", .liftLog)
                        row("Health", "heart.text.square.fill", .health)
                        row("Stress", "bolt.heart.fill", .stress)
                        row("Breathe", "wind", .breathe)
                        row("Intervals", "timer", .intervals)
                        row("Rhythm", "waveform.path", .rhythm, last: true)
                    }
                    group("Data") {
                        row("Your Data, Fused", "square.stack.3d.up.fill", .fusedRecord)
                        row("Apple Health", "heart.fill", .appleHealth)
                        row("Mi Band", "figure.walk.motion", .miBand)
                        row("Data Sources", "externaldrive.fill", .dataSources)
                        row("Backup & Sync", "externaldrive.fill.badge.icloud", .backupSync)
                        row("Shortcuts Export", "square.and.arrow.up.fill", .shortcutsExport)
                        row("NOOP Limitations", "list.bullet.rectangle", .noopLimitations, last: true)
                    }
                    group("App") {
                        row("Automations", "wand.and.stars", .automations)
                        row("Test Centre", "stethoscope", .testCentre)
                        row("Siri & Shortcuts", "mic.fill", .siriShortcuts)
                        row("Settings", "gearshape.fill", .settings, last: true)
                    }
                }
                .padding(.horizontal, ProMetrics.page)
                .padding(.top, 10)
                .padding(.bottom, ProMetrics.tabBarClearance)
            }
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .proPageChrome()
        .task(id: repo.refreshSeq) { deviceName = repo.activeDeviceDisplayName() }
    }

    private var profileHeader: some View {
        NavigationLink(value: ProRoute.screen(.settings)) {
            ProCard {
                HStack(spacing: 14) {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: 56)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Profile")
                            .font(ProFont.cardTitle)
                            .foregroundStyle(ProPalette.textPrimary)
                        Text(profileLine)
                            .font(ProFont.caption)
                            .foregroundStyle(ProPalette.textSecondary)
                            .lineLimit(1)
                        if let deviceName {
                            HStack(spacing: 4) {
                                Image(systemName: "applewatch.side.right")
                                Text(deviceName)
                            }
                            .font(ProFont.caption)
                            .foregroundStyle(ProPalette.textTertiary)
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ProPalette.textTertiary)
                }
            }
        }
        .buttonStyle(ProPressStyle())
    }

    private var profileLine: String {
        var parts: [String] = []
        if profile.age > 0 { parts.append(String(localized: "\(profile.age) yrs")) }
        if profile.heightCm > 0 { parts.append("\(Int(profile.heightCm.rounded())) cm") }
        if profile.weightKg > 0 { parts.append("\(Int(profile.weightKg.rounded())) kg") }
        return parts.isEmpty ? String(localized: "Set up your profile") : parts.joined(separator: " · ")
    }

    private var layoutSwitch: some View {
        ProCard {
            Toggle(isOn: $proInterface.animation(ProMotion.tab)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pro layout")
                        .font(ProFont.cardTitle)
                        .foregroundStyle(ProPalette.textPrimary)
                    Text("Turn off to return to the classic NOOP layout.")
                        .font(ProFont.caption)
                        .foregroundStyle(ProPalette.textSecondary)
                }
            }
            .tint(ProPalette.recoveryHigh)
        }
    }

    private func group<Rows: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).proLabel(12, color: ProPalette.textSecondary)
            ProCard(padding: 0) {
                VStack(spacing: 0) { rows() }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ screen: ProScreen, last: Bool = false) -> some View {
        NavigationLink(value: ProRoute.screen(screen)) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(ProPalette.icon)
                    .frame(width: 26)
                Text(title)
                    .font(ProFont.body)
                    .foregroundStyle(ProPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(ProPalette.divider).frame(height: 1).padding(.leading, 56) }
            }
        }
        .buttonStyle(ProPressStyle())
    }
}
#endif
