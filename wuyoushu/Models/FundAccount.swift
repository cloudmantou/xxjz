import Foundation

struct FundAccount: Identifiable, Hashable {
    let key: String
    let name: String
    let emoji: String

    var id: String { key }

    static let all: [FundAccount] = [
        FundAccount(key: "cash", name: "现金", emoji: "💵"),
        FundAccount(key: "wechat", name: "微信", emoji: "💚"),
        FundAccount(key: "alipay", name: "支付宝", emoji: "💙"),
        FundAccount(key: "debit", name: "储蓄卡", emoji: "🏦"),
        FundAccount(key: "credit", name: "信用卡", emoji: "💳"),
        FundAccount(key: "huabei", name: "花呗", emoji: "🌸"),
    ]

    static func find(key: String) -> FundAccount? {
        all.first { $0.key == key }
    }
}
