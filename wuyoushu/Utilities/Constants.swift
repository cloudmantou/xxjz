import Foundation
import SwiftUI

enum Constants {

    // MARK: - Asset Categories

    enum AssetCategory {
        static let all = [
            "电子产品",
            "数码配件",
            "家居用品",
            "家具",
            "交通工具",
            "珠宝首饰",
            "艺术品",
            "图书音像",
            "运动户外",
            "美妆护肤",
            "食品饮料",
            "其他"
        ]
    }

    // MARK: - UI Constants

    enum UI {
        static let cornerRadius: CGFloat = 16
        static let cardPadding: CGFloat = 16
        static let spacing: CGFloat = 8
        static let iconSize: CGFloat = 24
        static let thumbnailSize: CGFloat = 60
    }

    // MARK: - Responsive Layout

    enum LayoutBucket {
        case legacyCompact
        case standard
        case large
        case max
    }

    enum Layout {
        static func bucket(for width: CGFloat) -> LayoutBucket {
            switch width {
            case ...350:
                return .legacyCompact
            case 351...390:
                return .standard
            case 391...430:
                return .large
            default:
                return .max
            }
        }

        static func pageHorizontalPadding(for width: CGFloat) -> CGFloat {
            switch bucket(for: width) {
            case .legacyCompact:
                return 14
            case .standard:
                return 16
            case .large:
                return 18
            case .max:
                return 20
            }
        }

        static func sectionSpacing(for width: CGFloat) -> CGFloat {
            switch bucket(for: width) {
            case .legacyCompact:
                return 12
            case .standard:
                return 14
            case .large:
                return 16
            case .max:
                return 18
            }
        }

        static func heroCardMinHeight(for width: CGFloat) -> CGFloat {
            switch bucket(for: width) {
            case .legacyCompact:
                return 142
            case .standard:
                return 150
            case .large:
                return 158
            case .max:
                return 166
            }
        }

        static func floatingButtonBottomPadding(for width: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
            let base: CGFloat
            switch bucket(for: width) {
            case .legacyCompact:
                base = 54
            case .standard:
                base = 58
            case .large:
                base = 62
            case .max:
                base = 68
            }
            return max(base, safeAreaBottom + 12)
        }

        static func typeToggleHeight(for width: CGFloat) -> CGFloat {
            switch bucket(for: width) {
            case .legacyCompact:
                return 36
            case .standard:
                return 38
            case .large, .max:
                return 40
            }
        }

        static func categoryColumnCount(for width: CGFloat) -> Int {
            switch bucket(for: width) {
            case .legacyCompact, .standard:
                return 4
            case .large, .max:
                return 5
            }
        }

        static func categoryIconSize(for width: CGFloat) -> CGFloat {
            switch bucket(for: width) {
            case .legacyCompact:
                return 44
            case .standard:
                return 48
            case .large, .max:
                return 52
            }
        }

        static func chartLegendMinWidth(for width: CGFloat) -> CGFloat {
            switch bucket(for: width) {
            case .legacyCompact:
                return 0
            case .standard:
                return 138
            case .large:
                return 148
            case .max:
                return 156
            }
        }
    }

    // MARK: - Animation

    enum Animation {
        static let defaultDuration: Double = 0.3
        static let quickDuration: Double = 0.15
    }

    // MARK: - Chart

    enum Chart {
        static let maxCategories = 8
        static let topItemsLimit = 5
        static let monthsToShow = 6
    }

    // MARK: - Default Values

    enum Default {
        static let expectedLifeYears: Double = 5
        static let priority = 3
        static let targetPrice: Double = 0
    }

    // MARK: - Tab

    enum Tab: String, CaseIterable {
        case home
        case record
        case quick
        case asset
        case profile

        var title: String {
            switch self {
            case .home: return L10n.tr("主页")
            case .record: return L10n.tr("统计")
            case .quick: return L10n.tr("记一笔")
            case .asset: return L10n.tr("资产")
            case .profile: return L10n.tr("我的")
            }
        }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .record: return "chart.bar.xaxis"
            case .quick: return "pencil.circle.fill"
            case .asset: return "creditcard.fill"
            case .profile: return "person.fill"
            }
        }
    }

    // MARK: - Bookkeeping

    enum Bookkeeping {
        static let maxAmountDigits: Int = 10
        static let defaultBudgetAmount: Double = 5000
        static let maxPinnedCategories: Int = 6
        static let maxRecentCategoryHistory: Int = 12
        static let widgetSuiteName = "group.com.assetlife.bookkeeping"
        static let widgetTodaySummaryKey = "todaySummary"
        static let quickRecordMinimalModeKey = "quickRecordMinimalMode"
        static let lastCategoryKey = "lastUsedCategoryKey"
        static let lastSubcategoryKey = "lastUsedSubcategoryKey"
        static let recentExpenseCategoryKeys = "recentExpenseCategoryKeys"
        static let recentIncomeCategoryKeys = "recentIncomeCategoryKeys"
        static let expenseCategoryFrequencyMap = "expenseCategoryFrequencyMap"
        static let incomeCategoryFrequencyMap = "incomeCategoryFrequencyMap"
        static let expenseCategoryContextFrequencyPrefix = "expenseCategoryContextFrequency."
        static let incomeCategoryContextFrequencyPrefix = "incomeCategoryContextFrequency."
        static let lastFundAccountKey = "lastUsedFundAccountKey"
    }

    // MARK: - iCloud

    enum ICloud {
        /// Keep this aligned with Apple Developer -> Identifiers -> iCloud Containers.
        static let containerIdentifier = "iCloud.com.assetlife.app"
        /// UserDefaults key for user's preferred cloud sync state.
        static let cloudSyncPreferenceKey = "bookkeepingCloudSyncPreference"
    }

    // MARK: - Shortcuts Tutorial

    enum ShortcutsTutorial {
        static let installShortcutURLString = "https://www.icloud.com/shortcuts/39f06dae77d347509f2eb1e808aa8301"
        /// 可替换为你们自己的教程视频地址
        static let methodOneVideoURLString = "https://www.icloud.com/shortcuts/39f06dae77d347509f2eb1e808aa8301"
        /// 可替换为你们自己的教程视频地址
        static let methodTwoVideoURLString = "https://www.icloud.com/shortcuts/39f06dae77d347509f2eb1e808aa8301"

        static var installShortcutURL: URL? { URL(string: installShortcutURLString) }
        static var methodOneVideoURL: URL? { URL(string: methodOneVideoURLString) }
        static var methodTwoVideoURL: URL? { URL(string: methodTwoVideoURLString) }
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static var appDisplayName: String {
        tr("小西记账")
    }
}
