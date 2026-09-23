import Foundation

extension Double {
    // MARK: - Currency Formatting

    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: NSNumber(value: self)) ?? "¥\(self)"
    }

    var compactCurrencyString: String {
        if self >= 10_000 {
            return String(format: "¥%.1f万", self / 10_000)
        } else if self >= 1_000 {
            return String(format: "¥%.1f千", self / 1_000)
        } else {
            return currencyString
        }
    }

    // MARK: - Percentage Formatting

    var percentString: String {
        String(format: "%.1f%%", self)
    }

    var signedPercentString: String {
        if self > 0 {
            return "+\(percentString)"
        } else {
            return percentString
        }
    }

    // MARK: - Daily Cost Formatting

    var dailyCostString: String {
        String(format: "¥%.2f/天", self)
    }

    // MARK: - Price Change Formatting

    func priceChangeString(previous: Double) -> String {
        let change = self - previous
        if change >= 0 {
            return "+\(change.currencyString)"
        } else {
            return change.currencyString
        }
    }

    // MARK: - Rounding

    func rounded(to places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }

    // MARK: - Abbreviated

    var abbreviated: String {
        if self >= 1_000_000_000 {
            return String(format: "%.1fB", self / 1_000_000_000)
        } else if self >= 1_000_000 {
            return String(format: "%.1fM", self / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", self / 1_000)
        } else {
            return String(format: "%.0f", self)
        }
    }
}
