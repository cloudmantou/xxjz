import Foundation

/// 模糊文本匹配器
/// 基于AChai反向工程：_fuzzyDepthStack自定义递归深度搜索（非Levenshtein）
/// 用于OCR文本的容错匹配，处理漏字、多字、错字等OCR错误
final class FuzzyTextMatcher {

    /// 匹配结果
    struct FuzzyMatchResult {
        let matched: Bool
        let score: Float        // 0.0 ~ 1.0
        let depth: Int          // 匹配消耗的深度（操作数）
        let matchedRange: Range<String.Index>?
        let matchedText: String?
    }

    /// 通配符类型
    enum Wildcard: Character {
        case single = "?"       // 匹配单个字符
        case multi = "*"        // 匹配零个或多个字符
        case digit = "#"        // 匹配单个数字
    }

    /// 匹配配置
    struct Config {
        var maxDepth: Int = 3           // 最大递归深度（AChai的_fuzzyDepthStack深度限制）
        var ignoreCase: Bool = true     // 忽略大小写
        var ignoreWhitespace: Bool = false  // 忽略空白
        var ocrTolerance: Bool = true   // OCR容错（0↔O, 1↔l等）
        var partialMatch: Bool = false  // 允许部分匹配

        static let ocrBill = Config(
            maxDepth: 3,
            ignoreCase: true,
            ignoreWhitespace: false,
            ocrTolerance: true,
            partialMatch: true
        )

        static let strict = Config(
            maxDepth: 0,
            ignoreCase: false,
            ignoreWhitespace: false,
            ocrTolerance: false,
            partialMatch: false
        )
    }

    // MARK: - 核心模糊匹配

    /// 模糊匹配文本是否包含pattern
    /// 对应AChai的 _fuzzyDepthStack 递归搜索
    static func fuzzyContains(
        text: String,
        pattern: String,
        config: Config = .ocrBill
    ) -> FuzzyMatchResult {
        let processedText = preprocess(text, config: config)
        let processedPattern = preprocess(pattern, config: config)

        // 快速精确匹配
        if let range = processedText.range(of: processedPattern) {
            return FuzzyMatchResult(
                matched: true,
                score: 1.0,
                depth: 0,
                matchedRange: range,
                matchedText: String(processedText[range])
            )
        }

        // 滑动窗口 + 递归深度搜索
        let textChars = Array(processedText)
        let patternChars = Array(processedPattern)

        var bestResult = FuzzyMatchResult(matched: false, score: 0, depth: config.maxDepth + 1, matchedRange: nil, matchedText: nil)

        // 在文本中滑动窗口
        for startIdx in 0..<textChars.count {
            let result = fuzzyMatchRecursive(
                textChars: textChars,
                textIndex: startIdx,
                patternChars: patternChars,
                patternIndex: 0,
                depth: 0,
                maxDepth: config.maxDepth,
                ocrTolerance: config.ocrTolerance
            )

            if result.matched && (result.score > bestResult.score || (result.score == bestResult.score && result.depth < bestResult.depth)) {
                let endOffset = min(startIdx + result.depth + patternChars.count, textChars.count)
                let rangeStart = processedText.index(processedText.startIndex, offsetBy: startIdx)
                let rangeEnd = processedText.index(processedText.startIndex, offsetBy: endOffset)
                bestResult = FuzzyMatchResult(
                    matched: true,
                    score: result.score,
                    depth: result.depth,
                    matchedRange: rangeStart..<rangeEnd,
                    matchedText: String(textChars[startIdx..<endOffset])
                )
            }
        }

        return bestResult
    }

    /// 递归模糊匹配核心算法（AChai的_fuzzyDepthStack实现）
    private static func fuzzyMatchRecursive(
        textChars: [Character],
        textIndex: Int,
        patternChars: [Character],
        patternIndex: Int,
        depth: Int,
        maxDepth: Int,
        ocrTolerance: Bool
    ) -> (matched: Bool, score: Float, depth: Int) {
        // 边界条件
        if patternIndex >= patternChars.count {
            // pattern全部匹配完成
            let score = max(0, 1.0 - Float(depth) * 0.1)
            return (matched: true, score: score, depth: depth)
        }

        if textIndex >= textChars.count {
            // 文本已用完但pattern未匹配完
            if depth < maxDepth {
                // 允许跳过剩余pattern字符（视为OCR多识别）
                return fuzzyMatchRecursive(
                    textChars: textChars,
                    textIndex: textIndex,
                    patternChars: patternChars,
                    patternIndex: patternIndex + 1,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    ocrTolerance: ocrTolerance
                )
            }
            return (matched: false, score: 0, depth: depth)
        }

        // 深度超限
        if depth > maxDepth {
            return (matched: false, score: 0, depth: depth)
        }

        let textChar = textChars[textIndex]
        let patternChar = patternChars[patternIndex]

        // 处理通配符
        if patternChar == Wildcard.single.rawValue || patternChar == Wildcard.digit.rawValue {
            if patternChar == Wildcard.digit.rawValue && !textChar.isNumber {
                return (matched: false, score: 0, depth: depth)
            }
            return fuzzyMatchRecursive(
                textChars: textChars,
                textIndex: textIndex + 1,
                patternChars: patternChars,
                patternIndex: patternIndex + 1,
                depth: depth,
                maxDepth: maxDepth,
                ocrTolerance: ocrTolerance
            )
        }

        if patternChar == Wildcard.multi.rawValue {
            // 尝试匹配0个、1个、2个...字符
            for skip in 0...(textChars.count - textIndex) {
                let result = fuzzyMatchRecursive(
                    textChars: textChars,
                    textIndex: textIndex + skip,
                    patternChars: patternChars,
                    patternIndex: patternIndex + 1,
                    depth: depth,
                    maxDepth: maxDepth,
                    ocrTolerance: ocrTolerance
                )
                if result.matched {
                    return result
                }
            }
            return (matched: false, score: 0, depth: depth)
        }

        // 精确匹配
        if textChar == patternChar {
            let result = fuzzyMatchRecursive(
                textChars: textChars,
                textIndex: textIndex + 1,
                patternChars: patternChars,
                patternIndex: patternIndex + 1,
                depth: depth,
                maxDepth: maxDepth,
                ocrTolerance: ocrTolerance
            )
            if result.matched {
                return result
            }
        }

        // OCR容错匹配
        if ocrTolerance && ocrCharEquals(textChar, patternChar) {
            let result = fuzzyMatchRecursive(
                textChars: textChars,
                textIndex: textIndex + 1,
                patternChars: patternChars,
                patternIndex: patternIndex + 1,
                depth: depth + 1,
                maxDepth: maxDepth,
                ocrTolerance: ocrTolerance
            )
            if result.matched {
                return result
            }
        }

        // 策略1：跳过文本当前字符（OCR多识别了字符）
        let skipTextResult = fuzzyMatchRecursive(
            textChars: textChars,
            textIndex: textIndex + 1,
            patternChars: patternChars,
            patternIndex: patternIndex,
            depth: depth + 1,
            maxDepth: maxDepth,
            ocrTolerance: ocrTolerance
        )
        if skipTextResult.matched {
            return skipTextResult
        }

        // 策略2：跳过pattern当前字符（OCR漏识别了字符）
        let skipPatternResult = fuzzyMatchRecursive(
            textChars: textChars,
            textIndex: textIndex,
            patternChars: patternChars,
            patternIndex: patternIndex + 1,
            depth: depth + 1,
            maxDepth: maxDepth,
            ocrTolerance: ocrTolerance
        )
        if skipPatternResult.matched {
            return skipPatternResult
        }

        // 策略3：替换当前字符（OCR错识别了字符）
        let replaceResult = fuzzyMatchRecursive(
            textChars: textChars,
            textIndex: textIndex + 1,
            patternChars: patternChars,
            patternIndex: patternIndex + 1,
            depth: depth + 1,
            maxDepth: maxDepth,
            ocrTolerance: ocrTolerance
        )
        return replaceResult
    }

    // MARK: - 金额模糊匹配

    /// 模糊匹配金额文本（处理OCR金额常见错误）
    /// 例如：¥15.80 可能被识别为 Y15.80, ¥15,80, 15.80等
    static func fuzzyMatchAmount(
        text: String,
        targetAmount: String,
        config: Config = .ocrBill
    ) -> FuzzyMatchResult {
        // 标准化金额文本
        let normalizedText = normalizeAmountText(text)
        let normalizedTarget = normalizeAmountText(targetAmount)

        // 先尝试精确匹配
        if normalizedText.contains(normalizedTarget) {
            return FuzzyMatchResult(
                matched: true,
                score: 1.0,
                depth: 0,
                matchedRange: nil,
                matchedText: normalizedTarget
            )
        }

        // 模糊匹配
        return fuzzyContains(text: normalizedText, pattern: normalizedTarget, config: config)
    }

    /// 标准化金额文本
    private static func normalizeAmountText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "Y", with: "¥")
        result = result.replacingOccurrences(of: "￥", with: "¥")
        result = result.replacingOccurrences(of: ",", with: ".")
        result = result.replacingOccurrences(of: "。", with: ".")
        result = result.replacingOccurrences(of: " ", with: "")
        return result
    }

    // MARK: - 关键词批量匹配

    /// 批量匹配关键词列表（用于账单分类等）
    static func fuzzyMatchAny(
        text: String,
        patterns: [String],
        config: Config = .ocrBill
    ) -> [(pattern: String, result: FuzzyMatchResult)] {
        return patterns.compactMap { pattern in
            let result = fuzzyContains(text: text, pattern: pattern, config: config)
            return result.matched ? (pattern, result) : nil
        }.sorted { $0.result.score > $1.result.score }
    }

    /// 找到最佳匹配的关键词
    static func bestMatch(
        text: String,
        patterns: [String],
        config: Config = .ocrBill
    ) -> (pattern: String, result: FuzzyMatchResult)? {
        return fuzzyMatchAny(text: text, patterns: patterns, config: config).first
    }

    // MARK: - OCR字符容错

    /// OCR常见字符容错比较
    private static func ocrCharEquals(_ a: Character, _ b: Character) -> Bool {
        let pairs: [(Character, Character)] = [
            ("0", "O"), ("0", "o"), ("0", "Q"),
            ("1", "l"), ("1", "I"), ("1", "i"), ("1", "|"),
            ("5", "S"), ("5", "s"),
            ("8", "B"),
            ("2", "Z"), ("2", "z"),
            ("6", "G"), ("6", "b"),
            ("9", "g"), ("9", "q"),
            ("¥", "Y"), ("¥", "￥"),
            (".", ","), (".", "。"), (".", "·"),
            (":", "："), (":", "∶"),
        ]

        if a == b { return true }

        for (x, y) in pairs {
            if (a == x && b == y) || (a == y && b == x) {
                return true
            }
        }

        return false
    }

    // MARK: - 文本预处理

    private static func preprocess(_ text: String, config: Config) -> String {
        var result = text
        if config.ignoreCase {
            result = result.lowercased()
        }
        if config.ignoreWhitespace {
            result = result.replacingOccurrences(of: " ", with: "")
            result = result.replacingOccurrences(of: "\t", with: "")
            result = result.replacingOccurrences(of: "\n", with: "")
        }
        return result
    }
}
