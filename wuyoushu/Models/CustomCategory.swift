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

    @Published private(set) var categories: [CustomCategory] = []

    private var historical: [CustomCategory] = []
    private let defaults: UserDefaults
    private let usesSync: Bool

    private let storageKey = "custom_bookkeeping_categories"

    init(defaults: UserDefaults = .standard, usesSync: Bool = true) {
        self.defaults = defaults
        self.usesSync = usesSync
        load()
    }

    var expenseCategories: [CustomCategory] {
        categories.filter { !$0.isIncome }
    }

    var incomeCategories: [CustomCategory] {
        categories.filter { $0.isIncome }
    }

    @discardableResult
    func add(_ category: CustomCategory) -> Bool {
        if usesSync && PreferenceSyncCoordinator.shared.isConfigured { return PreferenceSyncCoordinator.shared.saveCategory(category) }
        return replaceAll(categories.filter { $0.id != category.id } + [category])
    }

    @discardableResult
    func update(_ category: CustomCategory) -> Bool { add(category) }

    @discardableResult
    func delete(_ category: CustomCategory) -> Bool {
        if usesSync && PreferenceSyncCoordinator.shared.isConfigured { return PreferenceSyncCoordinator.shared.deleteCategory(category) }
        return replaceAll(categories.filter { $0.id != category.id })
    }

    @discardableResult
    func applyProjection(_ replacements: [CustomCategory], historical: [CustomCategory]) -> Bool {
        guard replaceAll(replacements) else { return false }
        if self.historical != historical {
            objectWillChange.send()
            self.historical = historical
        }
        return true
    }

    /// Replaces all custom categories only after their encoded snapshot is durable.
    @discardableResult
    func replaceAll(_ replacements: [CustomCategory]) -> Bool {
        guard let data = try? JSONEncoder().encode(replacements) else { return false }
        defaults.set(data, forKey: storageKey)
        if categories != replacements { categories = replacements }
        return true
    }

    func backupSnapshot() throws -> [CustomCategory] {
        guard let data = defaults.data(forKey: storageKey) else { return categories }
        return try JSONDecoder().decode([CustomCategory].self, from: data)
    }

    func find(key: String) -> CustomCategory? {
        guard key.hasPrefix("custom_") else { return nil }
        let id = String(key.dropFirst("custom_".count))
        return categories.first { $0.id == id } ?? historical.first { $0.id == id }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) else {
            return
        }
        categories = decoded
    }
}
