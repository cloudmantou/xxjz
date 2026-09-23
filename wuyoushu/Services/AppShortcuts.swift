import AppIntents
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Codable candidate payload for router/shortcut transport.
/// Keeps parsing results detached from Core Data objects.
struct ParsedTransactionCandidatePayload: Codable, Hashable, Identifiable {
    var id: String
    var amount: Double?
    var categoryKey: String?
    var note: String?
    var isIncome: Bool
    var dateISO8601: String?
    var billSourceRaw: String
    var merchantName: String?
    var transactionTimeISO8601: String?
    var fundName: String?
    var originalMoney: Double?
    var discountMoney: Double?
    var toBiz: String?
    var status: Int?
    var ruleKind: Int?

    init(
        id: String = UUID().uuidString,
        amount: Double?,
        categoryKey: String?,
        note: String?,
        isIncome: Bool,
        dateISO8601: String?,
        billSourceRaw: String,
        merchantName: String?,
        transactionTimeISO8601: String?,
        fundName: String?,
        originalMoney: Double?,
        discountMoney: Double?,
        toBiz: String?,
        status: Int?,
        ruleKind: Int?
    ) {
        self.id = id
        self.amount = amount
        self.categoryKey = categoryKey
        self.note = note
        self.isIncome = isIncome
        self.dateISO8601 = dateISO8601
        self.billSourceRaw = billSourceRaw
        self.merchantName = merchantName
        self.transactionTimeISO8601 = transactionTimeISO8601
        self.fundName = fundName
        self.originalMoney = originalMoney
        self.discountMoney = discountMoney
        self.toBiz = toBiz
        self.status = status
        self.ruleKind = ruleKind
    }
}

extension ParsedTransactionCandidatePayload {
    init(transaction: ParsedTransaction) {
        let formatter = ISO8601DateFormatter()
        self.init(
            amount: transaction.amount,
            categoryKey: transaction.categoryKey,
            note: transaction.note,
            isIncome: transaction.isIncome,
            dateISO8601: transaction.date.map { formatter.string(from: $0) },
            billSourceRaw: transaction.billSource.rawValue,
            merchantName: transaction.merchantName,
            transactionTimeISO8601: transaction.transactionTime.map { formatter.string(from: $0) },
            fundName: transaction.fundName,
            originalMoney: transaction.originalMoney,
            discountMoney: transaction.discountMoney,
            toBiz: transaction.toBiz,
            status: transaction.status,
            ruleKind: transaction.ruleKind
        )
    }

    func toParsedTransaction() -> ParsedTransaction {
        let formatter = ISO8601DateFormatter()
        var result = ParsedTransaction()
        result.amount = amount
        result.categoryKey = categoryKey
        result.note = note
        result.isIncome = isIncome
        result.date = dateISO8601.flatMap { formatter.date(from: $0) }
        result.billSource = BillSource(rawValue: billSourceRaw) ?? .unknown
        result.merchantName = merchantName
        result.transactionTime = transactionTimeISO8601.flatMap { formatter.date(from: $0) }
        result.fundName = fundName
        result.originalMoney = originalMoney
        result.discountMoney = discountMoney
        result.toBiz = toBiz
        result.status = status
        result.ruleKind = ruleKind
        return result
    }
}

// MARK: - App Shortcuts Provider (iOS 16+)

#if canImport(AppIntents)
@available(iOS 16.0, *)
struct AssetLifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        var shortcuts: [AppShortcut] = []

        shortcuts.append(
            AppShortcut(
                intent: OpenRecordIntent(),
                phrases: ["记一笔 用\(.applicationName)"],
                shortTitle: "记一笔",
                systemImageName: "plus.circle.fill"
            )
        )
        shortcuts.append(
            AppShortcut(
                intent: RecordFromScreenshotIntent(),
                phrases: ["用\(.applicationName)截图自动记账"],
                shortTitle: "自动记账",
                systemImageName: "photo.on.rectangle.angled"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: OpenHomeIntent(),
                phrases: ["打开\(.applicationName)"],
                shortTitle: "打开主页",
                systemImageName: "house.fill"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: OpenAssetTabIntent(),
                phrases: ["打开\(.applicationName)资产"],
                shortTitle: "资产",
                systemImageName: "creditcard.fill"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: OpenWishTabIntent(),
                phrases: ["打开\(.applicationName)心愿"],
                shortTitle: "心愿",
                systemImageName: "heart.fill"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: OpenProfileIntent(),
                phrases: ["打开\(.applicationName)我的"],
                shortTitle: "我的",
                systemImageName: "person.fill"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: AddAssetIntent(),
                phrases: ["用\(.applicationName)记资产"],
                shortTitle: "记资产",
                systemImageName: "creditcard.and.123"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: AddWishIntent(),
                phrases: ["用\(.applicationName)记心愿"],
                shortTitle: "记心愿",
                systemImageName: "heart.text.square.fill"
            )
        )

        return shortcuts
    }
}
#endif

// MARK: - Quick Record Category Parameter

@available(iOS 16.0, *)
enum QuickRecordCategory: String, CaseIterable, AppEnum {
    case dining
    case transport
    case shopping
    case entertainment
    case housing
    case medical
    case education
    case social
    case transfer
    case salary
    case parttime
    case investment
    case refund
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "记账分类")

    static var caseDisplayRepresentations: [QuickRecordCategory: DisplayRepresentation] = [
        .dining: DisplayRepresentation(title: "餐饮"),
        .transport: DisplayRepresentation(title: "交通"),
        .shopping: DisplayRepresentation(title: "购物"),
        .entertainment: DisplayRepresentation(title: "娱乐"),
        .housing: DisplayRepresentation(title: "居住"),
        .medical: DisplayRepresentation(title: "医疗"),
        .education: DisplayRepresentation(title: "教育"),
        .social: DisplayRepresentation(title: "人情"),
        .transfer: DisplayRepresentation(title: "转账"),
        .salary: DisplayRepresentation(title: "工资"),
        .parttime: DisplayRepresentation(title: "兼职"),
        .investment: DisplayRepresentation(title: "理财收益"),
        .refund: DisplayRepresentation(title: "退款"),
        .other: DisplayRepresentation(title: "其他")
    ]
}

// MARK: - Tab Navigation Intents

@available(iOS 16.0, *)
struct OpenHomeIntent: AppIntent {
    static var title: LocalizedStringResource = "打开主页"
    static var description = IntentDescription("快速进入应用主页。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingAction = .openHome
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenAssetTabIntent: AppIntent {
    static var title: LocalizedStringResource = "打开资产页"
    static var description = IntentDescription("快速进入资产管理页。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingAction = .openAsset
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenWishTabIntent: AppIntent {
    static var title: LocalizedStringResource = "打开心愿页"
    static var description = IntentDescription("快速进入心愿管理页。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingAction = .openWish
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "打开我的页"
    static var description = IntentDescription("快速进入个人中心。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingAction = .openProfile
        return .result()
    }
}

// MARK: - Quick Action Intents

@available(iOS 16.0, *)
struct AddAssetIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记资产"
    static var description = IntentDescription("打开应用并直接进入新增资产页面。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingAction = .addAsset
        return .result()
    }
}

@available(iOS 16.0, *)
struct AddWishIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记心愿"
    static var description = IntentDescription("打开应用并直接进入新增心愿页面。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingAction = .addWish
        return .result()
    }
}

// MARK: - Record Intents

@available(iOS 16.0, *)
struct OpenRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description = IntentDescription("直接打开记一笔页面。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutStorage.pendingRecordParams = nil
        ShortcutStorage.pendingAction = .addRecord
        return .result()
    }
}

@available(iOS 16.0, *)
extension OpenRecordIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, *)
struct RecordFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "自动记账"
    static var description = IntentDescription("接收支付页面截屏，识别金额和分类后打开快速记账。")
    static var openAppWhenRun = true
    static var parameterSummary: some ParameterSummary {
        Summary("自动记账，处理 \(\.$screenshot)")
    }

    @Parameter(title: "支付页面截屏")
    var screenshot: IntentFile

    func perform() async throws -> some IntentResult {
        guard let imagePath = ScreenshotRecordHelper.persistImage(intentFile: screenshot) else {
            let parsed = try await ScreenshotRecordHelper.parse(intentFile: screenshot)
            ShortcutStorage.pendingRecordParams = .init(
                amount: parsed.amount,
                categoryKey: parsed.categoryKey,
                note: parsed.note,
                isIncome: parsed.isIncome,
                imagePath: nil,
                date: parsed.dateISO8601,
                candidates: parsed.candidates.isEmpty ? nil : parsed.candidates
            )
            ShortcutStorage.pendingAction = .addRecord
            return .result()
        }

        ShortcutStorage.pendingRecordImagePath = imagePath
        ShortcutStorage.pendingAction = .addRecord
        return .result()
    }
}

@available(iOS 16.0, *)
extension RecordFromScreenshotIntent: ForegroundContinuableIntent {}

// MARK: - Screenshot Parsing Helpers

@available(iOS 16.0, *)
enum ScreenshotRecordIntentError: LocalizedError {
    case unsupportedFileType
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "请传入图片类型的截图"
        case .invalidImageData:
            return "截图读取失败，请重试"
        }
    }
}

@available(iOS 16.0, *)
private struct ScreenshotParsedRecord {
    let amount: Double?
    let categoryKey: String?
    let note: String?
    let isIncome: Bool?
    let dateISO8601: String?
    let candidates: [ParsedTransactionCandidatePayload]
}

@available(iOS 16.0, *)
private enum ScreenshotRecordHelper {
    static func persistImage(intentFile: IntentFile) -> String? {
        guard intentFile.type?.conforms(to: .image) ?? true else { return nil }
        guard !intentFile.data.isEmpty else { return nil }

        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShortcutStorage.suiteName
        ) ?? FileManager.default.temporaryDirectory

        let targetURL = directory.appendingPathComponent("shortcut-capture-\(UUID().uuidString).png")

        do {
            try intentFile.data.write(to: targetURL, options: .atomic)
            return targetURL.path
        } catch {
            return nil
        }
    }

    static func parse(intentFile: IntentFile) async throws -> ScreenshotParsedRecord {
        guard intentFile.type?.conforms(to: .image) ?? true else {
            throw ScreenshotRecordIntentError.unsupportedFileType
        }

        guard let image = UIImage(data: intentFile.data) else {
            throw ScreenshotRecordIntentError.invalidImageData
        }

        let ocrResult = try await ProductionOCRService.shared.recognizeTextWithDetails(from: image)
        let parser = ProductionTransactionParserService()
        let parsedCandidates = parser.parse(ocrResult)
        let parsed = parser.bestCandidate(from: parsedCandidates)
        let dateISO8601 = parsed?.date.map { ISO8601DateFormatter().string(from: $0) }
        let candidatePayloads = parsedCandidates.map(ParsedTransactionCandidatePayload.init(transaction:))

        return ScreenshotParsedRecord(
            amount: parsed?.amount,
            categoryKey: parsed?.categoryKey,
            note: preferredNote(from: parsed, fallbackText: ocrResult.fullText),
            isIncome: parsed?.isIncome,
            dateISO8601: dateISO8601,
            candidates: candidatePayloads
        )
    }

    private static func preferredNote(from parsed: ParsedTransaction?, fallbackText: String) -> String? {
        if let merchant = parsed?.merchantName,
           OCRSemanticFilter.isLikelyMerchantText(merchant) {
            return merchant
        }
        if let toBiz = parsed?.toBiz,
           OCRSemanticFilter.isLikelyMerchantText(toBiz) {
            return toBiz
        }
        if let parsedNote = parsed?.note,
           !OCRSemanticFilter.isLikelyNoiseNote(parsedNote) {
            return String(OCRSemanticFilter.normalize(parsedNote).prefix(40))
        }
        return compactNote(from: fallbackText)
    }

    private static func compactNote(from text: String) -> String? {
        OCRSemanticFilter.firstMeaningfulNoteLine(from: text, maxLength: 40)
    }
}

@available(iOS 16.0, *)
private enum ShortcutDeepLinkBuilder {
    static func recordURL(
        amount: Double?,
        categoryKey: String?,
        note: String?,
        isIncome: Bool?
    ) -> URL {
        var components = URLComponents()
        components.scheme = "assetlife"
        components.host = "record"

        var items: [URLQueryItem] = []
        if let amount {
            items.append(URLQueryItem(name: "amount", value: String(amount)))
        }
        if let categoryKey, !categoryKey.isEmpty {
            items.append(URLQueryItem(name: "category", value: categoryKey))
        }
        if let note, !note.isEmpty {
            items.append(URLQueryItem(name: "note", value: note))
        }
        if let isIncome {
            items.append(URLQueryItem(name: "income", value: isIncome ? "1" : "0"))
        }

        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? URL(string: "assetlife://record")!
    }
}

// MARK: - Shortcut Storage

final class ShortcutStorage {
    static let suiteName = "group.com.assetlife.shortcuts"
    static let actionKey = "pendingShortcutAction"
    static let recordParamsKey = "pendingRecordParams"
    static let recordImagePathKey = "pendingRecordImagePath"
    static let consumedRecordEventMapKey = "consumedRecordEventMap"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
    }

    enum PendingAction: String {
        case openHome
        case openAsset
        case openWish
        case openProfile
        case addAsset
        case addWish
        case openRecord
        case addRecord
    }

    struct PendingRecordParams: Codable {
        var amount: Double?
        var categoryKey: String?
        var note: String?
        var isIncome: Bool?
        var imagePath: String? = nil
        var date: String? = nil  // ISO8601 formatted date string
        var candidates: [ParsedTransactionCandidatePayload]? = nil
        var eventID: String? = nil
    }

    private struct ConsumedRecordEvent: Codable {
        let consumedAt: TimeInterval
        let transactionURI: String?
    }

    static var pendingAction: PendingAction? {
        get {
            guard let rawValue = defaults?.string(forKey: actionKey) else {
                return nil
            }
            return PendingAction(rawValue: rawValue)
        }
        set {
            if let newValue = newValue {
                defaults?.set(newValue.rawValue, forKey: actionKey)
            } else {
                defaults?.removeObject(forKey: actionKey)
            }
            notifyPendingShortcutChanged()
        }
    }

    static var pendingRecordParams: PendingRecordParams? {
        get {
            guard let data = defaults?.data(forKey: recordParamsKey) else {
                return nil
            }
            return try? JSONDecoder().decode(PendingRecordParams.self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: recordParamsKey)
            } else {
                defaults?.removeObject(forKey: recordParamsKey)
            }
            notifyPendingShortcutChanged()
        }
    }

    static var pendingRecordImagePath: String? {
        get {
            defaults?.string(forKey: recordImagePathKey)
        }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                defaults?.set(newValue, forKey: recordImagePathKey)
            } else {
                defaults?.removeObject(forKey: recordImagePathKey)
            }
            notifyPendingShortcutChanged()
        }
    }

    static func clearPendingAction() {
        defaults?.removeObject(forKey: actionKey)
        defaults?.removeObject(forKey: recordParamsKey)
        defaults?.removeObject(forKey: recordImagePathKey)
        notifyPendingShortcutChanged()
    }

    static func hasConsumedRecordEvent(_ eventID: String, ttl: TimeInterval = 30 * 60) -> Bool {
        guard !eventID.isEmpty else { return false }
        var map = loadConsumedRecordEvents()
        pruneConsumedRecordEvents(&map, ttl: ttl)
        saveConsumedRecordEvents(map)
        guard let existing = map[eventID] else { return false }
        return Date().timeIntervalSince1970 - existing.consumedAt < ttl
    }

    static func consumedRecordTransactionURI(for eventID: String, ttl: TimeInterval = 30 * 60) -> URL? {
        guard !eventID.isEmpty else { return nil }
        var map = loadConsumedRecordEvents()
        pruneConsumedRecordEvents(&map, ttl: ttl)
        saveConsumedRecordEvents(map)
        guard let uriString = map[eventID]?.transactionURI else { return nil }
        return URL(string: uriString)
    }

    static func markRecordEventConsumed(_ eventID: String, transactionURI: URL?) {
        guard !eventID.isEmpty else { return }
        var map = loadConsumedRecordEvents()
        map[eventID] = ConsumedRecordEvent(
            consumedAt: Date().timeIntervalSince1970,
            transactionURI: transactionURI?.absoluteString
        )
        pruneConsumedRecordEvents(&map, ttl: 30 * 60)
        saveConsumedRecordEvents(map)
    }

    private static func loadConsumedRecordEvents() -> [String: ConsumedRecordEvent] {
        guard let data = defaults?.data(forKey: consumedRecordEventMapKey),
              let decoded = try? JSONDecoder().decode([String: ConsumedRecordEvent].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveConsumedRecordEvents(_ map: [String: ConsumedRecordEvent]) {
        if map.isEmpty {
            defaults?.removeObject(forKey: consumedRecordEventMapKey)
            return
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults?.set(data, forKey: consumedRecordEventMapKey)
    }

    private static func pruneConsumedRecordEvents(
        _ map: inout [String: ConsumedRecordEvent],
        ttl: TimeInterval
    ) {
        let now = Date().timeIntervalSince1970
        map = map.filter { now - $0.value.consumedAt < ttl }
    }

    private static func notifyPendingShortcutChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .assetLifeDidReceiveShortcutActivity, object: nil)
        }
    }
}
