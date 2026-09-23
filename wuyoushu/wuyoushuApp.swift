import SwiftUI
import UIKit
import CoreData
import Photos
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(Intents)
import Intents
#endif

extension Notification.Name {
    static let assetLifeDidReceiveShortcutActivity = Notification.Name("assetLifeDidReceiveShortcutActivity")
}

// MARK: - Activity Dedup Key (防止同一事件被多入口重复消费)

@MainActor
enum ActivityDeduplicator {
    private static var seen: [String: Date] = [:]
    private static let dedupTTL: TimeInterval = 8.0
    private static let baseDedupTTL: TimeInterval = 1.6

    /// 返回 true 表示重复，应跳过。
    static func isDuplicate(primaryKey: String, baseKey: String) -> Bool {
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < dedupTTL }

        if let lastPrimary = seen[primaryKey], now.timeIntervalSince(lastPrimary) < dedupTTL {
            return true
        }
        if let lastBase = seen[baseKey], now.timeIntervalSince(lastBase) < baseDedupTTL {
            return true
        }

        seen[primaryKey] = now
        seen[baseKey] = now
        return false
    }
}

private enum ShortcutEventIDBuilder {
    static func build(from source: String) -> String {
        let compact = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(fnv1a64(compact), radix: 16)
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

enum ShortcutUserActivityBridge {
    @MainActor
    static func handle(_ userActivity: NSUserActivity, source: String) -> Bool {
        let type = userActivity.activityType
        let info = userActivity.userInfo ?? [:]
        print("[\(source)] userActivity type=\(type), userInfoKeys=\(Array(info.keys))")

        let imagePathFromInfo = info["imagePath"] as? String
        let deepLink = (info["deepLink"] as? String) ?? ""
        let interactionFingerprint = extractInteractionFingerprint(from: userActivity)
        let imageFingerprint = imagePathFromInfo.flatMap(fileFingerprint(at:))
            ?? interactionFingerprint
            ?? "no-image"
        let dedupKey = "\(type)|\(deepLink)|\(imageFingerprint)"
        let baseKey = "\(type)|\(deepLink)"

        if ActivityDeduplicator.isDuplicate(primaryKey: dedupKey, baseKey: baseKey) {
            print("[\(source)] dedup skip: \(dedupKey)")
            return true
        }

        let imagePath = imagePathFromInfo ?? extractPendingImagePath(from: userActivity)
        if let imagePath, !imagePath.isEmpty {
            ShortcutStorage.pendingRecordImagePath = imagePath
        }

        let action = (info["action"] as? String)?.lowercased()
        let deepLinkLower = deepLink.lowercased()
        let typeLower = type.lowercased()
        let isIOS15HomeFallback: Bool = {
            guard type == "com.assetlife.openHome" else { return false }
            if #available(iOS 16.0, *) { return false }
            return true
        }()

        let shouldOpenRecord = (
            type == "com.assetlife.shortcuts.addRecord" ||
            type == "com.assetlife.shortcuts.autoBill" ||
            type == "com.assetlife.addRecord" ||
            type == "com.assetlife.openRecord" ||
            isIOS15HomeFallback ||
            typeLower.contains("addrecord") ||
            typeLower.contains("autobill") ||
            (typeLower.contains("openrecord") && typeLower.contains("assetlife")) ||
            action?.contains("addrecord") == true ||
            action?.contains("autobill") == true ||
            action?.contains("openrecord") == true ||
            deepLinkLower.hasPrefix("assetlife://record")
        )

        guard shouldOpenRecord else { return false }
        if isIOS15HomeFallback {
            print("[\(source)] iOS15 fallback: treat openHome as addRecord")
        }
        ShortcutStorage.pendingAction = .addRecord
        NotificationCenter.default.post(name: .assetLifeDidReceiveShortcutActivity, object: nil)
        return true
    }

    static func extractPendingImagePath(from activity: NSUserActivity) -> String? {
        if let imagePath = activity.userInfo?["imagePath"] as? String, !imagePath.isEmpty {
            return imagePath
        }

        #if canImport(Intents)
        if let intent = activity.interaction?.intent {
            // File-based image parameter: INFile?
            if let file = selectorValue(from: intent as NSObject, selectorName: "image") as? INFile {
                return persistINFile(file)
            }
        }
        #endif

        return nil
    }

    static func extractInteractionFingerprint(from activity: NSUserActivity) -> String? {
        #if canImport(Intents)
        guard let intent = activity.interaction?.intent,
              let file = selectorValue(from: intent as NSObject, selectorName: "image") as? INFile else {
            return nil
        }
        let data = file.data
        guard !data.isEmpty else { return nil }
        let head = data.prefix(256)
        return ShortcutEventIDBuilder.build(from: "infile:\(data.count)|\(head.base64EncodedString())")
        #else
        return nil
        #endif
    }

    static func fileFingerprint(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return ShortcutEventIDBuilder.build(from: "file:\(filename)|\(size)|\(modified)")
    }

    #if canImport(Intents)
    static func persistINFile(_ file: INFile) -> String? {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShortcutStorage.suiteName
        ) ?? FileManager.default.temporaryDirectory
        let filename = file.filename.isEmpty
            ? "shortcut-capture-\(UUID().uuidString).png"
            : "shortcut-capture-\(UUID().uuidString)-\(file.filename)"
        let targetURL = directory.appendingPathComponent(filename)

        let data = file.data
        guard !data.isEmpty else { return nil }
        do {
            try data.write(to: targetURL, options: .atomic)
            return targetURL.path
        } catch {
            return nil
        }
    }

    static func selectorValue(from object: NSObject, selectorName: String) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector), let unmanaged = object.perform(selector) else {
            return nil
        }
        return unmanaged.takeUnretainedValue()
    }
    #endif
}

@MainActor
final class AssetLifeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        for activity in connectionOptions.userActivities {
            _ = ShortcutUserActivityBridge.handle(activity, source: "SceneDelegate(willConnect)")
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = ShortcutUserActivityBridge.handle(userActivity, source: "SceneDelegate(continue)")
    }
}

// MARK: - AChai-style Intent Handler (runs in main app, not a separate extension)

@available(iOS 13.0, *)
final class AutoBillLegacyIntentHandler: NSObject, AutoBillLegacyIntentHandling {
    func handle(intent: AutoBillLegacyIntent) async -> AutoBillLegacyIntentResponse {
        let imageFile = intent.image
        print("[AutoBillHandler] handle called, image=\(imageFile != nil)")

        guard let imageFile else {
            print("[AutoBillHandler] No image file, returning failure")
            return AutoBillLegacyIntentResponse(code: .failure, userActivity: nil)
        }

        // Extract image data from INFile
        let imageData = imageFile.data

        guard !imageData.isEmpty, let image = UIImage(data: imageData) else {
            print("[AutoBillHandler] Empty or invalid image data (\(imageData.count) bytes)")
            return AutoBillLegacyIntentResponse(code: .failure, userActivity: nil)
        }

        print("[AutoBillHandler] Image loaded: \(image.size), running OCR...")

        // Run OCR
        let recognizedText: String
        do {
            recognizedText = try await ProductionOCRService.shared.recognizeText(from: image)
        } catch {
            print("[AutoBillHandler] OCR failed: \(error)")
            return await continueInApp(with: imageFile)
        }

        guard !recognizedText.isEmpty else {
            print("[AutoBillHandler] OCR returned empty text")
            return await continueInApp(with: imageFile)
        }

        print("[AutoBillHandler] OCR result: \(recognizedText.prefix(200))")

        // Parse transaction
        let parser = ProductionTransactionParserService()
        let parsedCandidates = parser.parse(recognizedText)
        guard let parsed = parser.bestCandidate(from: parsedCandidates),
              let amount = parsed.amount, amount > 0 else {
            print("[AutoBillHandler] No valid transaction parsed")
            return await continueInApp(with: imageFile)
        }

        // 快捷指令统一走“记一笔确认页”链路：不在 Intent 阶段自动落库，避免重复记账。
        let payloads = parsedCandidates.map(ParsedTransactionCandidatePayload.init(transaction:))
        let normalizedMerchant = (parsed.merchantName ?? parsed.toBiz ?? parsed.note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDate = parsed.date?.formatted(as: "yyyy-MM-dd") ?? ""
        let normalizedOCR = recognizedText
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let eventSeed = [
            parsed.billSource.rawValue,
            parsed.isIncome ? "income" : "expense",
            String(format: "%.2f", amount),
            normalizedDate,
            normalizedMerchant,
            String(normalizedOCR.prefix(240))
        ].joined(separator: "|")
        let eventID = ShortcutEventIDBuilder.build(from: eventSeed)

        let pendingParams = ShortcutStorage.PendingRecordParams(
            amount: parsed.amount,
            categoryKey: parsed.categoryKey,
            note: parsed.merchantName ?? parsed.toBiz ?? parsed.note,
            isIncome: parsed.isIncome,
            imagePath: nil,
            date: parsed.date.map { ISO8601DateFormatter().string(from: $0) },
            candidates: payloads,
            eventID: eventID
        )

        let resultText: String
        if parsedCandidates.count > 1 {
            resultText = "识别到 \(parsedCandidates.count) 笔，待你确认后入账"
        } else {
            resultText = "已识别 ¥\(String(format: "%.2f", amount))，待你确认后入账"
        }

        return await continueInApp(
            with: imageFile,
            result: resultText,
            pendingParams: pendingParams
        )
    }

    func confirm(intent: AutoBillLegacyIntent) async -> AutoBillLegacyIntentResponse {
        return AutoBillLegacyIntentResponse(code: .ready, userActivity: nil)
    }

    /// Open the app and navigate to record page, optionally with a result message.
    private func continueInApp(
        with file: INFile,
        result: String? = nil,
        pendingParams: ShortcutStorage.PendingRecordParams? = nil
    ) async -> AutoBillLegacyIntentResponse {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShortcutStorage.suiteName
        ) ?? FileManager.default.temporaryDirectory
        let targetURL = directory.appendingPathComponent("shortcut-capture-\(UUID().uuidString).png")

        let data = file.data
        let savedImagePath: String?
        do {
            try data.write(to: targetURL, options: .atomic)
            savedImagePath = targetURL.path
        } catch {
            print("[AutoBillHandler] Failed to persist fallback image: \(error)")
            savedImagePath = nil
        }

        await MainActor.run {
            ShortcutStorage.pendingAction = .addRecord
            if let pendingParams {
                ShortcutStorage.pendingRecordParams = pendingParams
            }
            if let savedImagePath {
                ShortcutStorage.pendingRecordImagePath = savedImagePath
            }
        }

        let activity = NSUserActivity(activityType: "com.assetlife.shortcuts.autoBill")
        activity.title = "自动记账"
        activity.userInfo = [
            "action": "com.assetlife.shortcuts.autoBill",
            "deepLink": "assetlife://record"
        ]

        let response = AutoBillLegacyIntentResponse(code: .continueInApp, userActivity: activity)
        response.result = result
        return response
    }

}

// MARK: - AppDelegate

@MainActor
final class AssetLifeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = AssetLifeSceneDelegate.self
        return configuration
    }

    // MARK: - AChai-style: handle intents directly in main app (no separate Intent Extension)

    func application(
        _ application: UIApplication,
        handlerFor intent: INIntent
    ) -> Any? {
        if intent is AutoBillLegacyIntent {
            print("[AppDelegate] handlerForIntent: returning AutoBillLegacyIntentHandler")
            return AutoBillLegacyIntentHandler()
        }
        print("[AppDelegate] handlerForIntent: unhandled intent type \(type(of: intent))")
        return nil
    }

    @MainActor
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        ShortcutUserActivityBridge.handle(userActivity, source: "AppDelegate(continue)")
    }
}

@main
struct AssetLifeApp: App {
    @UIApplicationDelegateAdaptor(AssetLifeAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    private let persistenceController = PersistenceController.shared

    @State private var screenshotBanner: ScreenshotBannerData?
    @State private var hasScheduledConsumption = false
    @State private var hasDonatedLegacyActivities = false
    @AppStorage("didMigrateLegacyShortcutDonations") private var didMigrateLegacyShortcutDonations = false

    struct ScreenshotBannerData {
        let amount: Double
        let categoryKey: String?
        let isIncome: Bool
        let image: UIImage
        let date: Date?
        let candidates: [ParsedTransactionCandidatePayload]
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                MainTabView()
                    .environmentObject(router)

                if let banner = screenshotBanner {
                    ScreenshotBannerView(
                        amount: banner.amount,
                        categoryKey: banner.categoryKey,
                        isIncome: banner.isIncome,
                        onTap: {
                            handleScreenshotBannerTap(banner)
                            screenshotBanner = nil
                        },
                        onDismiss: {
                            screenshotBanner = nil
                        }
                    )
                    .zIndex(999)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                if #available(iOS 16.0, *) {
                    AssetLifeShortcuts.updateAppShortcutParameters()
                    print("[Shortcuts] Registered \(AssetLifeShortcuts.appShortcuts.count) app shortcuts")
                }
                ensureScreenshotDetectionAuthorizationIfNeeded()
                migrateLegacyShortcutDonationsIfNeeded()
                donateLegacyActivitiesIfNeeded()
                consumePendingShortcutAction()
                refreshRulesSafely()
                refreshConfigSafely()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    ScreenshotDetector.shared.recordBackgroundTime()
                }
                guard newPhase == .active else { return }
                ensureScreenshotDetectionAuthorizationIfNeeded()
                consumePendingShortcutAction()
                checkForNewScreenshot()
                refreshRulesSafely()
                refreshConfigSafely()
            }
            .onReceive(NotificationCenter.default.publisher(for: .assetLifeDidReceiveShortcutActivity)) { _ in
                consumePendingShortcutAction()
            }
            .onOpenURL { url in
                router.handleDeepLink(url)
            }
            // Unified shortcut funnel: all onContinueUserActivity types go through the same bridge
            .onContinueUserActivity("com.assetlife.openHome") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(openHome)")
            }
            .onContinueUserActivity("com.assetlife.openRecord") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(openRecord)")
            }
            .onContinueUserActivity("com.assetlife.openStats") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(openStats)")
            }
            .onContinueUserActivity("com.assetlife.addRecord") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(addRecord)")
            }
            .onContinueUserActivity("com.assetlife.openAsset") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(openAsset)")
            }
            .onContinueUserActivity("com.assetlife.addAsset") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(addAsset)")
            }
            .onContinueUserActivity("com.assetlife.openWish") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(openWish)")
            }
            .onContinueUserActivity("com.assetlife.addWish") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(addWish)")
            }
            .onContinueUserActivity("com.assetlife.openProfile") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(openProfile)")
            }
            .onContinueUserActivity("com.assetlife.shortcuts.addRecord") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(shortcuts.addRecord)")
            }
            .onContinueUserActivity("com.assetlife.shortcuts.autoBill") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(shortcuts.autoBill)")
            }
            .onContinueUserActivity("com.assetlife.recordFromScreenshot") { activity in
                _ = ShortcutUserActivityBridge.handle(activity, source: "onContinue(recordFromScreenshot)")
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }

    @MainActor
    private func consumePendingShortcutAction() {
        guard !hasScheduledConsumption else { return }
        hasScheduledConsumption = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { @MainActor [self] in
            hasScheduledConsumption = false
            print(
                "[App] consumePendingShortcutAction: action=\(ShortcutStorage.pendingAction?.rawValue ?? "nil"), " +
                "hasParams=\(ShortcutStorage.pendingRecordParams != nil), " +
                "pendingImagePath=\(ShortcutStorage.pendingRecordImagePath ?? "nil")"
            )
            router.handlePendingShortcutAction()
        }
    }

    private func donateLegacyActivitiesIfNeeded() {
        guard !hasDonatedLegacyActivities else { return }
        hasDonatedLegacyActivities = true

        guard #unavailable(iOS 16.0) else { return }

        let activities: [(String, String, [String: Any])] = [
            (
                "com.assetlife.shortcuts.addRecord",
                "记一笔",
                [
                    "action": "com.assetlife.addRecord",
                    "deepLink": "assetlife://record"
                ]
            )
        ]

        for (type, title, userInfo) in activities {
            let activity = NSUserActivity(activityType: type)
            activity.title = title
            activity.userInfo = userInfo
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.keywords = [title, "小西记账", "记账", "快捷指令"]
            activity.persistentIdentifier = NSUserActivityPersistentIdentifier(type)
            activity.becomeCurrent()
            activity.resignCurrent()
        }

        print("[Shortcuts] Donated legacy searchable activities for iOS15: addRecord only")
    }

    private func migrateLegacyShortcutDonationsIfNeeded() {
        guard #unavailable(iOS 16.0) else { return }
        guard !didMigrateLegacyShortcutDonations else { return }

        let staleIdentifiers = [
            NSUserActivityPersistentIdentifier("com.assetlife.shortcuts.autoBill"),
            NSUserActivityPersistentIdentifier("com.assetlife.shortcuts.addRecord.legacy"),
            NSUserActivityPersistentIdentifier("com.assetlife.shortcuts.autoBill.legacy")
        ]

        NSUserActivity.deleteSavedUserActivities(withPersistentIdentifiers: staleIdentifiers) {
            print("[Shortcuts] Removed stale legacy donated activities: autoBill")
        }

        didMigrateLegacyShortcutDonations = true
    }

    private func checkForNewScreenshot() {
        guard ScreenshotDetector.shared.isEnabled else { return }
        Task {
            guard let image = await ScreenshotDetector.shared.checkForNewScreenshot() else { return }
            // Run OCR with spatial details on the screenshot
            guard let ocrResult = try? await ProductionOCRService.shared.recognizeTextWithDetails(from: image) else { return }
            let parser = ProductionTransactionParserService()
            let parsedCandidates = parser.parse(ocrResult)
            guard let parsed = parser.bestCandidate(from: parsedCandidates),
                  let amount = parsed.amount, amount > 0 else { return }
            let payloads = parsedCandidates.map(ParsedTransactionCandidatePayload.init(transaction:))

            await MainActor.run {
                screenshotBanner = ScreenshotBannerData(
                    amount: amount,
                    categoryKey: parsed.categoryKey,
                    isIncome: parsed.isIncome,
                    image: image,
                    date: parsed.date,
                    candidates: payloads
                )
            }
        }
    }

    private func refreshRulesSafely() {
        RuleUpdateService.shared.fetchLatestRules { _ in }
    }

    private func refreshConfigSafely() {
        ConfigHotUpdateService.shared.fetchLatestConfig { _ in }
    }

    private func ensureScreenshotDetectionAuthorizationIfNeeded() {
        guard ScreenshotDetector.shared.isEnabled else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .notDetermined else { return }
        Task {
            _ = await ScreenshotDetector.shared.requestAuthorization()
        }
    }

    private func handleScreenshotBannerTap(_ banner: ScreenshotBannerData) {
        // Save image to App Group and trigger QuickRecordView
        if let data = banner.image.pngData() {
            let directory = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: ShortcutStorage.suiteName
            ) ?? FileManager.default.temporaryDirectory
            let targetURL = directory.appendingPathComponent("screenshot-detected-\(UUID().uuidString).png")
            try? data.write(to: targetURL, options: .atomic)

            ShortcutStorage.pendingRecordImagePath = targetURL.path
        }
        ShortcutStorage.pendingRecordParams = .init(
            amount: banner.amount,
            categoryKey: banner.categoryKey,
            note: nil,
            isIncome: banner.isIncome,
            date: banner.date.map { ISO8601DateFormatter().string(from: $0) },
            candidates: banner.candidates.isEmpty ? nil : banner.candidates
        )
        ShortcutStorage.pendingAction = .addRecord
        router.handlePendingShortcutAction()
    }
}
