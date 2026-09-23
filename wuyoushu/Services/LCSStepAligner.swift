import Foundation

/// LCS（最长公共子序列）步进对齐器
/// 基于AChai反向工程：longestStepsOfTextObservations:completion: 和 top3StepsOfTextObservations:
/// 用于在多个OCR观察序列中找到最长的公共子序列，从而对齐账单模板
final class LCSStepAligner {

    /// 对齐步骤，表示两个观察结果的匹配
    struct AlignmentStep: Equatable {
        let sourceIndex: Int
        let targetIndex: Int
        let sourceText: String
        let targetText: String
        let similarity: Float  // 0.0 ~ 1.0

        static func == (lhs: AlignmentStep, rhs: AlignmentStep) -> Bool {
            return lhs.sourceIndex == rhs.sourceIndex &&
                   lhs.targetIndex == rhs.targetIndex
        }
    }

    /// 对齐结果，包含得分和步骤
    struct AlignmentResult {
        let steps: [AlignmentStep]
        let score: Float
        let length: Int

        /// 归一化得分（0~1）
        var normalizedScore: Float {
            guard length > 0 else { return 0 }
            return score / Float(length)
        }
    }

    // MARK: - 最长公共子序列（带相似度）

    /// 在两个文本观察序列中找到最长的对齐步骤
    /// 对应AChai的 longestStepsOfTextObservations:completion:
    static func longestSteps(
        of source: [String],
        with target: [String],
        similarityThreshold: Float = 0.6
    ) -> AlignmentResult {
        let m = source.count
        let n = target.count

        guard m > 0 && n > 0 else {
            return AlignmentResult(steps: [], score: 0, length: 0)
        }

        // 计算相似度矩阵
        var simMatrix = [[Float]](repeating: [Float](repeating: 0, count: n), count: m)
        for i in 0..<m {
            for j in 0..<n {
                simMatrix[i][j] = textSimilarity(source[i], target[j])
            }
        }

        // DP表格：dp[i][j] = 最优子问题的 (score, steps count)
        var dp = [[Float]](repeating: [Float](repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                let sim = simMatrix[i - 1][j - 1]
                if sim >= similarityThreshold {
                    // 匹配：累加相似度得分
                    dp[i][j] = dp[i - 1][j - 1] + sim
                } else {
                    // 不匹配：取最优子问题
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // 回溯提取步骤
        var steps: [AlignmentStep] = []
        var i = m
        var j = n
        while i > 0 && j > 0 {
            let sim = simMatrix[i - 1][j - 1]
            if sim >= similarityThreshold && dp[i][j] == dp[i - 1][j - 1] + sim {
                steps.append(AlignmentStep(
                    sourceIndex: i - 1,
                    targetIndex: j - 1,
                    sourceText: source[i - 1],
                    targetText: target[j - 1],
                    similarity: sim
                ))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        steps.reverse()

        return AlignmentResult(
            steps: steps,
            score: dp[m][n],
            length: steps.count
        )
    }

    /// 获取最优的前3个对齐结果
    /// 对应AChai的 top3StepsOfTextObservations:
    /// 使用不同相似度阈值生成多个候选对齐
    static func top3Steps(
        of source: [String],
        with target: [String]
    ) -> [AlignmentResult] {
        // 使用3个不同阈值生成候选
        let thresholds: [Float] = [0.9, 0.7, 0.5]
        var results: [AlignmentResult] = []

        for threshold in thresholds {
            let result = longestSteps(of: source, with: target, similarityThreshold: threshold)
            if result.length > 0 {
                results.append(result)
            }
        }

        // 补充：使用模糊匹配生成额外候选
        let fuzzyResult = fuzzyLongestSteps(of: source, with: target)
        if fuzzyResult.length > 0 {
            results.append(fuzzyResult)
        }

        // 去重并按得分排序，取前3
        var seen = Set<Int>()
        var unique: [AlignmentResult] = []
        for r in results.sorted(by: { $0.normalizedScore > $1.normalizedScore }) {
            let hash = r.steps.map { "\($0.sourceIndex)-\($0.targetIndex)" }.joined(separator: ",")
            let hashValue = hash.hashValue
            if !seen.contains(hashValue) {
                seen.insert(hashValue)
                unique.append(r)
            }
        }

        return Array(unique.prefix(3))
    }

    // MARK: - 模糊匹配LCS

    /// 支持通配符和OCR容错的模糊LCS
    static func fuzzyLongestSteps(
        of source: [String],
        with target: [String]
    ) -> AlignmentResult {
        let m = source.count
        let n = target.count

        guard m > 0 && n > 0 else {
            return AlignmentResult(steps: [], score: 0, length: 0)
        }

        var dp = [[Float]](repeating: [Float](repeating: 0, count: n + 1), count: m + 1)
        var simMatrix = [[Float]](repeating: [Float](repeating: 0, count: n), count: m)

        for i in 0..<m {
            for j in 0..<n {
                simMatrix[i][j] = fuzzyTextSimilarity(source[i], target[j])
            }
        }

        for i in 1...m {
            for j in 1...n {
                let sim = simMatrix[i - 1][j - 1]
                if sim >= 0.4 {
                    dp[i][j] = dp[i - 1][j - 1] + sim
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var steps: [AlignmentStep] = []
        var i = m
        var j = n
        while i > 0 && j > 0 {
            let sim = simMatrix[i - 1][j - 1]
            if sim >= 0.4 && dp[i][j] == dp[i - 1][j - 1] + sim {
                steps.append(AlignmentStep(
                    sourceIndex: i - 1,
                    targetIndex: j - 1,
                    sourceText: source[i - 1],
                    targetText: target[j - 1],
                    similarity: sim
                ))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        steps.reverse()

        return AlignmentResult(steps: steps, score: dp[m][n], length: steps.count)
    }

    // MARK: - 多序列LCS（扩展版）

    /// 在多个观察序列中找到全局最长公共子序列
    /// 取两两LCS结果的交集
    static func multiSequenceLCS(
        sequences: [[String]],
        similarityThreshold: Float = 0.6
    ) -> AlignmentResult {
        guard sequences.count >= 2 else {
            if let first = sequences.first {
                return AlignmentResult(
                    steps: (0..<first.count).map {
                        AlignmentStep(sourceIndex: $0, targetIndex: $0, sourceText: first[$0], targetText: first[$0], similarity: 1.0)
                    },
                    score: Float(first.count),
                    length: first.count
                )
            }
            return AlignmentResult(steps: [], score: 0, length: 0)
        }

        // 以第一个序列为基准，与其他序列逐一LCS
        var currentResult = longestSteps(of: sequences[0], with: sequences[1], similarityThreshold: similarityThreshold)

        for idx in 2..<sequences.count {
            // 提取当前结果中的源文本
            let currentSourceTexts = currentResult.steps.map { $0.sourceText }
            let nextResult = longestSteps(of: currentSourceTexts, with: sequences[idx], similarityThreshold: similarityThreshold)

            // 合并：只保留都匹配的位置
            var mergedSteps: [AlignmentStep] = []
            for step in nextResult.steps {
                if step.sourceIndex < currentResult.steps.count {
                    let originalStep = currentResult.steps[step.sourceIndex]
                    mergedSteps.append(AlignmentStep(
                        sourceIndex: originalStep.sourceIndex,
                        targetIndex: step.targetIndex,
                        sourceText: originalStep.sourceText,
                        targetText: step.targetText,
                        similarity: min(originalStep.similarity, step.similarity)
                    ))
                }
            }

            currentResult = AlignmentResult(
                steps: mergedSteps,
                score: mergedSteps.reduce(0) { $0 + $1.similarity },
                length: mergedSteps.count
            )
        }

        return currentResult
    }

    // MARK: - 文本相似度计算

    /// 精确相似度（基于归一化编辑距离）
    static func textSimilarity(_ a: String, _ b: String) -> Float {
        if a == b { return 1.0 }

        let aNorm = normalize(a)
        let bNorm = normalize(b)

        if aNorm == bNorm { return 0.95 }

        let distance = editDistance(aNorm, bNorm)
        let maxLen = max(aNorm.count, bNorm.count)
        guard maxLen > 0 else { return 1.0 }

        return 1.0 - Float(distance) / Float(maxLen)
    }

    /// 模糊相似度（处理OCR常见错误：0↔O, 1↔l, ¥↔Y等）
    static func fuzzyTextSimilarity(_ a: String, _ b: String) -> Float {
        if a == b { return 1.0 }

        let aNorm = normalizeOcrErrors(a)
        let bNorm = normalizeOcrErrors(b)

        if aNorm == bNorm { return 0.9 }

        let distance = editDistance(aNorm, bNorm)
        let maxLen = max(aNorm.count, bNorm.count)
        guard maxLen > 0 else { return 1.0 }

        return 1.0 - Float(distance) / Float(maxLen)
    }

    /// OCR常见错误归一化
    private static func normalizeOcrErrors(_ text: String) -> String {
        var result = text
        // 数字/字母混淆
        result = result.replacingOccurrences(of: "O", with: "0")
        result = result.replacingOccurrences(of: "o", with: "0")
        result = result.replacingOccurrences(of: "l", with: "1")
        result = result.replacingOccurrences(of: "I", with: "1")
        result = result.replacingOccurrences(of: "S", with: "5")
        result = result.replacingOccurrences(of: "B", with: "8")
        // 货币符号
        result = result.replacingOccurrences(of: "Y", with: "¥")
        result = result.replacingOccurrences(of: "￥", with: "¥")
        // 标点符号
        result = result.replacingOccurrences(of: "：", with: ":")
        result = result.replacingOccurrences(of: "，", with: ",")
        result = result.replacingOccurrences(of: "。", with: ".")
        return normalize(result)
    }

    /// 文本标准化（去除空格、标点，转小写）
    private static func normalize(_ text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    /// 编辑距离（Levenshtein distance）
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if aChars[i - 1] == bChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(
                        dp[i - 1][j],     // 删除
                        dp[i][j - 1],     // 插入
                        dp[i - 1][j - 1]  // 替换
                    )
                }
            }
        }

        return dp[m][n]
    }
}
