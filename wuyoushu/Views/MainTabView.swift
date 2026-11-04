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
        .tint(.brandPrimary500)
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
        DSSegmentedControl(
            items: [AppRouter.AssetSection.asset, .wish],
            selection: Binding(
                get: { selectedSection },
                set: { newValue in
                    guard newValue != selectedSection else { return }
                    previousSection = selectedSection
                    selectedSection = newValue
                }
            ),
            title: { $0 == .asset ? "资产" : "心愿" }
        )
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

    @Namespace private var indicatorNamespace

    var body: some View {
        let bottomPadding = max(10, safeAreaBottom - 6)

        HStack(spacing: 0) {
            regularTabButton(tab: .home)
            regularTabButton(tab: .record)
            centerQuickButton
            regularTabButton(tab: .asset)
            regularTabButton(tab: .profile)
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.appCardBackground.opacity(0.72))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.borderSoft, lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, bottomPadding)
    }

    private func regularTabButton(tab: Constants.Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            Haptics.selection()
            withAnimation(DS.Motion.snappy) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
            }
            .foregroundColor(isSelected ? .brandPrimary500 : .textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.brandPrimary500.opacity(0.10))
                        .matchedGeometryEffect(id: "tabIndicator", in: indicatorNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var centerQuickButton: some View {
        Button {
            Haptics.tap()
            openQuickRecord()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Color.brandPrimary500)
                        .shadow(color: Color.brandPrimary500.opacity(0.35), radius: 10, y: 4)
                )
                .frame(maxWidth: .infinity)
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
