import Foundation
import CoreGraphics

/// 支付宝专用解析器，基于AChai (阿柴记账) 的反向工程算法
/// 参考: `alipayBillsWithSortedLines:leftAlignedTextObservation:searchObject:` 方法
/// 参考: `handleAlipayBill:` 方法
/// 参考: `alipayCellStatus` 方法
final class AlipayTransactionParser {

    // MARK: - 数据结构

    /// 支付宝页面结构状态（AChai的alipayCellStatus）
    enum AlipayCellStatus {
        /// 支出详情页（"支出¥XX.XX"格式）
        case expenseDetail
        /// 收入详情页（"收入¥XX.XX"格式）
        case incomeDetail
        /// 转账详情页
        case transferDetail
        /// 不完整或无法识别的页面
        case incomplete
    }

    /// 空间文本观察结果（与WechatTransactionParser共享结构）
    struct SpatialTextObservation {
        let observation: OCRTextObservation
        let boundingBox: CGRect
        let center: CGPoint
        let id: Int

        private static var nextId = 0

        init(_ observation: OCRTextObservation) {
            self.observation = observation
            self.boundingBox = observation.boundingBox
            self.center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
            self.id = SpatialTextObservation.nextId
            SpatialTextObservation.nextId += 1
        }

        func isLeftAligned(with other: SpatialTextObservation, tolerance: CGFloat = 0.05) -> Bool {
            let verticalOverlap = boundingBox.minY < other.boundingBox.maxY && boundingBox.maxY > other.boundingBox.minY
            let horizontalDiff = abs(boundingBox.minX - other.boundingBox.minX)
            return verticalOverlap && horizontalDiff < tolerance
        }

        func isRightAligned(with other: SpatialTextObservation, tolerance: CGFloat = 0.05) -> Bool {
            let verticalOverlap = boundingBox.minY < other.boundingBox.maxY && boundingBox.maxY > other.boundingBox.minY
            let horizontalDiff = abs(boundingBox.maxX - other.boundingBox.maxX)
            return verticalOverlap && horizontalDiff < tolerance
        }
    }

    /// 结构化单元格（AChai的searchObject.cells）
    struct RecognizedCell {
        let key: String
        let value: String
        let rowIndex: Int
        let columnIndex: Int
        let observation: SpatialTextObservation

        var isAmountKey: Bool { amountKeys.contains(key) }
        var isDateKey: Bool { dateKeys.contains(key) }
        var isMerchantKey: Bool { merchantKeys.contains(key) }
        var isRemarkKey: Bool { remarkKeys.contains(key) }
        var isIncomeAmountKey: Bool { incomeAmountKeys.contains(key) }
    }

    // MARK: - 常量

    /// 支付宝关键词
    private static let alipayKeywords = [
        "支付宝", "支付宝支付", "支付宝转账", "花呗", "余额宝", "Alipay"
    ]

    /// 支付宝支出关键词（AChai的aliAppearWords中的支出相关）
    private static let expenseKeywords = [
        "付款", "支付", "消费", "支出", "扣款", "转出", "还款"
    ]

    /// 支付宝收入关键词（AChai的aliAppearWords中的收入相关）
    private static let incomeKeywords = [
        "收款", "收到", "到账", "转入", "入账", "退款", "退回", "红包", "奖励"
    ]

    /// 支付宝转账关键词
    private static let transferKeywords = [
        "转账", "转给", "收到转账", "转到"
    ]

    /// 支付宝花呗相关关键词
    private static let creditKeywords = [
        "花呗", "花呗还款", "花呗分期", "信用购"
    ]

    /// 支付宝商户标签
    private static let merchantLabels = [
        "收款方", "商户", "商户名称", "店铺", "商家", "对方", "交易对象", "收款方全称"
    ]

    /// 支付宝备注标签
    private static let remarkLabels = [
        "备注", "订单备注", "备注信息", "用途", "附言", "说明"
    ]

    /// 支付宝金额标签
    private static let amountLabels = [
        "实付", "应付", "支付金额", "付款金额", "交易金额", "订单金额", "金额"
    ]

    // MARK: - Cell结构化匹配常量

    private static let amountKeys = [
        "支付金额", "付款金额", "实付", "应付", "交易金额",
        "订单金额", "金额", "总计", "合计", "总额", "已还金额", "退款金额"
    ]

    private static let dateKeys = [
        "交易时间", "支付时间", "付款时间", "下单时间", "时间", "日期", "创建时间"
    ]

    private static let merchantKeys = [
        "收款方", "商户", "商户名称", "店铺", "商家", "对方", "交易对象", "名称", "收款方全称"
    ]

    private static let remarkKeys = [
        "备注", "订单备注", "备注信息", "用途", "附言", "说明"
    ]

    // MARK: - AChai对齐新增常量

    /// 支付宝资金账户关键词
    private static let fundAccountKeywords: [String: String] = [
        "花呗": "花呗",
        "余额宝": "余额宝",
        "余额": "余额",
        "信用卡": "信用卡",
        "借记卡": "借记卡",
        "银行卡": "银行卡"
    ]

    /// 支付宝toBiz/商户全称标签
    private static let toBizLabels = [
        "收款方全称", "商户全称", "对方账户"
    ]

    /// 原价/订单金额标签
    private static let originalMoneyLabels = [
        "原价", "商品金额", "订单金额", "账单金额"
    ]

    /// 优惠金额标签
    private static let discountMoneyLabels = [
        "优惠", "抵扣", "红包", "立减", "减免", "福利"
    ]

    private static let incomeAmountKeys = [
        "收款金额", "收入金额", "到账金额", "转入金额", "退款金额"
    ]

    // MARK: - 日期提取

    /// 支付宝日期格式1: yyyy-MM-dd HH:mm:ss（完整日期时间）
    private static let fullDatePattern = #"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})"#

    /// 支付宝日期格式2: MM-dd HH:mm（短格式，常见于列表页）
    private static let shortDatePattern = #"(\d{1,2})[-/](\d{1,2})\s+(\d{1,2})[：:](\d{2})"#

    /// 支付宝日期格式3: 今天/昨天 HH:mm（相对日期）
    private static let relativeDatePattern = #"(今天|昨天|前天)\s*(\d{1,2})[：:](\d{2})"#

    // MARK: - 金额格式

    /// 严格金额格式（2位小数）
    private static let strictMoneyPattern = #"^[-+−]?\d+\.\d{2}$"#

    /// 通用金额格式
    private static let moneyPattern = #"[-+−]?\d+(\.\d{1,2})?"#

    /// 支付宝特有: "¥XX.XX" 或 "支出¥XX.XX" 格式
    private static let alipayAmountPattern = #"(?:支出|收入|转账)?\s*[¥￥]\s*([0-9]+(?:\.[0-9]{1,2})?)"#

    // MARK: - 公开接口

    /// 解析OCR结果
    static func parse(ocrResult: OCRResult) -> [ParsedTransaction] {
        // 1. 转换OCR观察结果为空间观察结果
        // 如果OCR bbox不可用，回退到“伪布局”，让列结构/右对齐打分依然可用。
        let spatialObservations = buildSpatialObservations(
            from: ocrResult.fullText,
            observations: ocrResult.observations
        )

        // 2. 按Y坐标排序
        let sortedObservations = spatialObservations.sorted { $0.boundingBox.minY < $1.boundingBox.minY }

        // 3. 移除异常值
        let filteredObservations = removeOutliers(from: sortedObservations)

        // 4. 建立行结构
        let lines = groupObservationsIntoLines(filteredObservations)

        // 5. 检测支付宝页面结构状态（alipayCellStatus）
        let cellStatus = detectAlipayCellStatus(from: ocrResult.fullText)

        // 6. 提取日期
        let date = extractDateFromAlipayText(ocrResult.fullText) ?? Date()

        // 7. 提取交易
        let transactions = extractTransactions(from: lines, fullText: ocrResult.fullText, date: date, cellStatus: cellStatus)

        return transactions
    }

    /// 解析纯文本
    static func parse(text: String) -> [ParsedTransaction] {
        let observations = buildPseudoSpatialObservations(from: text)
        let lines = observations.map { [$0] }
        let date = extractDateFromAlipayText(text) ?? Date()
        let cellStatus = detectAlipayCellStatus(from: text)
        let transactions = extractTransactions(from: lines, fullText: text, date: date, cellStatus: cellStatus)
        return transactions
    }

    /// 构建空间观察结果：优先用真实OCR框，框缺失时回退伪布局
    private static func buildSpatialObservations(
        from text: String,
        observations: [OCRTextObservation]
    ) -> [SpatialTextObservation] {
        guard !observations.isEmpty else {
            return buildPseudoSpatialObservations(from: text)
        }

        if hasUsableBoundingBoxes(observations) {
            return observations.map { SpatialTextObservation($0) }
        }

        return buildPseudoSpatialObservations(from: text)
    }

    /// 判断OCR观察结果是否具备可用几何信息
    private static func hasUsableBoundingBoxes(_ observations: [OCRTextObservation]) -> Bool {
        guard observations.count >= 2 else { return false }
        let validBoxes = observations.filter { $0.boundingBox.width > 0.001 && $0.boundingBox.height > 0.001 }
        let minimumRequired = max(2, observations.count / 3)
        return validBoxes.count >= minimumRequired
    }

    /// 在纯文本/无bbox场景构造伪布局，用于后续列结构与对齐打分
    private static func buildPseudoSpatialObservations(from text: String) -> [SpatialTextObservation] {
        let rawLines = text.components(separatedBy: .newlines)
        let maxLineLength = max(1, rawLines.map(\.count).max() ?? 1)
        let lineStep: CGFloat = rawLines.count > 24 ? 0.03 : 0.035
        let lineHeight: CGFloat = 0.024

        return rawLines.enumerated().map { index, line in
            let hasTrailingAmount = line.range(
                of: #"[-+−]?\s*[¥￥]?\s*\d+(?:\.\d{1,2})?\s*$"#,
                options: .regularExpression
            ) != nil
            let normalizedWidth = min(0.9, max(0.15, CGFloat(max(line.count, 1)) / CGFloat(maxLineLength) * 0.85))
            let minX: CGFloat = hasTrailingAmount ? max(0.05, 0.95 - normalizedWidth) : 0.05
            let minY: CGFloat = min(0.95, CGFloat(index) * lineStep)
            let box = CGRect(x: minX, y: minY, width: normalizedWidth, height: lineHeight)
            let obs = OCRTextObservation(text: line, confidence: 0.95, boundingBox: box)
            return SpatialTextObservation(obs)
        }
    }

    // MARK: - alipayCellStatus 检测

    /// 检测支付宝页面结构状态（AChai的alipayCellStatus）
    /// 根据OCR文本判断当前页面是支出详情、收入详情还是转账详情
    static func detectAlipayCellStatus(from text: String) -> AlipayCellStatus {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 检测收入详情页
        let incomePatterns = ["收入¥", "收入￥", "+¥", "+￥", "已收入", "收款金额"]
        for pattern in incomePatterns {
            if normalized.contains(pattern) {
                return .incomeDetail
            }
        }

        // 检测转账详情页
        let transferPatterns = ["转账给", "转账到", "收到转账", "转给", "转账详情"]
        for pattern in transferPatterns {
            if normalized.contains(pattern) {
                return .transferDetail
            }
        }

        // 检测支出详情页
        let expensePatterns = ["支出¥", "支出￥", "-¥", "-￥", "实付金额", "支付成功", "交易成功"]
        for pattern in expensePatterns {
            if normalized.contains(pattern) {
                return .expenseDetail
            }
        }

        // 检查是否包含支付宝关键词（即使没有明确的金额前缀）
        if alipayKeywords.contains(where: { normalized.contains($0) }) {
            // 尝试从文本中推断类型
            if incomeKeywords.contains(where: { normalized.contains($0) }) {
                return .incomeDetail
            }
            if transferKeywords.contains(where: { normalized.contains($0) }) {
                return .transferDetail
            }
            return .expenseDetail
        }

        return .incomplete
    }

    // MARK: - 核心算法

    /// AChai的removeOutliersFromData: Q1/Q3 + 1.5*IQR + 容差
    private static func removeOutliers(
        from observations: [SpatialTextObservation],
        maxDistance: CGFloat = 0.1
    ) -> [SpatialTextObservation] {
        guard observations.count > 3 else { return observations }

        let yValues = observations.map { Double($0.boundingBox.midY) }.sorted()
        let q1 = calculateQuartile(yValues, position: 0.25)
        let q3 = calculateQuartile(yValues, position: 0.75)
        let iqr = q3 - q1

        // 极端情况下退回中位数窗口过滤
        guard iqr > 0 else {
            let median = yValues[yValues.count / 2]
            return observations.filter { abs(Double($0.boundingBox.midY) - median) <= Double(maxDistance) }
        }

        let fencePadding = max(0.015, min(Double(maxDistance), iqr * 0.25))
        let lowerFence = q1 - 1.5 * iqr - fencePadding
        let upperFence = q3 + 1.5 * iqr + fencePadding

        let filtered = observations.filter {
            let y = Double($0.boundingBox.midY)
            return y >= lowerFence && y <= upperFence
        }

        let minimumKeptCount = max(2, observations.count / 3)
        return filtered.count >= minimumKeptCount ? filtered : observations
    }

    /// AChai风格分位数：index=(n-1)*position，整数直接取值，非整数做线性插值
    private static func calculateQuartile(_ sortedValues: [Double], position: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        if sortedValues.count == 1 { return sortedValues[0] }

        let index = Double(sortedValues.count - 1) * position
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        let safeLower = max(0, min(lower, sortedValues.count - 1))
        let safeUpper = max(0, min(upper, sortedValues.count - 1))

        if safeLower == safeUpper {
            return sortedValues[safeLower]
        }

        let fraction = index - Double(safeLower)
        return sortedValues[safeLower] + fraction * (sortedValues[safeUpper] - sortedValues[safeLower])
    }

    /// 将空间观察结果分组为行
    private static func groupObservationsIntoLines(_ observations: [SpatialTextObservation]) -> [[SpatialTextObservation]] {
        guard !observations.isEmpty else { return [] }

        var lines: [[SpatialTextObservation]] = []
        var currentLine: [SpatialTextObservation] = []
        var currentYRange: ClosedRange<CGFloat>?

        for obs in observations {
            let yMid = obs.boundingBox.midY
            let yRange = (yMid - 0.02)...(yMid + 0.02)

            if let currentRange = currentYRange, currentRange.overlaps(yRange) {
                currentLine.append(obs)
                let newMin = min(currentRange.lowerBound, yRange.lowerBound)
                let newMax = max(currentRange.upperBound, yRange.upperBound)
                currentYRange = newMin...newMax
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentLine = [obs]
                currentYRange = yRange
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    /// 构建结构化单元格
    private static func buildStructuredCells(from lines: [[SpatialTextObservation]]) -> [RecognizedCell] {
        var cells: [RecognizedCell] = []
        let allLabels = amountKeys + dateKeys + merchantKeys + remarkKeys + incomeAmountKeys

        for (rowIndex, line) in lines.enumerated() {
            for (colIndex, obs) in line.enumerated() {
                let text = obs.observation.text

                for label in allLabels {
                    if text.contains(label) {
                        if let value = extractValueAfterLabel(text, labels: [label]) {
                            cells.append(RecognizedCell(
                                key: label,
                                value: value,
                                rowIndex: rowIndex,
                                columnIndex: colIndex,
                                observation: obs
                            ))
                        }
                    }
                }
            }
        }

        return cells
    }

    /// 从文本中提取标签后的值
    private static func extractValueAfterLabel(_ text: String, labels: [String]) -> String? {
        for label in labels {
            if let range = text.range(of: label) {
                let afterLabel = text[range.upperBound...]
                let trimmed = afterLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "^[：:]+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    // MARK: - 支付宝日期提取

    /// 从支付宝文本中提取日期（平台特定算法）
    /// 支付宝日期格式与微信不同:
    /// - 列表页: MM-dd HH:mm
    /// - 详情页: yyyy-MM-dd HH:mm:ss
    /// - 相对日期: 今天 HH:mm / 昨天 HH:mm
    static func extractDateFromAlipayText(_ text: String) -> Date? {
        // 尝试完整日期时间格式
        if let date = extractFullDate(text) {
            return date
        }

        // 尝试短日期格式（MM-dd HH:mm）
        if let date = extractShortDate(text) {
            return date
        }

        // 尝试相对日期格式（今天/昨天 HH:mm）
        if let date = extractRelativeDate(text) {
            return date
        }

        return nil
    }

    /// 提取完整日期时间: yyyy-MM-dd HH:mm:ss
    private static func extractFullDate(_ text: String) -> Date? {
        do {
            let regex = try NSRegularExpression(pattern: fullDatePattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges == 7 else {
                return nil
            }

            var components = DateComponents()
            for i in 1..<7 {
                guard let componentRange = Range(match.range(at: i), in: text),
                      let value = Int(text[componentRange]) else { continue }
                switch i {
                case 1: components.year = value
                case 2: components.month = value
                case 3: components.day = value
                case 4: components.hour = value
                case 5: components.minute = value
                case 6: components.second = value
                default: break
                }
            }

            guard let year = components.year, year >= 2000 && year <= 2099,
                  let month = components.month, month >= 1 && month <= 12,
                  let day = components.day, day >= 1 && day <= 31,
                  let hour = components.hour, hour >= 0 && hour <= 23,
                  let minute = components.minute, minute >= 0 && minute <= 59 else {
                return nil
            }

            return Calendar.current.date(from: components)
        } catch {
            return nil
        }
    }

    /// 提取短日期: MM-dd HH:mm（当月日期）
    private static func extractShortDate(_ text: String) -> Date? {
        do {
            let regex = try NSRegularExpression(pattern: shortDatePattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges == 5 else {
                return nil
            }

            guard let monthRange = Range(match.range(at: 1), in: text),
                  let dayRange = Range(match.range(at: 2), in: text),
                  let hourRange = Range(match.range(at: 3), in: text),
                  let minuteRange = Range(match.range(at: 4), in: text),
                  let month = Int(text[monthRange]),
                  let day = Int(text[dayRange]),
                  let hour = Int(text[hourRange]),
                  let minute = Int(text[minuteRange]) else {
                return nil
            }

            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)

            var components = DateComponents()
            components.year = currentYear
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute

            guard let date = calendar.date(from: components) else { return nil }

            // 如果日期在未来，回退到去年
            if date > now, let lastYear = calendar.date(byAdding: .year, value: -1, to: date) {
                return lastYear
            }

            return date
        } catch {
            return nil
        }
    }

    /// 提取相对日期: 今天/昨天 HH:mm
    private static func extractRelativeDate(_ text: String) -> Date? {
        do {
            let regex = try NSRegularExpression(pattern: relativeDatePattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges == 4 else {
                return nil
            }

            guard let dayRange = Range(match.range(at: 1), in: text),
                  let hourRange = Range(match.range(at: 2), in: text),
                  let minuteRange = Range(match.range(at: 3), in: text),
                  let hour = Int(text[hourRange]),
                  let minute = Int(text[minuteRange]) else {
                return nil
            }

            let dayText = String(text[dayRange])
            let calendar = Calendar.current
            let now = Date()

            let baseDate: Date
            switch dayText {
            case "今天":
                baseDate = now
            case "昨天":
                guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
                baseDate = yesterday
            case "前天":
                guard let dayBefore = calendar.date(byAdding: .day, value: -2, to: now) else { return nil }
                baseDate = dayBefore
            default:
                return nil
            }

            var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
            components.hour = hour
            components.minute = minute

            return calendar.date(from: components)
        } catch {
            return nil
        }
    }

    // MARK: - 交易提取

    private static func extractTransactions(
        from lines: [[SpatialTextObservation]],
        fullText: String,
        date: Date?,
        cellStatus: AlipayCellStatus
    ) -> [ParsedTransaction] {
        var transactions: [ParsedTransaction] = []

        // AChai风格: 优先使用结构化单元格匹配
        let cells = buildStructuredCells(from: lines)
        let structuredAmountCellCount = cells.filter { $0.isAmountKey || $0.isIncomeAmountKey }.count
        let hasStructuredContext = cells.contains { $0.isMerchantKey || $0.isDateKey || $0.isRemarkKey }
        let hasSummaryAmountCell = cells.contains { ["合计", "总计", "总额"].contains($0.key) }
        let amountCandidates = findAmountCandidates(in: lines, fullText: fullText, cellStatus: cellStatus)
        let usesSpatialLayout = hasUsableSpatialLayout(lines)

        if let amount = extractAmountFromCells(cells),
           hasStructuredContext || structuredAmountCellCount > 1 || cellStatus != .incomplete {
            var resolvedAmount = amount
            // 详情页中若存在“支出¥xx.xx/收入¥xx.xx”头部金额，优先视为最终结算额
            if let headerSettlementAmount = matchAlipayAmount(fullText),
               cellStatus != .incomplete,
               abs(headerSettlementAmount.value - amount.value) > 0.009 {
                resolvedAmount = headerSettlementAmount
            }
            if resolvedAmount.value <= 0.0001,
               let fallback = extractLastMeaningfulNumber(from: fullText, excludingValue: resolvedAmount.value) {
                resolvedAmount = (value: fallback, sign: resolvedAmount.sign)
            }

            // 避免“仅有合计一行”提前返回，导致多金额明细场景被吞掉
            let shouldUseMultiAmount = hasSummaryAmountCell && amountCandidates.count > 1
            if shouldUseMultiAmount == false {
                var transaction = ParsedTransaction()
                transaction.amount = resolvedAmount.value
                transaction.date = date
                transaction.billSource = .alipay
                transaction.isIncome = resolvedAmount.sign == 1 || cellStatus == .incomeDetail
                transaction.merchantName = extractMerchantFromCells(cells)
                transaction.note = extractNoteFromCells(cells)
                transaction.categoryKey = detectCategory(from: fullText, isIncome: transaction.isIncome)
                // AChai对齐新增字段
                transaction.fundName = extractFundNameFromCells(cells) ?? extractFundName(from: fullText)
                transaction.toBiz = extractToBizFromCells(cells) ?? extractToBiz(from: fullText)
                transaction.status = extractStatus(from: fullText)
                transaction.originalMoney = extractOriginalMoney(from: fullText)
                transaction.discountMoney = extractDiscountMoney(from: fullText)
                transactions.append(transaction)
                return transactions
            }
        }

        // 回退到空间分析方法
        if amountCandidates.isEmpty {
            // 从完整文本中提取金额
            if let amount = extractAmountFromText(fullText) {
                let finalAmount: Double
                if amount.value <= 0.0001,
                   let fallback = extractLastMeaningfulNumber(from: fullText, excludingValue: amount.value) {
                    finalAmount = fallback
                } else {
                    finalAmount = amount.value
                }
                var transaction = ParsedTransaction()
                transaction.amount = finalAmount
                transaction.date = date
                transaction.billSource = .alipay
                transaction.isIncome = amount.sign == 1 || cellStatus == .incomeDetail
                transaction.merchantName = extractMerchantFromText(fullText)
                transaction.note = extractNoteFromText(fullText)
                transaction.categoryKey = detectCategory(from: fullText, isIncome: transaction.isIncome)
                // AChai对齐新增字段
                transaction.fundName = extractFundName(from: fullText)
                transaction.toBiz = extractToBiz(from: fullText)
                transaction.status = extractStatus(from: fullText)
                transaction.originalMoney = extractOriginalMoney(from: fullText)
                transaction.discountMoney = extractDiscountMoney(from: fullText)
                transactions.append(transaction)
            }
            return transactions
        }

        let baselineAlignment = usesSpatialLayout ? 0.45 : 0.15
        let strongestCandidateScore = amountCandidates.map(\.alignmentConfidence).max() ?? 0
        let adaptiveAlignment = max(0.15, strongestCandidateScore - 0.05)
        let minimumAlignment = min(baselineAlignment, adaptiveAlignment)
        for candidate in amountCandidates {
            guard candidate.alignmentConfidence >= minimumAlignment else { continue }

            var transaction = ParsedTransaction()
            var finalAmount = candidate.value
            if finalAmount <= 0.0001 || shouldUseLastNumberFallback(candidate: candidate) {
                if let fallback = extractLastMeaningfulNumber(from: fullText, excludingValue: candidate.value) {
                    finalAmount = fallback
                }
            }
            transaction.amount = finalAmount
            transaction.date = date
            transaction.billSource = .alipay
            transaction.isIncome = candidate.isIncome
            transaction.merchantName = candidate.merchant
            transaction.note = candidate.note
            transaction.categoryKey = detectCategory(from: fullText, isIncome: candidate.isIncome)
            // AChai对齐新增字段
            transaction.fundName = extractFundName(from: fullText)
            transaction.toBiz = candidate.merchant
            transaction.status = extractStatus(from: fullText)
            transaction.originalMoney = extractOriginalMoney(from: fullText)
            transaction.discountMoney = extractDiscountMoney(from: fullText)
            transactions.append(transaction)
        }

        return transactions.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
    }

    // MARK: - 金额提取

    private static func extractAmountFromCells(_ cells: [RecognizedCell]) -> (value: Double, sign: Int)? {
        for cell in cells where cell.isIncomeAmountKey {
            if let amount = extractAmountFromText(cell.value) {
                return (value: amount.value, sign: 1)
            }
        }

        for cell in cells where cell.isAmountKey {
            if let amount = extractAmountFromText(cell.value) {
                return amount
            }
        }

        return nil
    }

    private static func extractAmountFromText(_ text: String) -> (value: Double, sign: Int)? {
        // 尝试支付宝特有格式: 支出¥XX.XX / 收入¥XX.XX
        if let alipayMatch = matchAlipayAmount(text) {
            return alipayMatch
        }

        // 尝试严格金额格式
        if let strictMatch = matchStrictMoney(text) {
            return strictMatch
        }

        // 尝试通用金额格式
        if let genericMatch = matchGenericMoney(text) {
            return genericMatch
        }

        return nil
    }

    /// 匹配支付宝特有格式: 支出¥XX.XX / 收入¥XX.XX
    private static func matchAlipayAmount(_ text: String) -> (value: Double, sign: Int)? {
        do {
            let regex = try NSRegularExpression(pattern: alipayAmountPattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                return nil
            }

            guard let valueRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[valueRange]) else {
                return nil
            }

            let isIncome = text.contains("收入") || text.contains("+")
            return (value: value, sign: isIncome ? 1 : -1)
        } catch {
            return nil
        }
    }

    private static func matchStrictMoney(_ text: String) -> (value: Double, sign: Int)? {
        do {
            let regex = try NSRegularExpression(pattern: strictMoneyPattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                return nil
            }

            guard let matchRange = Range(match.range, in: text) else { return nil }
            let amountStr = String(text[matchRange])

            let cleaned = amountStr.replacingOccurrences(of: "[+−]", with: "-", options: .regularExpression)
            let isNegative = amountStr.hasPrefix("-") || amountStr.hasPrefix("−")
            let absoluteStr = cleaned.replacingOccurrences(of: "-", with: "")

            guard let value = Double(absoluteStr) else { return nil }
            return (value: value, sign: isNegative ? -1 : 1)
        } catch {
            return nil
        }
    }

    private static func matchGenericMoney(_ text: String) -> (value: Double, sign: Int)? {
        do {
            // 先匹配完整的小数金额（避免把整数和小数拆开）
            let combinedPattern = #"([+−-]?\d+)\.(\d{1,2})"#
            let regex = try NSRegularExpression(pattern: combinedPattern)
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let intPartRange = Range(match.range(at: 1), in: text),
                      let decimalPartRange = Range(match.range(at: 2), in: text) else { continue }

                let intPart = String(text[intPartRange])
                let decimalPart = String(text[decimalPartRange])

                if isPartOfDate(text: text, matchRange: fullRange) ||
                    isPartOfTime(text: text, matchRange: fullRange) {
                    continue
                }

                let isNegative = intPart.hasPrefix("-") || intPart.hasPrefix("−")
                let absoluteStr = intPart.replacingOccurrences(of: "[+−-]", with: "", options: .regularExpression)

                if let value = Double(absoluteStr + "." + decimalPart), value >= 0.01 && value <= 1000000 {
                    return (value: value, sign: isNegative ? -1 : 1)
                }
            }

            let genericRegex = try NSRegularExpression(pattern: moneyPattern)
            let genericMatches = genericRegex.matches(in: text, options: [], range: range)
            for match in genericMatches {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let amountStr = String(text[matchRange])
                if amountStr.count > 6 { continue }

                let cleaned = amountStr.replacingOccurrences(of: "[+−]", with: "-", options: .regularExpression)
                let isNegative = amountStr.hasPrefix("-") || amountStr.hasPrefix("−")
                let absoluteStr = cleaned.replacingOccurrences(of: "-", with: "")
                guard let value = Double(absoluteStr) else { continue }

                // 跳过年份类数字（例如 2026）
                if amountStr.count == 4 && (amountStr.hasPrefix("20") || amountStr.hasPrefix("19")) {
                    if matchRange.upperBound < text.endIndex {
                        let nextChar = text[matchRange.upperBound]
                        if "-/.".contains(nextChar) { continue }
                    }
                }

                // 跳过时间片段（如 14:30 中的 14）
                if matchRange.upperBound < text.endIndex && text[matchRange.upperBound] == ":" {
                    continue
                }

                // 跳过日期中的月日
                if let intValue = Int(absoluteStr), intValue >= 1 && intValue <= 31 {
                    let beforeStr = text[..<matchRange.lowerBound]
                    let afterStr = text[matchRange.upperBound...]
                    let hasDateSeparatorBefore = beforeStr.last.map { "-/.".contains($0) } ?? false
                    let hasDateSeparatorAfter = afterStr.first.map { "-/.".contains($0) } ?? false
                    if hasDateSeparatorBefore || hasDateSeparatorAfter { continue }
                }

                if value >= 0.01 && value <= 1000000 {
                    return (value: value, sign: isNegative ? -1 : 1)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// 判断匹配是否是日期的一部分
    private static func isPartOfDate(text: String, matchRange: Range<String.Index>) -> Bool {
        let dateLikePatterns = [
            #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#,
            #"\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}"#
        ]
        return dateLikePatterns.contains { pattern in
            rangeOverlapsPattern(text: text, targetRange: matchRange, pattern: pattern)
        }
    }

    /// 判断匹配是否是时间的一部分
    private static func isPartOfTime(text: String, matchRange: Range<String.Index>) -> Bool {
        return rangeOverlapsPattern(
            text: text,
            targetRange: matchRange,
            pattern: #"\d{1,2}:\d{1,2}(?::\d{1,2})?"#
        )
    }

    /// 判断某段范围是否与指定正则匹配结果重叠
    private static func rangeOverlapsPattern(
        text: String,
        targetRange: Range<String.Index>,
        pattern: String
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let fullRange = NSRange(text.startIndex..., in: text)
        let targetNSRange = NSRange(targetRange, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        return matches.contains { NSIntersectionRange($0.range, targetNSRange).length > 0 }
    }

    private static func shouldUseLastNumberFallback(candidate: AmountCandidate) -> Bool {
        let text = candidate.sourceText
        if text.contains("¥0") || text.contains("￥0") {
            return true
        }
        // OCR 位移时会出现“0.00/00.00”误识别，作为异常金额处理。
        if candidate.value < 0.01 {
            return true
        }
        return false
    }

    /// 对齐微信 parser 的 0 金额兜底逻辑：从文本尾部反向提取最后一个有效金额。
    private static func extractLastMeaningfulNumber(
        from text: String,
        excludingValue: Double = 0
    ) -> Double? {
        let pattern = #"(\d+\.\d{2})|(\d+\.\d{1})|(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let numberStr = String(text[range])

            if numberStr.count == 4 && numberStr.hasPrefix("20") { continue }
            if let value = Int(numberStr), value >= 1 && value <= 31 { continue }
            guard let value = Double(numberStr), value >= 0.01 else { continue }
            if abs(value - excludingValue) < 0.001 { continue }
            if value <= 1_000_000 {
                return value
            }
        }
        return nil
    }

    // MARK: - 金额候选

    private struct AmountCandidate {
        let value: Double
        let sign: Int
        let isIncome: Bool
        let merchant: String?
        let note: String?
        let alignmentConfidence: Double
        let rowIndex: Int
        let sourceText: String
        let rightEdge: CGFloat?
    }

    private static func findAmountCandidates(
        in lines: [[SpatialTextObservation]],
        fullText: String,
        cellStatus: AlipayCellStatus
    ) -> [AmountCandidate] {
        var candidates: [AmountCandidate] = []
        let usesSpatialLayout = hasUsableSpatialLayout(lines)
        let rightAlignmentAnchor = expectedRightAlignmentAnchor(in: lines)

        for (rowIndex, line) in lines.enumerated() {
            for obs in line {
                let text = obs.observation.text

                if let amount = extractAmountFromText(text) {
                    let merchant = findNearbyMerchant(in: lines, rowIndex: rowIndex)
                    let note = findNearbyNote(in: lines, rowIndex: rowIndex)
                    let isIncome = detectIncomeFromContext(text: text, surroundingText: fullText, cellStatus: cellStatus)
                    let alignmentScore = calculateAlignmentScore(
                        rowIndex: rowIndex,
                        lines: lines,
                        currentObs: obs,
                        usesSpatialLayout: usesSpatialLayout,
                        expectedRightEdge: rightAlignmentAnchor
                    )
                    let contextScore = calculateContextScore(
                        text: text,
                        fullText: fullText,
                        rowIndex: rowIndex,
                        cellStatus: cellStatus
                    )
                    let confidence = min(1.0, alignmentScore * 0.65 + contextScore * 0.35)

                    candidates.append(AmountCandidate(
                        value: amount.value,
                        sign: amount.sign,
                        isIncome: isIncome,
                        merchant: merchant,
                        note: note,
                        alignmentConfidence: confidence,
                        rowIndex: rowIndex,
                        sourceText: text,
                        rightEdge: obs.boundingBox.maxX
                    ))
                }
            }
        }

        return removeCandidateOutliers(candidates, usesSpatialLayout: usesSpatialLayout)
    }

    /// 计算金额候选与周围元素的对齐分数
    private static func calculateAlignmentScore(
        rowIndex: Int,
        lines: [[SpatialTextObservation]],
        currentObs: SpatialTextObservation,
        usesSpatialLayout: Bool,
        expectedRightEdge: CGFloat?
    ) -> Double {
        if !usesSpatialLayout {
            return calculateTextRightAlignmentScore(from: currentObs.observation.text)
        }

        guard rowIndex < lines.count else { return 0.35 }
        let currentLine = lines[rowIndex]
        let searchStart = max(0, rowIndex - 3)
        let searchEnd = min(lines.count - 1, rowIndex + 3)

        var alignedLeftCount = 0
        var alignedRightCount = 0
        var totalLeftCount = 0
        var totalRightCount = 0

        for idx in searchStart...searchEnd {
            guard idx != rowIndex else { continue }
            for obs in lines[idx] {
                if obs.isLeftAligned(with: currentObs, tolerance: 0.08) {
                    alignedLeftCount += 1
                }
                totalLeftCount += 1

                if obs.isRightAligned(with: currentObs, tolerance: 0.08) {
                    alignedRightCount += 1
                }
                totalRightCount += 1
            }
        }

        for obs in currentLine where obs.id != currentObs.id {
            if obs.isLeftAligned(with: currentObs, tolerance: 0.08) {
                alignedLeftCount += 1
            }
            totalLeftCount += 1

            if obs.isRightAligned(with: currentObs, tolerance: 0.08) {
                alignedRightCount += 1
            }
            totalRightCount += 1
        }

        let leftScore = totalLeftCount > 0 ? Double(alignedLeftCount) / Double(totalLeftCount) : 0.35
        let rightScore = totalRightCount > 0 ? Double(alignedRightCount) / Double(totalRightCount) : 0.35

        var score = leftScore * 0.2 + rightScore * 0.8
        if let anchor = expectedRightEdge {
            let edgeDistance = abs(currentObs.boundingBox.maxX - anchor)
            let anchorScore = max(0, 1 - Double(edgeDistance / 0.15))
            score = score * 0.6 + anchorScore * 0.4
        }
        return min(1.0, max(0.0, score))
    }

    /// 文本模式下的右对齐评分（无几何信息时使用）
    private static func calculateTextRightAlignmentScore(from text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.1 }

        let hasTrailingAmount = trimmed.range(
            of: #"[-+−]?\s*[¥￥]?\s*\d+(?:\.\d{1,2})?\s*$"#,
            options: .regularExpression
        ) != nil
        let hasCurrency = trimmed.contains("¥") || trimmed.contains("￥")
        let hasAmountLabel = amountLabels.contains { trimmed.contains($0) }
        let hasDateInfo = datePatternMatches(trimmed) || rangeOverlapsPattern(
            text: trimmed,
            targetRange: trimmed.startIndex..<trimmed.endIndex,
            pattern: #"\d{1,2}:\d{1,2}(?::\d{1,2})?"#
        )

        var score = 0.2
        if hasTrailingAmount { score += 0.45 }
        if hasCurrency { score += 0.15 }
        if hasAmountLabel { score += 0.15 }
        if hasDateInfo { score -= 0.45 }
        return min(1.0, max(0.0, score))
    }

    /// 行文语义得分：结算金额加权，汇总/优惠/日期降权
    private static func calculateContextScore(
        text: String,
        fullText: String,
        rowIndex: Int,
        cellStatus: AlipayCellStatus
    ) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.1 }

        let hasSummaryKeyword = ["今日支出", "今日收入", "今日结余", "本月支出", "本月消费", "月统计", "统计支出"].contains {
            trimmed.contains($0)
        }
        let hasDiscountKeyword = discountMoneyLabels.contains { trimmed.contains($0) }
        let hasAmountLabel = amountLabels.contains { trimmed.contains($0) }
        let hasDateKeyword = dateKeys.contains { trimmed.contains($0) } || datePatternMatches(trimmed)
        let hasOrderKeyword = originalMoneyLabels.contains { trimmed.contains($0) }
        let hasSettlementKeyword = ["实付", "应付", "支付金额", "付款金额", "交易金额", "消费金额", "收款金额", "到账金额"].contains {
            trimmed.contains($0)
        }
        let hasCurrency = trimmed.contains("¥") || trimmed.contains("￥")

        var score = 0.3
        if hasSettlementKeyword { score += 0.35 }
        if hasAmountLabel { score += 0.18 }
        if hasCurrency { score += 0.1 }
        if hasOrderKeyword { score += 0.08 }
        if hasSummaryKeyword { score -= 0.28 }
        if hasDiscountKeyword { score -= 0.3 }
        if hasDateKeyword { score -= 0.55 }

        if rowIndex <= 1 && !hasSettlementKeyword && !hasAmountLabel {
            score -= 0.12
        }

        if cellStatus == .incomeDetail {
            if trimmed.contains("收入") || trimmed.contains("收款") || trimmed.contains("到账") {
                score += 0.08
            }
        } else if cellStatus == .expenseDetail {
            if trimmed.contains("支出") || trimmed.contains("付款") || trimmed.contains("支付") {
                score += 0.08
            }
        }

        if (fullText.contains("合计") || fullText.contains("总计")) && (trimmed.contains("合计") || trimmed.contains("总计")) {
            score += 0.08
        }

        return min(1.0, max(0.0, score))
    }

    /// 检测当前行集合是否具备可用几何布局
    private static func hasUsableSpatialLayout(_ lines: [[SpatialTextObservation]]) -> Bool {
        let observations = lines.flatMap { $0 }
        guard observations.count >= 2 else { return false }
        let validBoxes = observations.filter { $0.boundingBox.width > 0.001 && $0.boundingBox.height > 0.001 }
        guard validBoxes.count >= 2 else { return false }
        let uniqueRows = Set(validBoxes.map { Int(($0.boundingBox.midY * 1000).rounded()) })
        return uniqueRows.count >= 2
    }

    /// 估计金额列的右边界，用于右对齐置信增强
    private static func expectedRightAlignmentAnchor(in lines: [[SpatialTextObservation]]) -> CGFloat? {
        var edges: [CGFloat] = []
        for line in lines {
            for obs in line where extractAmountFromText(obs.observation.text) != nil {
                let edge = obs.boundingBox.maxX
                if edge > 0.001 {
                    edges.append(edge)
                }
            }
        }
        guard !edges.isEmpty else { return nil }
        let sorted = edges.sorted()
        return sorted[sorted.count / 2]
    }

    /// 候选异常值剔除：日期噪声 + 右对齐离群
    private static func removeCandidateOutliers(
        _ candidates: [AmountCandidate],
        usesSpatialLayout: Bool
    ) -> [AmountCandidate] {
        guard !candidates.isEmpty else { return [] }

        let nonDateCandidates = candidates.filter { candidate in
            let text = candidate.sourceText
            let hasDateKeyword = dateKeys.contains { text.contains($0) } || datePatternMatches(text)
            let hasSettlementKeyword = amountLabels.contains { text.contains($0) }
            return !(hasDateKeyword && !hasSettlementKeyword)
        }
        var filtered = nonDateCandidates.isEmpty ? candidates : nonDateCandidates

        guard usesSpatialLayout else {
            return filtered.sorted { lhs, rhs in
                if abs(lhs.alignmentConfidence - rhs.alignmentConfidence) < 0.0001 {
                    return lhs.rowIndex < rhs.rowIndex
                }
                return lhs.alignmentConfidence > rhs.alignmentConfidence
            }
        }

        let rightEdges = filtered.compactMap(\.rightEdge)
        guard rightEdges.count >= 3 else {
            return filtered.sorted { lhs, rhs in
                if abs(lhs.alignmentConfidence - rhs.alignmentConfidence) < 0.0001 {
                    return lhs.rowIndex < rhs.rowIndex
                }
                return lhs.alignmentConfidence > rhs.alignmentConfidence
            }
        }

        let sortedEdges = rightEdges.sorted().map(Double.init)
        let q1 = calculateQuartile(sortedEdges, position: 0.25)
        let q3 = calculateQuartile(sortedEdges, position: 0.75)
        let iqr = max(0.001, q3 - q1)
        let lowerFence = q1 - 1.5 * iqr
        let upperFence = q3 + 1.5 * iqr

        let alignmentFiltered = filtered.filter { candidate in
            guard let edge = candidate.rightEdge else { return true }
            let value = Double(edge)
            return value >= lowerFence && value <= upperFence
        }

        if alignmentFiltered.count >= max(1, filtered.count / 2) {
            filtered = alignmentFiltered
        }

        return filtered.sorted { lhs, rhs in
            if abs(lhs.alignmentConfidence - rhs.alignmentConfidence) < 0.0001 {
                return lhs.rowIndex < rhs.rowIndex
            }
            return lhs.alignmentConfidence > rhs.alignmentConfidence
        }
    }

    private static func findNearbyMerchant(
        in lines: [[SpatialTextObservation]],
        rowIndex: Int
    ) -> String? {
        let currentLine = lines[rowIndex]
        for obs in currentLine {
            let text = obs.observation.text
            if merchantLabels.contains(where: { text.contains($0) }) {
                return extractValueAfterLabel(text, labels: merchantLabels)
            }
        }

        // 检查上下行
        for offset in [-1, 1] {
            let idx = rowIndex + offset
            guard idx >= 0 && idx < lines.count else { continue }
            for obs in lines[idx] {
                let text = obs.observation.text
                if merchantLabels.contains(where: { text.contains($0) }) {
                    return extractValueAfterLabel(text, labels: merchantLabels)
                }
            }
        }

        // 支付宝成功页常见布局：金额下方 1~3 行出现商户，期间可能夹杂“获得森林能量”等提示语。
        for offset in [-2, -1, 1, 2, 3] {
            let idx = rowIndex + offset
            guard idx >= 0 && idx < lines.count else { continue }
            for obs in lines[idx] {
                let candidate = normalizedSemanticText(obs.observation.text)
                if isLikelyMerchantFallback(candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func findNearbyNote(
        in lines: [[SpatialTextObservation]],
        rowIndex: Int
    ) -> String? {
        let searchStart = max(0, rowIndex - 2)
        let searchEnd = min(lines.count - 1, rowIndex + 2)

        for idx in searchStart...searchEnd {
            let line = lines[idx]
            for obs in line {
                let text = obs.observation.text
                if remarkLabels.contains(where: { text.contains($0) }) {
                    if let value = extractValueAfterLabel(text, labels: remarkLabels), !value.isEmpty {
                        return value
                    }
                    // 标签在当前 obs，值可能在同行下一个 obs
                    let obsIndex = line.firstIndex(where: { $0.id == obs.id }) ?? -1
                    if obsIndex >= 0 && obsIndex + 1 < line.count {
                        let nextText = line[obsIndex + 1].observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !nextText.isEmpty { return nextText }
                    }
                }
            }
        }

        return nil
    }

    private static func extractMerchantFromCells(_ cells: [RecognizedCell]) -> String? {
        for cell in cells where cell.isMerchantKey {
            let value = normalizedSemanticText(cell.value)
            if isLikelyMerchantFallback(value) {
                return value
            }
        }
        return nil
    }

    private static func extractNoteFromCells(_ cells: [RecognizedCell]) -> String? {
        for cell in cells where cell.isRemarkKey {
            let value = cell.value
            if !value.isEmpty && value.count <= 100 {
                return value
            }
        }
        return nil
    }

    private static func extractMerchantFromText(_ text: String) -> String? {
        for label in merchantLabels {
            if let range = text.range(of: label) {
                let afterLabel = text[range.upperBound...]
                if let nextLineRange = afterLabel.range(of: "\n") {
                    let value = normalizedSemanticText(String(afterLabel[..<nextLineRange.lowerBound]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "^[：:]+", with: "", options: .regularExpression)
                    if isLikelyMerchantFallback(value) { return value }
                } else {
                    let value = normalizedSemanticText(String(afterLabel))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "^[：:]+", with: "", options: .regularExpression)
                    if isLikelyMerchantFallback(value) { return value }
                }
            }
        }

        let textLines = text.components(separatedBy: .newlines)
        for line in textLines {
            let trimmed = normalizedSemanticText(line)
            if isLikelyMerchantFallback(trimmed) {
                return trimmed
            }
        }

        return nil
    }

    private static func extractNoteFromText(_ text: String) -> String? {
        let emptyValues: Set<String> = [
            "无", "-", "—", "/", "暂无备注", "无备注", "none",
            "回首页", "搜索", "完成", "返回", "关闭",
            "获得森林能量", "森林能量", "红包待领取", "待领取", "去领取"
        ]
        for label in remarkLabels {
            if let range = text.range(of: label) {
                let afterLabel = text[range.upperBound...]
                let rawValue: String
                if let nextLineRange = afterLabel.range(of: "\n") {
                    rawValue = String(afterLabel[..<nextLineRange.lowerBound])
                } else {
                    rawValue = String(afterLabel)
                }
                let value = rawValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "^[：:]+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty &&
                    !emptyValues.contains(value) &&
                    value.count <= 60 &&
                    !OCRSemanticFilter.isLikelyNoiseNote(value) {
                    return normalizedSemanticText(value)
                }
            }
        }
        return nil
    }

    private static func normalizedSemanticText(_ text: String) -> String {
        OCRSemanticFilter.normalize(text)
    }

    private static func isLikelyMerchantFallback(_ text: String) -> Bool {
        let cleaned = normalizedSemanticText(text)
        guard !cleaned.isEmpty else { return false }
        guard !cleaned.contains("支付宝") else { return false }
        guard !datePatternMatches(cleaned) else { return false }
        guard !amountLabels.contains(where: { cleaned.contains($0) }) else { return false }
        guard !merchantLabels.contains(where: { cleaned == $0 }) else { return false }
        return OCRSemanticFilter.isLikelyMerchantText(cleaned)
    }

    // MARK: - 收入检测

    private static func detectIncomeFromContext(text: String, surroundingText: String, cellStatus: AlipayCellStatus) -> Bool {
        // alipayCellStatus 优先级最高
        if cellStatus == .incomeDetail {
            return true
        }
        if cellStatus == .transferDetail {
            // 转账可能是收入也可能是支出，看具体关键词
            if surroundingText.contains("收到转账") || surroundingText.contains("转入") {
                return true
            }
            return false
        }

        // 检查文本本身
        if incomeKeywords.contains(where: { text.contains($0) }) {
            return true
        }

        // 检查周围文本
        if incomeKeywords.contains(where: { surroundingText.contains($0) }) {
            if !expenseKeywords.contains(where: { surroundingText.contains($0) }) {
                return true
            }
        }

        return false
    }

    // MARK: - 类别检测

    private static func detectCategory(from text: String, isIncome: Bool) -> String? {
        if isIncome {
            if text.contains("工资") || text.contains("薪资") { return "salary" }
            if text.contains("理财") || text.contains("收益") || text.contains("余额宝") { return "investment" }
            if text.contains("退款") || text.contains("退回") { return "refund" }
            if text.contains("红包") { return "redpacket_income" }
            return "other_income"
        }

        let textLower = text.lowercased()
        if textLower.contains("外卖") || textLower.contains("餐厅") || textLower.contains("美食") { return "dining" }
        if textLower.contains("打车") || textLower.contains("地铁") || textLower.contains("公交") { return "transport" }
        if textLower.contains("淘宝") || textLower.contains("购物") { return "shopping" }
        if textLower.contains("花呗") { return "credit_repayment" }
        if textLower.contains("转账") { return "transfer" }

        return nil
    }

    // MARK: - 辅助

    private static func datePatternMatches(_ text: String) -> Bool {
        let patterns = [
            fullDatePattern,
            shortDatePattern,
            relativeDatePattern,
            #"\d{1,2}:\d{1,2}(?::\d{1,2})?"#
        ]
        let fullRange = NSRange(text.startIndex..., in: text)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: text, options: [], range: fullRange) != nil
        }
    }

    // MARK: - AChai对齐新增字段提取

    /// 从完整文本中提取资金账户名称
    static func extractFundName(from text: String) -> String? {
        // 直接在全文中查找账户类型关键词
        for (keyword, fundName) in fundAccountKeywords {
            if text.contains(keyword) {
                return fundName
            }
        }
        return nil
    }

    /// 从结构化单元格中提取资金账户
    private static func extractFundNameFromCells(_ cells: [RecognizedCell]) -> String? {
        for cell in cells {
            let text = cell.value
            for (keyword, fundName) in fundAccountKeywords {
                if text.contains(keyword) {
                    return fundName
                }
            }
        }
        return nil
    }

    /// 提取交易对方/商户全称
    static func extractToBiz(from text: String) -> String? {
        for label in toBizLabels {
            if let range = text.range(of: label) {
                let afterLabel = text[range.upperBound...]
                let lines = afterLabel.components(separatedBy: .newlines)
                if let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if !firstLine.isEmpty && firstLine.count <= 50 {
                        return firstLine
                    }
                }
            }
        }
        return nil
    }

    /// 提取交易对方从结构化单元格
    private static func extractToBizFromCells(_ cells: [RecognizedCell]) -> String? {
        for cell in cells where cell.isMerchantKey {
            let value = cell.value
            if !value.isEmpty && value.count <= 50 &&
               !datePatternMatches(value) &&
               !value.contains("支付宝") &&
               !value.contains("微信") {
                return value
            }
        }
        return nil
    }

    /// 提取交易状态
    static func extractStatus(from text: String) -> Int? {
        if text.contains("交易成功") || text.contains("支付成功") {
            return 1
        } else if text.contains("交易失败") || text.contains("支付失败") {
            return 2
        }
        return nil
    }

    /// 提取订单原价
    static func extractOriginalMoney(from text: String) -> Double? {
        for label in originalMoneyLabels {
            let escapedLabel = NSRegularExpression.escapedPattern(for: label)
            let pattern = "\(escapedLabel)\\s*[：:]?\\s*([0-9]+(?:\\.[0-9]{1,2})?)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let valueRange = Range(match.range(at: 1), in: text),
               let value = Double(text[valueRange]) {
                return value
            }
        }
        return nil
    }

    /// 提取优惠金额
    static func extractDiscountMoney(from text: String) -> Double? {
        for label in discountMoneyLabels {
            let escapedLabel = NSRegularExpression.escapedPattern(for: label)
            let pattern = "\(escapedLabel)\\s*[：:]?\\s*([0-9]+(?:\\.[0-9]{1,2})?)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let valueRange = Range(match.range(at: 1), in: text),
               let value = Double(text[valueRange]) {
                return value
            }
        }
        return nil
    }
}
