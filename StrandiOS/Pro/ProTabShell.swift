#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// The Pro navigation shell: four tab roots kept alive in a ZStack (so each keeps its scroll position
/// and navigation stack, like the classic `TabView`) under a floating capsule tab bar with a separate
/// round Coach button. Tags match the classic shell's so `NavRouter` requests land on the same tab:
/// 0 Home, 1 Health (Trends), 2 Activity, 3 Coach, 4 More.
struct ProTabShell: View {
    @Binding var selection: Int
    @Binding var tabPaths: [NavigationPath]
    let scrollTop: [Int]
    let coachEnabled: Bool
    @Binding var showLiveSession: Bool
    let onQuickActions: () -> Void

    @EnvironmentObject private var liftSession: LiftSessionController
    @StateObject private var dayStore = ProDayStore()
    @State private var visited: Set<Int> = [0]
    @State private var keyboardVisible = false

    private var atRoot: Bool {
        tabPaths.indices.contains(selection) ? tabPaths[selection].isEmpty : true
    }

    var body: some View {
        ZStack {
            ProCanvas()
            tabRoot(0) { ProHomeView(store: dayStore, startLiveSession: { showLiveSession = true }) }
            tabRoot(1) { ProHealthView() }
            tabRoot(2) { ProActivityView() }
            if coachEnabled {
                tabRoot(3) { CoachView() }
            }
            tabRoot(4) { ProMoreView() }
        }
        .overlay(alignment: .bottom) {
            if !keyboardVisible {
                VStack(spacing: 10) {
                    if liftSession.isActive {
                        LiftSessionBar()
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if atRoot {
                        ProTabBar(selection: $selection, coachEnabled: coachEnabled, onQuickActions: onQuickActions)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .animation(ProMotion.tab, value: atRoot)
        .animation(.easeInOut(duration: 0.25), value: liftSession.isActive)
        .onChange(of: selection) { _, tag in visited.insert(tag) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        // Live Session (silent guardian, beta) owns the display while it runs, as on classic Today.
        .fullScreenCover(isPresented: $showLiveSession) {
            LiveSessionView(onClose: { showLiveSession = false })
        }
        .environment(\.colorScheme, .dark)
    }

    /// Height the bottom overlay (tab bar, plus the gym-session bar when one runs) occupies over a tab.
    private func bottomReserve(for tag: Int) -> CGFloat {
        guard !keyboardVisible else { return 0 }
        let tabBarShown = tabPaths.indices.contains(tag) ? tabPaths[tag].isEmpty : true
        var height: CGFloat = 0
        if tabBarShown { height += ProMetrics.tabBarHeight + 2 }
        if liftSession.isActive { height += ProMetrics.liftBarReserve }
        return height
    }

    /// One tab root in its own NavigationStack, created the first time it is shown and kept alive
    /// (hidden, not destroyed) while another tab is in front.
    @ViewBuilder
    private func tabRoot<Content: View>(_ tag: Int, @ViewBuilder content: () -> Content) -> some View {
        let active = selection == tag
        let root = content()
        if visited.contains(tag) || active {
            NavigationStack(path: $tabPaths[tag]) {
                root
                    .toolbar(.hidden, for: .navigationBar)
                    .proRouteDestinations(store: dayStore)
                    .tabRouteDestinations()
            }
            // Reserve the floating bar's height as bottom safe area while it shows over this tab, so a
            // screen's own bottom controls (Coach's composer, a sheet-less input bar) sit above it while
            // scroll content still runs underneath the translucent bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomReserve(for: tag))
            }
            .environment(\.scrollToTopSignal, scrollTop.indices.contains(tag) ? scrollTop[tag] : 0)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(active ? 1 : 0)
        }
    }
}

/// The floating capsule tab bar plus the round Coach button at its side.
struct ProTabBar: View {
    @Binding var selection: Int
    let coachEnabled: Bool
    let onQuickActions: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                item(0, "Home", "house", "house.fill")
                item(1, "Health", "heart.text.square", "heart.text.square.fill")
                item(2, "Activity", "figure.run", "figure.run")
                item(4, "More", "line.3.horizontal", "line.3.horizontal")
            }
            .padding(.horizontal, 6)
            .frame(height: ProMetrics.tabBarHeight)
            .background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(ProPalette.tabBar.opacity(0.82)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.45), radius: 16, y: 6)
            )
            circleButton
        }
        .padding(.horizontal, ProMetrics.page)
    }

    private func item(_ tag: Int, _ title: LocalizedStringKey, _ icon: String, _ activeIcon: String) -> some View {
        let active = selection == tag
        return Button {
            selection = tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: active ? activeIcon : icon)
                    .font(.system(size: 19, weight: active ? .semibold : .regular))
                    .frame(height: 22)
                Text(title)
                    .font(ProFont.tab)
                    .lineLimit(1)
            }
            .foregroundStyle(active ? ProPalette.textPrimary : ProPalette.tabInactive)
            .frame(maxWidth: .infinity)
            .frame(height: ProMetrics.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    private var circleButton: some View {
        let active = coachEnabled && selection == 3
        return Button {
            if coachEnabled { selection = 3 } else { onQuickActions() }
        } label: {
            Image(systemName: coachEnabled ? "sparkles" : "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ProPalette.textPrimary)
                .frame(width: ProMetrics.tabBarHeight, height: ProMetrics.tabBarHeight)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [ProPalette.coachTop, ProPalette.coachBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(Color.white.opacity(active ? 0.7 : 0.14),
                                                       lineWidth: active ? 1.5 : 1))
                        .shadow(color: Color.black.opacity(0.45), radius: 16, y: 6)
                )
        }
        .buttonStyle(ProPressStyle())
        .accessibilityLabel(coachEnabled ? Text("Coach") : Text("Quick actions"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
#endif
