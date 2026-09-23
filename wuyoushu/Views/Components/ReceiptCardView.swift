import SwiftUI
import CoreData
import AVFoundation

/// 小票卡片组件 — 常驻显示今日所有交易（倒序：最新在上）
/// 增量动画由 transactions.count 变化自动触发（顶部出纸）
struct ReceiptCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let selectedDayTransactions: [BookkeepingTransaction]
    let isTodayContext: Bool
    let forcePrintTriggerID: UUID
    let forcePrintTargetURI: URL?
    var onRowTap: ((BookkeepingTransaction) -> Void)?
    var onDeleteRow: ((BookkeepingTransaction) -> Void)?

    @State private var isIncrementalAnimating = false
    @State private var isPreparingStagedPrint = false
    @State private var knownTransactionIDs: [NSManagedObjectID] = []
    @State private var activePrintRowID: NSManagedObjectID?
    @State private var sheetTranslateY: CGFloat = 0
    @State private var activeAnimationToken = UUID()
    @State private var lastAnimationStartedAt: Date = .distantPast
    @State private var lastPrintedRowID: NSManagedObjectID?
    @StateObject private var soundPlayer = ReceiptPrintSoundPlayer()

    // 印章动画
    @State private var stampScale: CGFloat = 1.0
    @State private var stampOpacity: Double = 1.0
    @State private var hasAnimatedStamp = false

    // 打印摆动
    @State private var printWobbleAngle: Double = 0

    private static let rowHeight: CGFloat = 48
    private static let rowsVerticalInset: CGFloat = 6
    private let startupDuration: TimeInterval = 0.08
    private let printDuration: TimeInterval = 0.68
    private let settleDuration: TimeInterval = 0.14
    private let printStepCount = 14

    private var sortedDayTransactions: [BookkeepingTransaction] {
        selectedDayTransactions.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.objectID.uriRepresentation().absoluteString > rhs.objectID.uriRepresentation().absoluteString
            }
            return lhs.date > rhs.date
        }
    }

    private var dayExpenseTotal: Double {
        sortedDayTransactions
            .filter(\.contributesToExpense)
            .reduce(0) { $0 + $1.normalizedAmount }
    }

    private var dayIncomeTotal: Double {
        sortedDayTransactions
            .filter(\.contributesToIncome)
            .reduce(0) { $0 + $1.normalizedAmount }
    }

    private var dayBalance: Double {
        dayIncomeTotal - dayExpenseTotal
    }

    private var effectivePrintTargetID: NSManagedObjectID? {
        guard isIncrementalAnimating || isPreparingStagedPrint else { return nil }
        return activePrintRowID
    }

    private var displayTransactions: [BookkeepingTransaction] {
        guard let targetID = effectivePrintTargetID else { return sortedDayTransactions }
        return sortedDayTransactions.filter { $0.objectID != targetID }
    }

    private var stagedTransaction: BookkeepingTransaction? {
        guard let targetID = effectivePrintTargetID else { return nil }
        return sortedDayTransactions.first { $0.objectID == targetID }
    }

    private var sheetLayerOffsetY: CGFloat {
        guard (isIncrementalAnimating || isPreparingStagedPrint), stagedTransaction != nil else { return 0 }
        return sheetTranslateY - ReceiptCardView.rowHeight
    }

    private var receiptPaperBrightness: Double {
        colorScheme == .dark ? -0.06 : 0
    }

    private var receiptPaperSaturation: Double {
        colorScheme == .dark ? 0.88 : 1
    }

    private var receiptShadowOpacity: Double {
        colorScheme == .dark ? 0.08 : 0.12
    }

    var body: some View {
        VStack(spacing: 0) {
            // 打印机机身
            PrinterBodyView(isActive: isIncrementalAnimating || isPreparingStagedPrint)
                .padding(.horizontal, 20)

            // 小票纸（从打印机缝隙吐出）
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    movingPaperContent

                    // 出纸口阴影覆盖，营造纸从机器里出来的深度感
                    LinearGradient(
                        colors: [Color.black.opacity(0.22), Color.black.opacity(0.06), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 14)
                    .allowsHitTesting(false)
                }
                .clipped()
            }
            .shadow(
                color: Color.black.opacity(receiptShadowOpacity),
                radius: colorScheme == .dark ? 8 : 12,
                x: 0,
                y: colorScheme == .dark ? 4 : 6
            )
            .padding(.horizontal, 20)
        }
        .rotationEffect(.degrees(printWobbleAngle), anchor: .top)
        .onAppear {
            if knownTransactionIDs.isEmpty {
                knownTransactionIDs = sortedDayTransactions.map(\.objectID)
                // 如果已有账单，初始化印章为可见
                stampScale = 1.0
                stampOpacity = sortedDayTransactions.isEmpty ? 0 : 1.0
                hasAnimatedStamp = !sortedDayTransactions.isEmpty
            }
            sheetTranslateY = 0
        }
        .onChange(of: sortedDayTransactions.map(\.objectID)) { ids in
            handleTransactionIdentityChange(ids)
        }
        .onChange(of: forcePrintTriggerID) { _ in
            handleForcedPrintTrigger()
        }
    }

    // MARK: - Receipt Sections

    /// 热敏小票顶部 — 商户/账本头
    private var emptyTransactionsPlaceholder: some View {
        VStack(spacing: 8) {
            Text("暂无记录")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.receiptText.opacity(0.5))
            Text("选择类目并输入金额开始记账")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.receiptText.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var movingPaperContent: some View {
        VStack(spacing: 0) {
            // 主体票面区域 — 白色底纸
            VStack(spacing: 0) {
                // 新增交易从顶部"打印"出来（先在打印机内拼装完成，再从口中送出）
                if let stagedTransaction {
                    transactionRow(stagedTransaction)
                }

                if displayTransactions.isEmpty {
                    if !isIncrementalAnimating && stagedTransaction == nil {
                        emptyTransactionsPlaceholder
                    }
                } else {
                    transactionRowsSection(displayTransactions)
                }

                receiptDashedLine
                    .padding(.horizontal, 48)

                VStack(spacing: 0) {
                    summarySection

                    receiptDashedLine
                        .padding(.horizontal, 18)

                    ticketFooterSection
                }
            }
            .background(
                ZStack {
                    Color.receiptPaper
                    ReceiptPaperTexture()
                        .opacity(0.28)
                }
            )

            // 撕纸锯齿 — 纸色齿片，齿缝透明露出背景
            ReceiptTornEdgeShape()
                .fill(Color.receiptPaper)
                .frame(height: 12)
        }
        .offset(y: sheetLayerOffsetY)
        .brightness(receiptPaperBrightness)
        .saturation(receiptPaperSaturation)
        .overlay(alignment: .top) {
            // 出纸口深色阴影渐变
            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 8)
            .opacity(isIncrementalAnimating ? 0.9 : 0)
        }
    }

    private func transactionRowsSection(_ transactions: [BookkeepingTransaction]) -> some View {
        VStack(spacing: 0) {
            ForEach(transactions, id: \.objectID) { tx in
                transactionRow(tx)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDeleteRow?(tx)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(.vertical, ReceiptCardView.rowsVerticalInset)
    }

    private func transactionRow(_ tx: BookkeepingTransaction) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(transactionTitle(for: tx))
                .font(.system(size: 14.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.receiptText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("1")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.receiptText.opacity(0.45))
                .frame(width: 20, alignment: .center)

            Text(signedReceiptAmount(tx))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    tx.kind == .income
                        ? Color.profitGreen
                        : (tx.kind == .transfer ? Color.receiptText.opacity(0.6) : Color.receiptText)
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            onRowTap?(tx)
        }
    }

    private var summarySection: some View {
        VStack(spacing: 4) {
            HStack {
                Text(isTodayContext ? "今日支出" : "当日支出")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.receiptText.opacity(0.6))
                Spacer()
                Text("¥ \(String(format: "%.2f", dayExpenseTotal))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.receiptText)
                    .monospacedDigit()
            }
            if dayIncomeTotal > 0 {
                HStack {
                    Text(isTodayContext ? "今日收入" : "当日收入")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.receiptText.opacity(0.6))
                    Spacer()
                    Text("+¥ \(String(format: "%.2f", dayIncomeTotal))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.profitGreen)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var ticketFooterSection: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 6) {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isTodayContext ? "今日结余" : "当日结余")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.receiptText.opacity(0.5))
                        Text(formattedBalance)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(dayBalance >= 0 ? Color.profitGreen : Color.lossRed)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                ReceiptBarcodeDecoration()
                    .frame(height: 26)
                    .padding(.horizontal, 14)

                Text("# 长按可以分享小票喔~ ✨")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.receiptText.opacity(0.4))
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)

            // 印章动画版
            animatedStampSeal
                .padding(.leading, 14)
                .padding(.bottom, 38)
                .scaleEffect(stampScale, anchor: .center)
                .opacity(stampOpacity)
        }
    }

    // MARK: - Dashed Line

    private var receiptDashedLine: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [6, 4]))
            .foregroundColor(Color.receiptText.opacity(0.2))
            .frame(height: 0.8)
    }

    // MARK: - Animation

    private func handleTransactionIdentityChange(_ ids: [NSManagedObjectID]) {
        defer { knownTransactionIDs = ids }

        guard !ids.isEmpty else {
            activePrintRowID = nil
            sheetTranslateY = 0
            isIncrementalAnimating = false
            isPreparingStagedPrint = false
            return
        }

        guard ids.count > knownTransactionIDs.count else { return }

        let knownSet = Set(knownTransactionIDs)
        let addedSet = Set(ids.filter { !knownSet.contains($0) })
        guard !addedSet.isEmpty else { return }
        guard let newestAddedID = ids.first(where: { addedSet.contains($0) }) else { return }

        guard isTodayContext else { return }
        playIncrementalAnimation(for: newestAddedID)
    }

    private func handleForcedPrintTrigger() {
        guard isTodayContext else {
            knownTransactionIDs = sortedDayTransactions.map(\.objectID)
            return
        }
        guard let latestID = sortedDayTransactions.first?.objectID else { return }
        guard let targetURI = forcePrintTargetURI,
              let requestedID = sortedDayTransactions.first(where: { $0.objectID.uriRepresentation() == targetURI })?.objectID,
              requestedID == latestID else {
            knownTransactionIDs = sortedDayTransactions.map(\.objectID)
            return
        }

        playIncrementalAnimation(for: requestedID)
        knownTransactionIDs = sortedDayTransactions.map(\.objectID)
    }

    private func playIncrementalAnimation(for rowID: NSManagedObjectID) {
        let now = Date()
        if (isPreparingStagedPrint || isIncrementalAnimating), activePrintRowID == rowID {
            return
        }
        if lastPrintedRowID == rowID,
           now.timeIntervalSince(lastAnimationStartedAt) < startupDuration + printDuration + settleDuration + 0.12 {
            return
        }

        let animationToken = UUID()
        activeAnimationToken = animationToken
        activePrintRowID = rowID
        sheetTranslateY = 0
        isPreparingStagedPrint = true
        isIncrementalAnimating = false
        lastAnimationStartedAt = now
        lastPrintedRowID = rowID

        // 印章先隐藏（即将打印）
        withAnimation(.easeOut(duration: 0.12)) {
            stampScale = 0.85
            stampOpacity = 0.5
        }

        let stepDuration = printDuration / Double(printStepCount)
        let totalDuration = startupDuration + printDuration + settleDuration

        // 启动阶段：纸张轻微压缩感（模拟进纸齿轮咬住纸）
        withAnimation(.easeIn(duration: startupDuration * 0.8)) {
            printWobbleAngle = 0.12
        }

        DispatchQueue.main.async {
            guard activeAnimationToken == animationToken else { return }
            guard isPreparingStagedPrint else { return }
            isPreparingStagedPrint = false
            isIncrementalAnimating = true
            soundPlayer.playPrintSegment()

            // 主出纸步骤
            for step in 1...printStepCount {
                let delay = startupDuration + stepDuration * Double(step)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard activeAnimationToken == animationToken else { return }
                    guard isIncrementalAnimating else { return }
                    let progress = CGFloat(step) / CGFloat(printStepCount)
                    withAnimation(.timingCurve(0.18, 0.84, 0.24, 1.0, duration: stepDuration * 0.92)) {
                        sheetTranslateY = ReceiptCardView.rowHeight * progress
                    }
                    // 轻微摆动：每4步摆一下
                    if step % 4 == 0 {
                        let wobble = (step % 8 == 0) ? -0.35 : 0.35
                        withAnimation(.easeInOut(duration: stepDuration * 2)) {
                            printWobbleAngle = wobble
                        }
                    }
                }
            }

            // 沉降阶段
            let settleStart = startupDuration + printDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + settleStart) {
                guard activeAnimationToken == animationToken else { return }
                guard isIncrementalAnimating else { return }
                withAnimation(.easeOut(duration: settleDuration)) {
                    sheetTranslateY = ReceiptCardView.rowHeight
                    printWobbleAngle = 0
                }
            }

            // 沉降后微弹（spring settle）
            let springStart = settleStart + settleDuration * 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + springStart) {
                guard activeAnimationToken == animationToken else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                    sheetTranslateY = ReceiptCardView.rowHeight + 2
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + springStart + 0.12) {
                guard activeAnimationToken == animationToken else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    sheetTranslateY = ReceiptCardView.rowHeight
                }
            }

            // 动画完成 → 恢复状态 + 印章入场
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.02) {
                guard activeAnimationToken == animationToken else { return }
                var noAnimation = Transaction()
                noAnimation.animation = nil
                withTransaction(noAnimation) {
                    activePrintRowID = nil
                    isIncrementalAnimating = false
                    isPreparingStagedPrint = false
                    sheetTranslateY = 0
                    printWobbleAngle = 0
                }

                // 印章弹入
                if !hasAnimatedStamp {
                    hasAnimatedStamp = true
                    stampScale = 0.3
                    stampOpacity = 0
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.08)) {
                        stampScale = 1.0
                        stampOpacity = 1.0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                        stampScale = 1.0
                        stampOpacity = 1.0
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var formattedBalance: String {
        let absBalance = abs(dayBalance)
        if dayBalance < 0 {
            return "-¥ \(String(format: "%.2f", absBalance))"
        }
        return "¥ \(String(format: "%.2f", absBalance))"
    }

    private var animatedStampSeal: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "EF6F87").opacity(0.45), style: StrokeStyle(lineWidth: 2.0, dash: [5, 3]))
                .frame(width: 68, height: 68)

            Circle()
                .stroke(Color(hex: "EF6F87").opacity(0.28), lineWidth: 1.0)
                .frame(width: 54, height: 54)

            VStack(spacing: 2) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "EF6F87").opacity(0.58))

                Text("小票留念")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "EF6F87").opacity(0.58))
            }
        }
        .rotationEffect(.degrees(-8))
    }

    private func transactionTitle(for tx: BookkeepingTransaction) -> String {
        if let merchant = tx.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty {
            return merchant
        }
        if let note = tx.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return note
        }
        return tx.categoryName
    }

    private func signedReceiptAmount(_ tx: BookkeepingTransaction) -> String {
        let prefix: String
        switch tx.kind {
        case .income: prefix = "+"
        case .expense: prefix = "-"
        case .transfer: prefix = "↔︎"
        }
        let amount = abs(tx.normalizedAmount)
        return "\(prefix) ¥ \(String(format: "%.2f", amount))"
    }
}

// MARK: - Helper Views

private struct ReceiptPaperTexture: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // 水平扫描线（热敏纸纹理）
                for y in stride(from: 0, through: size.height, by: 2.5) {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(
                        line,
                        with: .color(Color.black.opacity(0.018)),
                        style: StrokeStyle(lineWidth: 0.35, dash: [1.4, 2.2])
                    )
                }

                // 右侧折叠模拟线
                let foldX = size.width - 12
                var foldLine = Path()
                foldLine.move(to: CGPoint(x: foldX, y: 0))
                foldLine.addLine(to: CGPoint(x: foldX, y: size.height))
                context.stroke(
                    foldLine,
                    with: .color(Color.black.opacity(0.03)),
                    style: StrokeStyle(lineWidth: 0.5)
                )

                // 增加立体褶皱阴影
                let foldRect1 = CGRect(x: size.width * 0.25, y: 0, width: 20, height: size.height)
                context.fill(Path(foldRect1), with: .linearGradient(Gradient(colors: [.black.opacity(0.0), .black.opacity(0.015), .black.opacity(0.0)]), startPoint: CGPoint(x: foldRect1.minX, y: 0), endPoint: CGPoint(x: foldRect1.maxX, y: 0)))

                let foldRect2 = CGRect(x: size.width * 0.75, y: 0, width: 30, height: size.height)
                context.fill(Path(foldRect2), with: .linearGradient(Gradient(colors: [.black.opacity(0.0), .black.opacity(0.02), .black.opacity(0.0)]), startPoint: CGPoint(x: foldRect2.minX, y: 0), endPoint: CGPoint(x: foldRect2.maxX, y: 0)))

                // 随机噪点
                let widthSeed = max(1, Int(size.width))
                let heightSeed = max(1, Int(size.height))
                for i in 0..<260 {
                    let x = CGFloat((i * 37) % widthSeed)
                    let y = CGFloat((i * 71) % heightSeed)
                    let dot = CGRect(x: x, y: y, width: 0.9, height: 0.9)
                    context.fill(Path(ellipseIn: dot), with: .color(Color.black.opacity(0.02)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ReceiptBarcodeDecoration: View {
    private let pattern: [CGFloat] = [
        2, 1, 3, 1, 2, 2, 1, 1, 3, 2, 1, 1, 2, 2, 3, 1, 1, 2, 2, 1,
        1, 3, 2, 1, 3, 1, 2, 1, 1, 2, 3, 1, 2, 2
    ]

    var body: some View {
        GeometryReader { proxy in
            let unitCount = max(pattern.reduce(0, +), 1)
            let unitWidth = proxy.size.width / unitCount

            HStack(spacing: 0) {
                ForEach(0..<pattern.count, id: \.self) { i in
                    Rectangle()
                        .fill(i % 2 == 0 ? Color.black.opacity(0.9) : Color.clear)
                        .frame(width: pattern[i] * unitWidth)
                }
            }
        }
    }
}

private struct ReceiptTornEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minToothWidth: CGFloat = 3.5
        let maxToothWidth: CGFloat = 8.0
        let minDepth: CGFloat = rect.height * 0.35
        let maxDepth: CGFloat = rect.height * 0.95

        path.move(to: CGPoint(x: 0, y: 0))

        var currentX: CGFloat = 0.0
        // Use pseudo-random seed to make the torn look consistent and not change every frame
        var seed: UInt32 = 42
        func lcgRandom() -> CGFloat {
            seed = (seed &* 1664525) &+ 1013904223
            let value = CGFloat(seed) / CGFloat(UInt32.max)
            return value
        }

        while currentX < rect.width {
            let tWidth = minToothWidth + (maxToothWidth - minToothWidth) * lcgRandom()
            let nextX = min(currentX + tWidth, rect.width)
            let midX = currentX + (nextX - currentX) * (0.3 + 0.4 * lcgRandom())
            let depth = minDepth + (maxDepth - minDepth) * lcgRandom()

            path.addLine(to: CGPoint(x: midX, y: depth))
            path.addLine(to: CGPoint(x: nextX, y: 0))

            currentX = nextX
        }

        path.addLine(to: CGPoint(x: rect.width, y: 0))

        return path
    }
}

/// 仅顶部圆角的矩形（底部直角）— iOS 15 兼容
private struct TopRoundedRect: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: radius))
        p.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 热敏打印机机身外壳 — 真实立体感
private struct PrinterBodyView: View {
    let isActive: Bool

    @State private var ledPulse: Bool = false
    @State private var indicatorTick: Int = 0
    @State private var indicatorTimer: Timer?

    private let indicatorPalette: [Color] = [
        Color(hex: "7FFFD4"),
        Color(hex: "FFD166"),
        Color(hex: "FF8A65"),
        Color(hex: "7BC8FF"),
        Color(hex: "C6FF8F")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // 机身主体 — 仅顶部圆角，底部直角（出纸口）
            TopRoundedRect(radius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "2E9B8F"), Color(hex: "1E7B71")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    TopRoundedRect(radius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
                .overlay(
                    TopRoundedRect(radius: 16)
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                )
                .frame(height: 54)

            // 机身底部凹槽（出纸区域）
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 18)
                .overlay(
                    // 出纸缝 — 细长深槽
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(height: isActive ? 6 : 4)
                        .padding(.horizontal, 36)
                        .animation(.easeInOut(duration: 0.2), value: isActive)
                        ,alignment: .center
                )
                .overlay(
                    // 出纸时纸张高光
                    LinearGradient(
                        colors: [Color.white.opacity(isActive ? 0.55 : 0), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 3)
                    .padding(.horizontal, 38)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
                    , alignment: .top
                )

            // 装饰元素（左侧 LED + 按钮）
            HStack {
                // LED 指示灯
                Circle()
                    .fill(currentIndicatorColor(offset: 0, inactive: Color(hex: "A5D6CE")))
                    .frame(width: 6, height: 6)
                    .shadow(color: isActive ? currentIndicatorColor(offset: 0, inactive: .clear).opacity(0.85) : .clear, radius: isActive ? 4 : 0)
                    .opacity(ledPulse && isActive ? 0.5 : 1.0)
                    .animation(
                        isActive ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default,
                        value: ledPulse
                    )
                    .animation(.easeInOut(duration: 0.22), value: indicatorTick)
                    .padding(.leading, 14)
                    .padding(.bottom, 22)

                Spacer()

                // 右侧小按钮装饰
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 18, height: 6)
                    .padding(.trailing, 14)
                    .padding(.bottom, 22)
            }

            // 机身侧面进纸齿孔（左右各3个）
            HStack {
                printerSprockets
                Spacer()
                printerSprockets
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .opacity(isActive ? 1.0 : 0.6)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
        .shadow(color: Color(hex: "1BC9B3").opacity(0.15), radius: 12, x: 0, y: -2)
        .onAppear {
            syncIndicatorAnimation(with: isActive)
        }
        .onChange(of: isActive) { active in
            syncIndicatorAnimation(with: active)
        }
        .onDisappear {
            stopIndicatorTimer()
        }
    }

    private var printerSprockets: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 1)
                    .fill(currentIndicatorColor(offset: idx * 2, inactive: Color.black.opacity(0.45)))
                    .frame(width: 4, height: 4)
                    .shadow(color: isActive ? currentIndicatorColor(offset: idx * 2, inactive: .clear).opacity(0.45) : .clear, radius: 1.6)
            }
        }
    }

    private func currentIndicatorColor(offset: Int, inactive: Color) -> Color {
        guard isActive else { return inactive }
        return indicatorPalette[(indicatorTick + offset) % indicatorPalette.count]
    }

    private func startIndicatorTimerIfNeeded() {
        guard indicatorTimer == nil else { return }
        indicatorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            indicatorTick = (indicatorTick + 1) % 10_000
        }
    }

    private func stopIndicatorTimer() {
        indicatorTimer?.invalidate()
        indicatorTimer = nil
    }

    private func syncIndicatorAnimation(with active: Bool) {
        if active {
            ledPulse = true
            startIndicatorTimerIfNeeded()
        } else {
            ledPulse = false
            stopIndicatorTimer()
            indicatorTick = 0
        }
    }
}

/// 打印口指示条 (legacy, kept for reference)
private struct PrinterExitSlot: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.32),
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: isActive ? 8 : 3)

            if isActive {
                HStack {
                    sprocketHoles
                    Spacer()
                    sprocketHoles
                }
            }

            if isActive {
                LinearGradient(
                    colors: [Color.white.opacity(0.0), Color.white.opacity(0.18), Color.white.opacity(0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
                .offset(y: -1)
            }
        }
        .opacity(isActive ? 0.92 : 0.55)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private var sprocketHoles: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 3, height: 3)
            }
        }
        .padding(.horizontal, 4)
    }
}

private final class ReceiptPrintSoundPlayer: ObservableObject {
    private struct SoundProfile {
        let resource: String
        let ext: String
        let startTime: TimeInterval
        let playDuration: TimeInterval
        let fadeInDuration: TimeInterval
        let fadeOutDuration: TimeInterval
        let targetVolume: Float
    }

    // AChai 反编译音源：短打印声（与 0.9s 动画窗口对齐）
    private let preferredProfile = SoundProfile(
        resource: "receipt_more",
        ext: "mp3",
        startTime: 0,
        playDuration: 0.9,
        fadeInDuration: 0.035,
        fadeOutDuration: 0.11,
        targetVolume: 0.82
    )

    // 兜底音源：同样是阿柴包内 receipt.wav，保留切片播放策略
    private let fallbackProfile = SoundProfile(
        resource: "receipt",
        ext: "wav",
        startTime: 0.06,
        playDuration: 0.95,
        fadeInDuration: 0.08,
        fadeOutDuration: 0.12,
        targetVolume: 0.74
    )

    private var player: AVAudioPlayer?
    private var playToken = UUID()
    private var lastPlayAt: Date = .distantPast

    func playPrintSegment() {
        let now = Date()
        guard now.timeIntervalSince(lastPlayAt) > 0.14 else { return }
        lastPlayAt = now

        if play(with: preferredProfile) {
            return
        }
        _ = play(with: fallbackProfile)
    }

    @discardableResult
    private func play(with profile: SoundProfile) -> Bool {
        guard let url = Bundle.main.url(forResource: profile.resource, withExtension: profile.ext) else {
            return false
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = 0
            let clampedStartTime = min(max(0, profile.startTime), max(0, player.duration - 0.02))
            player.currentTime = clampedStartTime
            player.play()
            self.player = player

            let token = UUID()
            playToken = token
            let fadeStepCount = 8

            for step in 1...fadeStepCount {
                let delay = profile.fadeInDuration * Double(step) / Double(fadeStepCount)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    guard self.playToken == token else { return }
                    let progress = Float(step) / Float(fadeStepCount)
                    self.player?.volume = profile.targetVolume * progress
                }
            }

            let fadeOutStart = max(profile.fadeInDuration, profile.playDuration - profile.fadeOutDuration)
            for step in 0...fadeStepCount {
                let delay = fadeOutStart + profile.fadeOutDuration * Double(step) / Double(fadeStepCount)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    guard self.playToken == token else { return }
                    let progress = Float(step) / Float(fadeStepCount)
                    self.player?.volume = profile.targetVolume * max(0, 1 - progress)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + profile.playDuration + 0.03) { [weak self] in
                guard let self else { return }
                guard self.playToken == token else { return }
                self.player?.stop()
            }
            return true
        } catch {
            print("Failed to play receipt print sound: \(error)")
            return false
        }
    }
}
