import SwiftUI
import UIKit

private struct BottomBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomBarInset: CGFloat {
        get { self[BottomBarInsetKey.self] }
        set { self[BottomBarInsetKey.self] = newValue }
    }
}

struct MainTabView: View {
    @ObservedObject private var ledgerStore = LedgerStore.shared
    @ObservedObject private var sharingService = LedgerSharingService.shared
    @EnvironmentObject private var router: AppRouter
    @State private var assetFormMode: AssetFormMode = .add

    init() {
        UITabBar.appearance().isHidden = true
    }

    private var shouldExposeLegacySearchActivities: Bool {
        if #available(iOS 16.0, *) {
            return false
        }
        return true
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = max(proxy.safeAreaInsets.bottom, 10)
            let reservedBarHeight = 86 + bottomInset

            ZStack(alignment: .bottom) {
                tabContent
                    .id(ledgerStore.selectionToken)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(height: reservedBarHeight)
                    }
                    .environment(\.bottomBarInset, reservedBarHeight)
                    .floatingTabBarHiddenCompat()

                if !router.showQuickRecordSheet {
                    FloatingTabBar(
                        selectedTab: $router.selectedTab,
                        safeAreaBottom: proxy.safeAreaInsets.bottom,
                        quickRecordPresented: router.showQuickRecordSheet,
                        openQuickRecord: { router.trigger(.quickRecord) }
                    )
                }
            }
            .overlay(alignment: .top) {
                if sharingService.isAccepting { ProgressView("正在接受账本邀请…").padding().background(.regularMaterial).cornerRadius(12) }
            }
            .alert("iCloud 共享", isPresented: Binding(get: { sharingService.message != nil }, set: { if !$0 { sharingService.message = nil } })) {
                Button("好") { sharingService.message = nil }
            } message: { Text(sharingService.message ?? "") }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                if router.selectedTab == .quick {
                    router.selectedTab = .home
                }
            }
            .fullScreenCover(
                isPresented: $router.showQuickRecordSheet,
                onDismiss: {
                    router.syncAfterQuickRecordSheetDismissed()
                }
            ) {
                NavigationView {
                    QuickRecordView(
                        showBackButton: true,
                        onDismiss: { router.dismissQuickRecord(printTargetURI: nil) }
                    )
                }
                .navigationViewStyle(.stack)
            }
        }
    }

    private var tabContent: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(Constants.Tab.home.title, systemImage: Constants.Tab.home.icon)
                }
                .tag(Constants.Tab.home)
                .userActivity("com.assetlife.openHome") { activity in
                    activity.isEligibleForSearch = false
                    activity.isEligibleForPrediction = false
                    activity.title = "打开小西记账主页"
                }

            StatisticsHomeView()
                .tabItem {
                    Label(Constants.Tab.record.title, systemImage: Constants.Tab.record.icon)
                }
                .tag(Constants.Tab.record)
                .userActivity("com.assetlife.openStats") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开统计页"
                }

            AssetWishTabView()
                .tabItem {
                    Label(Constants.Tab.asset.title, systemImage: Constants.Tab.asset.icon)
                }
                .tag(Constants.Tab.asset)
                .userActivity("com.assetlife.openAsset") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开资产页"
                }
                .userActivity("com.assetlife.openWish") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开心愿清单"
                }

            ProfileView()
                .tabItem {
                    Label(Constants.Tab.profile.title, systemImage: Constants.Tab.profile.icon)
                }
                .tag(Constants.Tab.profile)
                .userActivity("com.assetlife.openProfile") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开我的页面"
                }
        }
        .tint(.warmTeal)
        .sheet(isPresented: $router.showAddAssetSheet) {
            AssetFormView(mode: assetFormMode)
                .onChange(of: router.showAddAssetSheet) { isShowing in
                    if isShowing {
                        if let params = router.pendingWishToAsset {
                            assetFormMode = .addFromWish(name: params.name, category: params.category, purchasePrice: params.purchasePrice)
                            router.pendingWishToAsset = nil
                        } else {
                            assetFormMode = .add
                        }
                    }
                }
        }
        .sheet(isPresented: $router.showAddWishSheet) {
            WishlistFormView(mode: .add)
        }
    }
}

private struct AssetWishTabView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedSection: AppRouter.AssetSection = .asset
    @State private var previousSection: AppRouter.AssetSection = .asset
    @Namespace private var sectionToggleNamespace

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionSelector
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(Color.appPageBackground)

            Group {
                if selectedSection == .asset {
                    AssetListView()
                        .transition(sectionTransition(to: .asset))
                } else {
                    WishlistView()
                        .transition(sectionTransition(to: .wish))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedSection)
        .onAppear {
            selectedSection = router.selectedAssetSection
            previousSection = router.selectedAssetSection
        }
        .onChange(of: router.selectedAssetSection) { newValue in
            guard newValue != selectedSection else { return }
            previousSection = selectedSection
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedSection = newValue
            }
        }
        .onChange(of: selectedSection) { newValue in
            guard router.selectedAssetSection != newValue else { return }
            router.selectedAssetSection = newValue
        }
    }

    private var sectionSelector: some View {
        HStack(spacing: 4) {
            sectionButton(title: "资产", section: .asset)
            sectionButton(title: "心愿", section: .wish)
        }
        .padding(3)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appPillBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.borderSoft.opacity(0.7), lineWidth: 0.8)
        )
    }

    private func sectionButton(title: String, section: AppRouter.AssetSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            guard section != selectedSection else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            previousSection = selectedSection
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                selectedSection = section
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.heroGradientTop, Color.heroGradientBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.warmTeal.opacity(0.24), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "assetWishSectionBackground", in: sectionToggleNamespace)
                }

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sectionTransition(to target: AppRouter.AssetSection) -> AnyTransition {
        let targetIndex = target == .asset ? 0 : 1
        let previousIndex = previousSection == .asset ? 0 : 1
        let insertFromTrailing = targetIndex > previousIndex
        return AnyTransition.asymmetric(
            insertion: .move(edge: insertFromTrailing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: insertFromTrailing ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

private struct FloatingTabBar: View {
    @Binding var selectedTab: Constants.Tab
    let safeAreaBottom: CGFloat
    let quickRecordPresented: Bool
    let openQuickRecord: () -> Void

    var body: some View {
        let bottomPadding = max(10, safeAreaBottom)

        ZStack(alignment: .top) {
            // 背景磨砂立体卡片
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.appTabBarBackground.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.appTabBarBorder],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .frame(height: 72)
                .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
                .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)

            HStack(spacing: 0) {
                regularTabButton(tab: .home)
                regularTabButton(tab: .record)
                centerQuickButton
                regularTabButton(tab: .asset)
                regularTabButton(tab: .profile)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, bottomPadding)
    }

    private func regularTabButton(tab: Constants.Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                    .scaleEffect(isSelected ? 1.08 : 1.0)

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))

                // 微型底部活动指示点
                Circle()
                    .fill(isSelected ? Color.warmTeal : Color.clear)
                    .frame(width: 4, height: 4)
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundColor(isSelected ? .warmTeal : .textSecondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var centerQuickButton: some View {
        let isSelected = quickRecordPresented

        return Button {
            Haptics.tap()
            openQuickRecord()
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    // 外发光层
                    Circle()
                        .fill(Color.warmTeal.opacity(0.25))
                        .frame(width: 58, height: 58)
                        .blur(radius: 6)

                    // 主渐变球体
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.heroGradientTop, Color.heroGradientBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1.2)
                        )
                        .shadow(color: Color.warmTeal.opacity(0.4), radius: 10, y: 5)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)

                    Image(systemName: "pencil")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.white)
                }
                .offset(y: -18)

                Text(Constants.Tab.quick.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .warmTeal : .textSecondary)
                    .padding(.top, -12)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88))
        .accessibilityLabel(Constants.Tab.quick.title)
    }
}

private extension View {
    @ViewBuilder
    func floatingTabBarHiddenCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppRouter())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
