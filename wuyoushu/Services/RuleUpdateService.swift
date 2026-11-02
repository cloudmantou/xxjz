import Foundation
import CommonCrypto

struct RulePackageStatus: Equatable {
    let baseRulesVersion: Int
    let patchRulesVersion: Int
    let configVersion: Int
    let activeRulesChecksum: String
    let publishTime: Date?
    let previousSnapshotRef: String?
    let activeSnapshotRef: String?
    let isRollingBack: Bool
    let lastRollbackReason: String?
}

/// 规则更新服务
/// 从服务端API获取关键词规则，类似于ConfigHotUpdateService
final class RuleUpdateService {

    static let shared = RuleUpdateService()

    private struct RemoteRuleConfig {
        let baseURL: String
        let aesKey: String
        let aesIV: String
    }

    private enum ConfigKey {
        static let baseURL = ["RULE_UPDATE_BASE_URL", "RuleUpdateBaseURL", "ruleUpdate.baseURL"]
        static let aesKey = ["RULE_UPDATE_AES_KEY", "RuleUpdateAESKey", "ruleUpdate.aesKey"]
        static let aesIV = ["RULE_UPDATE_AES_IV", "RuleUpdateAESIV", "ruleUpdate.aesIV"]
    }

    /// 服务端规则API地址占位（未配置时会自动降级，不会发请求）
    private let defaultBaseURLPlaceholder = "https://config.yourdomain.com"
    private let defaultAESKeyPlaceholder = "your-16byte-key!!"
    private let defaultAESIVPlaceholder = "your-16byte-iv!!!"

    /// 缓存key
    private static let rulesCacheKey = "com.wuyoushu.keywordRules"
    private static let rulesVersionKey = "com.wuyoushu.rulesVersion"
    private static let rulesPackageStateKey = "com.wuyoushu.rulesPackage.state"
    private static let rulesBaseSnapshotKey = "com.wuyoushu.rulesSnapshot.base"
    private static let rulesActiveSnapshotKey = "com.wuyoushu.rulesSnapshot.active"
    private static let rulesPreviousSnapshotKey = "com.wuyoushu.rulesSnapshot.previous"
    private static let rulesEmergencyDisabledKeysKey = "com.wuyoushu.rules.emergencyDisabledKeys"
    private static let rulesDynamicNoiseKeywordsKey = "com.wuyoushu.rules.dynamicNoiseKeywords"
    private static let rulesETagKey = "com.wuyoushu.rules.etag"
    private static let rulesInstallIDKey = "com.wuyoushu.rules.installID"
    /// Bump this when the bundled offline rule set changes.
    private static let bundledDefaultRulesVersion = 1

    fileprivate struct RuleIdentity: Codable, Hashable {
        static let wildcard = "*"

        var sourceApp: String
        var sceneType: String
        var ruleNamespace: String
        var ruleId: Int

        func matches(_ candidate: RuleIdentity) -> Bool {
            guard ruleId == candidate.ruleId else { return false }
            let sourceMatched = sourceApp == Self.wildcard || candidate.sourceApp == Self.wildcard || sourceApp == candidate.sourceApp
            let sceneMatched = sceneType == Self.wildcard || candidate.sceneType == Self.wildcard || sceneType == candidate.sceneType
            let namespaceMatched = ruleNamespace == Self.wildcard || candidate.ruleNamespace == Self.wildcard || ruleNamespace == candidate.ruleNamespace
            return sourceMatched && sceneMatched && namespaceMatched
        }

        var fingerprint: String {
            "\(sourceApp)|\(sceneType)|\(ruleNamespace)|\(ruleId)"
        }
    }

    fileprivate struct RuleTombstone: Codable, Hashable {
        var identity: RuleIdentity
        var expiresAt: TimeInterval?
        var reason: String?

        func isExpired(at date: Date = Date()) -> Bool {
            guard let expiresAt else { return false }
            return date.timeIntervalSince1970 >= expiresAt
        }
    }

    fileprivate struct RuleNoiseKeywordDelta {
        var add: Set<String>
        var remove: Set<String>
    }

    private struct RulePriorityAdjustment {
        var identity: RuleIdentity
        var minMatchValue: Double?
        var minMatchValueDelta: Double?
    }

    private struct RulePackageState: Codable {
        var baseRulesVersion: Int
        var patchRulesVersion: Int
        var configVersion: Int
        var activeRulesChecksum: String
        var publishTime: TimeInterval
        var tombstones: [RuleTombstone]
        var previousSnapshotRef: String?
        var activeSnapshotRef: String?
        var isRollingBack: Bool
        var lastRollbackReason: String?
    }

    fileprivate struct RulePackagePayload {
        let baseRulesVersion: Int
        let patchRulesVersion: Int
        let configVersion: Int
        let publishTime: Date
        let expectedChecksum: String?
        let responseETag: String?
        let rules: [KeywordRule]
        let tombstones: [RuleTombstone]
        let noiseKeywordDelta: RuleNoiseKeywordDelta?
        let snapshotRef: String
    }

    private struct RulePatchPayload {
        var upsertRules: [KeywordRule] = []
        var deleteRuleIdentities: [RuleIdentity] = []
        var tombstones: [RuleTombstone] = []
        var priorityAdjustments: [RulePriorityAdjustment] = []
        var noiseKeywordDelta: RuleNoiseKeywordDelta?
    }

    private struct PatchMergeResult {
        let rules: [KeywordRule]
        let tombstones: [RuleTombstone]
        let noiseKeywordDelta: RuleNoiseKeywordDelta?
    }

    struct RuleUpdateCheckResult {
        let hasUpdate: Bool
        let baseRulesVersion: Int
        let patchRulesVersion: Int
        let configVersion: Int
        fileprivate let payload: RulePackagePayload?
    }

    /// 内存缓存
    private var cachedRules: [KeywordRule]?
    private var lastFetchTime: Date?
    private let minFetchInterval: TimeInterval = 300 // 5分钟最小间隔

    private init() {
        cachedRules = loadCachedRules()
    }

    private func resolveRemoteConfig() -> RemoteRuleConfig? {
        let resolvedBaseURL = resolveConfigValue(keys: ConfigKey.baseURL) ?? defaultBaseURLPlaceholder
        let resolvedAESKey = resolveConfigValue(keys: ConfigKey.aesKey) ?? defaultAESKeyPlaceholder
        let resolvedAESIV = resolveConfigValue(keys: ConfigKey.aesIV) ?? defaultAESIVPlaceholder

        guard !isPlaceholderValue(resolvedBaseURL),
              !isPlaceholderValue(resolvedAESKey),
              !isPlaceholderValue(resolvedAESIV),
              resolvedAESKey.count >= 16,
              resolvedAESIV.count >= 16 else {
            return nil
        }

        return RemoteRuleConfig(
            baseURL: resolvedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            aesKey: resolvedAESKey,
            aesIV: resolvedAESIV
        )
    }

    private func resolveConfigValue(keys: [String]) -> String? {
        for key in keys {
            if let envValue = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envValue.isEmpty {
                return envValue
            }

            if let defaultsValue = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !defaultsValue.isEmpty {
                return defaultsValue
            }

            if let infoValue = Bundle.main.object(forInfoDictionaryKey: key) as? String {
                let trimmed = infoValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func isPlaceholderValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        if trimmed.contains("yourdomain.com") { return true }
        if trimmed.contains("your-16byte") { return true }
        if trimmed == "placeholder" { return true }
        return false
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func currentBuildVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private func currentReleaseChannel() -> String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    private func installIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: Self.rulesInstallIDKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: Self.rulesInstallIDKey)
        return generated
    }

    private func storedPackageETag() -> String? {
        guard let value = UserDefaults.standard.string(forKey: Self.rulesETagKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func savePackageETag(_ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return
        }
        UserDefaults.standard.set(value, forKey: Self.rulesETagKey)
    }

    // MARK: - Public Interface

    /// 获取当前规则（优先内存缓存，然后磁盘缓存）
    var currentRules: [KeywordRule] {
        return cachedRules ?? loadCachedRules() ?? []
    }

    var packageStatus: RulePackageStatus {
        let state = loadPackageState()
        let publishTime = state.publishTime > 0
            ? Date(timeIntervalSince1970: state.publishTime)
            : nil
        return RulePackageStatus(
            baseRulesVersion: state.baseRulesVersion,
            patchRulesVersion: state.patchRulesVersion,
            configVersion: state.configVersion,
            activeRulesChecksum: state.activeRulesChecksum,
            publishTime: publishTime,
            previousSnapshotRef: state.previousSnapshotRef,
            activeSnapshotRef: state.activeSnapshotRef,
            isRollingBack: state.isRollingBack,
            lastRollbackReason: state.lastRollbackReason
        )
    }

    func getRulePackageStatus() -> RulePackageStatus {
        packageStatus
    }

    func dynamicNoiseKeywords() -> Set<String> {
        guard let words = UserDefaults.standard.array(forKey: Self.rulesDynamicNoiseKeywordsKey) as? [String] else {
            return []
        }
        return Set(words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    /// 按规则类型获取规则
    func rules(byKind kind: RuleKind) -> [KeywordRule] {
        return currentRules.filter { rule in
            rule.searchTexts?.first?.ruleKind == kind
        }
    }

    /// 按交易类型获取规则
    func rules(byType type: RuleTransactionType) -> [KeywordRule] {
        return KeywordRulesTable.shared.fetchRules(byType: type)
    }

    /// 按资金账户获取规则
    func rules(byFundAccountId fundAccountId: Int) -> [KeywordRule] {
        return KeywordRulesTable.shared.fetchRules(byFundAccountId: fundAccountId)
    }

    /// 检查是否存在新规则（仅下载检查，不激活）
    func checkForRuleUpdate(completion: @escaping (RuleUpdateCheckResult) -> Void) {
        guard let remoteConfig = resolveRemoteConfig() else {
            completion(
                RuleUpdateCheckResult(
                    hasUpdate: false,
                    baseRulesVersion: packageStatus.baseRulesVersion,
                    patchRulesVersion: packageStatus.patchRulesVersion,
                    configVersion: packageStatus.configVersion,
                    payload: nil
                )
            )
            return
        }

        let state = loadPackageState()
        let localVersion = max(state.patchRulesVersion, UserDefaults.standard.integer(forKey: Self.rulesVersionKey))
        let urlString = "\(remoteConfig.baseURL)/api/KeyWordMatchingRule/List"
        guard let url = URL(string: urlString) else {
            completion(
                RuleUpdateCheckResult(
                    hasUpdate: false,
                    baseRulesVersion: state.baseRulesVersion,
                    patchRulesVersion: state.patchRulesVersion,
                    configVersion: state.configVersion,
                    payload: nil
                )
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("\(localVersion)", forHTTPHeaderField: "X-Rules-Version")
        request.setValue("\(state.configVersion)", forHTTPHeaderField: "X-Rules-Config-Version")
        request.setValue(currentAppVersion(), forHTTPHeaderField: "X-App-Version")
        request.setValue(currentBuildVersion(), forHTTPHeaderField: "X-Build")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        request.setValue(currentReleaseChannel(), forHTTPHeaderField: "X-Channel")
        let installID = installIdentifier()
        request.setValue(installID, forHTTPHeaderField: "X-Install-Id")
        request.setValue(installID, forHTTPHeaderField: "X-Cohort-Key")
        if let etag = storedPackageETag() {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                completion(
                    RuleUpdateCheckResult(
                        hasUpdate: false,
                        baseRulesVersion: state.baseRulesVersion,
                        patchRulesVersion: state.patchRulesVersion,
                        configVersion: state.configVersion,
                        payload: nil
                    )
                )
                return
            }

            let httpResponse = response as? HTTPURLResponse
            let responseETag = httpResponse?.value(forHTTPHeaderField: "ETag")
            if httpResponse?.statusCode == 304 {
                savePackageETag(responseETag)
                completion(
                    RuleUpdateCheckResult(
                        hasUpdate: false,
                        baseRulesVersion: state.baseRulesVersion,
                        patchRulesVersion: state.patchRulesVersion,
                        configVersion: state.configVersion,
                        payload: nil
                    )
                )
                return
            }

            guard let data, error == nil else {
                completion(
                    RuleUpdateCheckResult(
                        hasUpdate: false,
                        baseRulesVersion: state.baseRulesVersion,
                        patchRulesVersion: state.patchRulesVersion,
                        configVersion: state.configVersion,
                        payload: nil
                    )
                )
                return
            }

            do {
                guard let payload = try self.decodeRulePayload(
                    from: data,
                    currentState: state,
                    responseETag: responseETag
                ) else {
                    self.savePackageETag(responseETag)
                    completion(
                        RuleUpdateCheckResult(
                            hasUpdate: false,
                            baseRulesVersion: state.baseRulesVersion,
                            patchRulesVersion: state.patchRulesVersion,
                            configVersion: state.configVersion,
                            payload: nil
                        )
                    )
                    return
                }
                completion(
                    RuleUpdateCheckResult(
                        hasUpdate: true,
                        baseRulesVersion: payload.baseRulesVersion,
                        patchRulesVersion: payload.patchRulesVersion,
                        configVersion: payload.configVersion,
                        payload: payload
                    )
                )
            } catch {
                print("[RuleUpdateService] check update failed: \(error)")
                completion(
                    RuleUpdateCheckResult(
                        hasUpdate: false,
                        baseRulesVersion: state.baseRulesVersion,
                        patchRulesVersion: state.patchRulesVersion,
                        configVersion: state.configVersion,
                        payload: nil
                    )
                )
            }
        }.resume()
    }

    /// 应用检查到的规则更新（校验通过后才激活）
    func applyRuleUpdate(_ result: RuleUpdateCheckResult, completion: @escaping (Bool) -> Void) {
        guard let payload = result.payload else {
            completion(true)
            return
        }
        let applied = applyRulePayload(payload)
        completion(applied)
    }

    /// 异步拉取最新规则
    func fetchLatestRules(completion: @escaping (Bool) -> Void) {
        guard resolveRemoteConfig() != nil else {
            // 配置为空或占位符时，直接降级本地规则，不发无效请求
            let isReady = ensureLocalRulesAvailable()
            if isReady { lastFetchTime = Date() }
            completion(isReady)
            return
        }

        // 节流
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minFetchInterval {
            completion(true)
            return
        }

        checkForRuleUpdate { [weak self] result in
            guard let self else {
                completion(false)
                return
            }

            guard result.hasUpdate else {
                self.lastFetchTime = Date()
                completion(true)
                return
            }

            self.applyRuleUpdate(result) { success in
                self.lastFetchTime = Date()
                completion(success)
            }
        }
    }

    /// 强制刷新（忽略节流）
    func forceFetchRules(completion: @escaping (Bool) -> Void) {
        lastFetchTime = nil
        fetchLatestRules(completion: completion)
    }

    /// 从SQLite加载规则到内存
    @discardableResult
    func loadRulesFromSQLite() -> [KeywordRule] {
        let rules = KeywordRulesTable.shared.fetchAllRules()
        cachedRules = rules
        return rules
    }

    /// 插入本地规则（用于用户自定义规则）
    @discardableResult
    func insertLocalRule(_ rule: KeywordRule) -> Bool {
        var localRule = rule
        if localRule.ruleId <= 0 || isOccupiedByNonLocalRule(localRule.ruleId) {
            localRule.ruleId = nextAvailableLocalRuleId()
        }

        // A local rule must remain local even when it is edited from an existing rule.
        if let searchTexts = localRule.searchTexts, !searchTexts.isEmpty {
            let localRuleId = localRule.ruleId
            localRule.searchTexts = searchTexts.map { searchText in
                var localSearchText = searchText
                localSearchText.ruleId = localRuleId
                localSearchText.ruleKind = .local
                return localSearchText
            }
        } else {
            localRule.searchTexts = [
                AutoBillSearchText(
                    ruleId: localRule.ruleId,
                    ruleKind: .local,
                    billSource: .generic,
                    minMatchValue: 0,
                    matchType: .contains,
                    isFuzzy: true,
                    isFuzzyLastValue: false,
                    isOptional: false,
                    columnCount: 1,
                    candidateType: .textObservation,
                    subCandidateType: 0
                )
            ]
        }
        guard KeywordRulesTable.shared.upsertRule(localRule) else { return false }
        cachedRules = nil // 清空缓存，下次会重新加载
        postRulesDidChange()
        return true
    }

    /// 删除本地规则
    @discardableResult
    func deleteLocalRule(ruleId: Int) -> Bool {
        guard let rule = KeywordRulesTable.shared.fetchRule(byId: ruleId) else { return false }
        // 只删除本地规则
        guard ruleKind(of: rule) == .local else { return false }
        guard KeywordRulesTable.shared.deleteRule(byId: ruleId) else { return false }
        cachedRules = nil
        postRulesDidChange()
        return true
    }

    /// Replaces the full local rule snapshot as part of a user initiated backup restore.
    /// Rule package caches are updated only after SQLite commits successfully.
    @discardableResult
    func replaceRulesForLocalRestore(_ rules: [KeywordRule]) -> Bool {
        guard KeywordRulesTable.shared.replaceAllRules(rules) else { return false }

        let packageRules = rules.filter { ruleKind(of: $0) != .local }
        cachedRules = packageRules
        saveCachedRules(packageRules)
        saveRulesSnapshot(packageRules, key: Self.rulesActiveSnapshotKey)

        var state = loadPackageState()
        state.activeRulesChecksum = calculateChecksum(for: packageRules)
        state.activeSnapshotRef = "local-restore-\(Int(Date().timeIntervalSince1970))"
        state.publishTime = Date().timeIntervalSince1970
        state.isRollingBack = false
        state.lastRollbackReason = nil
        savePackageState(state)
        postRulesDidChange()
        return true
    }

    private func isOccupiedByNonLocalRule(_ ruleId: Int) -> Bool {
        guard let existing = KeywordRulesTable.shared.fetchRule(byId: ruleId) else { return false }
        return existing.searchTexts?.first?.ruleKind != .local
    }

    private func nextAvailableLocalRuleId() -> Int {
        repeat {
            let candidate = Int.random(in: 100_000...999_999)
            if KeywordRulesTable.shared.fetchRule(byId: candidate) == nil { return candidate }
        } while true
    }

    private func postRulesDidChange() {
        NotificationCenter.default.post(name: .keywordRulesDidActivate, object: nil)
        NotificationCenter.default.post(name: .keywordRulesDidUpdate, object: nil)
    }

    // MARK: - Local Cache

    private func loadCachedRules() -> [KeywordRule]? {
        guard let data = UserDefaults.standard.data(forKey: Self.rulesCacheKey) else { return nil }
        return try? JSONDecoder().decode([KeywordRule].self, from: data)
    }

    private func saveCachedRules(_ rules: [KeywordRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.rulesCacheKey)
        }
    }

    @discardableResult
    func ensureLocalRulesAvailable() -> Bool {
        let persistedRules = KeywordRulesTable.shared.fetchAllRules()
        let persistedPackageRules = persistedRules.filter { ruleKind(of: $0) != .local }
        if !persistedPackageRules.isEmpty {
            // SQLite is authoritative; rebuild deleted or stale UserDefaults snapshots from it.
            cachedRules = persistedPackageRules
            saveCachedRules(persistedPackageRules)
            if loadRulesSnapshot(key: Self.rulesActiveSnapshotKey)?.isEmpty != false {
                saveRulesSnapshot(persistedPackageRules, key: Self.rulesActiveSnapshotKey)
            }
            return true
        }

        let packageStatus = self.packageStatus
        let lastGoodPackage = [
            loadRulesSnapshot(key: Self.rulesActiveSnapshotKey),
            loadRulesSnapshot(key: Self.rulesPreviousSnapshotKey),
            loadCachedRules()
        ]
        .compactMap { $0 }
        .first { !$0.isEmpty && validateRules($0) }

        if let lastGoodPackage {
            let packageRules = lastGoodPackage.filter { ruleKind(of: $0) != .local }
            if !packageRules.isEmpty {
                return activateRules(
                    packageRules,
                    baseVersion: packageStatus.baseRulesVersion,
                    patchVersion: packageStatus.patchRulesVersion,
                    configVersion: packageStatus.configVersion,
                    publishedAt: packageStatus.publishTime ?? Date(),
                    expectedChecksum: nil,
                    tombstones: loadPackageState().tombstones,
                    noiseKeywordDelta: nil,
                    snapshotRef: "recovered-\(packageStatus.activeSnapshotRef ?? "local")",
                    responseETag: nil,
                    isRollback: true
                )
            }
        }

        return loadDefaultRules()
    }

    private func loadPackageState() -> RulePackageState {
        guard let data = UserDefaults.standard.data(forKey: Self.rulesPackageStateKey),
              let state = try? JSONDecoder().decode(RulePackageState.self, from: data) else {
            let fallbackVersion = UserDefaults.standard.integer(forKey: Self.rulesVersionKey)
            return RulePackageState(
                baseRulesVersion: fallbackVersion,
                patchRulesVersion: fallbackVersion,
                configVersion: fallbackVersion,
                activeRulesChecksum: "",
                publishTime: 0,
                tombstones: [],
                previousSnapshotRef: nil,
                activeSnapshotRef: nil,
                isRollingBack: false,
                lastRollbackReason: nil
            )
        }
        var normalized = state
        normalized.tombstones = normalized.tombstones.filter { !$0.isExpired() }
        return normalized
    }

    private func savePackageState(_ state: RulePackageState) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.rulesPackageStateKey)
        }
    }

    private func saveRulesSnapshot(_ rules: [KeywordRule], key: String) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadRulesSnapshot(key: String) -> [KeywordRule]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([KeywordRule].self, from: data)
    }

    private func decodeRulePayload(
        from responseData: Data,
        currentState: RulePackageState,
        responseETag: String?
    ) throws -> RulePackagePayload? {
        if let legacy = try? JSONDecoder().decode(RulesAPIResponse.self, from: responseData) {
            guard legacy.code == 0 else {
                throw NSError(domain: "RuleUpdateService", code: legacy.code, userInfo: [NSLocalizedDescriptionKey: legacy.message])
            }
            let targetVersion = legacy.version
            let publishedAt = Date()
            guard shouldApplyIncoming(
                baseRulesVersion: targetVersion,
                patchRulesVersion: targetVersion,
                configVersion: targetVersion,
                publishTime: publishedAt,
                currentState: currentState
            ) else {
                return nil
            }
            let rules = try JSONDecoder().decode([KeywordRule].self, from: legacy.data)
            let (guardedRules, guardedTombstones) = applyLocalOverrideGuards(
                to: rules,
                state: currentState,
                incomingTombstones: []
            )
            return RulePackagePayload(
                baseRulesVersion: targetVersion,
                patchRulesVersion: targetVersion,
                configVersion: targetVersion,
                publishTime: publishedAt,
                expectedChecksum: nil,
                responseETag: responseETag,
                rules: guardedRules,
                tombstones: guardedTombstones,
                noiseKeywordDelta: nil,
                snapshotRef: "legacy-\(targetVersion)"
            )
        }

        return try decodePackagePayload(
            from: responseData,
            currentState: currentState,
            responseETag: responseETag
        )
    }

    private func decodePackagePayload(
        from responseData: Data,
        currentState: RulePackageState,
        responseETag: String?
    ) throws -> RulePackagePayload? {
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }

        let code = intValue(keys: ["code"], in: json) ?? 0
        if code != 0 {
            let message = stringValue(keys: ["message"], in: json) ?? "unknown server error"
            throw NSError(domain: "RuleUpdateService", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let baseVersion = intValue(
            keys: ["baseRulesVersion", "base_rules_version", "baseVersion", "version"],
            in: json
        ) ?? currentState.baseRulesVersion
        let patchVersion = intValue(
            keys: ["patchRulesVersion", "patch_rules_version", "patchVersion", "version"],
            in: json
        ) ?? baseVersion
        let configVersion = intValue(
            keys: ["configVersion", "config_version", "ruleTimestamp", "rule_timestamp"],
            in: json
        ) ?? patchVersion

        let publishTime = dateValue(keys: ["publishTime", "publish_time", "publishAt", "publishedAt"], in: json) ?? Date()
        guard shouldApplyIncoming(
            baseRulesVersion: baseVersion,
            patchRulesVersion: patchVersion,
            configVersion: configVersion,
            publishTime: publishTime,
            currentState: currentState
        ) else {
            return nil
        }

        let checksum = stringValue(keys: ["checksum", "ruleChecksum", "rule_checksum"], in: json)
        let encrypted = boolValue(keys: ["encrypted", "isEncrypted"], in: json) ?? false
        let snapshotRef = stringValue(keys: ["snapshotRef", "snapshot_ref"], in: json)

        if let fullPayload = firstValue(
            keys: ["fullData", "fullRules", "rulesData", "data", "rules"],
            in: json
        ) {
            let payloadData = try decodePayloadData(fullPayload, encrypted: encrypted)
            let rules = try JSONDecoder().decode([KeywordRule].self, from: payloadData)
            let incomingTombstones = parseTombstones(from: firstValue(keys: ["tombstones", "deletes"], in: json))
            let (guardedRules, guardedTombstones) = applyLocalOverrideGuards(
                to: rules,
                state: currentState,
                incomingTombstones: incomingTombstones
            )
            let noiseKeywordDelta = parseNoiseKeywordDelta(from: firstValue(keys: ["noiseKeywords", "noiseKeywordDelta"], in: json))
            return RulePackagePayload(
                baseRulesVersion: baseVersion,
                patchRulesVersion: patchVersion,
                configVersion: configVersion,
                publishTime: publishTime,
                expectedChecksum: checksum,
                responseETag: responseETag,
                rules: guardedRules,
                tombstones: guardedTombstones,
                noiseKeywordDelta: noiseKeywordDelta,
                snapshotRef: snapshotRef ?? "full-\(baseVersion)-\(patchVersion)-\(configVersion)"
            )
        }

        if let patchPayload = firstValue(keys: ["patchData", "patchRules", "patch"], in: json) {
            let payloadData = try decodePayloadData(patchPayload, encrypted: encrypted)
            let patch = try decodePatchPayload(from: payloadData)
            let baseRules = loadRulesSnapshot(key: Self.rulesActiveSnapshotKey)
                ?? cachedRules
                ?? loadCachedRules()
                ?? loadRulesFromSQLite()
            let merged = mergePatchPayload(patch, onto: baseRules)
            let (guardedRules, guardedTombstones) = applyLocalOverrideGuards(
                to: merged.rules,
                state: currentState,
                incomingTombstones: merged.tombstones
            )
            return RulePackagePayload(
                baseRulesVersion: baseVersion,
                patchRulesVersion: patchVersion,
                configVersion: configVersion,
                publishTime: publishTime,
                expectedChecksum: checksum,
                responseETag: responseETag,
                rules: guardedRules,
                tombstones: guardedTombstones,
                noiseKeywordDelta: merged.noiseKeywordDelta,
                snapshotRef: snapshotRef ?? "patch-\(baseVersion)-\(patchVersion)-\(configVersion)"
            )
        }

        return nil
    }

    private func decodePayloadData(_ value: Any, encrypted: Bool) throws -> Data {
        if let data = value as? Data {
            return data
        }

        if let string = value as? String {
            if encrypted {
                guard let decrypted = aesDecrypt(string) else {
                    throw NSError(domain: "RuleUpdateService", code: -21, userInfo: [NSLocalizedDescriptionKey: "AES decrypt failed"])
                }
                return decrypted
            }

            if let base64 = Data(base64Encoded: string) {
                return base64
            }
            return Data(string.utf8)
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []) {
            return data
        }

        throw NSError(domain: "RuleUpdateService", code: -22, userInfo: [NSLocalizedDescriptionKey: "Unsupported payload format"])
    }

    private func mergePatchPayload(_ patch: RulePatchPayload, onto baseRules: [KeywordRule]) -> PatchMergeResult {
        var map: [RuleIdentity: KeywordRule] = [:]
        for rule in baseRules {
            map[ruleIdentity(for: rule)] = rule
        }

        let deleteKeys = Set(patch.deleteRuleIdentities)
        if !deleteKeys.isEmpty {
            map = map.filter { key, _ in
                !deleteKeys.contains { $0.matches(key) }
            }
        }

        for rule in patch.upsertRules {
            map[ruleIdentity(for: rule)] = rule
        }

        if !patch.priorityAdjustments.isEmpty {
            map = applyPriorityAdjustments(patch.priorityAdjustments, to: map)
        }

        let rules = map.values.sorted {
            if $0.ruleId == $1.ruleId {
                return $0.keyWord < $1.keyWord
            }
            return $0.ruleId < $1.ruleId
        }
        let defaultExpiry = Date().addingTimeInterval(60 * 60 * 24 * 30).timeIntervalSince1970
        let deleteTombstones = patch.deleteRuleIdentities.map {
            RuleTombstone(identity: $0, expiresAt: defaultExpiry, reason: "patch_delete")
        }
        let tombstones = normalizedTombstones(from: patch.tombstones + deleteTombstones)
        return PatchMergeResult(rules: rules, tombstones: tombstones, noiseKeywordDelta: patch.noiseKeywordDelta)
    }

    private func applyRulePayload(_ payload: RulePackagePayload) -> Bool {
        let currentState = loadPackageState()
        let (guardedRules, guardedTombstones) = applyLocalOverrideGuards(
            to: payload.rules,
            state: currentState,
            incomingTombstones: payload.tombstones
        )
        let adjustedPayload = RulePackagePayload(
            baseRulesVersion: payload.baseRulesVersion,
            patchRulesVersion: payload.patchRulesVersion,
            configVersion: payload.configVersion,
            publishTime: payload.publishTime,
            expectedChecksum: payload.expectedChecksum,
            responseETag: payload.responseETag,
            rules: guardedRules,
            tombstones: guardedTombstones,
            noiseKeywordDelta: payload.noiseKeywordDelta,
            snapshotRef: payload.snapshotRef
        )

        let activated = activateRules(
            adjustedPayload.rules,
            baseVersion: adjustedPayload.baseRulesVersion,
            patchVersion: adjustedPayload.patchRulesVersion,
            configVersion: adjustedPayload.configVersion,
            publishedAt: adjustedPayload.publishTime,
            expectedChecksum: adjustedPayload.expectedChecksum,
            tombstones: adjustedPayload.tombstones,
            noiseKeywordDelta: adjustedPayload.noiseKeywordDelta,
            snapshotRef: adjustedPayload.snapshotRef,
            responseETag: adjustedPayload.responseETag,
            isRollback: false
        )
        if activated {
            return true
        }

        let rollbackFallback = loadRulesSnapshot(key: Self.rulesActiveSnapshotKey)
            ?? loadCachedRules()
            ?? loadRulesFromSQLite()
        _ = rollbackToPreviousRules(
            fallbackRules: rollbackFallback,
            reason: "activate_failed:\(adjustedPayload.snapshotRef)"
        )
        return false
    }

    private func activateRules(
        _ rules: [KeywordRule],
        baseVersion: Int,
        patchVersion: Int,
        configVersion: Int,
        publishedAt: Date,
        expectedChecksum: String?,
        tombstones: [RuleTombstone],
        noiseKeywordDelta: RuleNoiseKeywordDelta?,
        snapshotRef: String,
        responseETag: String?,
        isRollback: Bool,
        notify: Bool = true
    ) -> Bool {
        guard validateRules(rules) else { return false }

        let checksum = calculateChecksum(for: rules)
        if let expectedChecksum,
           !expectedChecksum.isEmpty,
           expectedChecksum != checksum {
            print("[RuleUpdateService] checksum mismatch. expected=\(expectedChecksum), actual=\(checksum)")
            return false
        }

        let previousState = loadPackageState()
        let existingPackageRules = (cachedRules ?? loadCachedRules() ?? [])
            .filter { ruleKind(of: $0) != .local }
        if !existingPackageRules.isEmpty {
            saveRulesSnapshot(existingPackageRules, key: Self.rulesPreviousSnapshotKey)
        }

        guard KeywordRulesTable.shared.upsertRules(rules) else {
            print("[RuleUpdateService] rule package activation failed: local database write failed")
            return false
        }
        cachedRules = rules
        saveCachedRules(rules)
        saveRulesSnapshot(rules, key: Self.rulesActiveSnapshotKey)
        if snapshotRef.hasPrefix("full-") || snapshotRef.hasPrefix("legacy-") ||
            snapshotRef.hasPrefix("default-") || snapshotRef.hasPrefix("bundled-default-") {
            saveRulesSnapshot(rules, key: Self.rulesBaseSnapshotKey)
        }

        if let noiseKeywordDelta {
            applyNoiseKeywordDelta(noiseKeywordDelta)
        }

        let state = RulePackageState(
            baseRulesVersion: max(baseVersion, 0),
            patchRulesVersion: max(patchVersion, 0),
            configVersion: max(configVersion, 0),
            activeRulesChecksum: checksum,
            publishTime: publishedAt.timeIntervalSince1970,
            tombstones: normalizedTombstones(from: tombstones),
            previousSnapshotRef: previousState.activeSnapshotRef,
            activeSnapshotRef: snapshotRef,
            isRollingBack: isRollback,
            lastRollbackReason: isRollback ? previousState.lastRollbackReason : nil
        )
        savePackageState(state)
        UserDefaults.standard.set(max(patchVersion, 0), forKey: Self.rulesVersionKey)
        savePackageETag(responseETag ?? "\"\(checksum)\"")

        logRulePackageEvent(
            "activate",
            extra: "base=\(state.baseRulesVersion), patch=\(state.patchRulesVersion), config=\(state.configVersion), checksum=\(state.activeRulesChecksum.prefix(12)), rules=\(rules.count), rollback=\(isRollback)"
        )

        if notify {
            NotificationCenter.default.post(name: .keywordRulesDidActivate, object: nil)
            NotificationCenter.default.post(name: .keywordRulesDidUpdate, object: nil)
        }
        return true
    }

    private func rollbackToPreviousRules(fallbackRules: [KeywordRule]?, reason: String) -> Bool {
        var state = loadPackageState()
        state.isRollingBack = true
        state.lastRollbackReason = reason
        savePackageState(state)

        if let previous = loadRulesSnapshot(key: Self.rulesPreviousSnapshotKey),
           !previous.isEmpty {
            return activateRules(
                previous,
                baseVersion: state.baseRulesVersion,
                patchVersion: state.patchRulesVersion,
                configVersion: state.configVersion,
                publishedAt: Date(),
                expectedChecksum: nil,
                tombstones: state.tombstones,
                noiseKeywordDelta: nil,
                snapshotRef: state.previousSnapshotRef ?? "rollback-\(Int(Date().timeIntervalSince1970))",
                responseETag: nil,
                isRollback: true
            )
        }

        if let fallbackRules, !fallbackRules.isEmpty {
            return activateRules(
                fallbackRules,
                baseVersion: state.baseRulesVersion,
                patchVersion: state.patchRulesVersion,
                configVersion: state.configVersion,
                publishedAt: Date(),
                expectedChecksum: nil,
                tombstones: state.tombstones,
                noiseKeywordDelta: nil,
                snapshotRef: "fallback-\(Int(Date().timeIntervalSince1970))",
                responseETag: nil,
                isRollback: true
            )
        }
        logRulePackageEvent("rollback_failed", extra: reason)
        return false
    }

    private func shouldApplyIncoming(
        baseRulesVersion: Int,
        patchRulesVersion: Int,
        configVersion: Int,
        publishTime: Date,
        currentState: RulePackageState
    ) -> Bool {
        if configVersion != currentState.configVersion {
            return configVersion > currentState.configVersion
        }
        if patchRulesVersion != currentState.patchRulesVersion {
            return patchRulesVersion > currentState.patchRulesVersion
        }
        if baseRulesVersion != currentState.baseRulesVersion {
            return baseRulesVersion > currentState.baseRulesVersion
        }
        return publishTime.timeIntervalSince1970 > currentState.publishTime
    }

    private func decodePatchPayload(from payloadData: Data) throws -> RulePatchPayload {
        if let directRules = try? JSONDecoder().decode([KeywordRule].self, from: payloadData) {
            var payload = RulePatchPayload()
            payload.upsertRules = deduplicatedRulesByIdentity(directRules)
            return payload
        }

        guard let json = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw NSError(domain: "RuleUpdateService", code: -23, userInfo: [NSLocalizedDescriptionKey: "patch payload must be JSON object"])
        }

        var payload = RulePatchPayload()
        payload.upsertRules = deduplicatedRulesByIdentity(
            decodeRulesArray(from: firstValue(keys: ["upsert", "upserts", "rules", "ruleUpserts"], in: json))
        )

        let deleteIds = intArrayValue(
            keys: ["deleteRuleIds", "deleteIds", "removeRuleIds", "delete_rule_ids"],
            in: json
        )
        payload.deleteRuleIdentities.append(
            contentsOf: deleteIds.map {
                RuleIdentity(sourceApp: RuleIdentity.wildcard, sceneType: RuleIdentity.wildcard, ruleNamespace: RuleIdentity.wildcard, ruleId: $0)
            }
        )
        payload.deleteRuleIdentities.append(
            contentsOf: parseRuleIdentities(from: firstValue(keys: ["deleteRuleKeys", "deleteKeys", "removeKeys", "delete_rule_keys"], in: json))
        )

        payload.tombstones = parseTombstones(from: firstValue(keys: ["tombstones", "deletes"], in: json))
        payload.deleteRuleIdentities.append(contentsOf: payload.tombstones.map(\.identity))
        payload.priorityAdjustments = parsePriorityAdjustments(from: firstValue(keys: ["priorityAdjust", "priorityAdjustments", "weightAdjust"], in: json))
        payload.noiseKeywordDelta = parseNoiseKeywordDelta(from: firstValue(keys: ["noiseKeywords", "noiseKeywordDelta"], in: json))
        return payload
    }

    private func deduplicatedRulesByIdentity(_ rules: [KeywordRule]) -> [KeywordRule] {
        var map: [RuleIdentity: KeywordRule] = [:]
        for rule in rules {
            map[ruleIdentity(for: rule)] = rule
        }
        return map.values.sorted {
            if $0.ruleId == $1.ruleId {
                return $0.keyWord < $1.keyWord
            }
            return $0.ruleId < $1.ruleId
        }
    }

    private func decodeRulesArray(from value: Any?) -> [KeywordRule] {
        guard let value else { return [] }
        if let list = value as? [Any] {
            return list.compactMap { decodeRule(from: $0) }
        }
        if let rule = decodeRule(from: value) {
            return [rule]
        }
        return []
    }

    private func decodeRule(from value: Any) -> KeywordRule? {
        if let nested = (value as? [String: Any])?["rule"] {
            return decodeRule(from: nested)
        }

        if let dict = value as? [String: Any],
           JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let rule = try? JSONDecoder().decode(KeywordRule.self, from: data) {
            return rule
        }

        if let string = value as? String {
            if let data = Data(base64Encoded: string),
               let rule = try? JSONDecoder().decode(KeywordRule.self, from: data) {
                return rule
            }
            if let data = string.data(using: .utf8),
               let rule = try? JSONDecoder().decode(KeywordRule.self, from: data) {
                return rule
            }
        }

        return nil
    }

    private func parseRuleIdentities(from value: Any?) -> [RuleIdentity] {
        guard let value else { return [] }
        if let list = value as? [Any] {
            return list.compactMap { parseRuleIdentity(from: $0) }
        }
        if let one = parseRuleIdentity(from: value) {
            return [one]
        }
        return []
    }

    private func parseRuleIdentity(from value: Any) -> RuleIdentity? {
        if let string = value as? String {
            return parseRuleIdentityFingerprint(string)
        }

        guard let dict = value as? [String: Any] else { return nil }
        guard let ruleId = intValue(keys: ["ruleId", "rule_id", "id"], in: dict) else { return nil }

        let sourceApp = sourceAppToken(from: firstValue(keys: ["sourceApp", "source_app", "billSource", "bill_source"], in: dict))
        let sceneType = sceneTypeToken(from: firstValue(keys: ["sceneType", "scene_type", "keyWordSource", "keyword_source"], in: dict))
        let namespace = namespaceToken(from: firstValue(keys: ["ruleNamespace", "rule_namespace", "ruleKind", "rule_kind"], in: dict))

        return RuleIdentity(
            sourceApp: sourceApp,
            sceneType: sceneType,
            ruleNamespace: namespace,
            ruleId: ruleId
        )
    }

    private func parseTombstones(from value: Any?) -> [RuleTombstone] {
        guard let value else { return [] }
        let entries: [Any]
        if let list = value as? [Any] {
            entries = list
        } else {
            entries = [value]
        }

        var tombstones: [RuleTombstone] = []
        for entry in entries {
            guard let dict = entry as? [String: Any] else { continue }
            guard let identity = parseRuleIdentity(from: dict["key"] ?? dict) else { continue }
            let expiresAt = dateValue(keys: ["expiresAt", "expireAt", "expires_at"], in: dict)?.timeIntervalSince1970
                ?? doubleValue(keys: ["ttl", "ttlSeconds", "ttl_seconds"], in: dict).map { Date().addingTimeInterval($0).timeIntervalSince1970 }
            let reason = stringValue(keys: ["reason"], in: dict)
            tombstones.append(RuleTombstone(identity: identity, expiresAt: expiresAt, reason: reason))
        }
        return tombstones
    }

    private func parsePriorityAdjustments(from value: Any?) -> [RulePriorityAdjustment] {
        guard let value else { return [] }
        let entries: [Any]
        if let list = value as? [Any] {
            entries = list
        } else {
            entries = [value]
        }

        return entries.compactMap { item in
            guard let dict = item as? [String: Any],
                  let identity = parseRuleIdentity(from: dict["key"] ?? dict) else {
                return nil
            }
            let absolute = doubleValue(keys: ["minMatchValue", "min_match_value", "priority"], in: dict)
            let delta = doubleValue(keys: ["minMatchValueDelta", "priorityDelta", "priority_delta"], in: dict)
            if absolute == nil && delta == nil {
                return nil
            }
            return RulePriorityAdjustment(identity: identity, minMatchValue: absolute, minMatchValueDelta: delta)
        }
    }

    private func parseNoiseKeywordDelta(from value: Any?) -> RuleNoiseKeywordDelta? {
        guard let dict = value as? [String: Any] else { return nil }
        let add = Set(stringArray(from: firstValue(keys: ["add", "append", "upsert"], in: dict)))
        let remove = Set(stringArray(from: firstValue(keys: ["remove", "delete"], in: dict)))
        guard !add.isEmpty || !remove.isEmpty else { return nil }
        return RuleNoiseKeywordDelta(add: add, remove: remove)
    }

    private func applyPriorityAdjustments(
        _ adjustments: [RulePriorityAdjustment],
        to map: [RuleIdentity: KeywordRule]
    ) -> [RuleIdentity: KeywordRule] {
        guard !adjustments.isEmpty else { return map }
        var updated = map

        for adjustment in adjustments {
            let targets = updated.keys.filter { adjustment.identity.matches($0) }
            for key in targets {
                guard var rule = updated[key] else { continue }
                var searchTexts = rule.searchTexts ?? [fallbackSearchText(for: rule)]
                for index in searchTexts.indices {
                    if let absolute = adjustment.minMatchValue {
                        searchTexts[index].minMatchValue = max(0, absolute)
                    }
                    if let delta = adjustment.minMatchValueDelta {
                        searchTexts[index].minMatchValue = max(0, searchTexts[index].minMatchValue + delta)
                    }
                }
                rule.searchTexts = searchTexts
                updated[key] = rule
            }
        }

        return updated
    }

    private func fallbackSearchText(for rule: KeywordRule) -> AutoBillSearchText {
        AutoBillSearchText(
            ruleId: rule.ruleId,
            ruleKind: .auto,
            billSource: inferredBillSource(from: rule.keyWordSource),
            minMatchValue: 0,
            matchType: .contains,
            isFuzzy: true,
            isFuzzyLastValue: false,
            isOptional: false,
            columnCount: 1,
            candidateType: .textObservation,
            subCandidateType: 0
        )
    }

    private func applyLocalOverrideGuards(
        to rules: [KeywordRule],
        state: RulePackageState,
        incomingTombstones: [RuleTombstone]
    ) -> ([KeywordRule], [RuleTombstone]) {
        let mergedTombstones = normalizedTombstones(from: state.tombstones + incomingTombstones)
        let emergencyDisabled = loadEmergencyDisabledRuleIdentities()
        let filtered = rules.filter { rule in
            let identity = ruleIdentity(for: rule)
            let blockedByTombstone = mergedTombstones.contains(where: { $0.identity.matches(identity) })
            let blockedByEmergency = emergencyDisabled.contains(where: { $0.matches(identity) })
            return !blockedByTombstone && !blockedByEmergency
        }
        return (filtered, mergedTombstones)
    }

    private func normalizedTombstones(from tombstones: [RuleTombstone]) -> [RuleTombstone] {
        var merged: [RuleIdentity: RuleTombstone] = [:]
        for tombstone in tombstones where !tombstone.isExpired() {
            if let existing = merged[tombstone.identity] {
                let existingExpiry = existing.expiresAt ?? .infinity
                let newExpiry = tombstone.expiresAt ?? .infinity
                if newExpiry >= existingExpiry {
                    merged[tombstone.identity] = tombstone
                }
            } else {
                merged[tombstone.identity] = tombstone
            }
        }
        return merged.values.sorted { $0.identity.fingerprint < $1.identity.fingerprint }
    }

    private func loadEmergencyDisabledRuleIdentities() -> [RuleIdentity] {
        guard let raw = UserDefaults.standard.array(forKey: Self.rulesEmergencyDisabledKeysKey) as? [String] else {
            return []
        }
        return raw.compactMap(parseRuleIdentityFingerprint(_:))
    }

    private func parseRuleIdentityFingerprint(_ value: String) -> RuleIdentity? {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let ruleId = Int(parts[3]) else { return nil }
        return RuleIdentity(sourceApp: parts[0], sceneType: parts[1], ruleNamespace: parts[2], ruleId: ruleId)
    }

    private func applyNoiseKeywordDelta(_ delta: RuleNoiseKeywordDelta) {
        var keywords = dynamicNoiseKeywords()
        keywords.formUnion(delta.add)
        keywords.subtract(delta.remove)
        UserDefaults.standard.set(Array(keywords).sorted(), forKey: Self.rulesDynamicNoiseKeywordsKey)
    }

    private func ruleIdentity(for rule: KeywordRule) -> RuleIdentity {
        let sourceApp = sourceAppToken(from: rule.searchTexts?.first?.billSource.rawValue ?? inferredBillSource(from: rule.keyWordSource).rawValue)
        let sceneType = sceneTypeToken(from: rule.keyWordSource.rawValue)
        let namespace = namespaceToken(from: rule.searchTexts?.first?.ruleKind.rawValue ?? RuleKind.auto.rawValue)
        return RuleIdentity(sourceApp: sourceApp, sceneType: sceneType, ruleNamespace: namespace, ruleId: rule.ruleId)
    }

    private func sourceAppToken(from raw: Any?) -> String {
        if let number = raw as? Int {
            switch number {
            case RuleBillSource.alipay.rawValue: return "alipay"
            case RuleBillSource.wechat.rawValue: return "wechat"
            case RuleBillSource.generic.rawValue: return "generic"
            default: return RuleIdentity.wildcard
            }
        }
        if let number = raw as? NSNumber {
            return sourceAppToken(from: number.intValue)
        }
        if let string = raw as? String {
            let normalized = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty { return RuleIdentity.wildcard }
            if ["1", "wechat", "weixin"].contains(normalized) { return "wechat" }
            if ["2", "alipay", "ali"].contains(normalized) { return "alipay" }
            if ["3", "generic", "unknown"].contains(normalized) { return "generic" }
            return normalized
        }
        return RuleIdentity.wildcard
    }

    private func sceneTypeToken(from raw: Any?) -> String {
        if let number = raw as? Int {
            switch number {
            case KeywordListType.aliAppear.rawValue: return "alipay_appear"
            case KeywordListType.aliCredit.rawValue: return "alipay_credit"
            case KeywordListType.aliIncome.rawValue: return "alipay_income"
            case KeywordListType.aliTransfer.rawValue: return "alipay_transfer"
            case KeywordListType.weAppear.rawValue: return "wechat_appear"
            case KeywordListType.weCredit.rawValue: return "wechat_credit"
            case KeywordListType.weIncome.rawValue: return "wechat_income"
            case KeywordListType.weTransfer.rawValue: return "wechat_transfer"
            default: return RuleIdentity.wildcard
            }
        }
        if let number = raw as? NSNumber {
            return sceneTypeToken(from: number.intValue)
        }
        if let string = raw as? String {
            let normalized = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? RuleIdentity.wildcard : normalized
        }
        return RuleIdentity.wildcard
    }

    private func namespaceToken(from raw: Any?) -> String {
        if let number = raw as? Int {
            switch number {
            case RuleKind.local.rawValue: return "local"
            case RuleKind.common.rawValue: return "common"
            case RuleKind.auto.rawValue: return "auto"
            default: return RuleIdentity.wildcard
            }
        }
        if let number = raw as? NSNumber {
            return namespaceToken(from: number.intValue)
        }
        if let string = raw as? String {
            let normalized = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? RuleIdentity.wildcard : normalized
        }
        return RuleIdentity.wildcard
    }

    private func inferredBillSource(from keywordSource: KeywordListType) -> RuleBillSource {
        switch keywordSource {
        case .aliAppear, .aliCredit, .aliIncome, .aliTransfer:
            return .alipay
        case .weAppear, .weCredit, .weIncome, .weTransfer:
            return .wechat
        }
    }

    private func logRulePackageEvent(_ event: String, extra: String) {
        print("[RuleUpdateService] \(event): \(extra)")
    }

    private func ruleKind(of rule: KeywordRule) -> RuleKind {
        if let kind = rule.searchTexts?.first?.ruleKind { return kind }
        return (rule.memberId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? .local
            : .auto
    }

    private func validateRules(_ rules: [KeywordRule]) -> Bool {
        guard !rules.isEmpty else { return false }
        let ids = Set(rules.map(\.ruleId))
        guard ids.count == rules.count else { return false }
        return rules.allSatisfy { !$0.keyWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func calculateChecksum(for rules: [KeywordRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "" }
        return sha256Hex(data)
    }

    private func sha256Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { rawBuffer in
            _ = CC_SHA256(rawBuffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func firstValue(keys: [String], in json: [String: Any]) -> Any? {
        for key in keys {
            if let value = json[key] {
                return value
            }
        }
        return nil
    }

    private func stringValue(keys: [String], in json: [String: Any]) -> String? {
        for key in keys {
            if let value = json[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func intValue(keys: [String], in json: [String: Any]) -> Int? {
        for key in keys {
            if let value = json[key] as? Int {
                return value
            }
            if let value = json[key] as? NSNumber {
                return value.intValue
            }
            if let value = json[key] as? String, let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    private func intArrayValue(keys: [String], in json: [String: Any]) -> [Int] {
        guard let value = firstValue(keys: keys, in: json) else { return [] }
        if let ints = value as? [Int] {
            return ints
        }
        if let numbers = value as? [NSNumber] {
            return numbers.map(\.intValue)
        }
        if let strings = value as? [String] {
            return strings.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return []
    }

    private func doubleValue(keys: [String], in json: [String: Any]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return value
            }
            if let value = json[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = json[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }

    private func dateValue(keys: [String], in json: [String: Any]) -> Date? {
        for key in keys {
            guard let value = json[key] else { continue }
            if let number = value as? NSNumber {
                let seconds = number.doubleValue
                return seconds > 10_000_000_000
                    ? Date(timeIntervalSince1970: seconds / 1000.0)
                    : Date(timeIntervalSince1970: seconds)
            }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let timestamp = Double(trimmed) {
                    return timestamp > 10_000_000_000
                        ? Date(timeIntervalSince1970: timestamp / 1000.0)
                        : Date(timeIntervalSince1970: timestamp)
                }
                let isoFormatter = ISO8601DateFormatter()
                if let date = isoFormatter.date(from: trimmed) {
                    return date
                }
            }
        }
        return nil
    }

    private func boolValue(keys: [String], in json: [String: Any]) -> Bool? {
        for key in keys {
            if let value = json[key] as? Bool {
                return value
            }
            if let value = json[key] as? NSNumber {
                return value.boolValue
            }
            if let value = json[key] as? String {
                switch value.lowercased() {
                case "1", "true", "yes":
                    return true
                case "0", "false", "no":
                    return false
                default:
                    break
                }
            }
        }
        return nil
    }

    private func stringArray(from value: Any?) -> [String] {
        guard let value else { return [] }
        if let strings = value as? [String] {
            return strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let numbers = value as? [NSNumber] {
            return numbers.map(\.stringValue)
        }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? [] : [normalized]
        }
        return []
    }

    // MARK: - AES Decryption (same as ConfigHotUpdateService)

    /// AES-128-CFB解密
    private func aesDecrypt(_ base64String: String) -> Data? {
        guard let remoteConfig = resolveRemoteConfig() else {
            return nil
        }
        guard let encryptedData = Data(base64Encoded: base64String) else {
            return nil
        }
        return aesCFBDecrypt(data: encryptedData, key: remoteConfig.aesKey, iv: remoteConfig.aesIV)
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
                            CCOptions(kCCModeCFB),
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
            return nil
        }

        decrypted.removeSubrange(numBytesDecrypted..<decrypted.count)
        return decrypted
    }

#if DEBUG
    func debugResetPackageStateForTests() {
        UserDefaults.standard.removeObject(forKey: Self.rulesPackageStateKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesBaseSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesActiveSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesPreviousSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesEmergencyDisabledKeysKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesDynamicNoiseKeywordsKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.rulesETagKey)
        cachedRules = nil
    }

    @discardableResult
    func debugApplyRulesForTests(
        _ rules: [KeywordRule],
        baseVersion: Int,
        patchVersion: Int,
        expectedChecksum: String? = nil
    ) -> Bool {
        let payload = RulePackagePayload(
            baseRulesVersion: baseVersion,
            patchRulesVersion: patchVersion,
            configVersion: patchVersion,
            publishTime: Date(),
            expectedChecksum: expectedChecksum,
            responseETag: nil,
            rules: rules,
            tombstones: [],
            noiseKeywordDelta: nil,
            snapshotRef: "test-\(baseVersion)-\(patchVersion)-\(Int(Date().timeIntervalSince1970))"
        )
        return applyRulePayload(payload)
    }

    @discardableResult
    func debugApplyPatchJSONForTests(
        _ patchJSON: [String: Any],
        baseRules: [KeywordRule],
        baseVersion: Int,
        patchVersion: Int,
        configVersion: Int
    ) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: patchJSON) else { return false }
        guard let patch = try? decodePatchPayload(from: data) else { return false }
        let merged = mergePatchPayload(patch, onto: baseRules)
        let state = loadPackageState()
        let (guardedRules, guardedTombstones) = applyLocalOverrideGuards(
            to: merged.rules,
            state: state,
            incomingTombstones: merged.tombstones
        )
        let payload = RulePackagePayload(
            baseRulesVersion: baseVersion,
            patchRulesVersion: patchVersion,
            configVersion: configVersion,
            publishTime: Date(),
            expectedChecksum: nil,
            responseETag: nil,
            rules: guardedRules,
            tombstones: guardedTombstones,
            noiseKeywordDelta: merged.noiseKeywordDelta,
            snapshotRef: "test-patch-\(baseVersion)-\(patchVersion)-\(configVersion)-\(Int(Date().timeIntervalSince1970))"
        )
        return applyRulePayload(payload)
    }

    func debugSetEmergencyDisabledFingerprintsForTests(_ fingerprints: [String]) {
        UserDefaults.standard.set(fingerprints, forKey: Self.rulesEmergencyDisabledKeysKey)
    }

    func debugIdentityFingerprintForRule(_ rule: KeywordRule) -> String {
        ruleIdentity(for: rule).fingerprint
    }
#endif
}

// MARK: - API Response

struct RulesAPIResponse: Codable {
    let code: Int
    let message: String
    let data: Data
    let version: Int
}

// MARK: - Notification

extension Notification.Name {
    static let keywordRulesDidUpdate = Notification.Name("KeywordRulesDidUpdate")
    static let keywordRulesDidActivate = Notification.Name("KeywordRulesDidActivate")
}

// MARK: - Default Rules (Fallback)

extension RuleUpdateService {

    /// 获取默认规则（当SQLite为空时使用）
    @discardableResult
    func loadDefaultRules() -> Bool {
        let defaultRules = buildDefaultRules()
        return activateRules(
            defaultRules,
            baseVersion: Self.bundledDefaultRulesVersion,
            patchVersion: Self.bundledDefaultRulesVersion,
            configVersion: Self.bundledDefaultRulesVersion,
            publishedAt: Date(),
            expectedChecksum: nil,
            tombstones: loadPackageState().tombstones,
            noiseKeywordDelta: nil,
            snapshotRef: "bundled-default-v\(Self.bundledDefaultRulesVersion)",
            responseETag: nil,
            isRollback: false
        )
    }

    private func buildDefaultRules() -> [KeywordRule] {
        var rules: [KeywordRule] = []
        var ruleId = 1

        // 支付宝支出关键词
        let aliAppearRules = [
            ("外卖", "dining", KeywordListType.aliAppear),
            ("餐饮", "dining", KeywordListType.aliAppear),
            ("美食", "dining", KeywordListType.aliAppear),
            ("饿了么", "dining", KeywordListType.aliAppear),
            ("美团", "dining", KeywordListType.aliAppear),
            ("打车", "transport", KeywordListType.aliAppear),
            ("滴滴", "transport", KeywordListType.aliAppear),
            ("出行", "transport", KeywordListType.aliAppear),
            ("地铁", "transport", KeywordListType.aliAppear),
            ("公交", "transport", KeywordListType.aliAppear),
            ("购物", "shopping", KeywordListType.aliAppear),
            ("淘宝", "shopping", KeywordListType.aliAppear),
            ("京东", "shopping", KeywordListType.aliAppear),
            ("超市", "shopping", KeywordListType.aliAppear),
            ("电影", "entertainment", KeywordListType.aliAppear),
            ("游戏", "entertainment", KeywordListType.aliAppear),
            ("旅行", "entertainment", KeywordListType.aliAppear),
            ("酒店", "entertainment", KeywordListType.aliAppear),
            ("房租", "housing", KeywordListType.aliAppear),
            ("水电", "housing", KeywordListType.aliAppear),
            ("话费", "utilities", KeywordListType.aliAppear),
            ("医疗", "medical", KeywordListType.aliAppear),
            ("药店", "medical", KeywordListType.aliAppear),
            ("教育", "education", KeywordListType.aliAppear),
            ("书籍", "education", KeywordListType.aliAppear),
        ]

        for (keyword, categoryKey, source) in aliAppearRules {
            let rule = KeywordRule(
                ruleId: ruleId,
                keyWord: keyword,
                type: .expense,
                memberCateId: categoryKeyToId(categoryKey),
                billsBookId: 0,
                keyWordSource: source,
                fundAccountId: 2, // 支付宝
                searchTexts: [
                    AutoBillSearchText(
                        ruleId: ruleId,
                        ruleKind: .auto,
                        billSource: .alipay,
                        minMatchValue: 0,
                        matchType: .contains,
                        isFuzzy: true,
                        isFuzzyLastValue: false,
                        isOptional: false,
                        columnCount: 1,
                        candidateType: .textObservation,
                        subCandidateType: 0
                    )
                ]
            )
            rules.append(rule)
            ruleId += 1
        }

        // 支付宝收入关键词
        let aliIncomeRules = [
            ("工资", "salary", KeywordListType.aliIncome),
            ("薪资", "salary", KeywordListType.aliIncome),
            ("退款", "refund", KeywordListType.aliIncome),
            ("返还", "refund", KeywordListType.aliIncome),
            ("红包", "redpacket_income", KeywordListType.aliIncome),
            ("理财收益", "investment", KeywordListType.aliIncome),
            ("余额宝收益", "investment", KeywordListType.aliIncome),
        ]

        for (keyword, categoryKey, source) in aliIncomeRules {
            let rule = KeywordRule(
                ruleId: ruleId,
                keyWord: keyword,
                type: .income,
                memberCateId: categoryKeyToId(categoryKey),
                billsBookId: 0,
                keyWordSource: source,
                fundAccountId: 2,
                searchTexts: [
                    AutoBillSearchText(
                        ruleId: ruleId,
                        ruleKind: .auto,
                        billSource: .alipay,
                        minMatchValue: 0,
                        matchType: .contains,
                        isFuzzy: true,
                        isFuzzyLastValue: false,
                        isOptional: false,
                        columnCount: 1,
                        candidateType: .textObservation,
                        subCandidateType: 0
                    )
                ]
            )
            rules.append(rule)
            ruleId += 1
        }

        // 微信支出关键词
        let weAppearRules = [
            ("外卖", "dining", KeywordListType.weAppear),
            ("餐饮", "dining", KeywordListType.weAppear),
            ("美食", "dining", KeywordListType.weAppear),
            ("美团", "dining", KeywordListType.weAppear),
            ("打车", "transport", KeywordListType.weAppear),
            ("滴滴", "transport", KeywordListType.weAppear),
            ("出行", "transport", KeywordListType.weAppear),
            ("地铁", "transport", KeywordListType.weAppear),
            ("购物", "shopping", KeywordListType.weAppear),
            ("京东", "shopping", KeywordListType.weAppear),
            ("拼多多", "shopping", KeywordListType.weAppear),
            ("电影", "entertainment", KeywordListType.weAppear),
            ("游戏", "entertainment", KeywordListType.weAppear),
            ("旅行", "entertainment", KeywordListType.weAppear),
        ]

        for (keyword, categoryKey, source) in weAppearRules {
            let rule = KeywordRule(
                ruleId: ruleId,
                keyWord: keyword,
                type: .expense,
                memberCateId: categoryKeyToId(categoryKey),
                billsBookId: 0,
                keyWordSource: source,
                fundAccountId: 1, // 微信
                searchTexts: [
                    AutoBillSearchText(
                        ruleId: ruleId,
                        ruleKind: .auto,
                        billSource: .wechat,
                        minMatchValue: 0,
                        matchType: .contains,
                        isFuzzy: true,
                        isFuzzyLastValue: false,
                        isOptional: false,
                        columnCount: 1,
                        candidateType: .textObservation,
                        subCandidateType: 0
                    )
                ]
            )
            rules.append(rule)
            ruleId += 1
        }

        // 微信收入关键词
        let weIncomeRules = [
            ("红包", "redpacket_income", KeywordListType.weIncome),
            ("退款", "refund", KeywordListType.weIncome),
            ("转账", "transfer", KeywordListType.weIncome),
            ("工资", "salary", KeywordListType.weIncome),
        ]

        for (keyword, categoryKey, source) in weIncomeRules {
            let rule = KeywordRule(
                ruleId: ruleId,
                keyWord: keyword,
                type: .income,
                memberCateId: categoryKeyToId(categoryKey),
                billsBookId: 0,
                keyWordSource: source,
                fundAccountId: 1,
                searchTexts: [
                    AutoBillSearchText(
                        ruleId: ruleId,
                        ruleKind: .auto,
                        billSource: .wechat,
                        minMatchValue: 0,
                        matchType: .contains,
                        isFuzzy: true,
                        isFuzzyLastValue: false,
                        isOptional: false,
                        columnCount: 1,
                        candidateType: .textObservation,
                        subCandidateType: 0
                    )
                ]
            )
            rules.append(rule)
            ruleId += 1
        }

        return rules
    }

    /// 将categoryKey转换为memberCateId（这里简单处理，实际需要映射表）
    private func categoryKeyToId(_ categoryKey: String) -> Int {
        let map: [String: Int] = [
            "dining": 1,
            "transport": 2,
            "shopping": 3,
            "entertainment": 4,
            "housing": 5,
            "utilities": 6,
            "medical": 7,
            "education": 8,
            "salary": 100,
            "investment": 101,
            "refund": 102,
            "redpacket_income": 103,
            "transfer": 200,
        ]
        return map[categoryKey] ?? 0
    }
}
