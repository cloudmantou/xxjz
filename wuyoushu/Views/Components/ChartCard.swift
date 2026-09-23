import SwiftUI
import UIKit

struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let backgroundColor: Color
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        backgroundColor: Color = .appCardMutedBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backgroundColor = backgroundColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { // Reduced spacing
            VStack(alignment: .leading, spacing: 2) { // Reduced spacing
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded)) // Reduced font size

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(Constants.UI.cardPadding - 4) // Reduced padding
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius, style: .continuous)
                .stroke(Color.borderSoft, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: Constants.UI.cornerRadius))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 6)
    }
}

// MARK: - Pie Chart Card（保留给旧代码引用，内部已升级到 DonutChartView）

struct PieChartCard: View {
    let title: String
    let data: [(name: String, value: Double, color: Color)]

    var body: some View {
        ChartCard(title: title) {
            if data.isEmpty {
                emptyState
            } else {
                pieChartContent
            }
        }
    }

    private var totalValue: Double {
        data.reduce(0) { $0 + max($1.value, 0) }
    }

    private var pieChartContent: some View {
        VStack(spacing: 16) {
            AnimatedDonutChart(data: data, total: totalValue)
                .frame(width: 150, height: 150)

            legendView
        }
    }

    private var emptyState: some View {
        Text("暂无数据")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var legendView: some View {
        let total = max(totalValue, 1)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(data.prefix(5), id: \.name) { item in
                let percentage = max(item.value / total, 0) * 100
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 10, height: 10)

                    Text(item.name)
                        .font(.system(size: 14, design: .rounded))
                        .lineLimit(1)

                    Spacer()

                    Text(String(format: "%.0f%%", percentage))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(item.value.abbreviated)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - AnimatedDonutChart（入场动画 donut）

struct AnimatedDonutChart: View {
    let data: [(name: String, value: Double, color: Color)]
    let total: Double

    @State private var animationProgress: CGFloat = 0

    private var segmentData: [(startAngle: CGFloat, endAngle: CGFloat, color: Color)] {
        let t = max(total, 1)
        var result: [(startAngle: CGFloat, endAngle: CGFloat, color: Color)] = []
        var currentAngle: CGFloat = 0
        for item in data {
            let proportion = CGFloat(item.value / t)
            let angle = proportion * 360
            result.append((currentAngle, currentAngle + angle, item.color))
            currentAngle += angle
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = size * 0.22

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.08), lineWidth: lineWidth)

                ForEach(Array(segmentData.enumerated()), id: \.offset) { _, segment in
                    let clampedEnd = segment.startAngle + (segment.endAngle - segment.startAngle) * animationProgress
                    Circle()
                        .trim(
                            from: segment.startAngle / 360,
                            to: max(segment.startAngle / 360, clampedEnd / 360)
                        )
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 1) {
                    Text(total.abbreviated)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                    Text("合计")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) {
                animationProgress = 1.0
            }
        }
        .onChange(of: total) { _ in
            animationProgress = 0
            withAnimation(.easeOut(duration: 0.6)) {
                animationProgress = 1.0
            }
        }
    }
}

// MARK: - Bar Chart Card

struct BarChartCard: View {
    let title: String
    let data: [(name: String, value: Double)]

    var body: some View {
        ChartCard(title: title) {
            if data.isEmpty {
                emptyState
            } else {
                barChartContent
            }
        }
    }

    private var emptyState: some View {
        Text("暂无数据")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var barChartContent: some View {
        let maxValue = max(data.map(\.value).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(data.enumerated()), id: \.element.name) { index, item in
                AnimatedBarRow(
                    name: item.name,
                    value: item.value,
                    maxValue: maxValue,
                    delay: Double(index) * 0.06
                )
            }
        }
    }
}

private struct AnimatedBarRow: View {
    let name: String
    let value: Double
    let maxValue: Double
    let delay: Double

    @State private var animatedRatio: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 12, design: .rounded))
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.warmTeal, Color.warmTeal.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * animatedRatio)
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(value.abbreviated)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
        .onAppear {
            let ratio = maxValue > 0 ? CGFloat(value / maxValue) : 0
            withAnimation(.easeOut(duration: 0.55).delay(delay)) {
                animatedRatio = ratio
            }
        }
    }
}

// MARK: - Line Chart Card

struct LineChartCard: View {
    let title: String
    let data: [(date: Date, value: Double)]
    var budgetLine: Double? = nil
    var cardBackgroundColor: Color = .appCardMutedBackground

    @State private var pathProgress: CGFloat = 0
    @State private var pointsAppeared: Bool = false
    @State private var selectedIndex: Int? = nil

    var body: some View {
        ChartCard(title: title, backgroundColor: cardBackgroundColor) {
            if data.isEmpty {
                emptyState
            } else {
                lineChartContent
            }
        }
    }

    private var peakDay: (date: Date, value: Double)? {
        data.max { $0.value < $1.value }
    }

    private var emptyState: some View {
        Text("暂无数据")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var lineChartContent: some View {
        let sorted = data.sorted { $0.date < $1.date }
        let maxValue = max(sorted.map(\.value).max() ?? 1, 1)
        let hasBudget = budgetLine != nil && budgetLine! > 0
        let effectiveMax = hasBudget ? max(maxValue, budgetLine!) : maxValue

        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height - 30
                let pointCount = CGFloat(sorted.count)
                let stepX = pointCount > 1 ? width / (pointCount - 1) : width

                ZStack(alignment: .bottom) {
                    // 网格线
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in
                            if i > 0 { Divider() }
                            Spacer()
                        }
                    }
                    .frame(height: height)

                    // 预算参考线
                    if hasBudget, let budget = budgetLine {
                        let budgetY = height * (1 - CGFloat(budget / effectiveMax))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: budgetY))
                            path.addLine(to: CGPoint(x: width, y: budgetY))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundColor(Color.lossRed.opacity(0.6))

                        Text("预算¥\(Int(budget))/天")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Color.lossRed)
                            .position(x: width - 40, y: budgetY - 10)
                    }

                    // 面积填充
                    if sorted.count > 1 {
                        Path { path in
                            let firstPoint = CGPoint(
                                x: 0,
                                y: height * (1 - CGFloat(sorted[0].value / effectiveMax))
                            )
                            path.move(to: CGPoint(x: 0, y: height))
                            path.addLine(to: firstPoint)

                            for (index, item) in sorted.enumerated() {
                                let x = stepX * CGFloat(index)
                                let y = height * (1 - CGFloat(item.value / effectiveMax))
                                path.addLine(to: CGPoint(x: x, y: y))
                            }

                            path.addLine(to: CGPoint(x: width, y: height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.warmTeal.opacity(0.28), Color.warmTeal.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(pathProgress)
                    }

                    // 折线（带 trim 动画）
                    if sorted.count > 1 {
                        AnimatedLinePath(
                            sorted: sorted,
                            effectiveMax: effectiveMax,
                            stepX: stepX,
                            height: height,
                            progress: pathProgress
                        )
                        .stroke(Color.warmTeal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    // 选中点的垂直指示线
                    if let si = selectedIndex, si < sorted.count {
                        let selX = stepX * CGFloat(si)
                        Path { path in
                            path.move(to: CGPoint(x: selX, y: 0))
                            path.addLine(to: CGPoint(x: selX, y: height))
                        }
                        .stroke(Color.warmTeal.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    // 数据点
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, item in
                        let x = stepX * CGFloat(index)
                        let y = height * (1 - CGFloat(item.value / effectiveMax))
                        let isPeak = item.value == peakDay?.value
                        let isSelected = selectedIndex == index

                        // 选中时的外圈光晕
                        if isSelected {
                            Circle()
                                .fill(Color.warmTeal.opacity(0.15))
                                .frame(width: 20, height: 20)
                                .position(x: x, y: y)
                        }

                        Circle()
                            .fill(isSelected ? Color.blue : (isPeak ? Color.lossRed : Color.warmTeal)) // Updated selected color
                            .frame(width: isSelected ? 10 : 6, height: isSelected ? 10 : 6)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                            )
                            .position(x: x, y: y)
                            .scaleEffect(pointsAppeared ? 1.0 : 0.0)
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.6)
                                    .delay(0.5 + Double(index) * 0.03),
                                value: pointsAppeared
                            )

                        // 选中点上方金额气泡
                        if isSelected {
                            chartTooltip(value: item.value)
                                .position(x: tooltipX(x: x, width: width), y: max(y - 24, 10))
                        }
                    }

                    // 底部日期标签
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, item in
                        let x = stepX * CGFloat(index)
                        let isSelected = selectedIndex == index

                        if isSelected {
                            Text(item.date.formatted(as: "M/dd"))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.warmTeal)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.warmTeal.opacity(0.1))
                                )
                                .position(x: x, y: height + 14)
                        } else if selectedIndex == nil && (index == 0 || index == sorted.count - 1 || item.value == peakDay?.value) {
                            Text(item.date.formatted(as: "dd"))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary)
                                .position(x: x, y: height + 12)
                        }
                    }
                }
                .frame(height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let touchX = drag.location.x
                            let nearestIndex = max(0, min(sorted.count - 1, Int(round(touchX / stepX))))
                            if selectedIndex != nearestIndex {
                                selectedIndex = nearestIndex
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedIndex = nil
                                }
                            }
                        }
                )
            }
            .frame(height: 180)

            HStack {
                if let peak = peakDay {
                    Label("峰值 \(peak.date.formatted(as: "MM/dd")) ¥\(Int(peak.value))", systemImage: "arrow.up")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.lossRed)
                }

                Spacer()

                if hasBudget, let budget = budgetLine {
                    Label("预算 ¥\(Int(budget))/天", systemImage: "line.horizontal")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.lossRed.opacity(0.7))
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                pathProgress = 1.0
            }
            pointsAppeared = true
        }
        .onChange(of: data.count) { _ in
            pathProgress = 0
            pointsAppeared = false
            selectedIndex = nil
            withAnimation(.easeInOut(duration: 0.7)) {
                pathProgress = 1.0
            }
            pointsAppeared = true
        }
    }

    /// 金额气泡
    private func chartTooltip(value: Double) -> some View {
        Text("¥\(String(format: "%.2f", value))")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.warmTeal)
                    .shadow(color: Color.warmTeal.opacity(0.18), radius: 10, y: 4)
            )
    }

    /// 计算 tooltip X 坐标，防止溢出边缘
    private func tooltipX(x: CGFloat, width: CGFloat) -> CGFloat {
        let tooltipHalfWidth: CGFloat = 36
        if x < tooltipHalfWidth { return tooltipHalfWidth }
        if x > width - tooltipHalfWidth { return width - tooltipHalfWidth }
        return x
    }
}

/// 用 trim 实现折线绘制动画
private struct AnimatedLinePath: Shape {
    let sorted: [(date: Date, value: Double)]
    let effectiveMax: Double
    let stepX: CGFloat
    let height: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, item) in sorted.enumerated() {
            let x = stepX * CGFloat(index)
            let y = height * (1 - CGFloat(item.value / effectiveMax))
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path.trimmedPath(from: 0, to: progress)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            PieChartCard(
                title: "状态分布",
                data: [
                    ("使用中", 5, Color.profitGreen),
                    ("已卖出", 3, Color.warmTeal),
                    ("已报废", 1, Color.gray)
                ]
            )

            BarChartCard(
                title: "日均成本Top5",
                data: [
                    ("iPhone", 28.5),
                    ("MacBook", 15.2),
                    ("iPad", 8.3)
                ]
            )

            LineChartCard(
                title: "月度花费趋势",
                data: [
                    (Date(), 5000),
                    (Date().addingTimeInterval(-86400 * 30), 4500),
                    (Date().addingTimeInterval(-86400 * 60), 6000)
                ]
            )
        }
        .padding()
    }
}