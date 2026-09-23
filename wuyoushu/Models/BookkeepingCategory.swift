import SwiftUI

struct BookkeepingSubcategory: Identifiable, Hashable {
    let key: String
    let name: String
    let emoji: String

    var id: String { key }

    var localizedName: String {
        L10n.tr(name)
    }
}

struct BookkeepingCategory: Identifiable, Hashable {
    let key: String
    let name: String
    let emoji: String
    let colorHex: String
    let subcategories: [BookkeepingSubcategory]

    var id: String { key }

    var color: Color {
        Color(hex: colorHex)
    }

    var localizedName: String {
        L10n.tr(name)
    }

    // MARK: - Expense Categories

    static let expenseCategories: [BookkeepingCategory] = [
        BookkeepingCategory(
            key: "dining", name: "餐饮", emoji: "🍽️", colorHex: "FFF8E1",
            subcategories: [
                BookkeepingSubcategory(key: "breakfast", name: "早餐", emoji: "🥐"),
                BookkeepingSubcategory(key: "lunch", name: "午餐", emoji: "🍱"),
                BookkeepingSubcategory(key: "dinner", name: "晚餐", emoji: "🍲"),
                BookkeepingSubcategory(key: "snack", name: "零食", emoji: "🍫"),
                BookkeepingSubcategory(key: "drink", name: "饮品", emoji: "🧋"),
                BookkeepingSubcategory(key: "takeout", name: "外卖", emoji: "🛵"),
                BookkeepingSubcategory(key: "midnight", name: "夜宵", emoji: "🍜"),
                BookkeepingSubcategory(key: "gathering", name: "聚餐", emoji: "🎉")
            ]
        ),
        BookkeepingCategory(
            key: "transport", name: "交通", emoji: "🚗", colorHex: "E3F2FD",
            subcategories: [
                BookkeepingSubcategory(key: "bus", name: "公交", emoji: "🚌"),
                BookkeepingSubcategory(key: "metro", name: "地铁", emoji: "🚇"),
                BookkeepingSubcategory(key: "taxi", name: "出租车", emoji: "🚕"),
                BookkeepingSubcategory(key: "bicycle", name: "共享单车", emoji: "🚲"),
                BookkeepingSubcategory(key: "gas", name: "加油", emoji: "⛽"),
                BookkeepingSubcategory(key: "parking", name: "停车", emoji: "🅿️"),
                BookkeepingSubcategory(key: "train", name: "高铁", emoji: "🚄"),
                BookkeepingSubcategory(key: "flight", name: "飞机", emoji: "✈️")
            ]
        ),
        BookkeepingCategory(
            key: "shopping", name: "购物", emoji: "🛍️", colorHex: "FCE4EC",
            subcategories: [
                BookkeepingSubcategory(key: "clothes", name: "衣服", emoji: "👕"),
                BookkeepingSubcategory(key: "shoes", name: "鞋子", emoji: "👟"),
                BookkeepingSubcategory(key: "bag", name: "包包", emoji: "👜"),
                BookkeepingSubcategory(key: "daily", name: "日用品", emoji: "🧴"),
                BookkeepingSubcategory(key: "digital", name: "数码", emoji: "📱"),
                BookkeepingSubcategory(key: "home", name: "家居", emoji: "🏠")
            ]
        ),
        BookkeepingCategory(
            key: "entertainment", name: "娱乐", emoji: "🎮", colorHex: "F3E5F5",
            subcategories: [
                BookkeepingSubcategory(key: "movie", name: "电影", emoji: "🎬"),
                BookkeepingSubcategory(key: "game", name: "游戏", emoji: "🎮"),
                BookkeepingSubcategory(key: "music", name: "音乐", emoji: "🎵"),
                BookkeepingSubcategory(key: "ktv", name: "KTV", emoji: "🎤"),
                BookkeepingSubcategory(key: "sport", name: "运动", emoji: "⚽"),
                BookkeepingSubcategory(key: "travel", name: "旅行", emoji: "✈️")
            ]
        ),
        BookkeepingCategory(
            key: "housing", name: "居住", emoji: "🏠", colorHex: "E8F5E9",
            subcategories: [
                BookkeepingSubcategory(key: "rent", name: "房租", emoji: "🏠"),
                BookkeepingSubcategory(key: "utility", name: "水电", emoji: "💧"),
                BookkeepingSubcategory(key: "property", name: "物业", emoji: "🏢"),
                BookkeepingSubcategory(key: "internet", name: "网费", emoji: "📶"),
                BookkeepingSubcategory(key: "repair", name: "维修", emoji: "🔧")
            ]
        ),
        BookkeepingCategory(
            key: "medical", name: "医疗", emoji: "🏥", colorHex: "FFEBEE",
            subcategories: [
                BookkeepingSubcategory(key: "clinic", name: "门诊", emoji: "🏥"),
                BookkeepingSubcategory(key: "medicine", name: "药品", emoji: "💊"),
                BookkeepingSubcategory(key: "checkup", name: "体检", emoji: "🩺"),
                BookkeepingSubcategory(key: "health", name: "保健", emoji: "💪"),
                BookkeepingSubcategory(key: "dental", name: "牙科", emoji: "🦷")
            ]
        ),
        BookkeepingCategory(
            key: "education", name: "教育", emoji: "📚", colorHex: "E0F2F1",
            subcategories: [
                BookkeepingSubcategory(key: "books", name: "书籍", emoji: "📚"),
                BookkeepingSubcategory(key: "course", name: "课程", emoji: "🎓"),
                BookkeepingSubcategory(key: "training", name: "培训", emoji: "📝"),
                BookkeepingSubcategory(key: "exam", name: "考试", emoji: "📋")
            ]
        ),
        BookkeepingCategory(
            key: "social", name: "人情", emoji: "🎁", colorHex: "FFF3E0",
            subcategories: [
                BookkeepingSubcategory(key: "redpacket", name: "红包", emoji: "🧧"),
                BookkeepingSubcategory(key: "gift", name: "礼物", emoji: "🎁"),
                BookkeepingSubcategory(key: "treat", name: "请客", emoji: "🍽️"),
                BookkeepingSubcategory(key: "wedding", name: "婚礼", emoji: "💒")
            ]
        ),
        BookkeepingCategory(
            key: "transfer", name: "转账", emoji: "💸", colorHex: "E0F7FA",
            subcategories: [
                BookkeepingSubcategory(key: "wechat", name: "微信", emoji: "💸"),
                BookkeepingSubcategory(key: "alipay", name: "支付宝", emoji: "💰"),
                BookkeepingSubcategory(key: "bank", name: "银行", emoji: "🏦"),
                BookkeepingSubcategory(key: "cash", name: "现金", emoji: "💵")
            ]
        ),
        BookkeepingCategory(
            key: "other", name: "其他", emoji: "📦", colorHex: "F5F5F5",
            subcategories: [
                BookkeepingSubcategory(key: "misc", name: "杂费", emoji: "📦"),
                BookkeepingSubcategory(key: "lost", name: "丢失", emoji: "💸"),
                BookkeepingSubcategory(key: "fine", name: "罚款", emoji: "⚠️")
            ]
        )
    ]

    // MARK: - Income Categories

    static let incomeCategories: [BookkeepingCategory] = [
        BookkeepingCategory(key: "salary", name: "工资", emoji: "💰", colorHex: "FFF8E1", subcategories: []),
        BookkeepingCategory(key: "parttime", name: "兼职", emoji: "💼", colorHex: "E3F2FD", subcategories: []),
        BookkeepingCategory(key: "investment", name: "理财收益", emoji: "📈", colorHex: "E8F5E9", subcategories: []),
        BookkeepingCategory(key: "redpacket_income", name: "红包", emoji: "🧧", colorHex: "FCE4EC", subcategories: []),
        BookkeepingCategory(key: "refund", name: "退款", emoji: "🔄", colorHex: "E0F2F1", subcategories: []),
        BookkeepingCategory(key: "other_income", name: "其他收入", emoji: "💎", colorHex: "F3E5F5", subcategories: [])
    ]

    // MARK: - Lookup

    private static var allExpenseMap: [String: BookkeepingCategory] = {
        var map = [String: BookkeepingCategory]()
        for cat in expenseCategories {
            map[cat.key] = cat
            for sub in cat.subcategories {
                map[sub.key] = cat
            }
        }
        return map
    }()

    private static var allIncomeMap: [String: BookkeepingCategory] = {
        var map = [String: BookkeepingCategory]()
        for cat in incomeCategories {
            map[cat.key] = cat
        }
        return map
    }()

    static func find(key: String) -> BookkeepingCategory? {
        if let custom = CustomCategoryStore.shared.find(key: key) {
            return custom.toBookkeepingCategory()
        }
        return allExpenseMap[key] ?? allIncomeMap[key]
    }

    static func findSubcategory(key: String) -> BookkeepingSubcategory? {
        for cat in expenseCategories {
            if let sub = cat.subcategories.first(where: { $0.key == key }) {
                return sub
            }
        }
        return nil
    }
}
