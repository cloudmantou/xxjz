import Foundation

/// 自动记账规则引擎
/// 实现AChai的三层规则匹配: autoBillRules / commomRules / localRules
final class AutoBillRuleEngine {

    static let shared = AutoBillRuleEngine()

    // MARK: - Rule Tiers

    /// 三层规则
    private var autoRules: [KeywordRule] = []     // 服务端自动规则
    private var commonRules: [KeywordRule] = []   // 通用规则
    private var localRules: [KeywordRule] = []    // 本地用户规则
    private var injectedCategoryMapping: [Int: String] = [:]

    private static let defaultCategoryMapping: [Int: String] = [
        1: "dining",
        2: "transport",
        3: "shopping",
        4: "entertainment",
        5: "housing",
        6: "utilities",
        7: "medical",
        8: "education",
        100: "salary",
        101: "investment",
        102: "refund",
        103: "redpacket_income",
        200: "transfer",
    ]
    private static let categoryMappingConfigKeys = [
        "RULE_MEMBER_CATE_MAPPING_JSON",
        "RuleMemberCateMappingJSON",
        "ruleUpdate.memberCateMappingJSON"
    ]

    // MARK: - Initialization

    private init() {
        loadRulesFromSQLite()

        // 监听规则更新通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rulesDidUpdate),
            name: .keywordRulesDidActivate,
            object: nil
        )
    }

    @objc private func rulesDidUpdate() {
        loadRulesFromSQLite()
    }

    private func loadRulesFromSQLite() {
        var merged: [Int: KeywordRule] = [:]
        let currentMemberId = normalizedCurrentMemberId()

        // 1) 先加载SQLite（表驱动为主）
        let sqliteRules = KeywordRulesTable.shared.fetchRulesForMatching(memberId: currentMemberId)
        for rule in sqliteRules {
            merged[rule.ruleId] = hydrateRule(rule)
        }

        // 2) 再加载缓存规则（仅用于补缺，不覆盖SQLite）
        let cachedRules = filterRulesForCurrentMember(
            RuleUpdateService.shared.currentRules,
            memberId: currentMemberId
        )
        for rule in cachedRules {
            let hydrated = hydrateRule(rule)
            if merged[hydrated.ruleId] == nil {
                merged[hydrated.ruleId] = hydrated
                continue
            }

            // 仅在SQLite规则缺失searchTexts时，用缓存补齐。
            if let existing = merged[hydrated.ruleId],
               (existing.searchTexts?.isEmpty ?? true),
               let cachedSearchTexts = hydrated.searchTexts,
               !cachedSearchTexts.isEmpty {
                var patched = existing
                patched.searchTexts = cachedSearchTexts
                merged[hydrated.ruleId] = patched
            }
        }

        // 3) 都没有时，拉起默认规则
        if merged.isEmpty {
            RuleUpdateService.shared.loadDefaultRules()
            for rule in filterRulesForCurrentMember(
                RuleUpdateService.shared.currentRules,
                memberId: currentMemberId
            ) {
                merged[rule.ruleId] = hydrateRule(rule)
            }
        }

        let allRules = merged.values.sorted { $0.ruleId < $1.ruleId }
        autoRules = allRules.filter { ruleKind(of: $0) == .auto }
        commonRules = allRules.filter { ruleKind(of: $0) == .common }
        localRules = allRules.filter { ruleKind(of: $0) == .local }
    }

    private func normalizedCurrentMemberId() -> String? {
        let keys = ["currentMemberId", "memberId", "userId"]
        for key in keys {
            guard let raw = UserDefaults.standard.string(forKey: key) else { continue }
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private func filterRulesForCurrentMember(
        _ rules: [KeywordRule],
        memberId: String?
    ) -> [KeywordRule] {
        guard let memberId, !memberId.isEmpty else {
            return rules.filter { rule in
                guard let owner = rule.memberId else { return true }
                return owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        return rules.filter { rule in
            guard let owner = rule.memberId else { return true }
            let normalized = owner.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty || normalized == memberId
        }
    }

    private func hydrateRule(_ rule: KeywordRule) -> KeywordRule {
        if let searchTexts = rule.searchTexts, !searchTexts.isEmpty {
            return rule
        }

        var hydrated = rule
        hydrated.searchTexts = [
            AutoBillSearchText(
                ruleId: rule.ruleId,
                ruleKind: inferredRuleKind(for: rule),
                billSource: inferredBillSource(for: rule),
                minMatchValue: 0,
                matchType: .contains,
                isFuzzy: true,
                isFuzzyLastValue: false,
                isOptional: false,
                isMutableLine: false,
                columnCount: 1,
                alignment: .automatic,
                candidateType: .textObservation,
                subCandidateType: 0
            )
        ]
        return hydrated
    }

    private func inferredBillSource(for rule: KeywordRule) -> RuleBillSource {
        switch rule.keyWordSource {
        case .aliAppear, .aliCredit, .aliIncome, .aliTransfer:
            return .alipay
        case .weAppear, .weCredit, .weIncome, .weTransfer:
            return .wechat
        }
    }

    private func inferredRuleKind(for rule: KeywordRule) -> RuleKind {
        if let memberId = rule.memberId, !memberId.isEmpty {
            return .local
        }
        return .auto
    }

    private func ruleKind(of rule: KeywordRule) -> RuleKind {
        rule.searchTexts?.first?.ruleKind ?? inferredRuleKind(for: rule)
    }

    private func emitRuleMatchDiagnostics(
        result: RuleMatchResult?,
        tierMatchCounts: [String: Int],
        billSource: BillSource
    ) {
        guard ProcessInfo.processInfo.environment["RULE_MATCH_DIAGNOSTICS"] == "1" else { return }
        if let result {
            print("[RuleMatch] source=\(billSource.rawValue) ruleId=\(result.rule.ruleId) kind=\(ruleKind(of: result.rule)) score=\(result.matchScore) tiers=\(tierMatchCounts)")
        } else {
            print("[RuleMatch] source=\(billSource.rawValue) no_match tiers=\(tierMatchCounts)")
        }
    }

    // MARK: - Public Matching Interface

    /// 对OCR结果进行规则匹配
    /// - Parameters:
    ///   - ocrResult: OCR识别结果
    ///   - billSource: 账单来源
    ///   - amount: 识别到的金额
    /// - Returns: 匹配结果列表，按分数排序
    func matchRules(
        for ocrResult: OCRResult,
        billSource: BillSource,
        amount: Double?
    ) -> [RuleMatchResult] {
        var allMatches: [RuleMatchResult] = []
        var tierMatchCounts: [String: Int] = [:]

        // 按优先级尝试三层规则: local > common > auto
        let ruleTiers: [(rules: [KeywordRule], kind: RuleKind)] = [
            (localRules, .local),
            (commonRules, .common),
            (autoRules, .auto)
        ]

        for (rules, kind) in ruleTiers {
            let tierMatches = matchRulesTier(
                rules: rules,
                against: ocrResult,
                billSource: billSource,
                amount: amount
            )
            allMatches.append(contentsOf: tierMatches)
            tierMatchCounts[String(describing: kind)] = tierMatches.count
        }

        // 按分数排序
        let sorted = allMatches.sorted { $0.matchScore > $1.matchScore }
        emitRuleMatchDiagnostics(result: sorted.first, tierMatchCounts: tierMatchCounts, billSource: billSource)
        return sorted
    }

    /// 对文本进行规则匹配
    func matchRules(
        for text: String,
        billSource: BillSource,
        amount: Double?
    ) -> [RuleMatchResult] {
        let observations = [
            OCRTextObservation(text: text, confidence: 1.0, boundingBox: .zero)
        ]
        let lines = [
            OCRTextLine(text: text, observations: observations, yMidpoint: 0)
        ]
        let ocrResult = OCRResult(fullText: text, observations: observations, lines: lines)
        return matchRules(for: ocrResult, billSource: billSource, amount: amount)
    }

    // MARK: - Private Matching Logic

    private func matchRulesTier(
        rules: [KeywordRule],
        against ocrResult: OCRResult,
        billSource: BillSource,
        amount: Double?
    ) -> [RuleMatchResult] {
        var matches: [RuleMatchResult] = []

        for rule in rules {
            if let searchTexts = rule.searchTexts, !searchTexts.isEmpty {
                // AChai风格：rule 下可包含多个 searchText，按可选项/必选项综合匹配
                let sourceMatch = searchTexts.contains {
                    matchBillSource(ruleSource: $0.billSource, actualSource: billSource)
                }
                if !sourceMatch { continue }

                let minMatchValue = searchTexts.map(\.minMatchValue).max() ?? 0
                if minMatchValue > 0,
                   let actualAmount = amount,
                   actualAmount < minMatchValue {
                    continue
                }

                if let result = matchKeywords(
                    rule: rule,
                    searchTexts: searchTexts,
                    against: ocrResult
                ) {
                    matches.append(result)
                }
            } else {
                // 无searchText时，直接用keyWord匹配
                if let result = matchKeywordDirect(rule: rule, against: ocrResult) {
                    matches.append(result)
                }
            }
        }

        return matches
    }

    private func matchKeywords(
        rule: KeywordRule,
        searchTexts: [AutoBillSearchText],
        against ocrResult: OCRResult
    ) -> RuleMatchResult? {
        let ordered = orderedSearchTexts(searchTexts)
        var collected: [MatchedCandidate] = []
        var previousLine: Int?

        let lastRequiredIndex = ordered.lastIndex(where: { !$0.isOptional }) ?? (ordered.count - 1)

        for (position, searchText) in ordered.enumerated() {
            let matches = matchedCandidates(rule: rule, searchText: searchText, against: ocrResult)
            if matches.isEmpty {
                if searchText.isOptional {
                    continue
                }
                return nil
            }

            let preferLast = searchText.isFuzzyLastValue || (position >= lastRequiredIndex && searchText.isFuzzy)
            guard let selected = chooseBestCandidate(
                from: matches,
                searchText: searchText,
                previousLine: previousLine,
                preferLast: preferLast
            ) else {
                if searchText.isOptional {
                    continue
                }
                return nil
            }

            collected.append(selected)
            if selected.candidate.lineIndex >= 0 {
                previousLine = selected.candidate.lineIndex
            }
        }

        guard !collected.isEmpty else { return nil }

        let scoreSum = collected.reduce(0) { $0 + $1.score }
        let avgScore = scoreSum / Float(collected.count)
        let requiredCount = max(1, ordered.filter { !$0.isOptional }.count)
        let coverage = min(1.0, Float(collected.count) / Float(requiredCount))
        let sequenceBonus = sequenceContinuityBonus(for: collected)
        let combinedScore = min(1.0, avgScore * 0.72 + coverage * 0.18 + sequenceBonus * 0.10)
        let mergedMatchedText = collected.map(\.matchedText).joined(separator: " | ")
        let isFuzzy = collected.contains { $0.isFuzzy }

        return RuleMatchResult(
            rule: rule,
            matchedText: mergedMatchedText,
            matchScore: combinedScore,
            isFuzzyMatch: isFuzzy
        )
    }

    private func orderedSearchTexts(_ searchTexts: [AutoBillSearchText]) -> [AutoBillSearchText] {
        searchTexts.enumerated().sorted { lhs, rhs in
            let leftIndex = lhs.element.index
            let rightIndex = rhs.element.index
            if leftIndex != rightIndex {
                return leftIndex < rightIndex
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func sequenceContinuityBonus(for candidates: [MatchedCandidate]) -> Float {
        guard candidates.count >= 2 else { return 0.6 }

        var transitions = 0
        var forwardTransitions = 0
        var sameLineTransitions = 0

        for (lhs, rhs) in zip(candidates, candidates.dropFirst()) {
            let previous = lhs.candidate.lineIndex
            let current = rhs.candidate.lineIndex
            guard previous >= 0, current >= 0 else { continue }

            transitions += 1
            if current >= previous {
                forwardTransitions += 1
            }
            if current == previous {
                sameLineTransitions += 1
            }
        }

        guard transitions > 0 else { return 0.6 }
        let forwardRatio = Float(forwardTransitions) / Float(transitions)
        let sameLineBonus = min(0.2, Float(sameLineTransitions) * 0.04)
        return min(1.0, max(0.0, forwardRatio + sameLineBonus))
    }

    private func matchedCandidates(
        rule: KeywordRule,
        searchText: AutoBillSearchText,
        against ocrResult: OCRResult
    ) -> [MatchedCandidate] {
        let keyword = normalizedKeyword(for: searchText, fallback: rule.keyWord)
        guard !keyword.isEmpty else { return [] }

        let candidates = candidateTexts(for: searchText.candidateType, from: ocrResult)
        guard !candidates.isEmpty else { return [] }

        var matches: [MatchedCandidate] = []

        for candidate in candidates {
            let currentMatch = evaluateMatch(
                text: candidate.text,
                pattern: keyword,
                searchText: searchText
            )
            guard currentMatch.matched else { continue }

            let boost = candidateBoost(searchText: searchText, candidate: candidate)
            let finalScore = min(1.0, currentMatch.score + boost)

            matches.append(
                MatchedCandidate(
                    candidate: candidate,
                    matchedText: currentMatch.matchedText ?? keyword,
                    score: finalScore,
                    isFuzzy: searchText.isFuzzy
                )
            )
        }

        return matches
    }

    private func chooseBestCandidate(
        from candidates: [MatchedCandidate],
        searchText: AutoBillSearchText,
        previousLine: Int?,
        preferLast: Bool
    ) -> MatchedCandidate? {
        guard !candidates.isEmpty else { return nil }

        let validLines = candidates
            .map(\.candidate.lineIndex)
            .filter { $0 >= 0 }
        let maxLineIndex = validLines.max() ?? 0
        let lineSpan = max(1, maxLineIndex)

        func rankingScore(for candidate: MatchedCandidate) -> Float {
            var score = candidate.score
            let lineIndex = candidate.candidate.lineIndex

            if let previousLine, lineIndex >= 0 {
                let lineDelta = lineIndex - previousLine

                if searchText.isMutableLine {
                    if lineDelta == 0 {
                        score += 0.10
                    } else if lineDelta > 0 {
                        score += max(0.0, 0.08 - Float(lineDelta) * 0.03)
                    } else {
                        // 可变行允许回溯，但给予轻微惩罚以避免抖动。
                        score -= min(0.10, Float(abs(lineDelta)) * 0.03)
                    }
                } else {
                    if lineDelta == 0 {
                        score += 0.16
                    } else if lineDelta > 0 {
                        score -= min(0.14, Float(lineDelta) * 0.06)
                    } else {
                        score -= min(0.20, 0.12 + Float(abs(lineDelta)) * 0.06)
                    }
                }
            } else if previousLine != nil && lineIndex < 0 {
                score -= 0.08
            }

            if lineIndex >= 0 {
                let normalizedLine = Float(lineIndex) / Float(lineSpan)
                if preferLast {
                    score += normalizedLine * 0.18
                } else {
                    score += (1 - normalizedLine) * 0.04
                }
            } else if preferLast {
                score -= 0.02
            }

            if preferLast {
                score += Float(candidate.candidate.sourceOrder) * 0.0006
            }

            return score
        }

        return candidates.max { lhs, rhs in
            let lhsScore = rankingScore(for: lhs)
            let rhsScore = rankingScore(for: rhs)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            let lhsLine = lhs.candidate.lineIndex
            let rhsLine = rhs.candidate.lineIndex
            if lhsLine != rhsLine {
                return preferLast ? lhsLine < rhsLine : lhsLine > rhsLine
            }

            return preferLast
                ? lhs.candidate.sourceOrder < rhs.candidate.sourceOrder
                : lhs.candidate.sourceOrder > rhs.candidate.sourceOrder
        }
    }

    private func normalizedKeyword(for searchText: AutoBillSearchText, fallback: String) -> String {
        let key = searchText.key?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty {
            return key
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evaluateMatch(
        text: String,
        pattern: String,
        searchText: AutoBillSearchText
    ) -> FuzzyTextMatcher.FuzzyMatchResult {
        switch searchText.matchType {
        case .exact:
            return exactMatch(text: text, pattern: pattern, fuzzy: searchText.isFuzzy)
        case .contains:
            return containsMatch(text: text, pattern: pattern, fuzzy: searchText.isFuzzy)
        case .prefix:
            return prefixMatch(text: text, pattern: pattern, fuzzy: searchText.isFuzzy)
        case .regex:
            return regexMatch(text: text, pattern: pattern)
        }
    }

    private func candidateBoost(
        searchText: AutoBillSearchText,
        candidate: CandidateTextContext
    ) -> Float {
        var boost: Float = 0

        if searchText.candidateType == .keyObservation {
            if candidate.isKeyValueLike {
                boost += 0.08
            }
            if candidate.columnCount > 1 {
                boost += 0.04
            }
        }

        if searchText.columnCount > 1 {
            if candidate.columnCount >= searchText.columnCount {
                boost += 0.08
            } else {
                boost -= 0.06
            }
        }

        boost += alignmentBoost(expected: searchText.alignment, actual: candidate.alignment)
        return boost
    }

    private func matchBillSource(
        ruleSource: RuleBillSource,
        actualSource: BillSource
    ) -> Bool {
        switch ruleSource {
        case .generic:
            return true  // 通用规则匹配所有来源
        case .wechat:
            return actualSource == .wechatPay
        case .alipay:
            return actualSource == .alipay
        case .unknown:
            return true
        }
    }

    private func matchKeyword(
        rule: KeywordRule,
        searchText: AutoBillSearchText,
        against ocrResult: OCRResult
    ) -> RuleMatchResult? {
        let keyword = rule.keyWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }

        var patchedSearchText = searchText
        let key = patchedSearchText.key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty {
            patchedSearchText.key = keyword
        }

        let candidates = matchedCandidates(
            rule: rule,
            searchText: patchedSearchText,
            against: ocrResult
        )
        guard let bestMatch = chooseBestCandidate(
            from: candidates,
            searchText: patchedSearchText,
            previousLine: nil,
            preferLast: patchedSearchText.isFuzzyLastValue
        ) else {
            return nil
        }

        return RuleMatchResult(
            rule: rule,
            matchedText: bestMatch.matchedText,
            matchScore: bestMatch.score,
            isFuzzyMatch: bestMatch.isFuzzy
        )
    }

    private struct CandidateTextContext {
        let text: String
        let lineIndex: Int
        let sourceOrder: Int
        let columnCount: Int
        let alignment: SearchAlignment
        let isKeyValueLike: Bool
    }

    private struct MatchedCandidate {
        let candidate: CandidateTextContext
        let matchedText: String
        let score: Float
        let isFuzzy: Bool
    }

    private func alignmentBoost(expected: SearchAlignment, actual: SearchAlignment) -> Float {
        switch expected {
        case .automatic, .either:
            return 0
        case .left:
            if actual == .left || actual == .either { return 0.05 }
            if actual == .right { return -0.05 }
            return 0
        case .right:
            if actual == .right || actual == .either { return 0.05 }
            if actual == .left { return -0.05 }
            return 0
        }
    }

    private func candidateTexts(
        for candidateType: CandidateType,
        from ocrResult: OCRResult
    ) -> [CandidateTextContext] {
        switch candidateType {
        case .textObservation:
            return [
                CandidateTextContext(
                    text: ocrResult.fullText,
                    lineIndex: -1,
                    sourceOrder: 0,
                    columnCount: 1,
                    alignment: .either,
                    isKeyValueLike: false
                )
            ]
        case .keyObservation:
            var candidates: [CandidateTextContext] = []
            var sourceOrder = 0

            for (lineIndex, line) in ocrResult.lines.enumerated() {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let columnCount = estimateColumnCount(for: line)
                let lineAlignment = inferAlignment(for: line)
                let isKeyValueLike = text.contains("：") || text.contains(":")

                candidates.append(
                    CandidateTextContext(
                        text: text,
                        lineIndex: lineIndex,
                        sourceOrder: sourceOrder,
                        columnCount: columnCount,
                        alignment: lineAlignment,
                        isKeyValueLike: isKeyValueLike
                    )
                )
                sourceOrder += 1

                // 常见 OCR 键值格式: "收款方: 星巴克"
                if let splitIndex = text.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                    let key = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(text[text.index(after: splitIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty {
                        candidates.append(
                            CandidateTextContext(
                                text: key,
                                lineIndex: lineIndex,
                                sourceOrder: sourceOrder,
                                columnCount: max(1, columnCount),
                                alignment: .left,
                                isKeyValueLike: true
                            )
                        )
                        sourceOrder += 1
                    }
                    if !value.isEmpty {
                        let valueAlignment: SearchAlignment =
                            value.range(of: "[-+−]?\\s*[¥￥]?\\s*\\d+(?:[\\.,]\\d{1,2})?$", options: .regularExpression) != nil
                            ? .right
                            : lineAlignment
                        candidates.append(
                            CandidateTextContext(
                                text: value,
                                lineIndex: lineIndex,
                                sourceOrder: sourceOrder,
                                columnCount: max(2, columnCount),
                                alignment: valueAlignment,
                                isKeyValueLike: true
                            )
                        )
                        sourceOrder += 1
                    }
                }
            }

            if candidates.isEmpty {
                return [
                    CandidateTextContext(
                        text: ocrResult.fullText,
                        lineIndex: -1,
                        sourceOrder: 0,
                        columnCount: 1,
                        alignment: .either,
                        isKeyValueLike: false
                    )
                ]
            }

            // 去重（保留首个上下文，允许跨行重复文本参与候选重排）
            var seen: Set<String> = []
            var deduplicated: [CandidateTextContext] = []
            for candidate in candidates {
                let signature = "\(candidate.lineIndex)#\(candidate.text)#\(candidate.isKeyValueLike ? 1 : 0)"
                if seen.contains(signature) { continue }
                seen.insert(signature)
                deduplicated.append(candidate)
            }
            return deduplicated
        }
    }

    private func estimateColumnCount(for line: OCRTextLine) -> Int {
        if line.observations.count >= 2 {
            return min(3, line.observations.count)
        }
        let text = line.text
        if text.contains("：") || text.contains(":") {
            return 2
        }
        if text.range(of: "\\S+\\s+[¥￥]?[0-9]+(?:[\\.,][0-9]{1,2})?$", options: .regularExpression) != nil {
            return 2
        }
        return 1
    }

    private func inferAlignment(for line: OCRTextLine) -> SearchAlignment {
        let nonZeroBoxes = line.observations.map(\.boundingBox).filter { $0 != .zero }

        if !nonZeroBoxes.isEmpty {
            let minX = nonZeroBoxes.map(\.minX).min() ?? 0
            let maxX = nonZeroBoxes.map(\.maxX).max() ?? 0
            if minX > 0.45 || maxX > 0.82 {
                return .right
            }
            if minX < 0.25 {
                return .left
            }
        }

        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "[-+−]?\\s*[¥￥]?\\s*\\d+(?:[\\.,]\\d{1,2})?$", options: .regularExpression) != nil {
            return .right
        }
        if text.contains("：") || text.contains(":") {
            return .left
        }
        return .automatic
    }

    private func matchKeywordDirect(
        rule: KeywordRule,
        against ocrResult: OCRResult
    ) -> RuleMatchResult? {
        let text = ocrResult.fullText
        let keyword = rule.keyWord

        guard !keyword.isEmpty else { return nil }

        // 使用FuzzyTextMatcher进行包含匹配
        let result = FuzzyTextMatcher.fuzzyContains(
            text: text,
            pattern: keyword,
            config: .ocrBill
        )

        guard result.matched else { return nil }

        return RuleMatchResult(
            rule: rule,
            matchedText: result.matchedText ?? keyword,
            matchScore: result.score,
            isFuzzyMatch: true
        )
    }

    // MARK: - Match Strategies

    private func exactMatch(text: String, pattern: String, fuzzy: Bool) -> FuzzyTextMatcher.FuzzyMatchResult {
        if fuzzy {
            return FuzzyTextMatcher.fuzzyContains(text: text, pattern: pattern, config: .ocrBill)
        } else {
            let range = text.range(of: pattern)
            return FuzzyTextMatcher.FuzzyMatchResult(
                matched: range != nil,
                score: range != nil ? 1.0 : 0,
                depth: 0,
                matchedRange: range,
                matchedText: range.map { String(text[$0]) }
            )
        }
    }

    private func containsMatch(text: String, pattern: String, fuzzy: Bool) -> FuzzyTextMatcher.FuzzyMatchResult {
        if fuzzy {
            return FuzzyTextMatcher.fuzzyContains(text: text, pattern: pattern, config: .ocrBill)
        } else {
            let range = text.range(of: pattern)
            return FuzzyTextMatcher.FuzzyMatchResult(
                matched: range != nil,
                score: range != nil ? 1.0 : 0,
                depth: 0,
                matchedRange: range,
                matchedText: range.map { String(text[$0]) }
            )
        }
    }

    private func prefixMatch(text: String, pattern: String, fuzzy: Bool) -> FuzzyTextMatcher.FuzzyMatchResult {
        if fuzzy {
            return FuzzyTextMatcher.fuzzyContains(text: text, pattern: pattern + "*", config: .ocrBill)
        } else {
            let range = text.range(of: pattern, options: [.anchored])
            return FuzzyTextMatcher.FuzzyMatchResult(
                matched: range != nil,
                score: range != nil ? 1.0 : 0,
                depth: 0,
                matchedRange: range,
                matchedText: range.map { String(text[$0]) }
            )
        }
    }

    private func regexMatch(text: String, pattern: String) -> FuzzyTextMatcher.FuzzyMatchResult {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return FuzzyTextMatcher.FuzzyMatchResult(matched: false, score: 0, depth: 0, matchedRange: nil, matchedText: nil)
        }

        let range = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return FuzzyTextMatcher.FuzzyMatchResult(
            matched: range != nil,
            score: range != nil ? 1.0 : 0,
            depth: 0,
            matchedRange: range.flatMap { Range($0.range, in: text) },
            matchedText: range.flatMap { r -> String? in
                guard let swiftRange = Range(r.range, in: text) else { return nil }
                return String(text[swiftRange])
            }
        )
    }

    // MARK: - Apply Matched Rules to ParsedTransaction

    /// 应用规则到已解析的交易
    func applyRules(
        to transaction: ParsedTransaction,
        matches: [RuleMatchResult]
    ) -> ParsedTransaction {
        guard let bestMatch = matches.first else { return transaction }

        var result = transaction
        let rule = bestMatch.rule

        // 应用规则类型
        if let searchText = rule.searchTexts?.first {
            result.ruleKind = searchText.ruleKind.rawValue
        }

        // 应用交易类型
        switch rule.type {
        case .expense:
            result.isIncome = false
        case .income:
            result.isIncome = true
        default:
            break
        }

        // 应用资金账户名称
        if rule.fundAccountId > 0 {
            result.fundName = KeywordRule.fundAccountName(from: rule.fundAccountId)
        }

        // 应用toBiz（交易对方）
        if let toBiz = extractToBizFromRule(rule) {
            result.toBiz = toBiz
        }

        return result
    }

    private func extractToBizFromRule(_ rule: KeywordRule) -> String? {
        // 从rule的keyWord提取toBiz信息（如果有的话）
        // 某些规则可能专门用于提取交易对方
        guard !rule.keyWord.isEmpty else { return nil }

        // 检查是否是toBiz相关规则
        let toBizKeywords = ["收款方", "商户", "商家", "对方"]
        for keyword in toBizKeywords {
            if rule.keyWord.contains(keyword) {
                return nil // 不使用标签本身作为toBiz
            }
        }

        // 其他情况返回nil
        return nil
    }

    // MARK: - Category Mapping

    /// 外部可注入memberCateId映射（服务端/配置中心可用时调用）
    func updateCategoryMapping(_ mapping: [Int: String]) {
        injectedCategoryMapping = mapping
    }

    /// 将memberCateId转换为categoryKey
    func categoryKey(from memberCateId: Int) -> String? {
        if let injected = injectedCategoryMapping[memberCateId] {
            return injected
        }
        if let runtimeMapped = runtimeCategoryMapping()[memberCateId] {
            return runtimeMapped
        }
        return Self.defaultCategoryMapping[memberCateId]
    }

    private func runtimeCategoryMapping() -> [Int: String] {
        for key in Self.categoryMappingConfigKeys {
            if let raw = ProcessInfo.processInfo.environment[key], let mapped = decodeCategoryMapping(raw) {
                return mapped
            }
            if let raw = UserDefaults.standard.string(forKey: key), let mapped = decodeCategoryMapping(raw) {
                return mapped
            }
            if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               let mapped = decodeCategoryMapping(raw) {
                return mapped
            }
        }
        return [:]
    }

    private func decodeCategoryMapping(_ raw: String) -> [Int: String]? {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }

        var mapped: [Int: String] = [:]
        for (key, value) in decoded {
            guard let id = Int(key), !value.isEmpty else { continue }
            mapped[id] = value
        }
        return mapped.isEmpty ? nil : mapped
    }
}
