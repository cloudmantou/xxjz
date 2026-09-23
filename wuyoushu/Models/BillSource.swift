import Foundation

enum BillSource: String, Codable, CaseIterable {
    case unknown
    case wechatPay
    case alipay
    case meituan
    case eleme
    case pdd
    case jd
    case taobao
    case douyin
    case didi

    var displayName: String {
        switch self {
        case .unknown: return "未知"
        case .wechatPay: return "微信支付"
        case .alipay: return "支付宝"
        case .meituan: return "美团"
        case .eleme: return "饿了么"
        case .pdd: return "拼多多"
        case .jd: return "京东"
        case .taobao: return "淘宝"
        case .douyin: return "抖音"
        case .didi: return "滴滴出行"
        }
    }

    var emoji: String {
        switch self {
        case .unknown: return "📄"
        case .wechatPay: return "💚"
        case .alipay: return "💙"
        case .meituan: return "🟡"
        case .eleme: return "🔵"
        case .pdd: return "🔴"
        case .jd: return "🐶"
        case .taobao: return "🧡"
        case .douyin: return "🎵"
        case .didi: return "🚗"
        }
    }

    /// Keywords ordered longest-first for greedy matching.
    private static let keywordMap: [(keywords: [String], source: BillSource)] = [
        (["微信支付凭证", "微信支付"], .wechatPay),
        (["微信转账"], .wechatPay),
        (["支付宝转账"], .alipay),
        (["支付宝支付", "支付宝", "花呗"], .alipay),
        (["花呗"], .alipay),
        (["美团外卖", "美团"], .meituan),
        (["饿了么"], .eleme),
        (["拼多多"], .pdd),
        (["京东"], .jd),
        (["淘宝"], .taobao),
        (["抖音支付", "抖音"], .douyin),
        (["滴滴出行", "滴滴打车", "滴滴"], .didi),
    ]

    static func detect(from text: String) -> BillSource {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in keywordMap {
            for keyword in entry.keywords {
                if normalized.contains(keyword) {
                    return entry.source
                }
            }
        }
        return .unknown
    }

    /// Infer a fund account key from the detected bill source.
    static func inferFundAccount(from source: BillSource, rawText: String? = nil) -> String? {
        let text = rawText ?? ""
        if text.contains("花呗") {
            return "huabei"
        }
        if text.contains("信用卡") {
            return "credit"
        }
        if text.contains("借记卡") || text.contains("储蓄卡") || text.contains("银行卡") {
            return "debit"
        }
        if text.contains("零钱") || text.contains("零钱通") {
            return "wechat"
        }
        if text.contains("余额宝") {
            return "alipay"
        }

        switch source {
        case .wechatPay: return "wechat"
        case .alipay: return "alipay"
        case .unknown: return nil
        default: return nil
        }
    }
}
