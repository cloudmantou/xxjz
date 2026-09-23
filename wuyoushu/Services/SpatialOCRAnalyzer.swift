import Foundation
import CoreGraphics

/// 空间OCR分析器，基于AChai的MYTextObservation概念
/// 提供2D布局分析、行/列分组、8方向空间导航
final class SpatialOCRAnalyzer {

    // MARK: - 数据结构

    /// 增强的文本观察结果，添加空间关系
    struct SpatialObservation: Hashable {
        let observation: OCRTextObservation
        let boundingBox: CGRect
        let center: CGPoint
        let id: Int

        private static var nextId = 0

        init(_ observation: OCRTextObservation) {
            self.observation = observation
            self.boundingBox = observation.boundingBox
            self.center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
            self.id = SpatialObservation.nextId
            SpatialObservation.nextId += 1
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: SpatialObservation, rhs: SpatialObservation) -> Bool {
            return lhs.id == rhs.id
        }

        /// 文本
        var text: String { observation.text }

        /// 置信度
        var confidence: Float { observation.confidence }
    }

    /// 文本行，包含一行内的观察结果
    struct TextLine {
        let observations: [SpatialObservation]
        let yMidpoint: CGFloat
        let minY: CGFloat
        let maxY: CGFloat

        init(observations: [SpatialObservation]) {
            self.observations = observations.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            self.yMidpoint = observations.map { $0.center.y }.reduce(0, +) / CGFloat(observations.count)
            self.minY = observations.map { $0.boundingBox.minY }.min() ?? 0
            self.maxY = observations.map { $0.boundingBox.maxY }.max() ?? 0
        }

        /// 行文本（按从左到右顺序连接）
        var text: String {
            observations.map { $0.text }.joined(separator: " ")
        }
    }

    /// 文本列，基于对齐方式分组
    struct TextColumn {
        let observations: [SpatialObservation]
        let xPosition: CGFloat // 列的平均X位置
        let alignment: Alignment

        enum Alignment {
            case left, right, center
        }
    }

    /// 空间关系图，支持9方向导航（对应AChai的MYTextObservation 9-zone grid）
    struct SpatialGraph {
        let observations: [SpatialObservation]
        private var neighbors: [SpatialObservation: [Direction: SpatialObservation]]

        /// 9方向枚举，对应MYTextObservation的9个空间区域
        enum Direction: CaseIterable {
            case left, right, top, bottom
            case topLeft, topRight, bottomLeft, bottomRight
            case center

            /// 相反方向
            var opposite: Direction {
                switch self {
                case .left: return .right
                case .right: return .left
                case .top: return .bottom
                case .bottom: return .top
                case .topLeft: return .bottomRight
                case .topRight: return .bottomLeft
                case .bottomLeft: return .topRight
                case .bottomRight: return .topLeft
                case .center: return .center
                }
            }

            /// 方向的角度（用于对角线检测）
            var angle: CGFloat {
                switch self {
                case .right: return 0
                case .topRight: return .pi / 4
                case .top: return .pi / 2
                case .topLeft: return 3 * .pi / 4
                case .left: return .pi
                case .bottomLeft: return 5 * .pi / 4
                case .bottom: return 3 * .pi / 2
                case .bottomRight: return 7 * .pi / 4
                case .center: return 0
                }
            }
        }

        init(observations: [SpatialObservation]) {
            self.observations = observations
            self.neighbors = [:]
            buildGraph()
        }

        private mutating func buildGraph() {
            for obs in observations {
                neighbors[obs] = findNeighbors(for: obs)
            }
        }

        private func findNeighbors(for observation: SpatialObservation) -> [Direction: SpatialObservation] {
            var result: [Direction: SpatialObservation] = [:]
            let box = observation.boundingBox
            let center = observation.center

            // 四个正交方向
            // 左邻接：在左边且有垂直重叠
            let leftCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.maxX <= box.minX &&
                verticalOverlap(box, other.boundingBox)
            }
            if let closest = leftCandidates.max(by: { $0.boundingBox.maxX < $1.boundingBox.maxX }) {
                result[.left] = closest
            }

            // 右邻接
            let rightCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.minX >= box.maxX &&
                verticalOverlap(box, other.boundingBox)
            }
            if let closest = rightCandidates.min(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
                result[.right] = closest
            }

            // 上邻接
            let topCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.maxY <= box.minY &&
                horizontalOverlap(box, other.boundingBox)
            }
            if let closest = topCandidates.max(by: { $0.boundingBox.maxY < $1.boundingBox.maxY }) {
                result[.top] = closest
            }

            // 下邻接
            let bottomCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.minY >= box.maxY &&
                horizontalOverlap(box, other.boundingBox)
            }
            if let closest = bottomCandidates.min(by: { $0.boundingBox.minY < $1.boundingBox.minY }) {
                result[.bottom] = closest
            }

            // 四个对角线方向
            // 左上：在左上方，不与左/上邻接重叠
            let topLeftCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.maxX <= box.minX &&
                other.boundingBox.maxY <= box.minY
            }
            if let closest = findClosestDiagonal(from: center, candidates: topLeftCandidates, quadrant: .topLeft) {
                result[.topLeft] = closest
            }

            // 右上
            let topRightCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.minX >= box.maxX &&
                other.boundingBox.maxY <= box.minY
            }
            if let closest = findClosestDiagonal(from: center, candidates: topRightCandidates, quadrant: .topRight) {
                result[.topRight] = closest
            }

            // 左下
            let bottomLeftCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.maxX <= box.minX &&
                other.boundingBox.minY >= box.maxY
            }
            if let closest = findClosestDiagonal(from: center, candidates: bottomLeftCandidates, quadrant: .bottomLeft) {
                result[.bottomLeft] = closest
            }

            // 右下
            let bottomRightCandidates = observations.filter { other in
                other.id != observation.id &&
                other.boundingBox.minX >= box.maxX &&
                other.boundingBox.minY >= box.maxY
            }
            if let closest = findClosestDiagonal(from: center, candidates: bottomRightCandidates, quadrant: .bottomRight) {
                result[.bottomRight] = closest
            }

            // 中心：重叠区域最大的观察结果
            let overlappingCandidates = observations.filter { other in
                other.id != observation.id &&
                box.intersects(other.boundingBox)
            }
            if let closest = overlappingCandidates.max(by: {
                let area1 = intersectionArea(box, $0.boundingBox)
                let area2 = intersectionArea(box, $1.boundingBox)
                return area1 < area2
            }) {
                result[.center] = closest
            }

            return result
        }

        /// 找到对角线方向最近的邻居（按欧几里得距离）
        private func findClosestDiagonal(
            from center: CGPoint,
            candidates: [SpatialObservation],
            quadrant: Direction
        ) -> SpatialObservation? {
            guard !candidates.isEmpty else { return nil }

            // 按到中心的距离排序，取最近的
            return candidates.min(by: {
                let d1 = distance(center, $0.center)
                let d2 = distance(center, $1.center)
                return d1 < d2
            })
        }

        /// 欧几里得距离
        private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            let dx = p1.x - p2.x
            let dy = p1.y - p2.y
            return sqrt(dx * dx + dy * dy)
        }

        /// 矩形交集面积
        private func intersectionArea(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
            let intersection = box1.intersection(box2)
            return intersection.width * intersection.height
        }

        private func verticalOverlap(_ box1: CGRect, _ box2: CGRect) -> Bool {
            return box1.minY < box2.maxY && box1.maxY > box2.minY
        }

        private func horizontalOverlap(_ box1: CGRect, _ box2: CGRect) -> Bool {
            return box1.minX < box2.maxX && box1.maxX > box2.minX
        }

        /// 获取观察结果在指定方向的邻居
        func neighbor(of observation: SpatialObservation, direction: Direction) -> SpatialObservation? {
            return neighbors[observation]?[direction]
        }

        /// 获取左对齐的观察结果
        func leftAlignedObservations(for observation: SpatialObservation, tolerance: CGFloat = 0.05) -> [SpatialObservation] {
            observations.filter { other in
                abs(other.boundingBox.minX - observation.boundingBox.minX) < tolerance &&
                verticalOverlap(other.boundingBox, observation.boundingBox)
            }
        }

        /// 获取右对齐的观察结果
        func rightAlignedObservations(for observation: SpatialObservation, tolerance: CGFloat = 0.05) -> [SpatialObservation] {
            observations.filter { other in
                abs(other.boundingBox.maxX - observation.boundingBox.maxX) < tolerance &&
                verticalOverlap(other.boundingBox, observation.boundingBox)
            }
        }
    }

    /// 9-zone grid分区，对应AChai的MYTextObservation空间网格
    struct SpatialZone {
        /// 将屏幕划分为3x3网格，返回每个zone内的观察结果
        static func partition(observations: [SpatialObservation]) -> [ZonePosition: [SpatialObservation]] {
            var zones: [ZonePosition: [SpatialObservation]] = ZonePosition.allCases.reduce(into: [:]) { dict, pos in
                dict[pos] = []
            }

            for obs in observations {
                let x = obs.center.x
                let y = obs.center.y

                let col: ZonePosition.HorizontalColumn
                if x < 1.0 / 3.0 {
                    col = .left
                } else if x < 2.0 / 3.0 {
                    col = .center
                } else {
                    col = .right
                }

                let row: ZonePosition.VerticalRow
                if y < 1.0 / 3.0 {
                    row = .top
                } else if y < 2.0 / 3.0 {
                    row = .middle
                } else {
                    row = .bottom
                }

                let position = ZonePosition(row: row, column: col)
                zones[position]?.append(obs)
            }

            return zones
        }

        enum ZonePosition: CaseIterable, Hashable {
            case topLeft, topCenter, topRight
            case middleLeft, middleCenter, middleRight
            case bottomLeft, bottomCenter, bottomRight

            enum HorizontalColumn { case left, center, right }
            enum VerticalRow { case top, middle, bottom }

            init(row: VerticalRow, column: HorizontalColumn) {
                switch (row, column) {
                case (.top, .left): self = .topLeft
                case (.top, .center): self = .topCenter
                case (.top, .right): self = .topRight
                case (.middle, .left): self = .middleLeft
                case (.middle, .center): self = .middleCenter
                case (.middle, .right): self = .middleRight
                case (.bottom, .left): self = .bottomLeft
                case (.bottom, .center): self = .bottomCenter
                case (.bottom, .right): self = .bottomRight
                }
            }
        }
    }

    // MARK: - 属性

    private let observations: [SpatialObservation]
    private let graph: SpatialGraph

    // MARK: - 初始化

    init(ocrResult: OCRResult) {
        self.observations = ocrResult.observations.map { SpatialObservation($0) }
        self.graph = SpatialGraph(observations: observations)
    }

    init(observations: [OCRTextObservation]) {
        self.observations = observations.map { SpatialObservation($0) }
        self.graph = SpatialGraph(observations: self.observations)
    }

    // MARK: - 公开方法

    /// 获取按行分组的观察结果
    func groupIntoLines() -> [TextLine] {
        guard !observations.isEmpty else { return [] }

        // 按Y坐标排序
        let sorted = observations.sorted { $0.boundingBox.minY < $1.boundingBox.minY }

        var lines: [[SpatialObservation]] = []
        var currentLine: [SpatialObservation] = []
        var currentYRange: ClosedRange<CGFloat>?

        for obs in sorted {
            let yMid = obs.center.y
            let yRange = (yMid - 0.02)...(yMid + 0.02) // 2%垂直容差

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

        return lines.map { TextLine(observations: $0) }
    }

    /// 获取按列分组的观察结果（基于对齐方式）
    func groupIntoColumns() -> [TextColumn] {
        let lines = groupIntoLines()
        var allObservations: [SpatialObservation] = lines.flatMap { $0.observations }

        // 按X坐标排序
        allObservations.sort { $0.boundingBox.minX < $1.boundingBox.minX }

        // 简单列检测：基于X位置聚类
        var columns: [[SpatialObservation]] = []
        var currentColumn: [SpatialObservation] = []
        var currentXRange: ClosedRange<CGFloat>?

        for obs in allObservations {
            let xMid = obs.center.x
            let xRange = (xMid - 0.05)...(xMid + 0.05) // 5%水平容差

            if let currentRange = currentXRange, currentRange.overlaps(xRange) {
                currentColumn.append(obs)
                let newMin = min(currentRange.lowerBound, xRange.lowerBound)
                let newMax = max(currentRange.upperBound, xRange.upperBound)
                currentXRange = newMin...newMax
            } else {
                if !currentColumn.isEmpty {
                    columns.append(currentColumn)
                }
                currentColumn = [obs]
                currentXRange = xRange
            }
        }

        if !currentColumn.isEmpty {
            columns.append(currentColumn)
        }

        // 转换为TextColumn，确定对齐方式
        return columns.map { observations in
            let avgX = observations.map { $0.boundingBox.minX }.reduce(0, +) / CGFloat(observations.count)
            let leftAlignedCount = observations.filter { $0.boundingBox.minX < avgX + 0.03 }.count
            let rightAlignedCount = observations.filter { $0.boundingBox.maxX > avgX - 0.03 }.count

            let alignment: TextColumn.Alignment
            if leftAlignedCount > rightAlignedCount {
                alignment = .left
            } else if rightAlignedCount > leftAlignedCount {
                alignment = .right
            } else {
                alignment = .center
            }

            return TextColumn(observations: observations, xPosition: avgX, alignment: alignment)
        }
    }

    /// 查找左对齐的观察结果（用于微信/支付宝解析）
    func findLeftAlignedObservations() -> [SpatialObservation] {
        let columns = groupIntoColumns()
        guard let leftColumn = columns.first(where: { $0.alignment == .left }) else {
            return []
        }
        return leftColumn.observations
    }

    /// 查找右对齐的观察结果
    func findRightAlignedObservations() -> [SpatialObservation] {
        let columns = groupIntoColumns()
        guard let rightColumn = columns.first(where: { $0.alignment == .right }) else {
            return []
        }
        return rightColumn.observations
    }

    /// 根据空间关系排序观察结果（AChai的sortTextObservations）
    func sortObservations() -> [SpatialObservation] {
        // 先按Y坐标排序，再按X坐标排序
        return observations.sorted {
            if abs($0.center.y - $1.center.y) < 0.02 {
                return $0.center.x < $1.center.x
            }
            return $0.center.y < $1.center.y
        }
    }

    /// 移除空间异常值（AChai风格：Q1/Q3 + 1.5*IQR + 容差）
    func removeOutliers(observations: [SpatialObservation], maxDistance: CGFloat = 0.1) -> [SpatialObservation] {
        guard observations.count > 3 else { return observations }

        let yValues = observations.map { Double($0.center.y) }.sorted()
        let q1 = calculateQuartile(yValues, position: 0.25)
        let q3 = calculateQuartile(yValues, position: 0.75)
        let iqr = q3 - q1

        guard iqr > 0 else {
            let median = yValues[yValues.count / 2]
            return observations.filter { abs(Double($0.center.y) - median) <= Double(maxDistance) }
        }

        let fencePadding = max(0.015, min(Double(maxDistance), iqr * 0.25))
        let lowerFence = q1 - 1.5 * iqr - fencePadding
        let upperFence = q3 + 1.5 * iqr + fencePadding

        let filtered = observations.filter {
            let y = Double($0.center.y)
            return y >= lowerFence && y <= upperFence
        }
        let minimumKeptCount = max(2, observations.count / 3)
        return filtered.count >= minimumKeptCount ? filtered : observations
    }

    private func calculateQuartile(_ sortedValues: [Double], position: Double) -> Double {
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

    /// 检测账单来源（微信、支付宝、通用）
    func detectBillSource() -> BillSource {
        let allText = observations.map { $0.text }.joined(separator: " ")

        // 微信关键词
        let wechatKeywords = ["微信支付", "微信转账", "微信付款", "微信", "WeChat"]
        if wechatKeywords.contains(where: { allText.contains($0) }) {
            return .wechatPay
        }

        // 支付宝关键词
        let alipayKeywords = ["支付宝", "支付宝支付", "支付宝转账", "花呗"]
        if alipayKeywords.contains(where: { allText.contains($0) }) {
            return .alipay
        }

        // 其他平台检测
        return BillSource.detect(from: allText)
    }

    /// 提取结构化数据（键值对）
    func extractKeyValuePairs() -> [(key: String, value: String)] {
        let lines = groupIntoLines()
        var pairs: [(String, String)] = []

        for line in lines {
            let lineText = line.text
            // 简单分割键值对（基于冒号、空格等）
            let components = lineText.split(separator: ":", maxSplits: 1).map(String.init)
            if components.count == 2 {
                let key = components[0].trimmingCharacters(in: .whitespaces)
                let value = components[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    pairs.append((key, value))
                }
            }
        }

        return pairs
    }

    /// 获取指定方向的邻居观察结果（9方向）
    func neighbor(of observation: SpatialObservation, direction: SpatialGraph.Direction) -> SpatialObservation? {
        return graph.neighbor(of: observation, direction: direction)
    }

    /// 获取9-zone分区结果
    func partitionIntoZones() -> [SpatialZone.ZonePosition: [SpatialObservation]] {
        return SpatialZone.partition(observations: observations)
    }

    /// 查找指定zone中最靠近中心的观察结果
    func keyObservation(in zone: SpatialZone.ZonePosition) -> SpatialObservation? {
        let zones = partitionIntoZones()
        guard let zoneObs = zones[zone], !zoneObs.isEmpty else { return nil }

        // 返回zone内最靠近zone中心的观察结果
        let zoneCenter = CGPoint(
            x: zoneCenterX(for: zone),
            y: zoneCenterY(for: zone)
        )
        return zoneObs.min(by: {
            let d1 = sqrt(pow($0.center.x - zoneCenter.x, 2) + pow($0.center.y - zoneCenter.y, 2))
            let d2 = sqrt(pow($1.center.x - zoneCenter.x, 2) + pow($1.center.y - zoneCenter.y, 2))
            return d1 < d2
        })
    }

    private func zoneCenterX(for zone: SpatialZone.ZonePosition) -> CGFloat {
        switch zone {
        case .topLeft, .middleLeft, .bottomLeft: return 1.0 / 6.0
        case .topCenter, .middleCenter, .bottomCenter: return 1.0 / 2.0
        case .topRight, .middleRight, .bottomRight: return 5.0 / 6.0
        }
    }

    private func zoneCenterY(for zone: SpatialZone.ZonePosition) -> CGFloat {
        switch zone {
        case .topLeft, .topCenter, .topRight: return 1.0 / 6.0
        case .middleLeft, .middleCenter, .middleRight: return 1.0 / 2.0
        case .bottomLeft, .bottomCenter, .bottomRight: return 5.0 / 6.0
        }
    }
}
