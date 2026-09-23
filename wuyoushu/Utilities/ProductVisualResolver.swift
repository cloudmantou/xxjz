import SwiftUI

struct ProductVisualDescriptor {
    let symbolName: String
    let tintColor: Color

    var gradientColors: [Color] {
        [
            tintColor.opacity(0.14),
            tintColor.opacity(0.24)
        ]
    }
}

enum ProductVisualResolver {
    static func assetVisual(name: String, category: String) -> ProductVisualDescriptor {
        if let remote = remoteVisual(scope: .asset, name: name, category: category) {
            return remote
        }
        return builtInAssetVisual(name: name, category: category)
    }

    static func wishVisual(name: String, category: String) -> ProductVisualDescriptor {
        if let remote = remoteVisual(scope: .wish, name: name, category: category) {
            return remote
        }
        return builtInWishVisual(name: name, category: category)
    }

    private static func remoteVisual(
        scope: ProductVisualScope,
        name: String,
        category: String
    ) -> ProductVisualDescriptor? {
        guard let rule = ConfigHotUpdateService.shared.resolvedProductVisualRule(
            scope: scope,
            name: name,
            category: category
        ) else {
            return nil
        }

        return ProductVisualDescriptor(
            symbolName: rule.symbolName,
            tintColor: tintColor(hex: rule.tintHex, fallback: scope == .asset ? .warmTeal : .warmCoral)
        )
    }

    private static func builtInAssetVisual(name: String, category: String) -> ProductVisualDescriptor {
        let normalizedName = normalized(name)
        let normalizedCategory = normalized(category)

        let symbolName: String
        switch true {
        case containsAny(normalizedName, ["iphone", "手机", "小米", "华为", "vivo", "oppo"]):
            symbolName = "iphone.gen3"
        case containsAny(normalizedName, ["macbook", "电脑", "笔记本", "显示器", "主机"]):
            symbolName = "laptopcomputer"
        case containsAny(normalizedName, ["ipad", "平板"]):
            symbolName = "ipad"
        case containsAny(normalizedName, ["airpods", "耳机", "音箱"]):
            symbolName = "headphones"
        case containsAny(normalizedName, ["相机", "camera"]):
            symbolName = "camera.fill"
        case containsAny(normalizedName, ["手表", "watch"]):
            symbolName = "applewatch"
        case containsAny(normalizedName, ["键盘", "keyboard"]):
            symbolName = "keyboard"
        case containsAny(normalizedCategory, ["电子产品"]):
            symbolName = "laptopcomputer"
        case containsAny(normalizedCategory, ["数码配件"]):
            symbolName = "cable.connector"
        case containsAny(normalizedCategory, ["交通工具"]):
            symbolName = "car.fill"
        case containsAny(normalizedCategory, ["家具"]):
            symbolName = "sofa.fill"
        case containsAny(normalizedCategory, ["家居用品"]):
            symbolName = "house.fill"
        case containsAny(normalizedCategory, ["珠宝首饰"]):
            symbolName = "sparkles"
        case containsAny(normalizedCategory, ["艺术品"]):
            symbolName = "paintbrush.fill"
        case containsAny(normalizedCategory, ["图书音像"]):
            symbolName = "book.fill"
        case containsAny(normalizedCategory, ["运动户外"]):
            symbolName = "figure.run"
        default:
            symbolName = "shippingbox.fill"
        }

        return ProductVisualDescriptor(symbolName: symbolName, tintColor: .warmTeal)
    }

    private static func builtInWishVisual(name: String, category: String) -> ProductVisualDescriptor {
        let normalizedName = normalized(name)
        let normalizedCategory = normalized(category)

        let symbolName: String
        switch true {
        case containsAny(normalizedName, ["iphone", "手机"]):
            symbolName = "iphone.gen3"
        case containsAny(normalizedName, ["macbook", "电脑", "笔记本"]):
            symbolName = "laptopcomputer"
        case containsAny(normalizedName, ["airpods", "耳机"]):
            symbolName = "headphones"
        case containsAny(normalizedName, ["相机", "camera"]):
            symbolName = "camera.fill"
        case containsAny(normalizedName, ["口红", "护肤", "香水"]):
            symbolName = "sparkles"
        case containsAny(normalizedName, ["书", "书籍"]):
            symbolName = "book.fill"
        case containsAny(normalizedName, ["鞋", "包", "衣", "外套"]):
            symbolName = "bag.fill"
        case containsAny(normalizedCategory, ["电子产品"]):
            symbolName = "iphone.gen3"
        case containsAny(normalizedCategory, ["数码配件"]):
            symbolName = "headphones"
        case containsAny(normalizedCategory, ["家居用品"]):
            symbolName = "lamp.table.fill"
        case containsAny(normalizedCategory, ["服饰鞋包"]):
            symbolName = "bag.fill"
        case containsAny(normalizedCategory, ["图书音像"]):
            symbolName = "book.fill"
        case containsAny(normalizedCategory, ["运动户外"]):
            symbolName = "figure.run"
        case containsAny(normalizedCategory, ["美妆护肤"]):
            symbolName = "sparkles"
        case containsAny(normalizedCategory, ["食品饮料"]):
            symbolName = "cup.and.saucer.fill"
        default:
            symbolName = "heart.fill"
        }

        return ProductVisualDescriptor(symbolName: symbolName, tintColor: .warmCoral)
    }

    private static func tintColor(hex: String?, fallback: Color) -> Color {
        guard let hex, !hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return Color(hex: hex)
    }

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func containsAny(_ source: String, _ keywords: [String]) -> Bool {
        keywords.contains { source.contains(normalized($0)) }
    }
}
