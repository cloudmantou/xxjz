import Foundation
import SwiftUI
import CoreData

final class DashboardViewModel: ObservableObject {

    private let calculationService = CalculationService.shared

    // MARK: - Dashboard Stats

    @Published var totalAssetValue: Double = 0
    @Published var totalExtraCost: Double = 0
    @Published var totalAssets: Int = 0
    @Published var activeAssets: Int = 0
    @Published var soldAssets: Int = 0

    // MARK: - Distribution Data

    @Published var statusDistribution: [(status: AssetStatus, count: Int, value: Double)] = []
    @Published var categoryDistribution: [(category: String, count: Int, value: Double)] = []
    @Published var topDailyCostAssets: [(name: String, dailyCost: Double)] = []
    @Published var monthlyTrend: [(month: Date, amount: Double)] = []

    // MARK: - Computed Properties

    var totalHoldingDays: Int {
        assets.reduce(0) { $0 + $1.holdingDays }
    }

    var averageDailyCost: Double {
        guard totalHoldingDays > 0 else { return 0 }
        return (totalAssetValue + totalExtraCost) / Double(totalHoldingDays)
    }

    // MARK: - Private

    private var assets: [AssetItem] = []

    // MARK: - Loading

    func loadData(from context: NSManagedObjectContext) {
        loadAssets(from: context)
        calculateStats()
        calculateDistributions()
        calculateTopDailyCosts()
        calculateMonthlyTrend(from: context)
    }

    private func loadAssets(from context: NSManagedObjectContext) {
        let request = AssetItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AssetItem.purchaseDate, ascending: false)]

        do {
            assets = try context.fetch(request).filter { $0.status != .deleted }
        } catch {
            print("Failed to fetch assets: \(error)")
            assets = []
        }
    }

    private func calculateStats() {
        totalAssets = assets.count
        activeAssets = assets.filter { $0.status == .active }.count
        soldAssets = assets.filter { $0.status == .sold }.count

        totalAssetValue = assets
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.currentValue }

        totalExtraCost = assets
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.totalExtraCost }
    }

    private func calculateDistributions() {
        // Status Distribution
        var statusMap: [AssetStatus: (count: Int, value: Double)] = [:]
        for asset in assets {
            let current = statusMap[asset.status] ?? (0, 0)
            statusMap[asset.status] = (
                current.count + 1,
                current.value + (asset.status == .active ? asset.currentValue : asset.purchasePrice)
            )
        }
        statusDistribution = statusMap.map { ($0.key, $0.value.count, $0.value.value) }
            .sorted { $0.2 > $1.2 }

        // Category Distribution
        var categoryMap: [String: (count: Int, value: Double)] = [:]
        for asset in assets where asset.status == .active {
            let current = categoryMap[asset.category] ?? (0, 0)
            categoryMap[asset.category] = (
                current.count + 1,
                current.value + asset.currentValue
            )
        }
        categoryDistribution = Array(categoryMap.map { ($0.key, $0.value.count, $0.value.value) }
            .sorted { $0.2 > $1.2 }
            .prefix(Constants.Chart.maxCategories))
    }

    private func calculateTopDailyCosts() {
        let activeAssetsSorted = assets
            .filter { $0.status == .active }
            .sorted { $0.dailyCost > $1.dailyCost }

        topDailyCostAssets = activeAssetsSorted
            .prefix(Constants.Chart.topItemsLimit)
            .map { ($0.name, $0.dailyCost) }
    }

    private func calculateMonthlyTrend(from context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let now = Date()
        var trend: [(month: Date, amount: Double)] = []

        for monthOffset in (0..<Constants.Chart.monthsToShow).reversed() {
            guard let month = calendar.date(byAdding: .month, value: -monthOffset, to: now) else { continue }

            // Calculate spending for this month
            let monthSpending = calculationService.monthlySpending(
                records: assets.flatMap { $0.extraCosts },
                in: month
            )
            let monthPurchases = calculationService.monthlyAssetPurchases(assets: assets, in: month)

            trend.append((month, monthSpending + monthPurchases))
        }

        monthlyTrend = trend
    }
}
