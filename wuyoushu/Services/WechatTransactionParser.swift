import Foundation
import CoreGraphics

/// 微信支付专用解析器，基于AChai (阿柴记账) 的反向工程算法
/// 参考: `wechatBillsWithSortedLines:leftAlignedTextObservation:searchObject:` 方法
final class WechatTransactionParser {

    // MARK: - 数据结构

    /// 空间文本观察结果，增强版OCRTextObservation，添加空间导航能力
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

        /// 判断是否与另一个观察结果左对齐（在垂直重叠范围内）
        func isLeftAligned(with other: SpatialTextObservation, tolerance: CGFloat = 0.05) -> Bool {
            let verticalOverlap = boundingBox.minY < other.boundingBox.maxY && boundingBox.maxY > other.boundingBox.minY
            let horizontalDiff = abs(boundingBox.minX - other.boundingBox.minX)
            return verticalOverlap && horizontalDiff < tolerance
        }

        /// 判断是否与另一个观察结果右对齐
        func isRightAligned(with other: SpatialTextObservation, tolerance: CGFloat = 0.05) -> Bool {
            let verticalOverlap = boundingBox.minY < other.boundingBox.maxY && boundingBox.maxY > other.boundingBox.minY
            let horizontalDiff = abs(boundingBox.maxX - other.boundingBox.maxX)
            return verticalOverlap && horizontalDiff < tolerance
        }

        /// 判断是否在另一个观察结果上方（垂直方向）
        func isAbove(_ other: SpatialTextObservation, tolerance: CGFloat = 0.1) -> Bool {
            return boundingBox.maxY < other.boundingBox.minY &&
                   abs(boundingBox.midX - other.boundingBox.midX) < tolerance
        }

        /// 判断是否在另一个观察结果下方
        func isBelow(_ other: SpatialTextObservation, tolerance: CGFloat = 0.1) -> Bool {
            return boundingBox.minY > other.boundingBox.maxY &&
                   abs(boundingBox.midX - other.boundingBox.midX) < tolerance
        }
    }

    /// 解析后的文本行，包含行列索引
    struct RecognizedTextLine {
        let key: String?
        let value: String?
        let rowIndex: Int
        let columnIndex: Int
        let observation: SpatialTextObservation

        init(observation: SpatialTextObservation, rowIndex: Int, columnIndex: Int = 0) {
            self.observation = observation
            self.rowIndex = rowIndex
            self.columnIndex = columnIndex
            self.key = nil
            self.value = observation.observation.text
        }
    }

    /// AChai的AutoBillRecognizedTextLine: 结构化的键值单元格
    /// 对应AChai的searchObject.cells，用于结构化键值匹配
    struct RecognizedCell {
        let key: String       // 标签名（如"收款方"、"金额"）
        let value: String      // 标签对应的值
        let rowIndex: Int     // 行索引
        let columnIndex: Int  // 列索引
        let observation: SpatialTextObservation

        /// 判断是否是金额类型的key
        var isAmountKey: Bool {
            amountKeys.contains(key)
        }

        /// 判断是否是日期类型的key
        var isDateKey: Bool {
            dateKeys.contains(key)
        }

        /// 判断是否是商户类型的key
        var isMerchantKey: Bool {
            merchantKeys.contains(key)
        }

        /// 判断是否是备注类型的key
        var isRemarkKey: Bool {
            remarkKeys.contains(key)
        }

        /// 判断是否是收入金额key
        var isIncomeAmountKey: Bool {
            incomeAmountKeys.contains(key)
        }
    }

    // MARK: - 常量

    /// 微信支付关键词（用于检测）
    private static let wechatKeywords = [
        "微信支付", "微信转账", "微信付款", "微信", "WeChat"
    ]

    /// 收入关键词（微信支付中表示收入）
    private static let incomeKeywords = [
        "收款", "收到", "到账", "转入", "入账"
    ]

    /// 支出关键词（微信支付中表示支出）
    private static let expenseKeywords = [
        "付款", "支付", "消费", "支出", "扣款", "转出"
    ]

    /// 商户标签关键词
    private static let merchantLabels = [
        "收款方", "商户", "商户名称", "店铺", "商家", "付款方", "对方", "交易对象"
    ]

    /// 备注标签关键词
    private static let remarkLabels = [
        "备注", "订单备注", "备注信息", "用途", "附言"
    ]

    /// 金额标签关键词（优先级排序）
    private static let amountLabels = [
        "实付", "应付", "支付金额", "付款金额", "交易金额", "订单金额", "消费金额", "金额"
    ]

    /// 7组日期正则表达式（基于AChai反向工程）
    /// 格式: yyyy-MM-dd HH:mm:ss 或 yyyy/MM/dd HH:mm:ss 或 yyyy.MM.dd HH:mm:ss
    private static let datePattern = #"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})"#

    /// 严格金额格式（2位小数，可选正负号）- AChai风格
    private static let strictMoneyPattern = #"^[-+−]?\d+\.\d{2}$"#

    /// 通用金额格式（1-2位小数）
    private static let moneyPattern = #"[-+−]?\d+(\.\d{1,2})?"#

    // MARK: - Cell结构化匹配常量（AChai风格）

    /// 金额类key（AChai的searchObject.cells键类型）
    private static let amountKeys = [
        "支付金额", "付款金额", "实付", "应付", "交易金额",
        "订单金额", "消费金额", "金额", "总计", "合计", "总额"
    ]

    /// 日期类key
    private static let dateKeys = [
        "交易时间", "支付时间", "付款时间", "下单时间", "时间", "日期"
    ]

    /// 商户类key
    private static let merchantKeys = [
        "收款方", "商户", "商户名称", "店铺", "商家", "付款方", "对方", "交易对象", "名称"
    ]

    /// 备注类key
    private static let remarkKeys = [
        "备注", "订单备注", "备注信息", "用途", "附言", "说明"
    ]

    /// 收入金额类key（正向金额）
    private static let incomeAmountKeys = [
        "收款金额", "收入金额", "到账金额", "转入金额", "入账金额"
    ]

    // MARK: - AChai对齐新增常量

    /// 微信资金账户关键词
    private static let wechatFundAccountKeywords: [String: String] = [
        "零钱": "零钱",
        "零钱通": "零钱通",
        "银行": "银行卡",
        "信用卡": "信用卡"
    ]

    /// 微信toBiz/商户全称标签
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

    // MARK: - 公开接口

    /// 解析OCR结果，返回多个交易（微信支付可能包含多个子交易）
    static func parse(ocrResult: OCRResult) -> [ParsedTransaction] {
        // 1. 转换OCR观察结果为空间观察结果
        // 如果OCR bbox不可用，回退到“伪布局”，让列结构/右对齐打分依然可用。
        let spatialObservations = buildSpatialObservations(
            from: ocrResult.fullText,
            observations: ocrResult.observations
        )

        // 2. 按Y坐标排序（从上到下）
        let sortedObservations = spatialObservations.sorted { $0.boundingBox.minY < $1.boundingBox.minY }

        // 3. AChai的removeOutliersFromData: 移除Y坐标距离过大的异常值
        let filteredObservations = removeOutliers(from: sortedObservations)

        // 4. 建立行结构
        let lines = groupObservationsIntoLines(filteredObservations)

        // 4. 检测是否为微信支付（如果未检测到微信关键词，仍尝试解析）
 let _ = detectWechatSource(from: ocrResult.fullText)

        // 5. 提取日期（使用AChai的7组日期正则表达式）
        let fullTextDate = extractDateFromWechatText(ocrResult.fullText)

        // 6. 提取金额和商户信息
        let transactions = extractTransactions(from: lines, fullText: ocrResult.fullText, fullTextDate: fullTextDate)

        return transactions
    }

    /// 解析纯文本（兼容现有接口）
    static func parse(text: String) -> [ParsedTransaction] {
        let observations = buildPseudoSpatialObservations(from: text)
        let lines = observations.map { [$0] }

        let fullTextDate = extractDateFromWechatText(text)
        let transactions = extractTransactions(from: lines, fullText: text, fullTextDate: fullTextDate)
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

        // AChai里还会额外扩一个固定容差，归一化坐标系下用小常量替代
        let fencePadding = max(0.015, min(Double(maxDistance), iqr * 0.25))
        let lowerFence = q1 - 1.5 * iqr - fencePadding
        let upperFence = q3 + 1.5 * iqr + fencePadding

        let filtered = observations.filter {
            let y = Double($0.boundingBox.midY)
            return y >= lowerFence && y <= upperFence
        }

        // 防止过度剔除导致关键行丢失
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

    /// 将空间观察结果分组为行（基于Y坐标重叠）
    private static func groupObservationsIntoLines(_ observations: [SpatialTextObservation]) -> [[SpatialTextObservation]] {
        guard !observations.isEmpty else { return [] }

        var lines: [[SpatialTextObservation]] = []
        var currentLine: [SpatialTextObservation] = []
        var currentYRange: ClosedRange<CGFloat>?

        for obs in observations {
            let yMid = obs.boundingBox.midY
            let yRange = (yMid - 0.02)...(yMid + 0.02) // 2%的垂直容差

            if let currentRange = currentYRange, currentRange.overlaps(yRange) {
                // 属于当前行
                currentLine.append(obs)
                // 扩展Y范围
                let newMin = min(currentRange.lowerBound, yRange.lowerBound)
                let newMax = max(currentRange.upperBound, yRange.upperBound)
                currentYRange = newMin...newMax
            } else {
                // 新行
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

        // 每行内按X坐标排序（从左到右）
        return lines.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    /// AChai的searchObject.cells: 从行结构构建结构化单元格
    /// 识别键值对（key: value），用于精确的字段提取
    private static func buildStructuredCells(from lines: [[SpatialTextObservation]]) -> [RecognizedCell] {
        var cells: [RecognizedCell] = []
        let allLabels = amountKeys + dateKeys + merchantKeys + remarkKeys + incomeAmountKeys

        for (rowIndex, line) in lines.enumerated() {
            for (colIndex, obs) in line.enumerated() {
                let text = obs.observation.text

                // 检查当前文本是否包含标签
                for label in allLabels {
                    if text.contains(label) {
                        // 找到了key，提取value
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

    /// 从结构化单元格中提取金额
    private static func extractAmountFromCells(_ cells: [RecognizedCell]) -> (value: Double, sign: Int)? {
        // 优先查找收入金额
        for cell in cells where cell.isIncomeAmountKey {
            if let amount = extractAmountFromText(cell.value) {
                return (value: amount.value, sign: 1) // 收入为正
            }
        }

        // 查找普通金额
        for cell in cells where cell.isAmountKey {
            if let amount = extractAmountFromText(cell.value) {
                return amount
            }
        }

        return nil
    }

    /// 从结构化单元格中提取商户
    private static func extractMerchantFromCells(_ cells: [RecognizedCell]) -> String? {
        for cell in cells where cell.isMerchantKey {
            let value = cell.value
            // 过滤掉常见的非商户内容
            if !value.isEmpty && value.count <= 50 &&
               !datePatternMatches(value) &&
               !value.contains("微信") &&
               !value.contains("支付") {
                return value
            }
        }
        return nil
    }

    /// 从结构化单元格中提取备注
    private static func extractNoteFromCells(_ cells: [RecognizedCell]) -> String? {
        for cell in cells where cell.isRemarkKey {
            let value = cell.value
            if !value.isEmpty && value.count <= 100 {
                return value
            }
        }
        return nil
    }

    /// 检测是否为微信支付来源
    private static func detectWechatSource(from text: String) -> Bool {
        let normalized = text.lowercased()
        return wechatKeywords.contains { normalized.contains($0.lowercased()) }
    }

    /// 从微信支付文本中提取日期（AChai算法）
    private static func extractDateFromWechatText(_ text: String) -> Date? {
        do {
            let regex = try NSRegularExpression(pattern: datePattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                return nil
            }

            // 验证组数
            guard match.numberOfRanges == 7 else { return nil }

            // 提取组件
            var components = DateComponents()

            for i in 1..<7 {
                guard let componentRange = Range(match.range(at: i), in: text) else { continue }
                let substring = String(text[componentRange])
                guard let value = Int(substring) else { continue }

                switch i {
                case 1: components.year = value  // 年
                case 2: components.month = value // 月
                case 3: components.day = value   // 日
                case 4: components.hour = value  // 时
                case 5: components.minute = value // 分
                case 6: components.second = value // 秒
                default: break
                }
            }

            // 验证日期范围（基于AChai逻辑）
            guard let year = components.year, year >= 2000 && year <= 2099 else { return nil }
            guard let month = components.month, month >= 1 && month <= 12 else { return nil }

            // AChai-style: validate day against actual days in this month (not hardcoded 1-31)
            let calendar = Calendar.current
            var dayComponents = DateComponents()
            dayComponents.year = year
            dayComponents.month = month
            dayComponents.day = 1
            guard let firstOfMonth = calendar.date(from: dayComponents),
                  let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
                return nil
            }
            guard let day = components.day, day >= dayRange.lowerBound && day <= dayRange.upperBound else { return nil }

            guard let hour = components.hour, hour >= 0 && hour <= 23 else { return nil }
            guard let minute = components.minute, minute >= 0 && minute <= 59 else { return nil }
            guard let second = components.second, second >= 0 && second <= 59 else { return nil }

            // 创建日期
            return calendar.date(from: components)

        } catch {
            return nil
        }
    }

    /// AChai的30秒日期容差: 比较两个日期是否在30秒内相同
    /// 用于当从多个来源提取日期时验证它们是否指向同一时间
    private static func datesMatchWithTolerance(_ date1: Date?, _ date2: Date?, tolerance: TimeInterval = 30) -> Bool {
        guard let d1 = date1, let d2 = date2 else { return false }
        return abs(d1.timeIntervalSince(d2)) <= tolerance
    }

    /// 从结构化cells提取日期
    private static func extractDateFromCells(_ cells: [RecognizedCell]) -> Date? {
        for cell in cells where cell.isDateKey {
            if let parsed = parseFlexibleDateValue(cell.value) {
                return parsed
            }
        }
        return nil
    }

    /// 全文日期 + cells日期 双源校验；30秒内视为同一时间，否则按cells优先回退
    private static func resolveDate(fullTextDate: Date?, cellDate: Date?) -> Date? {
        if datesMatchWithTolerance(fullTextDate, cellDate) {
            return cellDate ?? fullTextDate
        }
        if let cellDate {
            return cellDate
        }
        return fullTextDate
    }

    private static func parseFlexibleDateValue(_ raw: String) -> Date? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        if let exact = extractDateFromWechatText(normalized) {
            return exact
        }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        let formatters = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM-dd HH:mm",
            "MM-dd"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .current
            formatter.dateFormat = format
            guard let date = formatter.date(from: normalized) else { continue }

            if format == "MM-dd HH:mm" || format == "MM-dd" {
                var comps = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
                comps.year = currentYear
                return calendar.date(from: comps)
            }
            return date
        }

        return nil
    }

    /// 从行中提取交易信息
    private static func extractTransactions(
        from lines: [[SpatialTextObservation]],
        fullText: String,
        fullTextDate: Date?
    ) -> [ParsedTransaction] {
        var transactions: [ParsedTransaction] = []

        // AChai风格: 优先使用结构化单元格匹配（searchObject.cells）
        let cells = buildStructuredCells(from: lines)
        let cellDate = extractDateFromCells(cells)
        let resolvedDate = resolveDate(fullTextDate: fullTextDate, cellDate: cellDate) ?? Date()
        let structuredAmountCellCount = cells.filter { $0.isAmountKey || $0.isIncomeAmountKey }.count
        let hasStructuredContext = cells.contains { $0.isMerchantKey || $0.isDateKey || $0.isRemarkKey }
        let hasSummaryAmountCell = cells.contains { ["合计", "总计", "总额"].contains($0.key) }
        let amountCandidates = findAmountCandidates(in: lines, fullText: fullText)
        let usesSpatialLayout = hasUsableSpatialLayout(lines)

        // 避免“仅有合计一行”时提前返回单笔，导致多金额场景被吞掉
        if let amount = extractAmountFromCells(cells),
           hasStructuredContext || structuredAmountCellCount > 1 {
            let shouldUseMultiAmount = hasSummaryAmountCell && amountCandidates.count > 1
            if shouldUseMultiAmount == false {
                // 结构化匹配成功
                var transaction = ParsedTransaction()
                transaction.amount = amount.value
                transaction.date = resolvedDate
                transaction.billSource = .wechatPay
                transaction.isIncome = amount.sign == 1
                transaction.merchantName = extractMerchantFromCells(cells)
                transaction.note = extractNoteFromCells(cells)
                transaction.categoryKey = detectCategory(from: fullText, isIncome: amount.sign == 1)
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
        // 如果没有找到金额，尝试从完整文本中提取
        if amountCandidates.isEmpty {
            if let amount = extractAmountFromText(fullText) {
                var transaction = ParsedTransaction()
                transaction.amount = amount.value
                transaction.date = resolvedDate
                transaction.billSource = .wechatPay
                transaction.isIncome = amount.sign == 1
                transaction.merchantName = extractMerchantFromText(fullText)
                transaction.note = extractNoteFromText(fullText)
                transaction.categoryKey = detectCategory(from: fullText, isIncome: amount.sign == 1)
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

        // 为每个金额候选创建交易（multi-bill支持）
        let baselineAlignment = usesSpatialLayout ? 0.45 : 0.15
        let strongestCandidateScore = amountCandidates.map(\.alignmentConfidence).max() ?? 0
        let adaptiveAlignment = max(0.15, strongestCandidateScore - 0.05)
        let minimumAlignment = min(baselineAlignment, adaptiveAlignment)
        for candidate in amountCandidates {
            // 过滤低置信度候选（AChai风格）
            guard candidate.alignmentConfidence >= minimumAlignment else { continue }

            var transaction = ParsedTransaction()
            var finalAmount = candidate.value

            // AChai的extractLastNumberFromString fallback: 当金额为0时尝试提取最后一个有效数字
            if finalAmount == 0 {
                if let fallback = extractLastMeaningfulNumber(from: fullText, excludingValue: candidate.value) {
                    finalAmount = fallback
                }
            }

            transaction.amount = finalAmount
            transaction.date = resolvedDate
            transaction.billSource = .wechatPay
            transaction.isIncome = candidate.isIncome
            transaction.merchantName = candidate.merchant
            transaction.note = candidate.note
            transaction.categoryKey = detectCategory(from: fullText, isIncome: candidate.isIncome)
            // AChai对齐新增字段
            transaction.fundName = extractFundName(from: fullText)
            transaction.toBiz = candidate.toBiz ?? candidate.merchant
            transaction.status = extractStatus(from: fullText)
            transaction.originalMoney = extractOriginalMoney(from: fullText)
            transaction.discountMoney = extractDiscountMoney(from: fullText)
            transactions.append(transaction)
        }

        // AChai风格: 按金额大小排序（降序）
        let sorted = transactions.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        return sorted
    }

    /// 在行中查找金额候选
    private static func findAmountCandidates(
        in lines: [[SpatialTextObservation]],
        fullText: String
    ) -> [AmountCandidate] {
        var candidates: [AmountCandidate] = []
        let usesSpatialLayout = hasUsableSpatialLayout(lines)
        let rightAlignmentAnchor = expectedRightAlignmentAnchor(in: lines)

        for (rowIndex, line) in lines.enumerated() {
            for (colIndex, obs) in line.enumerated() {
                let text = obs.observation.text

                // 检查是否为金额
                if let amount = extractAmountFromText(text) {
                    // 查找相邻的商户信息
                    let merchant = findNearbyMerchant(in: lines, rowIndex: rowIndex, colIndex: colIndex)
                    // 查找备注
                    let note = findNearbyNote(in: lines, rowIndex: rowIndex, colIndex: colIndex)
                    // 判断是否为收入
                    let isIncome = detectIncomeFromContext(text: text, surroundingText: fullText)
                    // AChai风格: 计算与周围元素的空间对齐置信度
                    let alignmentScore = calculateAlignmentScore(
                        rowIndex: rowIndex,
                        colIndex: colIndex,
                        lines: lines,
                        currentObs: obs,
                        usesSpatialLayout: usesSpatialLayout,
                        expectedRightEdge: rightAlignmentAnchor
                    )
                    // AChai风格: 文本上下文打分，补齐 cells/candidates 链路
                    let contextScore = calculateContextScore(
                        text: text,
                        fullText: fullText,
                        rowIndex: rowIndex
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
                        rightEdge: obs.boundingBox.maxX,
                        toBiz: merchant // 使用merchant作为toBiz
                    ))
                }
            }
        }

        return removeCandidateOutliers(candidates, usesSpatialLayout: usesSpatialLayout)
    }

    /// 从文本中提取金额
    private static func extractAmountFromText(_ text: String) -> (value: Double, sign: Int)? {
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

    /// 匹配严格金额格式（AChai风格）
    private static func matchStrictMoney(_ text: String) -> (value: Double, sign: Int)? {
        do {
            let regex = try NSRegularExpression(pattern: strictMoneyPattern)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                return nil
            }

            guard let matchRange = Range(match.range, in: text) else { return nil }
            let amountStr = String(text[matchRange])

            // 解析金额和符号
            let cleaned = amountStr.replacingOccurrences(of: "[+−]", with: "-", options: .regularExpression)
            let isNegative = amountStr.hasPrefix("-") || amountStr.hasPrefix("−")
            let absoluteStr = cleaned.replacingOccurrences(of: "-", with: "")

            guard let value = Double(absoluteStr) else { return nil }
            return (value: value, sign: isNegative ? -1 : 1)
        } catch {
            return nil
        }
    }

    /// 匹配通用金额格式
    /// 正确处理如"-15.80"这样的金额（整数和小数点分离的情况）
    private static func matchGenericMoney(_ text: String) -> (value: Double, sign: Int)? {
        do {
            let regex = try NSRegularExpression(pattern: moneyPattern)
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            // 策略：先查找完整的"整数.小数"模式，再处理单个金额
            // 步骤1: 查找"数字后面跟随.数字"的完整模式
            let combinedPattern = #"([+−-]?\d+)\.(\d{1,2})"#
            let combinedRegex = try NSRegularExpression(pattern: combinedPattern)
            let combinedMatches = combinedRegex.matches(in: text, options: [], range: range)

            for match in combinedMatches {
                guard let fullRange = Range(match.range, in: text),
                      let intPartRange = Range(match.range(at: 1), in: text),
                      let decimalPartRange = Range(match.range(at: 2), in: text) else { continue }

                let intPart = String(text[intPartRange])
                let decimalPart = String(text[decimalPartRange])

                // 验证这不是日期的一部分
                if !isPartOfDate(text: text, matchRange: fullRange) &&
                   !isPartOfTime(text: text, matchRange: fullRange) {
                    let isNegative = intPart.hasPrefix("-") || intPart.hasPrefix("−")
                    let absoluteStr = intPart.replacingOccurrences(of: "[+−-]", with: "", options: .regularExpression)
                    if let value = Double(absoluteStr + "." + decimalPart), value >= 0.01 && value <= 1000000 {
                        return (value: value, sign: isNegative ? -1 : 1)
                    }
                }
            }

            // 步骤2: 处理独立的金额（没有小数点或单独的整数）
            for match in matches {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let amountStr = String(text[matchRange])

                // 跳过明显不是金额的情况
                if amountStr.count > 6 { continue }

                // 解析金额和符号
                let cleaned = amountStr.replacingOccurrences(of: "[+−]", with: "-", options: .regularExpression)
                let isNegative = amountStr.hasPrefix("-") || amountStr.hasPrefix("−")
                let absoluteStr = cleaned.replacingOccurrences(of: "-", with: "")

                guard let value = Double(absoluteStr) else { continue }

                // 跳过年份-like数字
                if amountStr.count == 4 && (amountStr.hasPrefix("20") || amountStr.hasPrefix("19")) {
                    if matchRange.upperBound < text.endIndex {
                        let nextChar = text[matchRange.upperBound]
                        if "-/.".contains(nextChar) { continue }
                    }
                }

                // 跳过时间组件（数字后面跟随冒号）
                if matchRange.upperBound < text.endIndex && text[matchRange.upperBound] == ":" {
                    continue
                }

                // 跳过日期中的月日（1-31范围内的单独数字，且前后有日期分隔符）
                if let intValue = Int(absoluteStr), intValue >= 1 && intValue <= 31 {
                    let beforeStr = text[..<matchRange.lowerBound]
                    let afterStr = text[matchRange.upperBound...]
                    let hasDateSeparatorBefore = beforeStr.last.map { "-/.".contains($0) } ?? false
                    let hasDateSeparatorAfter = afterStr.first.map { "-/.".contains($0) } ?? false
                    if hasDateSeparatorBefore || hasDateSeparatorAfter { continue }
                }

                // 验证金额合理性
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

    /// AChai的extractLastNumberFromString fallback:
    /// 当主要金额识别为0时，从文本中反向查找最后一个有意义的数字
    private static func extractLastMeaningfulNumber(
        from text: String,
        excludingValue: Double = 0
    ) -> Double? {
        // 匹配金额模式: 2位小数或整数
        let pattern = #"(\d+\.\d{2})|(\d+\.\d{1})|(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        // 反向遍历匹配结果
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let numberStr = String(text[range])

            // 跳过年份-like数字 (4位数字，以20开头)
            if numberStr.count == 4 && numberStr.hasPrefix("20") { continue }

            // 跳过日期中的月日 (1-31范围内的单独数字)
            if let value = Int(numberStr), value >= 1 && value <= 31 { continue }

            // 跳过非常小的值
            guard let value = Double(numberStr), value >= 0.01 else { continue }

            // 跳过排除的值
            if abs(value - excludingValue) < 0.001 { continue }

            // 验证金额合理范围
            if value >= 0.01 && value <= 1000000 {
                return value
            }
        }

        return nil
    }

    /// 查找附近的商户信息
    private static func findNearbyMerchant(
        in lines: [[SpatialTextObservation]],
        rowIndex: Int,
        colIndex: Int
    ) -> String? {
        // 检查当前行是否有商户标签
        let currentLine = lines[rowIndex]
        for obs in currentLine {
            let text = obs.observation.text
            if merchantLabels.contains(where: { text.contains($0) }) {
                // 返回标签后的文本
                return extractValueAfterLabel(text, labels: merchantLabels)
            }
        }

        // 检查上一行
        if rowIndex > 0 {
            let prevLine = lines[rowIndex - 1]
            for obs in prevLine {
                let text = obs.observation.text
                if !amountLabels.contains(where: { text.contains($0) }) &&
                   !datePatternMatches(text) &&
                   text.count > 1 && text.count < 50 {
                    return text
                }
            }
        }

        return nil
    }

    /// 查找附近的备注信息（扫描当前行及上下2行）
    private static func findNearbyNote(
        in lines: [[SpatialTextObservation]],
        rowIndex: Int,
        colIndex: Int
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
                    if idx < lines.count {
                        let obsIndex = line.firstIndex(where: { $0.id == obs.id }) ?? -1
                        if obsIndex >= 0 && obsIndex + 1 < line.count {
                            let nextText = line[obsIndex + 1].observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !nextText.isEmpty { return nextText }
                        }
                    }
                }
            }
        }

        return nil
    }

    /// AChai风格: 计算当前观察结果与周围元素的空间对齐分数
    /// 检查上下3行内是否有与当前金额同对齐的元素（用于验证金额-商户关系）
    private static func calculateAlignmentScore(
        rowIndex: Int,
        colIndex: Int,
        lines: [[SpatialTextObservation]],
        currentObs: SpatialTextObservation,
        usesSpatialLayout: Bool,
        expectedRightEdge: CGFloat?
    ) -> Double {
        if !usesSpatialLayout {
            return calculateTextRightAlignmentScore(from: currentObs.observation.text)
        }

        // 查找当前行的所有观察结果
        guard rowIndex < lines.count else { return 0.35 }
        let currentLine = lines[rowIndex]

        // 在当前行和上下3行内检查对齐
        let searchStart = max(0, rowIndex - 3)
        let searchEnd = min(lines.count - 1, rowIndex + 3)

        var alignedLeftCount = 0
        var alignedRightCount = 0
        var totalLeftCount = 0
        var totalRightCount = 0

        for idx in searchStart...searchEnd {
            guard idx != rowIndex else { continue }
            for obs in lines[idx] {
                // 左对齐检查
                if obs.isLeftAligned(with: currentObs, tolerance: 0.08) {
                    alignedLeftCount += 1
                }
                totalLeftCount += 1

                // 右对齐检查
                if obs.isRightAligned(with: currentObs, tolerance: 0.08) {
                    alignedRightCount += 1
                }
                totalRightCount += 1
            }
        }

        // 当前行内检查
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

        // 金额通常更依赖右对齐
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

    /// 结合行文语义的候选分数（AChai candidatesWithLines 的上下文思路）
    private static func calculateContextScore(
        text: String,
        fullText: String,
        rowIndex: Int
    ) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.1 }

        let lower = trimmed.lowercased()
        let hasSummaryKeyword = ["今日支出", "今日收入", "今日结余", "本月支出", "本月消费", "月统计"].contains { trimmed.contains($0) }
        let hasDiscountKeyword = discountMoneyLabels.contains { trimmed.contains($0) }
        let hasAmountLabel = amountLabels.contains { trimmed.contains($0) }
        let hasDateKeyword = dateKeys.contains { trimmed.contains($0) } || datePatternMatches(trimmed)
        let hasOrderKeyword = originalMoneyLabels.contains { trimmed.contains($0) }
        let hasSettlementKeyword = ["实付", "应付", "支付金额", "付款金额", "交易金额", "消费金额", "收款金额"].contains { trimmed.contains($0) }
        let hasCurrency = trimmed.contains("¥") || trimmed.contains("￥")

        var score = 0.3
        if hasSettlementKeyword { score += 0.35 }
        if hasAmountLabel { score += 0.18 }
        if hasCurrency { score += 0.1 }
        if hasOrderKeyword { score += 0.08 }
        if hasSummaryKeyword { score -= 0.28 }
        if hasDiscountKeyword { score -= 0.3 }
        if hasDateKeyword { score -= 0.55 }

        // 首屏偏上、关键词弱时通常是头部噪声，略降权
        if rowIndex <= 1 && !hasSettlementKeyword && !hasAmountLabel {
            score -= 0.12
        }

        // 当全文包含“合计/总计”且当前行为其一时，适度保留（用于多金额票据）
        if (fullText.contains("合计") || fullText.contains("总计")) && (trimmed.contains("合计") || trimmed.contains("总计")) {
            score += 0.08
        }

        // 使用lower避免未使用警告并预留英文关键字扩展位
        if lower.contains("total") {
            score += 0.02
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

    /// 从完整文本中提取商户信息
    private static func extractMerchantFromText(_ text: String) -> String? {
        // 查找商户标签
        for label in merchantLabels {
            if let range = text.range(of: label) {
                let afterLabel = text[range.upperBound...]
                if let nextLineRange = afterLabel.range(of: "\n") {
                    let value = String(afterLabel[..<nextLineRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "^[：:]+", with: "", options: .regularExpression)
                    if !value.isEmpty {
                        return value
                    }
                } else {
                    let value = String(afterLabel)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "^[：:]+", with: "", options: .regularExpression)
                    if !value.isEmpty {
                        return value
                    }
                }
            }
        }

        // 查找常见的商户名称模式
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 跳过包含金额、日期、标签的行
            if !trimmed.isEmpty &&
               !datePatternMatches(trimmed) &&
               !amountLabels.contains(where: { trimmed.contains($0) }) &&
               !merchantLabels.contains(where: { trimmed.contains($0) }) &&
               !remarkLabels.contains(where: { trimmed.contains($0) }) &&
               trimmed.count > 1 && trimmed.count < 50 {
                return trimmed
            }
        }

        return nil
    }

    /// 从完整文本中提取备注
    private static func extractNoteFromText(_ text: String) -> String? {
        let emptyValues: Set<String> = ["无", "-", "—", "/", "暂无备注", "无备注", "none", "回首页"]
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
                if !value.isEmpty && !emptyValues.contains(value) && value.count <= 60 {
                    return value
                }
            }
        }
        return nil
    }

    /// 检测是否为收入
    private static func detectIncomeFromContext(text: String, surroundingText: String) -> Bool {
        // 检查文本本身是否包含收入关键词
        if incomeKeywords.contains(where: { text.contains($0) }) {
            return true
        }

        // 检查周围文本
        if incomeKeywords.contains(where: { surroundingText.contains($0) }) {
            // 确保没有支出关键词
            if !expenseKeywords.contains(where: { surroundingText.contains($0) }) {
                return true
            }
        }

        return false
    }

    /// 检测类别
    private static func detectCategory(from text: String, isIncome: Bool) -> String? {
        // 如果是收入，使用收入类别映射
        if isIncome {
            // 简单映射
            if text.contains("工资") || text.contains("薪资") {
                return "salary"
            } else if text.contains("理财") || text.contains("收益") {
                return "investment"
            } else if text.contains("退款") || text.contains("退回") {
                return "refund"
            } else if text.contains("红包") {
                return "redpacket_income"
            }
            return "other_income"
        }

        // 支出类别检测（简化版，实际应使用更复杂的逻辑）
        let textLower = text.lowercased()

        if textLower.contains("早餐") || textLower.contains("午餐") || textLower.contains("晚餐") ||
           textLower.contains("外卖") || textLower.contains("奶茶") || textLower.contains("咖啡") {
            return "dining"
        } else if textLower.contains("打车") || textLower.contains("地铁") || textLower.contains("公交") ||
                  textLower.contains("滴滴") || textLower.contains("加油") {
            return "transport"
        } else if textLower.contains("购物") || textLower.contains("衣服") || textLower.contains("淘宝") ||
                  textLower.contains("京东") || textLower.contains("拼多多") {
            return "shopping"
        } else if textLower.contains("电影") || textLower.contains("游戏") || textLower.contains("ktv") {
            return "entertainment"
        } else if textLower.contains("房租") || textLower.contains("水电") || textLower.contains("物业") {
            return "housing"
        } else if textLower.contains("看病") || textLower.contains("药") || textLower.contains("医院") {
            return "medical"
        } else if textLower.contains("书") || textLower.contains("课") || textLower.contains("学费") {
            return "education"
        }

        return nil
    }

    /// 检查文本是否匹配日期模式
    private static func datePatternMatches(_ text: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: datePattern)
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    // MARK: - AChai对齐新增字段提取

    /// 从完整文本中提取微信资金账户名称
    static func extractFundName(from text: String) -> String? {
        for (keyword, fundName) in wechatFundAccountKeywords {
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
            for (keyword, fundName) in wechatFundAccountKeywords {
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
               !value.contains("微信") &&
               !value.contains("支付宝") {
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

    // MARK: - 辅助结构

    /// 金额候选
    private struct AmountCandidate {
        let value: Double
        let sign: Int // -1: 支出, 1: 收入
        let isIncome: Bool
        let merchant: String?
        let note: String?
        let alignmentConfidence: Double // 0.0-1.0, 基于与周围元素的对齐程度
        let rowIndex: Int
        let sourceText: String
        let rightEdge: CGFloat?
        var toBiz: String? // 交易对方
    }
}
