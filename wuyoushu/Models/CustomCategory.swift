import Foundation
import SwiftUI

struct CustomCategory: Identifiable, Codable, Hashable {
    let id: String        // UUID string
    var name: String
    var emoji: String
    var colorHex: String
    var isIncome: Bool

    init(id: String = UUID().uuidString, name: String, emoji: String, colorHex: String = "E8F5E9", isIncome: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.isIncome = isIncome
    }

    var categoryKey: String { "custom_\(id)" }

    func toBookkeepingCategory() -> BookkeepingCategory {
        BookkeepingCategory(
            key: categoryKey,
            name: name,
            emoji: emoji,
            colorHex: colorHex,
            subcategories: []
        )
    }
}

class CustomCategoryStore: ObservableObject {
    static let shared = CustomCategoryStore()

    @Published var categories: [CustomCategory] = []

    private let storageKey = "custom_bookkeeping_categories"

    private init() {
        load()
    }

    var expenseCategories: [CustomCategory] {
        categories.filter { !$0.isIncome }
    }

    var incomeCategories: [CustomCategory] {
        categories.filter { $0.isIncome }
    }

    func add(_ category: CustomCategory) {
        categories.append(category)
        save()
    }

    func update(_ category: CustomCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
            save()
        }
    }

    func delete(_ category: CustomCategory) {
        categories.removeAll { $0.id == category.id }
        save()
    }

    func find(key: String) -> CustomCategory? {
        guard key.hasPrefix("custom_") else { return nil }
        let id = String(key.dropFirst("custom_".count))
        return categories.first { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) else {
            return
        }
        categories = decoded
    }
}
