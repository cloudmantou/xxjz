import SwiftUI
import CoreData
import UIKit

struct ProfileView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.updatedAt, ascending: false)],
        animation: .default
    )
    private var assets: FetchedResults<AssetItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WishlistItem.updatedAt, ascending: false)],
        animation: .default
    )
    private var wishItems: FetchedResults<WishlistItem>

    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    )
    private var transactions: FetchedResults<BookkeepingTransaction>

    var totalAssetsValue: Double {
        assets.filter { $0.status == .active }.reduce(0) { $0 + $1.currentValue }
    }

    var totalExtraCost: Double {
        assets.filter { $0.status == .active }.reduce(0) { $0 + $1.totalExtraCost }
    }

    private var bookkeepingCloudSyncEnabled: Bool {
        PersistenceController.shared.bookkeepingCloudSyncEnabled
    }

    @State private var cloudSyncPreference: Bool = UserDefaults.standard.object(forKey: Constants.ICloud.cloudSyncPreferenceKey) as? Bool ?? true
    @State private var showCloudSyncRestartAlert = false
    @State private var remoteProfileLinks: [AppProfileLinkConfig] = []

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    private var sectionSpacing: CGFloat {
        Constants.Layout.sectionSpacing(for: screenWidth)
    }

    var activeAssetCount: Int { assets.filter { $0.status == .active }.count }
    var soldAssetCount: Int { assets.filter { $0.status == .sold }.count }
    var wishCount: Int { wishItems.filter { !$0.isPurchased }.count }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: sectionSpacing) {
                    // User Info Card with gradient
                    userInfoCard

                    // Stats Grid (2 columns)
                    statsGrid

                    // Asset Overview Card
                    assetOverviewCard

                    sectionHeader("设置")
                    // Settings Section
                    settingsSection

                    sectionHeader("快捷指令与自动化")
                    // Shortcuts Section
                    shortcutsSection

                    if !visibleProfileLinks.isEmpty {
                        sectionHeader("官方主页与社媒")
                        profileLinksSection
                    }

                    sectionHeader("关于")
                    // About Section
                    aboutSection
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 12 + bottomBarInset)
            }
            .background(Color.appPageBackground)
            .navigationTitle("我的")
            .onAppear {
                reloadProfileLinksFromConfig()
                refreshProfileLinks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .configDidUpdate)) { _ in
                reloadProfileLinksFromConfig()
            }
        }
    }

    private var visibleProfileLinks: [AppProfileLinkConfig] {
        remoteProfileLinks.filter { link in
            guard (link.enabled ?? true) else { return false }
            guard let url = URL(string: link.url), !link.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, -4)
    }

    private var userInfoCard: some View {
        ZStack(alignment: .bottomLeading) {
            // 渐变背景
            RoundedRectangle(cornerRadius: CardRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.heroGradientTop, Color.heroGradientBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 右下角装饰圆
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 140, height: 140)
                .offset(x: 160, y: 40)

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 90, height: 90)
                .offset(x: 230, y: -10)

            // 内容
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    // 头像区
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 56, height: 56)
                        Image(systemName: "person.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("用户")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white)

                        Text("AssetLife 用户")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }

                    Spacer()
                }

                // 分割线
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 0.5)

                // 资产摘要行
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("资产总价值")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                        Text(totalAssetsValue.currencyString)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("记账笔数")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                        Text("\(transactions.count)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                }
            }
            .padding(18)
        }
        .frame(height: 170)
        .clipped()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            StatCard(
                title: "资产总数",
                value: "\(assets.count)",
                icon: "creditcard.fill"
            )

            StatCard(
                title: "使用中",
                value: "\(activeAssetCount)",
                icon: "checkmark.circle.fill",
                iconColor: .profitGreen
            )

            StatCard(
                title: "已卖出",
                value: "\(soldAssetCount)",
                icon: "tag.fill",
                iconColor: .warmTeal
            )

            StatCard(
                title: "心愿清单",
                value: "\(wishCount)",
                icon: "heart.fill",
                iconColor: .warmCoral
            )

            StatCard(
                title: "记账笔数",
                value: "\(transactions.count)",
                icon: "number.square.fill"
            )

            StatCard(
                title: "附加成本",
                value: totalExtraCost.compactCurrencyString,
                icon: "minus.circle.fill",
                iconColor: .warmCoral
            )
        }
    }

    private var assetOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资产总览")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("资产总价值")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalAssetsValue.currencyString)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.warmTeal)
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("资产净价值")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((totalAssetsValue - totalExtraCost).currencyString)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle((totalAssetsValue - totalExtraCost) >= 0 ? Color.profitGreen : Color.lossRed)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            iCloudSyncStatusRow
            Divider().padding(.leading, 52)
            NavigationLink {
                BudgetManagementView()
            } label: {
                settingsRowLabel(icon: "target", title: "预算管理")
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                settingsRowLabel(icon: "moon.fill", title: "外观")
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                ImportView()
            } label: {
                settingsRowLabel(icon: "square.and.arrow.down", title: "导入账单")
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                AssetImportExportView(initialTab: 0)
            } label: {
                settingsRowLabel(icon: "archivebox.fill", title: "资产导入")
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                ExportView()
            } label: {
                settingsRowLabel(icon: "square.and.arrow.up", title: "导出账单")
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                LocalBackupView()
            } label: {
                settingsRowLabel(icon: "externaldrive.fill", title: "完整数据备份")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .cardStyle()
    }

    private var iCloudSyncStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 16))
                .foregroundStyle(cloudSyncPreference ? Color.warmTeal : Color.gray)
                .frame(width: 24)

            Text(L10n.tr("账本 iCloud 同步"))
                .font(.subheadline)

            Spacer()

            Toggle("", isOn: $cloudSyncPreference)
                .labelsHidden()
                .onChange(of: cloudSyncPreference) { newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.ICloud.cloudSyncPreferenceKey)
                    showCloudSyncRestartAlert = true
                }
        }
        .padding(.vertical, 10)
        .alert("重启生效", isPresented: $showCloudSyncRestartAlert) {
            Button("好的") {}
        } message: {
            Text(cloudSyncPreference ? "iCloud 同步已开启，重启 App 后生效" : "iCloud 同步已关闭，重启 App 后生效")
        }
    }

    private func settingsRowLabel(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.warmTeal)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                openShortcutsApp()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.warmTeal)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("打开快捷指令 App")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("点击后自动跳转并导入「小西记账」快捷指令")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 34)

            NavigationLink {
                ShortcutTutorialView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.warmTeal)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动记账教程")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("视频教程 + 文档教程，快速完成自动记账配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardStyle()
    }

    private func openShortcutsApp() {
        if let url = Constants.ShortcutsTutorial.installShortcutURL,
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private var aboutSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("版本")
                    .font(.subheadline)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            Divider().padding(.leading, 16)
            HStack {
                Text("构建")
                    .font(.subheadline)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, pageHorizontalPadding)
        .cardStyle()
    }

    private var profileLinksSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleProfileLinks.enumerated()), id: \.element.stableId) { index, link in
                Button {
                    openProfileLink(link)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: link))
                            .font(.system(size: 16))
                            .foregroundStyle(Color.warmTeal)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(link.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < visibleProfileLinks.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .cardStyle()
    }

    private func iconName(for link: AppProfileLinkConfig) -> String {
        if let custom = link.symbolName, !custom.isEmpty {
            return custom
        }

        switch (link.platform ?? "").lowercased() {
        case "douyin":
            return "play.rectangle.fill"
        case "xiaohongshu":
            return "book.fill"
        case "wechat":
            return "message.fill"
        case "bilibili":
            return "tv.fill"
        default:
            return "link"
        }
    }

    private func openProfileLink(_ link: AppProfileLinkConfig) {
        guard let url = URL(string: link.url) else { return }
        UIApplication.shared.open(url)
    }

    private func reloadProfileLinksFromConfig() {
        let links = ConfigHotUpdateService.shared.currentConfig
            .appSettings?
            .profileLinks ?? []
        remoteProfileLinks = links
    }

    private func refreshProfileLinks() {
        ConfigHotUpdateService.shared.fetchLatestConfig { _ in
            reloadProfileLinksFromConfig()
        }
    }
}

#Preview {
    ProfileView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
