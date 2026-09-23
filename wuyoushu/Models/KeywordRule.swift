import Foundation

// MARK: - 规则类型（对应AChai的ruleKind）

/// 规则类型（对应AChai的ruleKind）
enum RuleKind: Int, Codable {
    case auto = 0     // 服务端自动规则
    case common = 1   // 通用规则
    case local = 2    // 本地用户规则
}

// MARK: - 账单来源类型

/// 账单来源类型（对应AChai的billSource）
/// 1=WeChat, 2=Alipay, 3=Generic
enum RuleBillSource: Int, Codable {
    case unknown = 0
    case wechat = 1
    case alipay = 2
    case generic = 3

    var toBillSource: BillSource {
        switch self {
        case .wechat: return .wechatPay
        case .alipay: return .alipay
        case .generic, .unknown: return .unknown
        }
    }

    init(from billSource: BillSource) {
        switch billSource {
        case .wechatPay: self = .wechat
        case .alipay: self = .alipay
        default: self = .generic
        }
    }
}

// MARK: - 关键词列表类型

/// 关键词列表类型（对应AChai的keyWordSource）
/// 阿里/微信 x 出现/信用/收入/转账
enum KeywordListType: Int, Codable {
    case aliAppear = 0
    case aliCredit = 1
    case aliIncome = 2
    case aliTransfer = 3
    case weAppear = 4
    case weCredit = 5
    case weIncome = 6
    case weTransfer = 7
}

// MARK: - 匹配类型

/// 匹配类型（对应AChai的matchType）
enum MatchType: Int, Codable {
    case exact = 1      // 精确匹配
    case contains = 2   // 包含匹配
    case prefix = 3     // 前缀匹配
    case regex = 4      // 正则匹配
}

// MARK: - 观察类型

/// 观察类型（对应AChai的candidateType）
enum CandidateType: Int, Codable {
    case keyObservation = 1  // 键观察
    case textObservation = 2 // 文本观察
}

// MARK: - 匹配对齐方式

/// 对齐模式（对应AChai的alignment）
/// 常见值：0(自动) 1(左对齐) 2(右对齐) 3(不限制/双向)
enum SearchAlignment: Int, Codable {
    case automatic = 0
    case left = 1
    case right = 2
    case either = 3
}

// MARK: - 交易类型

/// 交易类型（对应AChai的type）
enum RuleTransactionType: Int, Codable {
    case expense = 1
    case income = 2
    case transfer = 5
}

// MARK: - AutoBillSearchText

/// 单个关键词搜索文本（对应AChai的AutoBillSearchText）
struct AutoBillSearchText: Codable {
    var key: String?
    var index: Int
    var ruleId: Int
    var ruleKind: RuleKind
    var billSource: RuleBillSource
    var minMatchValue: Double
    var matchType: MatchType
    var isFuzzy: Bool
    var isFuzzyLastValue: Bool
    var isOptional: Bool
    var isMutableLine: Bool
    var columnCount: Int
    var alignment: SearchAlignment
    var candidateType: CandidateType
    var subCandidateType: Int

    init(
        key: String? = nil,
        index: Int = 0,
        ruleId: Int = 0,
        ruleKind: RuleKind = .auto,
        billSource: RuleBillSource = .generic,
        minMatchValue: Double = 0,
        matchType: MatchType = .contains,
        isFuzzy: Bool = false,
        isFuzzyLastValue: Bool = false,
        isOptional: Bool = false,
        isMutableLine: Bool = false,
        columnCount: Int = 1,
        alignment: SearchAlignment = .automatic,
        candidateType: CandidateType = .textObservation,
        subCandidateType: Int = 0
    ) {
        self.key = key
        self.index = index
        self.ruleId = ruleId
        self.ruleKind = ruleKind
        self.billSource = billSource
        self.minMatchValue = minMatchValue
        self.matchType = matchType
        self.isFuzzy = isFuzzy
        self.isFuzzyLastValue = isFuzzyLastValue
        self.isOptional = isOptional
        self.isMutableLine = isMutableLine
        self.columnCount = columnCount
        self.alignment = alignment
        self.candidateType = candidateType
        self.subCandidateType = subCandidateType
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case index
        case ruleId
        case ruleKind
        case billSource
        case minMatchValue
        case matchType
        case isFuzzy
        case isFuzzyLastValue
        case isOptional
        case isMutableLine
        case columnCount
        case alignment
        case candidateType
        case subCandidateType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        key = try container.decodeIfPresent(String.self, forKey: .key)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        ruleId = try container.decodeIfPresent(Int.self, forKey: .ruleId) ?? 0
        ruleKind = try container.decodeIfPresent(RuleKind.self, forKey: .ruleKind) ?? .auto
        billSource = try container.decodeIfPresent(RuleBillSource.self, forKey: .billSource) ?? .generic
        minMatchValue = try container.decodeIfPresent(Double.self, forKey: .minMatchValue) ?? 0
        matchType = try container.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .contains
        isFuzzy = try container.decodeIfPresent(Bool.self, forKey: .isFuzzy) ?? false
        isFuzzyLastValue = try container.decodeIfPresent(Bool.self, forKey: .isFuzzyLastValue) ?? false
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        isMutableLine = try container.decodeIfPresent(Bool.self, forKey: .isMutableLine) ?? false
        columnCount = try container.decodeIfPresent(Int.self, forKey: .columnCount) ?? 1
        alignment = try container.decodeIfPresent(SearchAlignment.self, forKey: .alignment) ?? .automatic
        candidateType = try container.decodeIfPresent(CandidateType.self, forKey: .candidateType) ?? .textObservation
        subCandidateType = try container.decodeIfPresent(Int.self, forKey: .subCandidateType) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encode(index, forKey: .index)
        try container.encode(ruleId, forKey: .ruleId)
        try container.encode(ruleKind, forKey: .ruleKind)
        try container.encode(billSource, forKey: .billSource)
        try container.encode(minMatchValue, forKey: .minMatchValue)
        try container.encode(matchType, forKey: .matchType)
        try container.encode(isFuzzy, forKey: .isFuzzy)
        try container.encode(isFuzzyLastValue, forKey: .isFuzzyLastValue)
        try container.encode(isOptional, forKey: .isOptional)
        try container.encode(isMutableLine, forKey: .isMutableLine)
        try container.encode(columnCount, forKey: .columnCount)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(candidateType, forKey: .candidateType)
        try container.encode(subCandidateType, forKey: .subCandidateType)
    }
}

// MARK: - KeywordRule

/// 关键词规则（对应AChai的keywordRules表）
struct KeywordRule: Codable, Identifiable {
    var id: Int { ruleId }

    var ruleId: Int
    var keyWord: String
    var memberId: String?
    var type: RuleTransactionType
    var memberCateId: Int           // 类别ID，映射到categoryKey
    var billsBookId: Int
    var keyWordSource: KeywordListType
    var fundAccountId: Int          // 1=wechat, 2=alipay, 3=huabei, 4=余额宝, 5=信用卡
    var memberTagIds: String?        // JSON array of tag IDs
    var createDate: String?
    var updateDate: String?
    var searchTexts: [AutoBillSearchText]?

    init(
        ruleId: Int = 0,
        keyWord: String = "",
        memberId: String? = nil,
        type: RuleTransactionType = .expense,
        memberCateId: Int = 0,
        billsBookId: Int = 0,
        keyWordSource: KeywordListType = .aliAppear,
        fundAccountId: Int = 0,
        memberTagIds: String? = nil,
        createDate: String? = nil,
        updateDate: String? = nil,
        searchTexts: [AutoBillSearchText]? = nil
    ) {
        self.ruleId = ruleId
        self.keyWord = keyWord
        self.memberId = memberId
        self.type = type
        self.memberCateId = memberCateId
        self.billsBookId = billsBookId
        self.keyWordSource = keyWordSource
        self.fundAccountId = fundAccountId
        self.memberTagIds = memberTagIds
        self.createDate = createDate
        self.updateDate = updateDate
        self.searchTexts = searchTexts
    }

    /// 从关键词构建简单规则（用于本地规则）
    static func simple(
        keyword: String,
        categoryKey: String,
        billSource: BillSource = .unknown,
        isIncome: Bool = false
    ) -> KeywordRule {
        KeywordRule(
            ruleId: Int.random(in: 100000...999999),
            keyWord: keyword,
            type: isIncome ? .income : .expense,
            memberCateId: 0,
            billsBookId: 0,
            keyWordSource: .aliAppear,
            fundAccountId: 0
        )
    }
}

// MARK: - RuleMatchResult

/// 规则匹配结果
struct RuleMatchResult {
    let rule: KeywordRule
    let matchedText: String
    let matchScore: Float
    let isFuzzyMatch: Bool

    init(rule: KeywordRule, matchedText: String, matchScore: Float, isFuzzyMatch: Bool = false) {
        self.rule = rule
        self.matchedText = matchedText
        self.matchScore = matchScore
        self.isFuzzyMatch = isFuzzyMatch
    }
}

// MARK: - 资金账户映射

extension KeywordRule {
    /// 根据fundAccountId获取资金账户名称
    static func fundAccountName(from fundAccountId: Int) -> String? {
        switch fundAccountId {
        case 1: return "微信"
        case 2: return "支付宝"
        case 3: return "花呗"
        case 4: return "余额宝"
        case 5: return "信用卡"
        case 6: return "零钱"
        case 7: return "零钱通"
        default: return nil
        }
    }

    /// 根据关键词获取资金账户ID
    static func fundAccountId(from keyword: String) -> Int? {
        switch keyword {
        case "微信", "wechat": return 1
        case "支付宝", "alipay": return 2
        case "花呗", "huabei": return 3
        case "余额宝", "yuebao": return 4
        case "信用卡", "credit": return 5
        case "零钱", "change": return 6
        case "零钱通", "changeplus": return 7
        default: return nil
        }
    }
}
