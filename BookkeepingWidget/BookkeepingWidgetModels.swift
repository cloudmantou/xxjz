import Foundation

struct TodaySummary: Codable {
    let totalExpense: Double
    let transactionCount: Int
    let dateString: String
}

struct SharedDefaults {
    static let suiteName = "group.com.assetlife.bookkeeping"
    static let todaySummaryKey = "todaySummary"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func loadTodaySummary() -> TodaySummary? {
        guard let data = defaults?.data(forKey: todaySummaryKey) else { return nil }
        return try? JSONDecoder().decode(TodaySummary.self, from: data)
    }
}
