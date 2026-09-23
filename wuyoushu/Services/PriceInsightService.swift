import Foundation

struct PlatformQuote {
    let platform: String
    let price: Double
    let recordedAt: Date
}

struct HistoricalPricePoint {
    let date: Date
    let price: Double
    let platform: String?
}

protocol PriceInsightServiceProtocol: AnyObject {
    func fetchPlatformQuotes(for item: WishlistItem) async throws -> [PlatformQuote]
    func fetchHistoricalPrices(for item: WishlistItem) async throws -> [HistoricalPricePoint]
}

final class MockPriceInsightService: PriceInsightServiceProtocol {
    static let shared = MockPriceInsightService()
    private init() {}

    func fetchPlatformQuotes(for item: WishlistItem) async throws -> [PlatformQuote] {
        try await Task.sleep(nanoseconds: 600_000_000)

        let basePrice = max(item.targetPrice, 100)
        return [
            PlatformQuote(platform: "京东", price: basePrice * 1.05, recordedAt: Date()),
            PlatformQuote(platform: "天猫", price: basePrice * 1.02, recordedAt: Date()),
            PlatformQuote(platform: "拼多多", price: basePrice * 0.96, recordedAt: Date())
        ]
    }

    func fetchHistoricalPrices(for item: WishlistItem) async throws -> [HistoricalPricePoint] {
        try await Task.sleep(nanoseconds: 600_000_000)

        let basePrice = max(item.targetPrice, 100)
        let now = Date()
        let calendar = Calendar.current

        return [
            HistoricalPricePoint(date: now, price: basePrice * 1.00, platform: "京东"),
            HistoricalPricePoint(date: calendar.date(byAdding: .day, value: -7, to: now) ?? now, price: basePrice * 1.08, platform: "天猫"),
            HistoricalPricePoint(date: calendar.date(byAdding: .day, value: -14, to: now) ?? now, price: basePrice * 1.12, platform: "京东"),
            HistoricalPricePoint(date: calendar.date(byAdding: .day, value: -30, to: now) ?? now, price: basePrice * 1.18, platform: "拼多多")
        ]
    }
}
