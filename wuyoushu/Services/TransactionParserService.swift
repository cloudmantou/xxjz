import Foundation
import CoreGraphics

/// Shared semantic filter for OCR lines used by shortcut prefill and parser fallback.
enum OCRSemanticFilter {

    static let navigationNoiseKeywords: Set<String> = [
        "回首页", "搜索", "完成", "返回", "关闭", "取消", "更多", "详情", "账单详情"
    ]

    static let statusBarNoiseKeywords: Set<String> = [
        "4g", "5g", "lte", "wifi", "wlan", "中国移动", "中国联通", "中国电信"
    ]

    static let paymentNoiseKeywords: Set<String> = [
        "支付成功", "交易成功", "付款成功", "收款成功", "今日支出", "今日结余", "今日收入"
    ]

    static let promotionNoiseKeywords: Set<String> = [
        "获得森林能量", "森林能量", "蚂蚁森林", "红包待领取", "待领取", "去领取",
        "碰友日红包", "碰友日立减", "砸友日红包", "立减", "福利红包"
    ]

    static let noteNoiseKeywordSet: Set<String> = navigationNoiseKeywords
        .union(statusBarNoiseKeywords)
        .union(paymentNoiseKeywords)
        .union(promotionNoiseKeywords)
        .union([
            "支付时间", "交易时间", "付款时间", "下单时间", "创建时间",
            "付款方式", "收款方全称", "交易单号", "商户单号",
            "实付", "应付", "支付金额", "订单金额", "合计", "总计", "总额",
            "账单分类", "标签", "请选择", "极速付款", "管理极速付款",
            "广告", "积分", "优惠券", "立即领取", "长按可以分享"
        ])

    static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\u{200B}\\u{FEFF}]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func firstMeaningfulNoteLine(from text: String, maxLength: Int = 40) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(normalize(_:))
            .filter { !$0.isEmpty }

        for line in lines {
            if isLikelyNoiseNote(line) {
                continue
            }
            return String(line.prefix(maxLength))
        }

        return nil
    }

    static func isLikelyNoiseNote(_ text: String) -> Bool {
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { return true }

        if cleaned.count <= 1 { return true }
        if cleaned.range(of: #"^[0-9\-:/\s\.]+$"#, options: .regularExpression) != nil { return true }
        if cleaned.range(of: #"^[¥￥+-]?\s*\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil { return true }
        if cleaned.range(of: #"^\d{1,2}[:：]\d{2}(?:[:：]\d{2})?\s*[a-zA-Z]?$"#, options: .regularExpression) != nil { return true }
        if cleaned.range(of: #"^[\p{P}\p{S}\s]+$"#, options: .regularExpression) != nil { return true }

        let lowered = cleaned.lowercased()
        let runtimeNoiseKeywordSet = noteNoiseKeywordSet.union(RuleUpdateService.shared.dynamicNoiseKeywords())
        if runtimeNoiseKeywordSet.contains(where: { cleaned.contains($0) || lowered.contains($0.lowercased()) }) {
            return true
        }

        return false
    }

    static func isLikelyMerchantText(_ text: String) -> Bool {
        let cleaned = normalize(text)
        guard (2...40).contains(cleaned.count) else { return false }
        guard !isLikelyNoiseNote(cleaned) else { return false }

        if cleaned.range(of: #"^\d+$"#, options: .regularExpression) != nil { return false }

        let hasLetters = cleaned.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        if !hasLetters { return false }

        let alphaNumCount = cleaned.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        if alphaNumCount < max(1, cleaned.count / 3) { return false }

        return true
    }
}

struct ParsedTransaction {
    var amount: Double?
    var categoryKey: String?
    var note: String?
    var isIncome: Bool = false
    var date: Date?
    var billSource: BillSource = .unknown
    var merchantName: String?
    var transactionTime: Date?

    // MARK: - AChai对齐新增字段

    /// 资金账户名称（余额/花呗/信用卡/零钱）
    var fundName: String?

    /// 订单原价（优惠场景）
    var originalMoney: Double?

    /// 优惠金额
    var discountMoney: Double?

    /// 交易对方/商户全称
    var toBiz: String?

    /// 交易状态（1=成功, 2=失败）
    var status: Int?

    /// 匹配规则类型 (0=auto, 1=common, 2=local)
    var ruleKind: Int?
}

protocol TransactionParserServiceProtocol {
    func parse(_ text: String) -> [ParsedTransaction]
    func parse(_ ocrResult: OCRResult) -> [ParsedTransaction]
}

extension TransactionParserServiceProtocol {
    func bestCandidate(from candidates: [ParsedTransaction]) -> ParsedTransaction? {
        candidates.first
    }
}

final class MockTransactionParserService: TransactionParserServiceProtocol {

    // MARK: - Category Keywords

    private static let categoryKeywords: [String: String] = [
        // Dining
        "早餐": "dining", "午餐": "dining", "晚餐": "dining", "饭": "dining",
        "外卖": "dining", "奶茶": "dining", "咖啡": "dining", "吃": "dining",
        "零食": "dining", "饮品": "dining", "聚餐": "dining", "夜宵": "dining", "汉堡": "dining",
        "生煎": "dining", "小笼包": "dining", "面馆": "dining", "包子": "dining",
        "饺子": "dining", "烧烤": "dining", "火锅": "dining", "麻辣烫": "dining",
        "米线": "dining", "炸鸡": "dining", "披萨": "dining", "餐厅": "dining",
        // Transport
        "打车": "transport", "地铁": "transport", "公交": "transport",
        "滴滴": "transport", "加油": "transport", "高铁": "transport",
        "出租": "transport", "单车": "transport", "停车": "transport", "飞机": "transport",
        // Shopping
        "买了": "shopping", "购物": "shopping", "衣服": "shopping",
        "淘宝": "shopping", "京东": "shopping", "拼多多": "shopping",
        "鞋子": "shopping", "包包": "shopping", "日用品": "shopping", "数码": "shopping",
        // Entertainment
        "电影": "entertainment", "游戏": "entertainment", "KTV": "entertainment",
        "唱歌": "entertainment", "运动": "entertainment", "旅行": "entertainment",
        // Housing
        "房租": "housing", "水电": "housing", "物业": "housing",
        "网费": "housing", "维修": "housing", "房贷": "housing",
        // Medical
        "看病": "medical", "药": "medical", "体检": "medical",
        "医院": "medical", "牙": "medical", "保健": "medical",
        // Education
        "书": "education", "课": "education", "考试": "education",
        "培训": "education", "学费": "education",
        // Social
        "红包": "social", "礼物": "social", "请客": "social",
        "结婚": "social", "份子": "social",
        // Transfer
        "转账": "transfer", "提现": "transfer"
    ]

    private static let incomeKeywords: Set<String> = [
        "工资", "收入", "退款", "奖金", "报销", "收到", "到账", "兼职", "理财", "收款", "返现", "转入", "入账"
    ]

    private static let expenseKeywords: Set<String> = [
        "支出", "付款", "支付", "消费", "扣款", "转出", "买", "实付", "应付", "花费", "花了", "花呗还款"
    ]

    private static let sourceCategoryMap: [BillSource: String] = [
        .meituan: "dining",
        .eleme: "dining",
        .didi: "transport",
        .taobao: "shopping",
        .jd: "shopping",
        .pdd: "shopping",
        .douyin: "shopping"
    ]

    private static let incomeCategoryKeywords: [String: String] = [
        "工资": "salary",
        "薪资": "salary",
        "兼职": "parttime",
        "理财": "investment",
        "收益": "investment",
        "退款": "refund",
        "退回": "refund",
        "红包": "redpacket_income",
        "收款": "other_income",
        "到账": "other_income"
    ]

    private static let merchantLabels = [
        "收款方", "商户", "商户名称", "店铺", "商家", "付款方", "对方", "交易对象", "对方账户"
    ]

    private static let remarkLabels = [
        "备注", "订单备注", "备注信息", "用途", "附言"
    ]

    private static let blacklistSnippets = [
        "广告", "点击查看", "立即开通", "会员", "优惠券", "邀请你", "长按可以分享",
        "支付成功", "交易成功", "详情页", "扫码", "支付奖励", "统计支出"
    ]

    private static let noteNoiseKeywords: Set<String> = {
        var keywords: Set<String> = [
        // 时间相关
        "支付时间", "交易时间", "付款时间", "下单时间", "创建时间",
        // 状态/提示
        "交易成功", "支付成功", "付款成功", "转账成功", "收款成功",
        "查看详情", "账单详情", "详情页", "点击查看", "确认收货",
        "立即支付", "立即开通", "扫码支付",
        // 分类/标签
        "账单分类", "请选择", "标签", "更多", "全部",
        // 统计
        "统计支出", "月统计", "月支出", "本月支出", "本月消费", "今日支出",
        // 营销
        "广告", "邀请你", "支付奖励", "积分", "优惠券", "会员优惠",
        "长按可以分享", "立即领取",
        // 付款方式标签
        "付款方式", "收款方全称", "付款方",
        // 平台关键词（不应作为备注）
        "微信支付", "支付宝", "微信", "WeChat", "Alipay",
        // 金额类标签（不应作为备注）
        "实付", "应付", "支付金额", "订单金额", "合计", "总计", "总额",
        // 其他噪音
        "暂无备注", "无备注", "无", "-", "—", "/"
        ]
        keywords.formUnion(OCRSemanticFilter.noteNoiseKeywordSet)
        return keywords
    }()

    private static let amountKeywordScores: [String: Int] = [
        "实付": 170,
        "应付": 170,
        "支付金额": 165,
        "付款金额": 165,
        "交易金额": 165,
        "订单金额": 130,
        "消费金额": 160,
        "收款金额": 160,
        "退款金额": 160,
        "到账金额": 160,
        "合计": 120,
        "总计": 120,
        "总额": 120,
        "金额": 100,
        "今日支出": 60,
        "今日结余": 60
    ]

    private static let settlementKeywordScores: [String: Int] = [
        "实付": 260,
        "应付": 250,
        "支付金额": 245,
        "付款金额": 245,
        "交易金额": 245,
        "实际支付": 240,
        "实际付款": 240,
        "本次支付": 235,
        "消费金额": 230,
        "收款金额": 230,
        "到账金额": 230,
        "合计": 220,
        "总计": 220,
        "总额": 215
    ]

    private static let orderAmountKeywordScores: [String: Int] = [
        "订单金额": 170,
        "商品金额": 165,
        "原价": 150,
        "账单金额": 155
    ]

    private static let discountKeywords: [String] = [
        "抵扣", "金抵扣", "优惠", "优惠金额", "优惠券", "立减", "减免", "福利", "红包", "折扣", "满减"
    ]

    private static let monthlySummaryKeywords: [String] = [
        "统计支出", "月统计", "月支出", "本月支出", "本月消费", "月消费"
    ]

    private static let settlementContextKeywords: [String] = [
        "实付", "应付", "支付金额", "付款金额", "交易金额", "收款金额", "到账金额", "支出", "收入", "转账"
    ]

    private static let summaryContextKeywords: [String] = [
        "今日支出", "今日收入", "今日结余", "本月支出", "本月消费", "月统计", "统计支出"
    ]

    private static let orderContextKeywords: [String] = [
        "订单金额", "商品金额", "原价", "账单金额"
    ]

    // MARK: - Amount Patterns

    private struct AmountCandidate {
        let value: Double
        let score: Int
        let location: Int
        let sign: Int?
    }

    private struct AmountParseResult {
        let value: Double
        let sign: Int?
    }

    private struct StructuredLine {
        let text: String
        let cleanedText: String
        let rowIndex: Int
    }

    /// 平台候选打分用的行上下文（带列结构与OCR布局）
    private struct AmountContextLine {
        let text: String
        let lineIndex: Int
        let totalLines: Int
        let columnCount: Int
        let observations: [OCRTextObservation]
    }

    private static let keywordAmountPattern =
        "(?:实付|应付|支付金额|付款金额|订单金额|消费金额|合计|总计|总额|金额|今日支出|今日结余)\\s*[：:]?\\s*(?:[-+−]?\\s*)?(?:[¥￥]\\s*)?([0-9]+(?:[\\.,][0-9]{1,2})?)"
    private static let currencyAmountPattern = "[-+−]?\\s*[¥￥]\\s*([0-9]+(?:[\\.,][0-9]{1,2})?)"
    private static let trailingCurrencyAmountPattern = "([0-9]+(?:[\\.,][0-9]{1,2})?)\\s*[¥￥]"
    private static let unitAmountPattern = "([+-−]?[0-9]+(?:[\\.,][0-9]{1,2})?)\\s*(?:元|块|RMB|CNY)"
    // Signed amount like -4.38 or +100.50 (standard payment app bill format)
    private static let signedAmountPattern = "(?<![0-9.])([-+−]\\d+\\.\\d{1,2})(?![0-9.])"
    // Standalone amount with exactly 2 decimal places (AChai-style: ¥XX.XX format)
    private static let twoDecimalAmountPattern = "(?<![0-9.])(\\d+\\.\\d{2})(?![0-9.])"
    // AChai strict money format: ^[+-]?\d+\.\d{2}$ (exactly 2 decimal places, optional sign)
    private static let achaiStrictMoneyPattern = "^[-+−]?\\d+\\.\\d{2}$"
    private static let fallbackNumberPattern = "(?<![0-9])([0-9]{1,6}(?:\\.[0-9]{1,2})?)(?![0-9])"

    // MARK: - Parse

    func parse(_ text: String) -> [ParsedTransaction] {
        let cleanedText = cleanRecognizedText(text)
        let normalizedText = normalizeRecognizedText(cleanedText)
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let detectedSource = BillSource.detect(from: normalizedText)
        var candidates = platformCandidatesFromText(normalizedText, detectedSource: detectedSource)

        if let genericCandidate = buildGenericTextCandidate(
            from: normalizedText,
            billSource: detectedSource
        ), shouldAppendGenericCandidate(genericCandidate, to: candidates) {
            candidates.append(genericCandidate)
        }

        return rankAndEnhanceCandidates(
            candidates,
            fullText: normalizedText,
            fallbackSource: detectedSource
        )
    }

    // MARK: - Candidate Pipeline

    private let strongRuleCategoryThreshold: Float = 0.80

    private struct TransactionDedupKey: Hashable {
        let amountRounded2: Int
        let merchantOrToBizNormalized: String
        let isIncome: Bool
        let dayBucket: Int
    }

    private struct BroadTransactionDedupKey: Hashable {
        let amountRounded2: Int
        let isIncome: Bool
        let dayBucket: Int
    }

    private struct ScoredTransactionCandidate {
        let transaction: ParsedTransaction
        let finalScore: Int
        let initialOrder: Int
        let dedupKey: TransactionDedupKey
    }

    private func platformCandidatesFromText(
        _ normalizedText: String,
        detectedSource: BillSource
    ) -> [ParsedTransaction] {
        switch detectedSource {
        case .wechatPay:
            return WechatTransactionParser.parse(text: normalizedText).map { candidate in
                var patched = candidate
                patched.billSource = .wechatPay
                return patched
            }
        case .alipay:
            return AlipayTransactionParser.parse(text: normalizedText).map { candidate in
                var patched = candidate
                patched.billSource = .alipay
                return patched
            }
        default:
            return []
        }
    }

    private func platformCandidatesFromOCR(
        _ ocrResult: OCRResult,
        detectedSource: BillSource
    ) -> [ParsedTransaction] {
        switch detectedSource {
        case .wechatPay:
            return WechatTransactionParser.parse(ocrResult: ocrResult).map { candidate in
                var patched = candidate
                patched.billSource = .wechatPay
                return patched
            }
        case .alipay:
            return AlipayTransactionParser.parse(ocrResult: ocrResult).map { candidate in
                var patched = candidate
                patched.billSource = .alipay
                return patched
            }
        default:
            return []
        }
    }

    private func buildGenericTextCandidate(
        from normalizedText: String,
        billSource: BillSource
    ) -> ParsedTransaction? {
        var result = ParsedTransaction()
        result.billSource = billSource

        let amountResult = extractPreferredAmountResult(from: normalizedText) ?? extractAmountResult(from: normalizedText)
        result.amount = amountResult?.value

        let (date, time) = extractDateTime(from: normalizedText)
        result.date = date
        result.transactionTime = time

        let explicitRemark = extractLabelValue(from: normalizedText, labels: Self.remarkLabels)
        let merchant = extractMerchantFromRawText(normalizedText, source: result.billSource)
        result.merchantName = merchant

        result.note = buildSmartNote(
            explicitRemark: explicitRemark,
            merchant: merchant,
            fallbackText: normalizedText
        )

        result.isIncome = detectIncome(from: normalizedText, amountSign: amountResult?.sign)
        result.categoryKey = detectCategory(
            from: normalizedText,
            source: result.billSource,
            merchant: merchant,
            isIncome: result.isIncome
        )

        return result
    }

    private func buildGenericOCRCandidate(
        from ocrResult: OCRResult,
        normalizedFullText: String,
        billSource: BillSource
    ) -> ParsedTransaction? {
        let structuredLines = setupStructuredLines(from: ocrResult)
        var result = ParsedTransaction()
        result.billSource = billSource

        let amountResult =
            extractPreferredAmountResult(from: normalizedFullText) ??
            extractAmountSpatial(from: structuredLines) ??
            extractAmountResult(from: normalizedFullText)
        result.amount = amountResult?.value

        result.isIncome = detectIncome(from: normalizedFullText, amountSign: amountResult?.sign)

        let (date, time) = extractDateTime(from: normalizedFullText)
        result.date = date
        result.transactionTime = time

        let explicitRemark = extractLabelValue(from: structuredLines, labels: Self.remarkLabels)
        result.merchantName = extractMerchant(from: structuredLines, fullText: normalizedFullText, source: result.billSource)
        result.note = buildSmartNote(
            explicitRemark: explicitRemark,
            merchant: result.merchantName,
            fallbackText: normalizedFullText
        )

        result.categoryKey = detectCategory(
            from: normalizedFullText,
            source: result.billSource,
            merchant: result.merchantName,
            isIncome: result.isIncome
        )

        return result
    }

    private func rankAndEnhanceCandidates(
        _ rawCandidates: [ParsedTransaction],
        fullText: String,
        fallbackSource: BillSource,
        ocrResult: OCRResult? = nil
    ) -> [ParsedTransaction] {
        guard !rawCandidates.isEmpty else { return [] }

        let normalized = normalizeRecognizedText(cleanRecognizedText(fullText))
        let amountContextLines = buildAmountContextLines(
            normalizedText: normalized,
            ocrLines: ocrResult?.lines
        )

        let scoredCandidates: [ScoredTransactionCandidate] = rawCandidates.enumerated().compactMap { index, candidate in
            var base = candidate
            if base.billSource == .unknown {
                base.billSource = fallbackSource
            }

            guard let amount = base.amount, amount > 0 else {
                return nil
            }

            let ruleMatches = matchRules(for: base, normalizedText: normalized, ocrResult: ocrResult)
            let enhanced = applyRuleEnhancement(
                to: base,
                matches: ruleMatches,
                categoryStrongOverrideThreshold: strongRuleCategoryThreshold
            )

            let ruleScore = Int((ruleMatches.first?.matchScore ?? 0) * 120)
            let structureScore = candidateStructureBonus(for: enhanced, matches: ruleMatches)
            let contextScore = platformTransactionScore(
                enhanced,
                index: index,
                amountContextLines: amountContextLines,
                normalizedText: normalized,
                source: enhanced.billSource
            )
            let finalScore = contextScore + ruleScore + structureScore

            return ScoredTransactionCandidate(
                transaction: enhanced,
                finalScore: finalScore,
                initialOrder: index,
                dedupKey: dedupKey(for: enhanced, roundedAmount: amount)
            )
        }

        guard !scoredCandidates.isEmpty else { return [] }

        var deduplicated: [TransactionDedupKey: ScoredTransactionCandidate] = [:]
        for item in scoredCandidates {
            guard let existing = deduplicated[item.dedupKey] else {
                deduplicated[item.dedupKey] = item
                continue
            }
            if item.finalScore > existing.finalScore ||
                (item.finalScore == existing.finalScore && item.initialOrder < existing.initialOrder) {
                deduplicated[item.dedupKey] = item
            }
        }

        let noisySuppressed = suppressNoisyDuplicateCandidates(Array(deduplicated.values))

        return noisySuppressed
            .sorted { lhs, rhs in
                if lhs.finalScore != rhs.finalScore {
                    return lhs.finalScore > rhs.finalScore
                }
                let leftAmount = lhs.transaction.amount ?? 0
                let rightAmount = rhs.transaction.amount ?? 0
                if abs(leftAmount - rightAmount) > 0.001 {
                    return leftAmount > rightAmount
                }
                return lhs.initialOrder < rhs.initialOrder
            }
            .map(\.transaction)
    }

    private func suppressNoisyDuplicateCandidates(
        _ candidates: [ScoredTransactionCandidate]
    ) -> [ScoredTransactionCandidate] {
        guard !candidates.isEmpty else { return [] }

        let grouped = Dictionary(grouping: candidates) { item -> BroadTransactionDedupKey in
            let roundedAmount = Int((((item.transaction.amount ?? 0) * 100).rounded()))
            return BroadTransactionDedupKey(
                amountRounded2: roundedAmount,
                isIncome: item.transaction.isIncome,
                dayBucket: dayBucket(from: item.transaction.transactionTime ?? item.transaction.date)
            )
        }

        var result: [ScoredTransactionCandidate] = []
        result.reserveCapacity(candidates.count)

        for group in grouped.values {
            // 单账单常见噪声（如 "18:18 S"）只要同组存在非噪声候选，就不应独立展示。
            let denoisedGroup = group.filter { !isLikelyNoiseCounterpartyText(candidateCounterpartyText(for: $0.transaction)) }
            let sourceGroup = denoisedGroup.isEmpty ? group : denoisedGroup
            let reliable = sourceGroup.filter { hasReliableCounterparty(for: $0.transaction) }
            // If the group has exactly one reliable candidate and the rest are noise,
            // compress to single candidate (single-bill convergence).
            if reliable.count == 1 && sourceGroup.count > 1 {
                result.append(reliable[0])
            } else if !reliable.isEmpty {
                result.append(contentsOf: reliable)
            } else {
                // No reliable counterparty in group — keep highest-scored only if group has multiple
                if sourceGroup.count > 1, let best = sourceGroup.max(by: { $0.finalScore < $1.finalScore }) {
                    result.append(best)
                } else {
                    result.append(contentsOf: sourceGroup)
                }
            }
        }

        return result
    }

    private func candidateStructureBonus(
        for candidate: ParsedTransaction,
        matches: [RuleMatchResult]
    ) -> Int {
        var score = 0

        if candidate.status == 1 { score += 8 }
        if candidate.status == 2 { score -= 20 }
        if candidate.fundName != nil { score += 3 }
        if candidate.date != nil || candidate.transactionTime != nil { score += 4 }
        if candidate.merchantName != nil || candidate.toBiz != nil { score += 8 }

        if let bestMatch = matches.first {
            score += bestMatch.isFuzzyMatch ? 2 : 8
            if bestMatch.matchScore >= strongRuleCategoryThreshold {
                score += 10
            }
        }

        return score
    }

    private func matchRules(
        for candidate: ParsedTransaction,
        normalizedText: String,
        ocrResult: OCRResult?
    ) -> [RuleMatchResult] {
        guard let amount = candidate.amount else { return [] }
        let effectiveSource: BillSource = candidate.billSource == .unknown ? .unknown : candidate.billSource

        if let ocrResult {
            return AutoBillRuleEngine.shared.matchRules(
                for: ocrResult,
                billSource: effectiveSource,
                amount: amount
            )
        }

        return AutoBillRuleEngine.shared.matchRules(
            for: normalizedText,
            billSource: effectiveSource,
            amount: amount
        )
    }

    private func dedupKey(
        for candidate: ParsedTransaction,
        roundedAmount: Double
    ) -> TransactionDedupKey {
        let merchant = normalizeMerchantForDedup(candidateCounterpartyText(for: candidate))
        let amountRounded2 = Int((roundedAmount * 100).rounded())
        let bucketDate = candidate.transactionTime ?? candidate.date

        return TransactionDedupKey(
            amountRounded2: amountRounded2,
            merchantOrToBizNormalized: merchant,
            isIncome: candidate.isIncome,
            dayBucket: dayBucket(from: bucketDate)
        )
    }

    private func normalizeMerchantForDedup(_ value: String) -> String {
        let source = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty || isLikelyNoiseCounterpartyText(source) {
            return "__unknown__"
        }

        let cleaned = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fa5]", with: "", options: .regularExpression)
        return cleaned.isEmpty ? "__unknown__" : cleaned
    }

    private func shouldAppendGenericCandidate(
        _ genericCandidate: ParsedTransaction,
        to existingCandidates: [ParsedTransaction]
    ) -> Bool {
        guard let genericAmount = genericCandidate.amount, genericAmount > 0 else { return false }
        guard !existingCandidates.isEmpty else { return true }

        let genericAmountRounded = Int((genericAmount * 100).rounded())
        let genericDay = dayBucket(from: genericCandidate.transactionTime ?? genericCandidate.date)
        let genericIsReliable = hasReliableCounterparty(for: genericCandidate)

        for existing in existingCandidates {
            guard let existingAmount = existing.amount else { continue }
            let existingAmountRounded = Int((existingAmount * 100).rounded())
            let existingDay = dayBucket(from: existing.transactionTime ?? existing.date)

            let amountClose = abs(existingAmountRounded - genericAmountRounded) <= 1
            let dayClose = genericDay == 0 || existingDay == 0 || genericDay == existingDay
            let sameDirection = existing.isIncome == genericCandidate.isIncome
            guard amountClose, dayClose, sameDirection else { continue }

            let existingMerchant = normalizeMerchantForDedup(candidateCounterpartyText(for: existing))
            let genericMerchant = normalizeMerchantForDedup(candidateCounterpartyText(for: genericCandidate))
            if existingMerchant == genericMerchant {
                return false
            }

            if hasReliableCounterparty(for: existing), !genericIsReliable {
                return false
            }
        }

        return true
    }

    private func candidateCounterpartyText(for candidate: ParsedTransaction) -> String {
        if let merchant = candidate.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty {
            return merchant
        }
        if let toBiz = candidate.toBiz?.trimmingCharacters(in: .whitespacesAndNewlines), !toBiz.isEmpty {
            return toBiz
        }
        if let note = candidate.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return note
        }
        return ""
    }

    private func hasReliableCounterparty(for candidate: ParsedTransaction) -> Bool {
        let text = candidateCounterpartyText(for: candidate)
        guard !text.isEmpty else { return false }
        return !isLikelyNoiseCounterpartyText(text)
    }

    private func isLikelyNoiseCounterpartyText(_ text: String) -> Bool {
        let trimmed = OCRSemanticFilter.normalize(text)
        guard !trimmed.isEmpty else { return true }
        if OCRSemanticFilter.isLikelyNoiseNote(trimmed) { return true }

        let compact = trimmed.lowercased()

        // e.g. "18:18", "18:18 s"
        if compact.range(
            of: #"^\d{1,2}:\d{2}(?::\d{2})?\s*[a-z]?$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        // Digits/punctuation only.
        if compact.range(of: #"^[0-9\.\-: ]+$"#, options: .regularExpression) != nil {
            return true
        }

        let normalized = compact
            .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fa5]", with: "", options: .regularExpression)

        guard !normalized.isEmpty else { return true }

        let hasChinese = normalized.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        if !hasChinese && normalized.count <= 2 {
            return true
        }

        if OCRSemanticFilter.navigationNoiseKeywords.contains(where: { trimmed.contains($0) }) {
            return true
        }

        let statusTokens: Set<String> = [
            "s", "x", "4g", "5g", "lte", "wifi", "wlan", "chinaunicom", "chinamobile", "chinatelecom"
        ]
        if statusTokens.contains(normalized) {
            return true
        }

        return false
    }

    private func dayBucket(from date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return year * 10_000 + month * 100 + day
    }

    // MARK: - Amount Extraction

    private func extractAmount(from text: String) -> Double? {
        extractAmountResult(from: text)?.value
    }

    /// AChai-style prioritization:
    /// 1) explicit settlement labels (实付/支付金额/交易金额...)
    /// 2) bill-detail header signed amount (e.g. "-5.94")
    /// 3) order amount minus discount lines (订单金额 - 抵扣/优惠)
    private func extractPreferredAmountResult(from text: String) -> AmountParseResult? {
        let normalized = normalizeRecognizedText(text)

        if let settlement = extractLabeledAmountResult(
            from: normalized,
            keywordScores: Self.settlementKeywordScores
        ) {
            return settlement
        }

        if let headerSettlement = extractHeaderSettlementAmount(from: normalized) {
            return headerSettlement
        }

        if let netAmount = extractNetAmountByDiscount(from: normalized) {
            return netAmount
        }

        return nil
    }

    private func extractLabeledAmountResult(
        from text: String,
        keywordScores: [String: Int]
    ) -> AmountParseResult? {
        var candidates: [AmountCandidate] = []

        for (keyword, score) in keywordScores {
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            let pattern = "\(escaped)\\s*[：:]?\\s*([-+−]?\\s*(?:[¥￥]\\s*)?[0-9]+(?:[\\.,][0-9]{1,2})?)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                guard let numberRange = Range(match.range(at: 1), in: text),
                      let value = sanitizeAmount(String(text[numberRange])) else { continue }

                let fullMatch = Range(match.range, in: text).map { String(text[$0]) } ?? String(text[numberRange])
                let sign = inferSign(in: fullMatch, around: numberRange, from: text)
                candidates.append(
                    AmountCandidate(
                        value: value,
                        score: score,
                        location: match.range.location,
                        sign: sign
                    )
                )
            }
        }

        // Filter out monthly summary amounts
        candidates = candidates.filter { cand in
            !isInMonthlySummaryContext(text: text, location: cand.location)
        }

        guard !candidates.isEmpty else { return nil }
        let best = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.location < $1.location
        }.first

        guard let best else { return nil }
        return AmountParseResult(value: best.value, sign: best.sign)
    }

    private func extractHeaderSettlementAmount(from text: String) -> AmountParseResult? {
        let hasBillDetailContext =
            text.contains("交易成功") ||
            text.contains("支付成功") ||
            text.contains("账单详情")
        guard hasBillDetailContext else { return nil }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(6) {
            if line.contains("订单金额") || line.contains("支付时间") || line.contains("付款方式") || line.contains("收款方") {
                continue
            }

            let signedCandidates = extractCandidates(
                in: line,
                pattern: Self.signedAmountPattern,
                score: 0,
                applyFallbackFilter: false
            )

            if let candidate = signedCandidates.first(where: { $0.value >= 1 }) {
                return AmountParseResult(value: candidate.value, sign: candidate.sign ?? -1)
            }
        }

        return nil
    }

    private func extractNetAmountByDiscount(from text: String) -> AmountParseResult? {
        guard let orderAmount = extractLabeledAmountResult(from: text, keywordScores: Self.orderAmountKeywordScores) else {
            return nil
        }

        let discount = extractDiscountTotal(from: text)
        guard discount > 0, orderAmount.value > discount else { return nil }

        let net = ((orderAmount.value - discount) * 100).rounded() / 100
        guard net > 0 else { return nil }
        return AmountParseResult(value: net, sign: orderAmount.sign ?? -1)
    }

    private func extractDiscountTotal(from text: String) -> Double {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var totalDiscount: Double = 0

        for line in lines {
            guard Self.discountKeywords.contains(where: { line.contains($0) }) else { continue }

            var lineCandidates: [AmountCandidate] = []
            lineCandidates.append(contentsOf: extractCandidates(
                in: line,
                pattern: Self.signedAmountPattern,
                score: 0,
                applyFallbackFilter: false
            ))
            lineCandidates.append(contentsOf: extractCandidates(
                in: line,
                pattern: Self.currencyAmountPattern,
                score: 0,
                applyFallbackFilter: false
            ))
            lineCandidates.append(contentsOf: extractCandidates(
                in: line,
                pattern: Self.twoDecimalAmountPattern,
                score: 0,
                applyFallbackFilter: false
            ))

            guard !lineCandidates.isEmpty else { continue }
            let uniqueCandidates = deduplicateCandidates(lineCandidates)

            let negativeValues = uniqueCandidates
                .filter { $0.sign == -1 }
                .map { $0.value }

            if !negativeValues.isEmpty {
                totalDiscount += negativeValues.reduce(0, +)
                continue
            }

            // Discount lines without explicit sign usually still represent deduction.
            if let minimumPositive = uniqueCandidates.map(\.value).filter({ $0 > 0 }).min() {
                totalDiscount += minimumPositive
            }
        }

        return ((totalDiscount * 100).rounded() / 100)
    }

    private func deduplicateCandidates(_ candidates: [AmountCandidate]) -> [AmountCandidate] {
        var result: [AmountCandidate] = []
        let sorted = candidates.sorted { $0.location < $1.location }

        for candidate in sorted {
            let roundedValue = Int((candidate.value * 100).rounded())
            let sign = candidate.sign ?? 0

            let isNearbyDuplicate = result.contains { existing in
                let existingRounded = Int((existing.value * 100).rounded())
                let existingSign = existing.sign ?? 0
                return existingRounded == roundedValue &&
                    existingSign == sign &&
                    abs(existing.location - candidate.location) <= 2
            }

            if !isNearbyDuplicate {
                result.append(candidate)
            }
        }

        return result
    }

    private func extractAmountResult(from text: String) -> AmountParseResult? {
        let normalized = normalizeRecognizedText(text)
        var candidates: [AmountCandidate] = []

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.keywordAmountPattern,
            score: 100,
            applyFallbackFilter: false
        ))

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.currencyAmountPattern,
            score: 80,
            applyFallbackFilter: false
        ))

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.trailingCurrencyAmountPattern,
            score: 75,
            applyFallbackFilter: false
        ))

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.unitAmountPattern,
            score: 65,
            applyFallbackFilter: false
        ))

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.signedAmountPattern,
            score: 60,
            applyFallbackFilter: false
        ))

        // AChai strict money pattern (high confidence)
        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.achaiStrictMoneyPattern,
            score: 70,
            applyFallbackFilter: false
        ))

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.twoDecimalAmountPattern,
            score: 55,
            applyFallbackFilter: false
        ))

        candidates.append(contentsOf: extractCandidates(
            in: normalized,
            pattern: Self.fallbackNumberPattern,
            score: 20,
            applyFallbackFilter: true
        ))

        // Filter out candidates in discount context (e.g., "优惠金额 ¥0.06")
        candidates = candidates.filter { cand in
            !isInDiscountContext(text: normalized, location: cand.location)
        }

        // Filter out candidates in monthly summary context (e.g., "4月统计支出 ¥221.13")
        candidates = candidates.filter { cand in
            !isInMonthlySummaryContext(text: normalized, location: cand.location)
        }

        guard !candidates.isEmpty else { return nil }

        let best = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.location < $1.location
        }.first

        guard let best else { return nil }
        return AmountParseResult(value: best.value, sign: best.sign)
    }

    /// Check if the text around `location` contains discount keywords,
    /// meaning the matched amount is likely a discount/fee, not the actual payment.
    private func isInDiscountContext(text: String, location: Int) -> Bool {
        let nsText = text as NSString
        let lookback = min(8, location)
        guard lookback > 0 else { return false }
        let prefix = nsText.substring(with: NSRange(location: location - lookback, length: lookback))
        return Self.discountKeywords.contains(where: { prefix.contains($0) })
    }

    /// Check if the text around `location` contains monthly summary keywords,
    /// meaning the matched amount is a monthly total, not an individual transaction.
    private func isInMonthlySummaryContext(text: String, location: Int) -> Bool {
        let nsText = text as NSString
        let lookback = min(12, location)
        guard lookback > 0 else { return false }
        let prefix = nsText.substring(with: NSRange(location: location - lookback, length: lookback))
        return Self.monthlySummaryKeywords.contains(where: { prefix.contains($0) })
    }

    private func extractCandidates(
        in text: String,
        pattern: String,
        score: Int,
        applyFallbackFilter: Bool
    ) -> [AmountCandidate] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let searchRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: searchRange)
        var candidates: [AmountCandidate] = []

        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[numberRange])

            if applyFallbackFilter && isLikelyNonAmount(raw, in: text, range: numberRange) {
                continue
            }

            guard let value = sanitizeAmount(raw) else { continue }
            let fullMatch: String
            if let fullRange = Range(match.range, in: text) {
                fullMatch = String(text[fullRange])
            } else {
                fullMatch = raw
            }
            let sign = inferSign(in: fullMatch, around: numberRange, from: text)
            candidates.append(
                AmountCandidate(
                    value: value,
                    score: score,
                    location: match.range.location,
                    sign: sign
                )
            )
        }

        return candidates
    }

    private func inferSign(in fullMatch: String, around numberRange: Range<String.Index>, from text: String) -> Int? {
        if fullMatch.contains("-") || fullMatch.contains("−") || fullMatch.contains("－") || fullMatch.contains("—") || fullMatch.contains("–") {
            return -1
        }
        if fullMatch.contains("+") {
            return 1
        }

        let prefixStart = text.index(numberRange.lowerBound, offsetBy: -3, limitedBy: text.startIndex) ?? text.startIndex
        let prefix = String(text[prefixStart..<numberRange.lowerBound])
        if prefix.contains("-") || prefix.contains("−") || prefix.contains("－") || prefix.contains("—") || prefix.contains("–") {
            return -1
        }
        if prefix.contains("+") {
            return 1
        }
        return nil
    }

    private func sanitizeAmount(_ raw: String) -> Double? {
        var cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " ", with: "")

        cleaned = cleaned.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? cleaned

        if cleaned.contains(",") && cleaned.contains(".") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else if cleaned.contains(",") {
            let parts = cleaned.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count <= 2 {
                cleaned = "\(parts[0]).\(parts[1])"
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        guard let number = Double(cleaned) else { return nil }
        let value = abs(number)
        guard value > 0, value < 100000 else { return nil }
        return value
    }

    private func isLikelyNonAmount(_ raw: String, in text: String, range: Range<String.Index>) -> Bool {
        let prefixStart = text.index(range.lowerBound, offsetBy: -4, limitedBy: text.startIndex) ?? text.startIndex
        let suffixEnd = text.index(range.upperBound, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = String(text[prefixStart..<range.lowerBound])
        let suffix = String(text[range.upperBound..<suffixEnd])
        let context = prefix + raw + suffix

        // Time format (14:42:08) or date with slash (2026/04/06)
        if context.contains(":") || context.contains("/") {
            return true
        }

        // Date format: number flanked by dashes (2026-04-06 → "06" between dashes)
        let prefixTrimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixTrimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if (prefixTrimmed.hasSuffix("-") || prefixTrimmed.hasSuffix("—") || prefixTrimmed.hasSuffix("–")),
           (suffixTrimmed.hasPrefix("-") || suffixTrimmed.hasPrefix("—") || suffixTrimmed.hasPrefix("–")) {
            return true
        }

        // Long number without decimal (likely order ID, timestamp, etc.)
        if raw.count >= 5 && !raw.contains(".") {
            return true
        }

        // Integer only (no decimal) and small — likely a date component or count
        if !raw.contains(".") && raw.count <= 2 {
            let contextHint = prefix + suffix
            let expenseHintPattern = "(午餐|晚餐|早餐|打车|地铁|公交|外卖|奶茶|咖啡|购物|买|支付|付款|消费|花费|花了)"
            let hasRegexExpenseHint = contextHint.range(of: expenseHintPattern, options: .regularExpression) != nil
            let hasCategoryKeywordHint = Self.categoryKeywords.keys.contains { contextHint.contains($0) }
            let hasIncomeKeywordHint = Self.incomeKeywords.contains { contextHint.contains($0) }
            let hasExpenseKeywordHint = Self.expenseKeywords.contains { contextHint.contains($0) }

            let hasSemanticHint = hasRegexExpenseHint ||
                hasCategoryKeywordHint ||
                hasIncomeKeywordHint ||
                hasExpenseKeywordHint

            if !hasSemanticHint {
                return true
            }
        }

        return false
    }

    /// AChai's recognizedStringCleaning: pre-processing before normalization
    /// Removes zero-width characters, normalizes line endings, strips control chars
    private func cleanRecognizedText(_ text: String) -> String {
        var cleaned = text

        // Remove zero-width characters (common OCR artifacts)
        cleaned = cleaned.replacingOccurrences(of: "\u{200B}", with: "")  // zero-width space
        cleaned = cleaned.replacingOccurrences(of: "\u{FEFF}", with: "")  // BOM
        cleaned = cleaned.replacingOccurrences(of: "\u{200C}", with: "")   // zero-width non-joiner
        cleaned = cleaned.replacingOccurrences(of: "\u{200D}", with: "")  // zero-width joiner
        cleaned = cleaned.replacingOccurrences(of: "\u{00AD}", with: "")  // soft hyphen

        // Normalize line endings
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")

        // Remove other invisible control characters but preserve newlines/tabs
        cleaned = cleaned.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }.map { String($0) }.joined()

        // Remove vertical tab and form feed
        cleaned = cleaned.replacingOccurrences(of: "\u{000B}", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\u{000C}", with: "")

        return cleaned
    }

    private func normalizeRecognizedText(_ text: String) -> String {
        text
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "￥", with: "¥")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    // MARK: - Category Detection

    private func detectCategory(
        from text: String,
        source: BillSource,
        merchant: String?,
        isIncome: Bool
    ) -> String? {
        let combined = [text, merchant].compactMap { $0 }.joined(separator: " ")

        if isIncome {
            for (keyword, categoryKey) in Self.incomeCategoryKeywords {
                if combined.contains(keyword) {
                    return categoryKey
                }
            }
            return nil
        }

        for (keyword, categoryKey) in Self.categoryKeywords {
            if combined.contains(keyword) {
                return categoryKey
            }
        }

        if let mapped = Self.sourceCategoryMap[source] {
            return mapped
        }
        return nil
    }

    // MARK: - Income Detection

    private func detectIncome(from text: String, amountSign: Int?) -> Bool {
        if amountSign == 1 { return true }
        if amountSign == -1 { return false }

        let hasIncomeKeyword = Self.incomeKeywords.contains { text.contains($0) }
        let hasExpenseKeyword = Self.expenseKeywords.contains { text.contains($0) }

        if hasIncomeKeyword && !hasExpenseKeyword { return true }
        if hasExpenseKeyword && !hasIncomeKeyword { return false }
        if text.contains("退款") || text.contains("收款") || text.contains("到账") { return true }
        if text.contains("支出") || text.contains("付款") || text.contains("消费") { return false }

        return false
    }

    // MARK: - Label Value

    private func extractLabelValue(from text: String, labels: [String]) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { StructuredLine(text: $0.element, cleanedText: normalizeRecognizedText($0.element), rowIndex: $0.offset) }
        return extractLabelValue(from: lines, labels: labels)
    }

    private func extractLabelValue(from lines: [StructuredLine], labels: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        for (index, line) in lines.enumerated() {
            for label in labels where line.cleanedText.contains(label) {
                if let sameLine = valueAfterLabel(in: line.cleanedText, label: label), isMeaningfulNote(sameLine) {
                    return cleanedForNote(sameLine)
                }
                if index + 1 < lines.count {
                    let next = lines[index + 1].cleanedText
                    if isMeaningfulNote(next), !labels.contains(where: { next.contains($0) }) {
                        return cleanedForNote(next)
                    }
                }
            }
        }
        return nil
    }

    private func valueAfterLabel(in line: String, label: String) -> String? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = "\(escapedLabel)\\s*[:：]?\\s*(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isMeaningfulNote(_ text: String) -> Bool {
        let cleaned = cleanedForNote(text)
        guard (2...40).contains(cleaned.count) else { return false }
        if cleaned.range(of: "^[0-9\\-:/\\s\\.]+$", options: .regularExpression) != nil { return false }
        if cleaned.range(of: "^[¥￥+-]?\\d+(?:\\.\\d{1,2})?$", options: .regularExpression) != nil { return false }
        if Self.noteNoiseKeywords.contains(where: { cleaned.contains($0) }) { return false }
        if looksLikeDateOrTime(cleaned) { return false }
        return true
    }

    private func cleanedForNote(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\u{200B}\\u{FEFF}]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func looksLikeDateOrTime(_ text: String) -> Bool {
        if text.range(of: "^\\d{1,2}[:：]\\d{2}([:：]\\d{2})?[！!]*$", options: .regularExpression) != nil {
            return true
        }
        if text.range(of: "\\d{4}[\\-/.年]\\d{1,2}[\\-/.月]\\d{1,2}", options: .regularExpression) != nil {
            return true
        }
        if text.range(of: "\\d{1,2}[:：]\\d{2}([:：]\\d{2})?", options: .regularExpression) != nil,
           text.range(of: "\\d", options: .regularExpression) != nil,
           text.contains("时间") {
            return true
        }
        return false
    }

    // MARK: - Date Extraction

    private func extractDate(from text: String) -> Date? {
        let normalized = normalizeRecognizedText(text)
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)

        // Pattern 1: 2024年03月28日 or 2024年3月28日
        if let date = extractDateWithPattern(
            normalized,
            pattern: "(\\d{4})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日",
            yearIndex: 1, monthIndex: 2, dayIndex: 3,
            calendar: calendar
        ) { return clampToPast(date, now: now) }

        // Pattern 2: 2024-03-28 or 2024/03/28
        if let date = extractDateWithPattern(
            normalized,
            pattern: "(\\d{4})[/-](\\d{1,2})[/-](\\d{1,2})",
            yearIndex: 1, monthIndex: 2, dayIndex: 3,
            calendar: calendar
        ) { return clampToPast(date, now: now) }

        // Pattern 3: 3月28日 (current year assumed)
        if let date = extractDateWithPattern(
            normalized,
            pattern: "(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日",
            yearIndex: nil, monthIndex: 1, dayIndex: 2,
            calendar: calendar,
            defaultYear: currentYear
        ) { return clampToPast(date, now: now) }

        // Pattern 4: 03-28 or 03/28 (current year assumed)
        if let date = extractDateWithPattern(
            normalized,
            pattern: "(?<!\\d)(\\d{1,2})[/-](\\d{1,2})(?!\\d)",
            yearIndex: nil, monthIndex: 1, dayIndex: 2,
            calendar: calendar,
            defaultYear: currentYear
        ) {
            // Avoid matching time patterns like 14:30
            return clampToPast(date, now: now)
        }

        return nil
    }

    private func extractDateWithPattern(
        _ text: String,
        pattern: String,
        yearIndex: Int?,
        monthIndex: Int,
        dayIndex: Int,
        calendar: Calendar,
        defaultYear: Int? = nil
    ) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        let year: Int
        if let yi = yearIndex, let yr = captureInt(match, at: yi, in: text) {
            year = yr
        } else if let defaultYear {
            year = defaultYear
        } else {
            return nil
        }

        guard let month = captureInt(match, at: monthIndex, in: text),
              let day = captureInt(match, at: dayIndex, in: text),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private func captureInt(_ match: NSTextCheckingResult, at index: Int, in text: String) -> Int? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    /// If the parsed date is in the future (e.g., Dec 31 parsed as 12/31 but today is Jan 15),
    /// assume it belongs to last year.
    private func clampToPast(_ date: Date, now: Date) -> Date {
        if date > now,
           let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: date) {
            return lastYear
        }
        return date
    }

    // MARK: - Rule Enhancement

    /// 应用规则增强（规则分用于排序，规则结果用于候选增强）
    private func applyRuleEnhancement(
        to result: ParsedTransaction,
        matches: [RuleMatchResult],
        categoryStrongOverrideThreshold: Float
    ) -> ParsedTransaction {
        guard let bestMatch = matches.first else { return result }

        var enhanced = AutoBillRuleEngine.shared.applyRules(to: result, matches: matches)

        if let ruleCategoryKey = AutoBillRuleEngine.shared.categoryKey(from: bestMatch.rule.memberCateId) {
            let shouldAllowStrongOverride = (
                result.billSource != .unknown ||
                result.categoryKey == nil
            )

            if enhanced.categoryKey == nil {
                enhanced.categoryKey = ruleCategoryKey
            } else if bestMatch.matchScore >= categoryStrongOverrideThreshold, shouldAllowStrongOverride {
                enhanced.categoryKey = ruleCategoryKey
            }
        }

        return enhanced
    }

    // MARK: - Platform Candidate Selection

    /// AChai风格：专用解析器可能返回多个候选，按上下文选择最可能是“本次支付额”的一笔。
    private func selectBestPlatformTransaction(
        from candidates: [ParsedTransaction],
        fullText: String,
        source: BillSource,
        ocrLines: [OCRTextLine]? = nil
    ) -> ParsedTransaction? {
        guard !candidates.isEmpty else { return nil }

        let normalized = normalizeRecognizedText(cleanRecognizedText(fullText))
        let amountContextLines = buildAmountContextLines(
            normalizedText: normalized,
            ocrLines: ocrLines
        )

        let scored = candidates.enumerated().map { index, candidate in
            (
                transaction: candidate,
                score: platformTransactionScore(
                    candidate,
                    index: index,
                    amountContextLines: amountContextLines,
                    normalizedText: normalized,
                    source: source
                )
            )
        }

        let best = scored.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            let leftAmount = lhs.transaction.amount ?? 0
            let rightAmount = rhs.transaction.amount ?? 0
            return leftAmount < rightAmount
        }

        return best?.transaction
    }

    private func platformTransactionScore(
        _ transaction: ParsedTransaction,
        index: Int,
        amountContextLines: [AmountContextLine],
        normalizedText: String,
        source: BillSource
    ) -> Int {
        guard let amount = transaction.amount, amount > 0 else { return Int.min / 2 }

        var score = 100
        score += max(0, 16 - index * 3) // 优先保留专用解析器前排候选

        if transaction.status == 1 { score += 24 }
        if transaction.status == 2 { score -= 45 }
        if transaction.ruleKind != nil { score += 8 }

        if let merchant = transaction.merchantName,
           isLikelyMerchant(merchant) {
            score += 16
        } else if let toBiz = transaction.toBiz,
                  isLikelyMerchant(toBiz) {
            score += 14
        }

        if let note = transaction.note, isMeaningfulNote(note) {
            score += 6
        }

        if transaction.fundName != nil {
            score += 4
        }
        if transaction.date != nil || transaction.transactionTime != nil {
            score += 4
        }

        if let original = transaction.originalMoney,
           original > 0 {
            let hasDiscount = (transaction.discountMoney ?? 0) > 0
            let expectedNet = max(0, ((original - (transaction.discountMoney ?? 0)) * 100).rounded() / 100)

            if hasDiscount && abs(expectedNet - amount) < 0.02 {
                score += 36
            } else if abs(original - amount) < 0.02 && hasDiscount {
                score -= 16 // 更像原价，不像实际支付额
            }
        }

        if let discount = transaction.discountMoney,
           discount > 0,
           abs(discount - amount) < 0.02 {
            score -= 70
        }

        let lineScores = amountContextLines
            .filter { lineContainsApproxAmount($0.text, amount: amount) }
            .map { scoreForAmountContextLine($0, amount: amount) }

        if lineScores.isEmpty {
            score -= 10
        } else if let bestLineScore = lineScores.max() {
            score += bestLineScore
        }

        if source == .wechatPay,
           normalizedText.contains("零钱") || normalizedText.contains("零钱通"),
           transaction.fundName?.isEmpty != false {
            score += 3
        }

        return score
    }

    private func scoreForAmountContextLine(_ contextLine: AmountContextLine, amount: Double) -> Int {
        let line = contextLine.text
        let lineIndex = contextLine.lineIndex
        let totalLines = contextLine.totalLines
        var score = 0

        if Self.settlementContextKeywords.contains(where: { line.contains($0) }) {
            score += 30
        }
        if line.contains("交易成功") || line.contains("支付成功") {
            score += 12
        }
        if Self.discountKeywords.contains(where: { line.contains($0) }) {
            score -= 55
        }
        if Self.summaryContextKeywords.contains(where: { line.contains($0) }) {
            score -= 70
        }
        if Self.orderContextKeywords.contains(where: { line.contains($0) }) {
            score -= 18
        }

        if lineIndex <= max(2, totalLines / 8),
           line.range(of: "[-+−]?\\s*[¥￥]?\\s*\\d+\\.\\d{2}", options: .regularExpression) != nil {
            score += 10
        }

        if contextLine.columnCount >= 2 {
            score += 8
        }
        if contextLine.columnCount >= 3 {
            score += 3
        }
        if hasRightAlignedAmount(in: contextLine, amount: amount) {
            score += 14
            if Self.settlementContextKeywords.contains(where: { line.contains($0) }) {
                score += 6
            }
        }

        // 只包含金额而无其他上下文时，减少优先级（通常是杂讯行）
        let stripped = line
            .replacingOccurrences(of: "[¥￥+\\-−0-9\\.,\\s]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty {
            score -= 6
        }

        if amount >= 100000 {
            score -= 20
        }

        return score
    }

    private func buildAmountContextLines(
        normalizedText: String,
        ocrLines: [OCRTextLine]?
    ) -> [AmountContextLine] {
        if let ocrLines, !ocrLines.isEmpty {
            var items: [(text: String, observations: [OCRTextObservation])] = []
            items.reserveCapacity(ocrLines.count)

            for rawLine in ocrLines {
                let cleaned = normalizeRecognizedText(rawLine.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                items.append((text: cleaned, observations: rawLine.observations))
            }

            if !items.isEmpty {
                let total = items.count
                return items.enumerated().map { index, item in
                    AmountContextLine(
                        text: item.text,
                        lineIndex: index,
                        totalLines: total,
                        columnCount: inferColumnCount(
                            for: item.text,
                            observations: item.observations
                        ),
                        observations: item.observations
                    )
                }
            }
        }

        let fallbackLines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let total = fallbackLines.count

        return fallbackLines.enumerated().map { index, line in
            AmountContextLine(
                text: line,
                lineIndex: index,
                totalLines: total,
                columnCount: inferColumnCount(for: line, observations: []),
                observations: []
            )
        }
    }

    private func inferColumnCount(
        for line: String,
        observations: [OCRTextObservation]
    ) -> Int {
        if observations.count >= 2 {
            let sorted = observations.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let widths = sorted.map { max(0.001, $0.boundingBox.width) }.sorted()
            let medianWidth = widths[widths.count / 2]
            let gapThreshold = max(0.025, min(0.08, medianWidth * 0.8))

            var columns = 1
            for (lhs, rhs) in zip(sorted, sorted.dropFirst()) {
                let gap = rhs.boundingBox.minX - lhs.boundingBox.maxX
                if gap > gapThreshold {
                    columns += 1
                }
            }

            if columns == 1 && (line.contains("：") || line.contains(":")) {
                columns = 2
            }
            return min(4, max(1, columns))
        }

        if line.contains("：") || line.contains(":") {
            return 2
        }
        if line.range(of: "\\S+\\s+[¥￥]?\\s*[-+−]?\\d+(?:[\\.,]\\d{1,2})?$", options: .regularExpression) != nil {
            return 2
        }
        return 1
    }

    private func hasRightAlignedAmount(in contextLine: AmountContextLine, amount: Double) -> Bool {
        if contextLine.observations.isEmpty {
            if contextLine.text.range(of: "[:：]\\s*[-+−]?\\s*[¥￥]?\\s*\\d+(?:[\\.,]\\d{1,2})?\\s*$", options: .regularExpression) != nil {
                return true
            }
            if contextLine.text.range(of: "\\S+\\s{1,}[¥￥]?\\s*[-+−]?\\d+(?:[\\.,]\\d{1,2})?\\s*$", options: .regularExpression) != nil {
                return true
            }
            return false
        }

        let sorted = contextLine.observations.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let leftMostX = sorted.first?.boundingBox.minX ?? 0
        let matchingAmountObservations = sorted.filter { observation in
            let text = normalizeRecognizedText(observation.text)
            return extractLineAmounts(from: text).contains { abs($0 - amount) < 0.02 }
        }

        guard !matchingAmountObservations.isEmpty else {
            return false
        }

        for amountObservation in matchingAmountObservations {
            if amountObservation.boundingBox.maxX >= 0.72 || amountObservation.boundingBox.minX >= 0.55 {
                return true
            }
            if let last = sorted.last,
               abs(amountObservation.boundingBox.maxX - last.boundingBox.maxX) < 0.01,
               amountObservation.boundingBox.minX - leftMostX > 0.18 {
                return true
            }
        }
        return false
    }

    private func lineContainsApproxAmount(_ line: String, amount: Double) -> Bool {
        extractLineAmounts(from: line).contains { abs($0 - amount) < 0.02 }
    }

    private func extractLineAmounts(from line: String) -> [Double] {
        let pattern = "[-+−]?\\s*[¥￥]?\\s*([0-9]+(?:[\\.,][0-9]{1,2})?)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, options: [], range: range).compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: line) else { return nil }
            return sanitizeAmount(String(line[numberRange]))
        }
    }

    // MARK: - OCR Result Parsing

    func parse(_ ocrResult: OCRResult) -> [ParsedTransaction] {
        let cleanedText = cleanRecognizedText(ocrResult.fullText)
        let fullText = normalizeRecognizedText(cleanedText)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let billSource = BillSource.detect(from: fullText)
        var candidates = platformCandidatesFromOCR(ocrResult, detectedSource: billSource)

        if let genericCandidate = buildGenericOCRCandidate(
            from: ocrResult,
            normalizedFullText: fullText,
            billSource: billSource
        ), shouldAppendGenericCandidate(genericCandidate, to: candidates) {
            candidates.append(genericCandidate)
        }

        return rankAndEnhanceCandidates(
            candidates,
            fullText: fullText,
            fallbackSource: billSource,
            ocrResult: ocrResult
        )
    }

    // MARK: - Spatial Amount Extraction

    private func extractAmountSpatial(from lines: [StructuredLine]) -> AmountParseResult? {
        guard !lines.isEmpty else { return nil }
        var candidates: [AmountCandidate] = []

        for (lineIndex, line) in lines.enumerated() {
            let keywordScore = strongestAmountKeywordScore(in: line.cleanedText)
            guard keywordScore > 0 else { continue }

            // AChai-style: prefer nearby rows around the key line.
            let searchIndices = [lineIndex, lineIndex + 1, lineIndex + 2]
            let proximityScores = [30, 16, 8]

            for (offset, idx) in searchIndices.enumerated() {
                guard idx < lines.count else { continue }
                let searchText = lines[idx].cleanedText
                let lineCandidates = extractCandidates(
                    in: searchText,
                    pattern: Self.twoDecimalAmountPattern,
                    score: keywordScore + proximityScores[offset],
                    applyFallbackFilter: false
                )
                candidates.append(contentsOf: lineCandidates)

                let currencyCandidates = extractCandidates(
                    in: searchText,
                    pattern: Self.currencyAmountPattern,
                    score: keywordScore + proximityScores[offset] + 6,
                    applyFallbackFilter: false
                )
                candidates.append(contentsOf: currencyCandidates)

                if !lineCandidates.isEmpty || !currencyCandidates.isEmpty { break }
            }
        }

        if candidates.isEmpty {
            // Fallback: collect signed/currency amounts from top lines, but weaker score.
            for line in lines.prefix(8) {
                // Skip lines that contain discount keywords
                if Self.discountKeywords.contains(where: { line.cleanedText.contains($0) }) {
                    continue
                }
                // Skip lines that contain monthly summary keywords
                if Self.monthlySummaryKeywords.contains(where: { line.cleanedText.contains($0) }) {
                    continue
                }
                candidates.append(contentsOf: extractCandidates(
                    in: line.cleanedText,
                    pattern: Self.signedAmountPattern,
                    score: 72,
                    applyFallbackFilter: false
                ))
                candidates.append(contentsOf: extractCandidates(
                    in: line.cleanedText,
                    pattern: Self.currencyAmountPattern,
                    score: 68,
                    applyFallbackFilter: false
                ))
            }
        }

        guard !candidates.isEmpty else { return nil }

        let best = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.location < $1.location
        }.first

        guard let best else { return nil }
        return AmountParseResult(value: best.value, sign: best.sign)
    }

    private func strongestAmountKeywordScore(in text: String) -> Int {
        // Skip lines that contain discount keywords — they are not settlement amounts.
        if Self.discountKeywords.contains(where: { text.contains($0) }) {
            return 0
        }
        if Self.monthlySummaryKeywords.contains(where: { text.contains($0) }) {
            return 0
        }
        var best = 0
        for (keyword, score) in Self.amountKeywordScores where text.contains(keyword) {
            best = max(best, score)
        }
        return best
    }

    private func setupStructuredLines(from ocrResult: OCRResult) -> [StructuredLine] {
        var result: [StructuredLine] = []
        for (idx, rawLine) in ocrResult.lines.enumerated() {
            let cleaned = normalizeRecognizedText(rawLine.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard !isBlacklistText(cleaned) else { continue }
            result.append(StructuredLine(text: rawLine.text, cleanedText: cleaned, rowIndex: idx))
        }
        return result
    }

    private func isBlacklistText(_ text: String) -> Bool {
        if text.range(of: "^[\\-_=~•·\\s]+$", options: .regularExpression) != nil {
            return true
        }
        if text.count <= 1 {
            return true
        }
        for snippet in Self.blacklistSnippets where text.contains(snippet) {
            return true
        }
        return false
    }

    // MARK: - Enhanced Date + Time Extraction

    private func extractDateTime(from text: String) -> (date: Date?, time: Date?) {
        let normalized = normalizeRecognizedText(text)

        // Extract time first: HH:mm:ss or HH:mm
        var extractedHour: Int?
        var extractedMinute: Int?
        let timePatterns = [
            "(\\d{1,2})\\s*[：:]\\s*(\\d{2})\\s*[：:]\\s*(\\d{2})",  // HH:mm:ss
            "(\\d{1,2})\\s*[：:]\\s*(\\d{2})",                          // HH:mm
        ]
        for (_, tp) in timePatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: tp) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            if let match = regex.firstMatch(in: normalized, options: [], range: range),
               let hour = captureInt(match, at: 1, in: normalized),
               let minute = captureInt(match, at: 2, in: normalized),
               (0...23).contains(hour), (0...59).contains(minute) {
                // Skip if this looks like a date component (year too large)
                if hour > 23 { continue }
                extractedHour = hour
                extractedMinute = minute
                break
            }
        }

        // Relative time overrides
        let calendar = Calendar.current
        let now = Date()
        if normalized.contains("刚刚") || normalized.contains("刚才") {
            return (now, now)
        }
        if normalized.contains("昨天"),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            let date = combineDateTime(date: yesterday, hour: extractedHour, minute: extractedMinute)
            return (date, date)
        }
        if normalized.contains("前天"),
           let dayBefore = calendar.date(byAdding: .day, value: -2, to: now) {
            let date = combineDateTime(date: dayBefore, hour: extractedHour, minute: extractedMinute)
            return (date, date)
        }

        // X分钟前 / X小时前
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*分钟前"),
           let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let mins = captureInt(match, at: 1, in: normalized),
           let agoDate = calendar.date(byAdding: .minute, value: -mins, to: now) {
            return (agoDate, agoDate)
        }
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*小时前"),
           let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let hours = captureInt(match, at: 1, in: normalized),
           let agoDate = calendar.date(byAdding: .hour, value: -hours, to: now) {
            return (agoDate, agoDate)
        }

        // Extract date using existing logic
        let date = extractDate(from: text)

        // Combine date + time if both found
        if let date {
            let combined = combineDateTime(date: date, hour: extractedHour, minute: extractedMinute)
            return (combined, combined)
        }

        // Time only (today + time)
        if extractedHour != nil {
            let combined = combineDateTime(date: now, hour: extractedHour, minute: extractedMinute)
            return (nil, combined)
        }

        return (nil, nil)
    }

    private func combineDateTime(date: Date, hour: Int?, minute: Int?) -> Date {
        guard let hour, let minute else { return date }
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps) ?? date
    }

    // MARK: - Merchant Name Extraction

    private static let skipKeywords: Set<String> = {
        var keywords: Set<String> = [
        "微信支付", "支付宝", "支付成功", "交易成功", "付款成功",
        "收款方", "付款方", "商品说明", "交易单号", "商户单号",
        "实付", "应付", "合计", "总计", "金额", "日期", "时间",
        "账单", "订单", "凭证", "详情", "退款", "转账", "今日支出", "今日结余", "NO.",
        "备注", "附言", "用途", "备注信息", "订单备注",
        "支付时间", "交易时间", "付款方式", "收款方全称",
        "账单分类", "标签", "请选择", "更多", "极速付款", "管理极速付款",
        "统计支出", "月统计", "月支出", "支付奖励", "积分"
        ]
        keywords.formUnion(OCRSemanticFilter.navigationNoiseKeywords)
        keywords.formUnion(OCRSemanticFilter.statusBarNoiseKeywords)
        return keywords
    }()

    private func extractMerchantFromRawText(_ text: String, source: BillSource) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { StructuredLine(text: $0.element, cleanedText: normalizeRecognizedText($0.element), rowIndex: $0.offset) }
        return extractMerchant(from: lines, fullText: text, source: source)
    }

    private func extractMerchant(from lines: [StructuredLine], fullText: String, source: BillSource) -> String? {
        switch source {
        case .wechatPay:
            for line in lines {
                let text = line.cleanedText
                if isLikelyMerchant(text) {
                    return text
                }
            }
        case .alipay:
            for (i, line) in lines.enumerated() {
                if line.cleanedText.contains("收款方"), i + 1 < lines.count {
                    let candidate = lines[i + 1].cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isLikelyMerchant(candidate) {
                        return candidate
                    }
                }
            }
            for line in lines {
                let text = line.cleanedText
                if isLikelyMerchant(text) {
                    return text
                }
            }
        default:
            break
        }

        // AChai-like: merchant is often the nearest text line above the header amount.
        if let nearHeader = extractMerchantNearHeaderAmount(from: lines) {
            return nearHeader
        }

        // Generic heuristic: first meaningful top-half line.
        let upperHalfThreshold = max(lines.count / 2, 1)
        for line in lines {
            guard line.rowIndex <= upperHalfThreshold else { continue }
            let text = line.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isLikelyMerchant(text) {
                return text
            }
        }

        // Last fallback from full text.
        if let firstMeaningful = fullText
            .components(separatedBy: .newlines)
            .map({ cleanedForNote($0) })
            .first(where: { isLikelyMerchant($0) }) {
            return firstMeaningful
        }

        // Label fallback: some providers only expose merchant in labeled fields.
        if let byLabel = extractLabelValue(from: lines, labels: Self.merchantLabels),
           isLikelyMerchant(byLabel) {
            return byLabel
        }

        return nil
    }

    private func extractMerchantNearHeaderAmount(from lines: [StructuredLine]) -> String? {
        guard let amountIndex = lines.firstIndex(where: { isHeaderAmountLine($0.cleanedText) }) else {
            return nil
        }

        let candidateOffsets = [-1, -2, 1]
        for offset in candidateOffsets {
            let idx = amountIndex + offset
            guard idx >= 0, idx < lines.count else { continue }
            let candidate = lines[idx].cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isLikelyMerchant(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isHeaderAmountLine(_ text: String) -> Bool {
        if text.range(of: Self.signedAmountPattern, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: "^[-+−]?\\s*[¥￥]?\\s*\\d+\\.\\d{2}$", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func isLikelyMerchant(_ text: String) -> Bool {
        let normalized = OCRSemanticFilter.normalize(text)
        guard (2...28).contains(normalized.count) else { return false }
        guard OCRSemanticFilter.isLikelyMerchantText(normalized) else { return false }
        // Skip lines that are pure numbers
        if normalized.range(of: "^\\d+$", options: .regularExpression) != nil { return false }
        if looksLikeDateOrTime(normalized) { return false }
        // Skip keyword lines
        for kw in Self.skipKeywords {
            if normalized.contains(kw) { return false }
        }
        // Skip lines that look like amounts
        if normalized.range(of: "^[¥￥]?\\d+\\.\\d{2}$", options: .regularExpression) != nil { return false }
        // Merchant should include at least one letter-like character (Chinese/Latin/etc).
        let hasLetter = normalized.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        if !hasLetter { return false }
        // Skip lines that are mostly punctuation
        let alphaNumCount = normalized.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        if alphaNumCount < max(1, normalized.count / 3) { return false }
        return true
    }

    // MARK: - Note Building

    private func buildSmartNote(explicitRemark: String?, merchant: String?, fallbackText: String) -> String? {
        // 1. 最高优先级：明确的备注标签值（由调用方从 label 提取）
        if let explicitRemark, isMeaningfulNote(explicitRemark) {
            return String(cleanedForNote(explicitRemark).prefix(40))
        }

        // 2. 不用 merchant 当 note fallback（merchant 和 note 是不同字段）
        // 3. fallback 只取含中文、不在黑名单、不是纯标签行的行
        let skipLabels = Self.remarkLabels + ["收款方", "商户", "商户名称", "店铺", "商家",
                                               "付款方", "对方", "交易对象", "交易时间", "支付时间",
                                               "支付金额", "订单金额", "实付", "应付", "合计"]
        let lines = fallbackText.components(separatedBy: .newlines).map { cleanedForNote($0) }
        for line in lines {
            guard isMeaningfulNote(line) else { continue }
            // 跳过纯标签行
            if skipLabels.contains(where: { line == $0 }) { continue }
            // 必须含中文，避免把英文/数字噪音误识别为备注
            let hasChinese = line.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            if !hasChinese { continue }
            // 不能与 merchant 完全相同（避免重复）
            if let merchant, cleanedForNote(merchant) == line { continue }
            return String(line.prefix(40))
        }

        return nil
    }
}

final class ProductionTransactionParserService: TransactionParserServiceProtocol {
    func parse(_ text: String) -> [ParsedTransaction] {
        MockTransactionParserService().parse(text)
    }

    func parse(_ ocrResult: OCRResult) -> [ParsedTransaction] {
        MockTransactionParserService().parse(ocrResult)
    }
}
