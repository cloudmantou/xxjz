import Foundation

extension Date {
    // MARK: - Formatting

    func formatted(as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }

    var shortDateString: String {
        formatted(as: "yyyy-MM-dd")
    }

    var mediumDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var longDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var monthYearString: String {
        formatted(as: "yyyy年MM月")
    }

    // MARK: - Components

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? self
    }

    var endOfMonth: Date {
        var components = DateComponents()
        components.month = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfMonth) ?? self
    }

    // MARK: - Calculations

    func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: self, to: date).day ?? 0
    }

    func monthsUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.month], from: self, to: date).month ?? 0
    }

    func yearsUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.year], from: self, to: date).year ?? 0
    }

    // MARK: - Relative Time

    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    // MARK: - Convenience

    static func from(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isThisMonth: Bool {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        let nowComponents = Calendar.current.dateComponents([.year, .month], from: Date())
        return components.year == nowComponents.year && components.month == nowComponents.month
    }
}
