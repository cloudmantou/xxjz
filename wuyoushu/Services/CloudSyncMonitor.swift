import Foundation
import CoreData
import CloudKit
import Combine

/// A completed store load or account check is not evidence that records reached iCloud.
struct CloudSyncState {
    enum Phase: String, CaseIterable, Codable { case setup, upload, download }

    struct Failure: Equatable, Codable {
        let domain: String
        let code: Int
        let message: String

        static func from(_ error: Error) -> Failure {
            let outer = error as NSError
            // CloudKit errors are often wrapped by Core Data or a partial failure.
            let nested = (outer.userInfo[NSUnderlyingErrorKey] as? NSError)
                ?? (outer.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError])?.values.first
            if let nested, nested !== outer { return from(nested) }
            let message: String
            if outer.domain == CKErrorDomain, let code = CKError.Code(rawValue: outer.code) {
                switch code {
                case .notAuthenticated: message = "请在系统设置中登录 iCloud，并允许小西记账使用 iCloud。"
                case .networkUnavailable, .networkFailure: message = "网络暂不可用，联网后系统会重试同步。"
                case .quotaExceeded: message = "iCloud 空间不足，请释放空间后重试。"
                case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    message = "iCloud 暂时繁忙，系统会稍后重试。"
                case .permissionFailure, .missingEntitlement, .badContainer:
                    message = "iCloud 权限或应用配置异常，请联系开发者。"
                default: message = "iCloud 同步暂未成功，请稍后检查状态。"
                }
            } else {
                message = "iCloud 同步暂未成功，请稍后检查状态。"
            }
            // Never retain localizedDescription / userInfo: they can contain record data or account identifiers.
            return Failure(domain: outer.domain, code: outer.code, message: message)
        }
    }

    struct Activity {
        var active: [UUID: Date] = [:]
        var lastResultStart: Date?
        var lastSuccess: Date?
        var failure: Failure?
    }

    var activities: [Phase: Activity] = [:]
    private var storeActivities: [String: [Phase: Activity]] = [:]

    mutating func receive(id: UUID, phase: Phase, start: Date, end: Date?, succeeded: Bool, failure: Failure?, storeIdentifier: String? = nil) {
        if let storeIdentifier {
            var single = CloudSyncState()
            single.activities = storeActivities[storeIdentifier] ?? [:]
            single.receive(id: id, phase: phase, start: start, end: end, succeeded: succeeded, failure: failure)
            storeActivities[storeIdentifier] = single.activities
            // Success in the private store cannot clear an unresolved shared-store failure.
            for p in Phase.allCases {
                var combined = Activity()
                for key in storeActivities.keys.sorted() {
                    guard let item = storeActivities[key]?[p] else { continue }
                    combined.active.merge(item.active) { _, new in new }
                    if let date = item.lastSuccess { combined.lastSuccess = max(combined.lastSuccess ?? .distantPast, date) }
                    if let date = item.lastResultStart { combined.lastResultStart = max(combined.lastResultStart ?? .distantPast, date) }
                    if let failure = item.failure { combined.failure = failure }
                }
                activities[p] = combined
            }
            return
        }
        var activity = activities[phase] ?? Activity()
        guard let end else {
            activity.active[id] = start
            activities[phase] = activity
            return
        }
        activity.active.removeValue(forKey: id)
        // An older operation finishing late must not overwrite a newer result.
        if activity.lastResultStart == nil || start >= activity.lastResultStart! {
            activity.lastResultStart = start
            if succeeded {
                activity.failure = nil
                activity.lastSuccess = max(activity.lastSuccess ?? .distantPast, end)
            } else {
                activity.failure = failure ?? Failure(domain: "CloudSync", code: -1, message: "同步未完成，系统会稍后重试。")
            }
        }
        activities[phase] = activity
    }

    var failures: [Failure] { Phase.allCases.compactMap { activities[$0]?.failure } }
    var isActive: Bool { activities.values.contains { !$0.active.isEmpty } }
    var hasCompletedTransfer: Bool {
        activities[.upload]?.lastSuccess != nil || activities[.download]?.lastSuccess != nil
    }
}

/// All observation callbacks are delivered to the main queue before publishing UI state.
/// This object is owned by a persistence controller, not a global observer of every test/store.
final class CloudSyncMonitor: ObservableObject {
    @Published private(set) var state = CloudSyncState()
    @Published private(set) var accountStatus: CKAccountStatus?
    @Published private(set) var accountFailure: CloudSyncState.Failure?
    @Published private(set) var storeFailure: CloudSyncState.Failure?
    @Published private(set) var pushFailure: CloudSyncState.Failure?
    @Published private(set) var isCheckingAccount = false
    @Published private(set) var isEnabled = false
    @Published private(set) var requestedAtLaunch = false
    let runtimeAvailable: Bool

    private let center: NotificationCenter
    private let accountProvider: (@escaping (CKAccountStatus, Error?) -> Void) -> Void
    private let diagnosticsURL: URL?
    private var eventObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private var observationID = UUID()
    private var accountRequestID = UUID()
    private let accountTimeout: TimeInterval
    private var timeoutWork: DispatchWorkItem?
    private weak var observedContainer: NSPersistentCloudKitContainer?

    init(
        runtimeAvailable: Bool,
        center: NotificationCenter = .default,
        diagnosticsURL: URL? = nil,
        accountTimeout: TimeInterval = 20,
        accountProvider: @escaping (@escaping (CKAccountStatus, Error?) -> Void) -> Void = { completion in
            CKContainer(identifier: Constants.ICloud.containerIdentifier).accountStatus(completionHandler: completion)
        }
    ) {
        self.runtimeAvailable = runtimeAvailable
        self.center = center
        self.diagnosticsURL = diagnosticsURL
        self.accountTimeout = accountTimeout
        self.accountProvider = accountProvider
    }

    deinit {
        timeoutWork?.cancel()
        if let eventObserver { center.removeObserver(eventObserver) }
        if let accountObserver { center.removeObserver(accountObserver) }
    }

    func observe(_ container: NSPersistentCloudKitContainer) {
        observedContainer = container
        if let eventObserver { center.removeObserver(eventObserver) }
        observationID = UUID()
        let generation = observationID
        guard runtimeAvailable else { return }
        eventObserver = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: nil
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let phase: CloudSyncState.Phase
            switch event.type {
            case .setup: phase = .setup
            case .import: phase = .download
            case .export: phase = .upload
            @unknown default: return
            }
            let failure = event.error.map(CloudSyncState.Failure.from)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observationID == generation, self.isEnabled else { return }
                self.state.receive(id: event.identifier, phase: phase, start: event.startDate,
                                   end: event.endDate, succeeded: event.succeeded, failure: failure, storeIdentifier: event.storeIdentifier)
                self.writeDiagnostics()
            }
        }
    }

    func configure(requested: Bool, enabled: Bool, storeError: Error?) {
        requestedAtLaunch = requested
        isEnabled = enabled && runtimeAvailable
        storeFailure = storeError.map(CloudSyncState.Failure.from)
        if !isEnabled {
            observationID = UUID()
            accountRequestID = UUID()
            timeoutWork?.cancel()
            isCheckingAccount = false
            if let eventObserver { center.removeObserver(eventObserver); self.eventObserver = nil }
        } else if accountObserver == nil {
            accountObserver = center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Results from a previous account must never appear as current sync evidence.
                if let container = self.observedContainer { self.observe(container) }
                self.timeoutWork?.cancel()
                self.state = CloudSyncState()
                self.accountStatus = nil
                self.accountRequestID = UUID()
                self.isCheckingAccount = false
                self.refreshAccountStatus()
            }
        }
        writeDiagnostics()
    }

    func refreshAccountStatus() {
        guard isEnabled, runtimeAvailable, !isCheckingAccount else { return }
        isCheckingAccount = true
        let requestID = UUID()
        accountRequestID = requestID
        timeoutWork?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.accountRequestID == requestID, self.isCheckingAccount else { return }
            self.accountRequestID = UUID()
            self.isCheckingAccount = false
            self.accountFailure = .init(domain: "CloudSync", code: -2, message: "账户检查超时，请检查网络后重试。")
            self.writeDiagnostics()
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + accountTimeout, execute: timeout)
        accountProvider { [weak self] status, error in
            let failure = error.map(CloudSyncState.Failure.from)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.accountRequestID == requestID, self.isEnabled else { return }
                self.timeoutWork?.cancel()
                self.isCheckingAccount = false
                self.accountStatus = status
                self.accountFailure = failure
                self.writeDiagnostics()
            }
        }
    }

    func recordPushRegistration(error: Error?) {
        pushFailure = error.map(CloudSyncState.Failure.from)
        writeDiagnostics()
    }

    var failures: [CloudSyncState.Failure] {
        [storeFailure, accountFailure, pushFailure].compactMap { $0 } + state.failures
    }

    func statusText(preference: Bool) -> String {
        if preference != requestedAtLaunch {
            return preference ? "开启待重启；当前仍仅在本机保存" : "关闭待重启；当前同步配置仍生效"
        }
        if !preference { return "已关闭；数据仅在本机保存" }
        if !runtimeAvailable { return "此运行环境不启用 iCloud 同步" }
        if storeFailure != nil || !isEnabled { return "同步未启用，已退回本地存储" }
        if accountFailure != nil { return "暂时无法检查 iCloud 账户" }
        switch accountStatus {
        case .noAccount: return "未登录 iCloud"
        case .restricted: return "iCloud 访问受限制"
        case .temporarilyUnavailable: return "iCloud 账户暂不可用"
        case .couldNotDetermine: return "无法确定 iCloud 账户状态"
        case nil: return "正在检查 iCloud 账户"
        case .available: break
        @unknown default: return "未知 iCloud 账户状态"
        }
        if !failures.isEmpty { return "同步遇到问题；本地数据仍可使用" }
        if state.isActive { return "正在同步" }
        if state.hasCompletedTransfer { return "最近同步活动已完成" }
        return "等待系统同步；尚无上传或下载成功记录"
    }

    /// Privacy-safe support evidence; no record contents, tokens, account IDs, or raw error descriptions.
    private func writeDiagnostics() {
        guard let diagnosticsURL else { return }
        var data: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "requestedAtLaunch": requestedAtLaunch, "enabled": isEnabled,
            "accountStatus": accountStatus?.rawValue ?? -1,
            "errors": failures.map { ["domain": $0.domain, "code": $0.code] as [String: Any] }
        ]
        for phase in CloudSyncState.Phase.allCases {
            if let date = state.activities[phase]?.lastSuccess {
                data[phase.rawValue + "SucceededAt"] = ISO8601DateFormatter().string(from: date)
            }
        }
        do {
            let encoded = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
            try encoded.write(to: diagnosticsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Diagnostic persistence must never block local bookkeeping or sync itself.
        }
    }
}
