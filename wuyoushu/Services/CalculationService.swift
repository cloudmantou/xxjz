import Foundation

final class CalculationService {

    static let shared = CalculationService()

    private init() {}

    // MARK: - Holding Days

    func holdingDays(from purchaseDate: Date, to date: Date = Date()) -> Int {
        Calendar.current.dateComponents([.day], from: purchaseDate, to: date).day ?? 0
    }

    // MARK: - Daily Cost

    func dailyCost(purchasePrice: Double, totalExtraCosts: Double, holdingDays: Int) -> Double {
        guard holdingDays > 0 else { return purchasePrice + totalExtraCosts }
        return (purchasePrice + totalExtraCosts) / Double(holdingDays)
    }

    func dailyCost(asset: AssetItem) -> Double {
        dailyCost(
            purchasePrice: asset.purchasePrice,
            totalExtraCosts: asset.totalExtraCost,
            holdingDays: asset.holdingDays
        )
    }

    // MARK: - Lifecycle Progress

    func lifecycleProgress(purchaseDate: Date, expectedLifeYears: Double) -> Double {
        let totalDays = expectedLifeYears * 365
        let heldDays = holdingDays(from: purchaseDate)
        let progress = Double(heldDays) / totalDays
        return min(max(progress, 0), 1)
    }

    // MARK: - Sale Profit/Loss

    func saleProfitLoss(
        purchasePrice: Double,
        totalCosts: Double,
        salePrice: Double
    ) -> Double {
        salePrice - totalCosts
    }

    func saleProfitLossPercent(
        purchasePrice: Double,
        totalCosts: Double,
        salePrice: Double
    ) -> Double {
        guard totalCosts > 0 else { return 0 }
        return ((salePrice - totalCosts) / totalCosts) * 100
    }

    // MARK: - Price Change

    func priceChangePercent(current: Double, previous: Double) -> Double {
        guard previous > 0 else { return 0 }
        return ((current - previous) / previous) * 100
    }

    // MARK: - Price Statistics

    func averagePrice(_ prices: [Double]) -> Double {
        guard !prices.isEmpty else { return 0 }
        return prices.reduce(0, +) / Double(prices.count)
    }

    func lowestPrice(_ prices: [Double]) -> Double {
        prices.min() ?? 0
    }

    func highestPrice(_ prices: [Double]) -> Double {
        prices.max() ?? 0
    }

    // MARK: - Monthly Statistics

    func monthlySpending(records: [AssetExtraCost], in month: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)

        return records
            .filter { record in
                let recordComponents = calendar.dateComponents([.year, .month], from: record.date)
                return recordComponents.year == components.year && recordComponents.month == components.month
            }
            .reduce(0) { $0 + $1.amount }
    }

    func monthlyAssetPurchases(assets: [AssetItem], in month: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)

        return assets
            .filter { asset in
                let assetComponents = calendar.dateComponents([.year, .month], from: asset.purchaseDate)
                return assetComponents.year == components.year && assetComponents.month == components.month
            }
            .reduce(0) { $0 + $1.purchasePrice }
    }
}
