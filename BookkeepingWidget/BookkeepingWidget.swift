import WidgetKit
import SwiftUI

struct BookkeepingEntry: TimelineEntry {
    let date: Date
    let totalExpense: Double
    let transactionCount: Int
}

struct BookkeepingProvider: TimelineProvider {
    func placeholder(in context: Context) -> BookkeepingEntry {
        BookkeepingEntry(date: Date(), totalExpense: 0, transactionCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (BookkeepingEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookkeepingEntry>) -> Void) {
        let entry = loadEntry()
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(endOfDay))
        completion(timeline)
    }

    private func loadEntry() -> BookkeepingEntry {
        let summary = SharedDefaults.loadTodaySummary()
        return BookkeepingEntry(
            date: Date(),
            totalExpense: summary?.totalExpense ?? 0,
            transactionCount: summary?.transactionCount ?? 0
        )
    }
}

struct BookkeepingWidgetEntryView: View {
    let entry: BookkeepingEntry

    var body: some View {
        VStack(spacing: 8) {
            Text("今日支出")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(format: "¥%.2f", entry.totalExpense))
                .font(.title)
                .fontWeight(.bold)

            Text("\(entry.transactionCount) 笔记录")
                .font(.caption2)
                .foregroundColor(.secondary)

            Link(destination: URL(string: "assetlife://record")!) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text("记一笔")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct BookkeepingWidget: Widget {
    let kind: String = "BookkeepingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookkeepingProvider()) { entry in
            BookkeepingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("记账概览")
        .description("查看今日支出并快速记账")
        .supportedFamilies([.systemSmall])
    }
}
