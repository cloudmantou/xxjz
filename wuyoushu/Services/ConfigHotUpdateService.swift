import Foundation
import Combine
import CommonCrypto

/// 配置热更新服务
/// 基于AChai反向工程：CCConfigRequest → api/Config/GetV2 → CCConfigModel → ocrRegDict
/// 支持服务端下发OCR正则、关键词列表、账单模板等配置，客户端缓存+AES解密

// MARK: - 配置数据模型

/// OCR正则字典（对应AChai的ocrRegDict）
struct OCRRegexConfig: Codable {
    /// 支付宝出现关键词
    var aliAppearWords: [String]
    /// 微信出现关键词
    var weAppearWords: [String]
    /// 支付宝收入关键词
    var aliIncomeWords: [String]
    /// 微信收入关键词
    var weIncomeWords: [String]
    /// 金额正则表达式
    var amountRegex: [String]
    /// 日期正则表达式
    var dateRegex: [String]
    /// 分类关键词映射
    var categoryKeywords: [String: [String]]
    /// 版本号
    var version: Int
}

enum ProductVisualScope: String, Codable {
    case asset
    case wish
}

struct ProductVisualRuleConfig: Codable, Identifiable {
    var scope: ProductVisualScope
    var category: String?
    var keywords: [String]
    var symbolName: String
    var priority: Int
    var tintHex: String?

    var id: String {
        [
            scope.rawValue,
            category ?? "",
            symbolName,
            keywords.joined(separator: "|"),
            "\(priority)"
        ].joined(separator: "::")
    }

    init(
        scope: ProductVisualScope,
        category: String? = nil,
        keywords: [String] = [],
        symbolName: String,
        priority: Int = 0,
        tintHex: String? = nil
    ) {
        self.scope = scope
        self.category = category
        self.keywords = keywords
        self.symbolName = symbolName
        self.priority = priority
        self.tintHex = tintHex
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case category
        case keywords
        case symbolName
        case priority
        case tintHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(ProductVisualScope.self, forKey: .scope)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        symbolName = try container.decode(String.self, forKey: .symbolName)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        tintHex = try container.decodeIfPresent(String.self, forKey: .tintHex)
    }
}

/// 完整服务端配置模型（对应AChai的CCConfigModel）
struct ServerConfigModel: Codable {
    var ocrRegDict: OCRRegexConfig?
    /// 快捷记账模板
    var shortcutTemplates: [ShortcutTemplateConfig]?
    /// 分类列表
    var categories: [CategoryConfig]?
    /// 功能开关
    var featureFlags: [String: Bool]?
    /// 产品视觉兜底规则（资产/心愿）
    var productVisualRules: [ProductVisualRuleConfig]?
    /// App 公共配置（隐私政策等）
    var appSettings: AppSettingsConfig?
}

struct ShortcutTemplateConfig: Codable {
    var id: String
    var name: String
    var icon: String
    var categoryId: String
    var defaultAmount: Double?
}

struct CategoryConfig: Codable {
    var id: String
    var name: String
    var icon: String
    var type: String  // "expense" or "income"
    var parentId: String?
}

struct AppSettingsConfig: Codable {
    var privacyPolicyURL: String?
    var adminPanelURL: String?
    var profileLinks: [AppProfileLinkConfig]?
}

struct AppProfileLinkConfig: Codable, Identifiable {
    var id: String?
    var name: String
    var platform: String?
    var url: String
    var enabled: Bool?
    var symbolName: String?
    var openInExternalBrowser: Bool?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return "\(name)::\(url)"
    }
}

// MARK: - 热更新服务

final class ConfigHotUpdateService: ObservableObject {

    static let shared = ConfigHotUpdateService()

    private let baseURLConfigKeys = [
        "CONFIG_HOT_UPDATE_BASE_URL",
        "ConfigHotUpdateBaseURL",
        "configHotUpdate.baseURL"
    ]

    /// AES密钥（与服务端一致）
    private let aesKey = "your-16byte-key!!"  // 16字节AES-128密钥
    private let aesIV = "your-16byte-iv!!!"   // 16字节IV

    /// 缓存key
    private static let configCacheKey = "com.wuyoushu.serverConfig"
    private static let configVersionKey = "com.wuyoushu.configVersion"

    /// 内存缓存
    @Published private(set) var cachedConfig: ServerConfigModel?
    private var lastFetchTime: Date?
    private let minFetchInterval: TimeInterval = 300 // 5分钟最小间隔

    private init() {
        loadCachedConfig()
    }

    // MARK: - 公开方法

    /// 获取当前配置（优先内存缓存，然后磁盘缓存）
    var currentConfig: ServerConfigModel {
        return cachedConfig ?? defaultConfig()
    }

    /// OCR正则配置
    var ocrRegexConfig: OCRRegexConfig {
        return currentConfig.ocrRegDict ?? defaultOCRConfig()
    }

    func resolvedProductVisualRule(
        scope: ProductVisualScope,
        name: String,
        category: String
    ) -> ProductVisualRuleConfig? {
        let normalizedName = normalizeMatchingText(name)
        let normalizedCategory = normalizeMatchingText(category)

        let candidates = (currentConfig.productVisualRules ?? [])
            .filter { $0.scope == scope }

        return candidates
            .compactMap { rule -> (rule: ProductVisualRuleConfig, score: Int, keywordCount: Int)? in
                let normalizedRuleCategory = normalizeMatchingText(rule.category ?? "")
                let hasCategoryConstraint = !normalizedRuleCategory.isEmpty
                let categoryMatched = hasCategoryConstraint && normalizedRuleCategory == normalizedCategory
                let keywordMatched = rule.keywords
                    .map(normalizeMatchingText)
                    .filter { !$0.isEmpty }
                    .contains { normalizedName.contains($0) }

                let score: Int
                switch (keywordMatched, categoryMatched) {
                case (true, true):
                    score = 3
                case (true, false):
                    score = 2
                case (false, true):
                    score = 1
                default:
                    return nil
                }

                return (rule, score, rule.keywords.count)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.rule.priority != rhs.rule.priority {
                    return lhs.rule.priority > rhs.rule.priority
                }
                if lhs.keywordCount != rhs.keywordCount {
                    return lhs.keywordCount > rhs.keywordCount
                }
                return (lhs.rule.category ?? "").count > (rhs.rule.category ?? "").count
            }
            .first?
            .rule
    }

    /// 异步拉取最新配置
    func fetchLatestConfig(completion: @escaping (Bool) -> Void) {
        guard let baseURL = configuredBaseURL,
              let url = URL(string: "\(baseURL)/api/config/get") else {
            // Remote config is an optional enhancement. An unconfigured client stays local-only.
            DispatchQueue.main.async { completion(true) }
            return
        }

        // 节流：5分钟内不重复请求
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minFetchInterval {
            completion(true)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        // 添加本地版本号，服务端可判断是否需要返回新数据
        let localVersion = UserDefaults.standard.integer(forKey: Self.configVersionKey)
        request.setValue("\(localVersion)", forHTTPHeaderField: "X-Config-Version")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            do {
                // 解析响应
                let response = try JSONDecoder().decode(ConfigAPIResponse.self, from: data)

                // 检查版本号
                guard response.version > localVersion else {
                    // 本地已是最新
                    DispatchQueue.main.async {
                        self.lastFetchTime = Date()
                        completion(true)
                    }
                    return
                }

                // 解密配置数据
                let decryptedData: Data
                if response.encrypted {
                    guard let decoded = self.aesDecrypt(response.data) else {
                        DispatchQueue.main.async {
                            completion(false)
                        }
                        return
                    }
                    decryptedData = decoded
                } else {
                    decryptedData = response.data.data(using: .utf8) ?? Data()
                }

                // 解析配置
                let config = try JSONDecoder().decode(ServerConfigModel.self, from: decryptedData)

                // 更新缓存
                DispatchQueue.main.async {
                    self.cachedConfig = config
                    self.lastFetchTime = Date()
                    self.saveCachedConfig(config)
                    UserDefaults.standard.set(response.version, forKey: Self.configVersionKey)

                    // 通知配置更新
                    NotificationCenter.default.post(name: .configDidUpdate, object: nil)

                    // 同时拉取最新规则
                    RuleUpdateService.shared.fetchLatestRules { _ in }

                    completion(true)
                }
            } catch {
                print("[ConfigHotUpdate] 解析配置失败: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }.resume()
    }

    /// 强制刷新（忽略节流）
    func forceFetchConfig(completion: @escaping (Bool) -> Void) {
        lastFetchTime = nil
        fetchLatestConfig(completion: completion)
    }

    // MARK: - 本地缓存

    private func loadCachedConfig() {
        guard let data = UserDefaults.standard.data(forKey: Self.configCacheKey) else { return }
        cachedConfig = try? JSONDecoder().decode(ServerConfigModel.self, from: data)
    }

    private var configuredBaseURL: String? {
        for key in baseURLConfigKeys {
            let value = ProcessInfo.processInfo.environment[key]
                ?? UserDefaults.standard.string(forKey: key)
                ?? (Bundle.main.object(forInfoDictionaryKey: key) as? String)
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.localizedCaseInsensitiveContains("yourdomain.com"),
                  let components = URLComponents(string: trimmed),
                  ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil else {
                continue
            }
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return nil
    }

    private func saveCachedConfig(_ config: ServerConfigModel) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configCacheKey)
        }
    }

    private func normalizeMatchingText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    // MARK: - AES-128-CFB解密（对应AChai的加密方式）

    /// AES-128-CFB解密
    /// AChai服务端使用AES-128-CFB加密配置数据
    private func aesDecrypt(_ base64String: String) -> Data? {
        guard let encryptedData = Data(base64Encoded: base64String) else {
            return nil
        }

        // 使用CommonCrypto进行AES-128-CFB解密
        return aesCFBDecrypt(data: encryptedData, key: aesKey, iv: aesIV)
    }

    private func aesCFBDecrypt(data: Data, key: String, iv: String) -> Data? {
        guard let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8) else {
            return nil
        }

        var decrypted = Data(count: data.count)
        var numBytesDecrypted: size_t = 0

        let cryptStatus = decrypted.withUnsafeMutableBytes { decryptedBytes in
            data.withUnsafeBytes { dataBytes in
                ivData.withUnsafeBytes { ivBytes in
                    keyData.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCModeCFB),  // CFB模式
                            keyBytes.baseAddress, kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            decryptedBytes.baseAddress, data.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        guard cryptStatus == kCCSuccess else {
            print("[ConfigHotUpdate] AES解密失败，状态码: \(cryptStatus)")
            return nil
        }

        decrypted.removeSubrange(numBytesDecrypted..<decrypted.count)
        return decrypted
    }

    // MARK: - 默认配置

    private func defaultConfig() -> ServerConfigModel {
        return ServerConfigModel(
            ocrRegDict: defaultOCRConfig(),
            shortcutTemplates: nil,
            categories: nil,
            featureFlags: nil,
            productVisualRules: nil,
            appSettings: nil
        )
    }

    private func defaultOCRConfig() -> OCRRegexConfig {
        return OCRRegexConfig(
            aliAppearWords: ["支付宝", "支付宝支付", "花呗", "余额宝"],
            weAppearWords: ["微信支付", "微信转账", "WeChat Pay"],
            aliIncomeWords: ["收款", "收到", "到账", "转入", "退款", "红包"],
            weIncomeWords: ["收款", "收到", "转账收款", "退款", "红包"],
            amountRegex: [
                #"(?:支出|收入|转账)?\s*[¥￥]\s*([0-9]+(?:\.[0-9]{1,2})?)"#,
                #"¥\s*([0-9]+(?:\.[0-9]{1,2})?)"#,
                #"([0-9]+\.[0-9]{2})"#
            ],
            dateRegex: [
                #"(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}[：:]\d{2}[：:]\d{2})"#,
                #"(\d{1,2}[-/]\d{1,2}\s+\d{1,2}[：:]\d{2})"#,
                #"(今天|昨天|前天)\s*(\d{1,2}[：:]\d{2})"#
            ],
            categoryKeywords: [
                "餐饮": ["外卖", "餐饮", "美食", "饿了么", "美团", "麦当劳", "肯德基", "星巴克", "瑞幸"],
                "交通": ["滴滴", "出行", "加油", "停车", "地铁", "公交", "高铁", "机票", "打车"],
                "购物": ["淘宝", "京东", "拼多多", "超市", "商场", "购物"],
                "娱乐": ["电影", "游戏", "KTV", "旅游", "酒店"],
                "生活缴费": ["电费", "水费", "燃气", "话费", "宽带", "物业"]
            ],
            version: 1
        )
    }
}

// MARK: - API响应模型

struct ConfigAPIResponse: Codable {
    let code: Int
    let message: String
    let data: String      // JSON字符串或AES加密的base64
    let version: Int
    let encrypted: Bool
}

// MARK: - 通知

extension Notification.Name {
    static let configDidUpdate = Notification.Name("ConfigDidUpdate")
}
