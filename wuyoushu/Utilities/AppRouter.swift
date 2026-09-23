import Foundation

@MainActor
final class AppRouter: ObservableObject {
    enum QuickAction: String {
        case addAsset
        case addWish
        case quickRecord
    }

    enum AssetSection: String {
        case asset
        case wish
    }

    struct RecordParams {
        var amount: Double? = nil
        var categoryKey: String? = nil
        var note: String? = nil
        var isIncome: Bool? = nil
        var imagePath: String? = nil
        var date: Date? = nil
        var candidates: [ParsedTransactionCandidatePayload]? = nil
        var eventID: String? = nil
    }

    struct WishToAssetParams {
        let name: String
        let category: String
        let purchasePrice: Double
    }

    @Published var selectedTab: Constants.Tab = .home
    @Published var selectedAssetSection: AssetSection = .asset
    @Published var showAddAssetSheet = false
    @Published var showAddWishSheet = false
    @Published var showQuickRecordSheet = false
    @Published private(set) var previousTabBeforeQuickRecord: Constants.Tab?
    @Published var pendingRecordParams: RecordParams?
    @Published var pendingWishToAsset: WishToAssetParams?
    @Published var receiptPrintTrigger: UUID = UUID()
    @Published var receiptPrintTargetURI: URL?
    private var lastShortcutPresentationSignature: String = ""
    private var lastShortcutPresentationAt: Date = .distantPast

    // MARK: - Home Receipt Date State

    /// The date currently being viewed on the home receipt. Defaults to today.
    @Published var selectedReceiptDate: Date = Date()

    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedReceiptDate)
    }

    func goToPreviousDay() {
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedReceiptDate) {
            selectedReceiptDate = prev
        }
    }

    func goToNextDay() {
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedReceiptDate) {
            selectedReceiptDate = next
        }
    }

    func goToToday() {
        selectedReceiptDate = Date()
    }

    func trigger(_ action: QuickAction) {
        switch action {
        case .addAsset:
            selectedTab = .asset
            selectedAssetSection = .asset
            showAddWishSheet = false
            showQuickRecordSheet = false
            showAddAssetSheet = true
        case .addWish:
            selectedTab = .asset
            selectedAssetSection = .wish
            showAddAssetSheet = false
            showQuickRecordSheet = false
            showAddWishSheet = true
        case .quickRecord:
            presentQuickRecord(with: RecordParams())
        }
    }

    func triggerWishToAsset(name: String, category: String, purchasePrice: Double) {
        pendingWishToAsset = WishToAssetParams(name: name, category: category, purchasePrice: purchasePrice)
        selectedTab = .asset
        selectedAssetSection = .asset
        showAddWishSheet = false
        showQuickRecordSheet = false
        showAddAssetSheet = true
    }

    func triggerReceiptPrint(targetURI: URL? = nil) {
        receiptPrintTargetURI = targetURI
        receiptPrintTrigger = UUID()
    }

    @MainActor
    func completeQuickRecordAndReturnHome(printTargetURI: URL?) {
        dismissQuickRecord(printTargetURI: printTargetURI)
    }

    func dismissQuickRecord(printTargetURI: URL?) {
        pendingRecordParams = nil
        if let previousTabBeforeQuickRecord {
            selectedTab = previousTabBeforeQuickRecord
        }
        previousTabBeforeQuickRecord = nil
        showQuickRecordSheet = false
        triggerReceiptPrint(targetURI: printTargetURI)
    }

    func syncAfterQuickRecordSheetDismissed() {
        guard !showQuickRecordSheet else { return }
        pendingRecordParams = nil
        if let previousTabBeforeQuickRecord {
            selectedTab = previousTabBeforeQuickRecord
            self.previousTabBeforeQuickRecord = nil
        }
    }

    /// Handle pending shortcut action (called from App onAppear)
    func handlePendingShortcutAction() {
        // Fallback: if action flag was lost but payload exists, force addRecord flow.
        if ShortcutStorage.pendingAction == nil {
            let hasPendingParams = ShortcutStorage.pendingRecordParams != nil
            let hasPendingImage = !(ShortcutStorage.pendingRecordImagePath ?? "").isEmpty
            if hasPendingParams || hasPendingImage {
                ShortcutStorage.pendingAction = .addRecord
            }
        }

        if ShortcutStorage.pendingAction == nil {
            print(
                "[Router] handlePendingShortcutAction: no action, " +
                "hasParams=\(ShortcutStorage.pendingRecordParams != nil), " +
                "pendingImagePath=\(ShortcutStorage.pendingRecordImagePath ?? "nil")"
            )
        }

        guard let action = ShortcutStorage.pendingAction else { return }

        switch action {
        case .openHome:
            selectedTab = .home
            showAddAssetSheet = false
            showAddWishSheet = false
            showQuickRecordSheet = false
            pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
        case .openAsset:
            selectedTab = .asset
            selectedAssetSection = .asset
            showAddAssetSheet = false
            showAddWishSheet = false
            showQuickRecordSheet = false
            pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
        case .openWish:
            selectedTab = .asset
            selectedAssetSection = .wish
            showAddAssetSheet = false
            showAddWishSheet = false
            showQuickRecordSheet = false
            pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
        case .openProfile:
            selectedTab = .profile
            showAddAssetSheet = false
            showAddWishSheet = false
            showQuickRecordSheet = false
            pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
        case .addAsset:
            selectedTab = .asset
            selectedAssetSection = .asset
            showAddWishSheet = false
            showQuickRecordSheet = false
            showAddAssetSheet = true
            pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
        case .addWish:
            selectedTab = .asset
            selectedAssetSection = .wish
            showAddAssetSheet = false
            showQuickRecordSheet = false
            showAddWishSheet = true
            pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
        case .openRecord:
            presentQuickRecord(with: RecordParams())
            ShortcutStorage.pendingAction = nil
        case .addRecord:
            print("[Router] addRecord: pendingParams=\(ShortcutStorage.pendingRecordParams != nil), pendingImagePath=\(ShortcutStorage.pendingRecordImagePath ?? "nil")")

            var merged = RecordParams()

            if let params = ShortcutStorage.pendingRecordParams {
                merged.amount = params.amount
                merged.categoryKey = params.categoryKey
                merged.note = params.note
                merged.isIncome = params.isIncome
                merged.imagePath = params.imagePath
                merged.candidates = params.candidates
                merged.eventID = params.eventID
                if let dateString = params.date,
                   let parsedDate = ISO8601DateFormatter().date(from: dateString) {
                    merged.date = parsedDate
                }
            }

            if let imagePath = ShortcutStorage.pendingRecordImagePath, !imagePath.isEmpty {
                merged.imagePath = imagePath
            }

            let signature = shortcutPresentationSignature(from: merged)
            if showQuickRecordSheet,
               signature == lastShortcutPresentationSignature,
               Date().timeIntervalSince(lastShortcutPresentationAt) < 3.0 {
                ShortcutStorage.clearPendingAction()
                return
            }
            lastShortcutPresentationSignature = signature
            lastShortcutPresentationAt = Date()

            presentQuickRecord(with: merged)
            // Data has been copied to router.pendingRecordParams above.
            // Clear ALL storage now to prevent the UserDefaults.didChangeNotification
            // fallback from re-triggering addRecord in an infinite loop.
            ShortcutStorage.clearPendingAction()
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "assetlife" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // Handle record deep link: assetlife://record?amount=25&category=dining&note=lunch
        if components.host == "record" {
            var params = RecordParams()
            if let amountStr = components.queryItems?.first(where: { $0.name == "amount" })?.value,
               let amount = Double(amountStr) {
                params.amount = amount
            }
            if let category = components.queryItems?.first(where: { $0.name == "category" })?.value {
                params.categoryKey = category
            }
            if let note = components.queryItems?.first(where: { $0.name == "note" })?.value {
                params.note = note
            }
            if let incomeRaw = components.queryItems?.first(where: { $0.name == "income" })?.value {
                params.isIncome = ["1", "true", "yes", "income"].contains(incomeRaw.lowercased())
            }
            if let dateStr = components.queryItems?.first(where: { $0.name == "date" })?.value {
                let fullFormatter = ISO8601DateFormatter()
                let dateOnlyFormatter = ISO8601DateFormatter()
                dateOnlyFormatter.formatOptions = [.withYear, .withMonth, .withDay]
                params.date = fullFormatter.date(from: dateStr)
                    ?? dateOnlyFormatter.date(from: dateStr)
            }
            // Preserve image path from ShortcutStorage (set by intent before opening deep link)
            if let imagePath = ShortcutStorage.pendingRecordImagePath, !imagePath.isEmpty {
                params.imagePath = imagePath
            }
            presentQuickRecord(with: params)
            return
        }

        if let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value,
           let action = QuickAction(rawValue: actionValue) {
            trigger(action)
            return
        }

        if let tabValue = components.queryItems?.first(where: { $0.name == "tab" })?.value {
            switch tabValue {
            case "home":
                selectedTab = .home
            case "record":
                selectedTab = .record
            case "stats":
                selectedTab = .record
            case "asset":
                selectedTab = .asset
                selectedAssetSection = .asset
            case "wish":
                selectedTab = .asset
                selectedAssetSection = .wish
            case "profile":
                selectedTab = .profile
            case "quick":
                presentQuickRecord(with: RecordParams())
            default:
                break
            }
        }
    }

    private func presentQuickRecord(with params: RecordParams?) {
        if previousTabBeforeQuickRecord == nil {
            let fallbackTab: Constants.Tab = selectedTab == .quick ? .home : selectedTab
            previousTabBeforeQuickRecord = fallbackTab
        }
        showAddAssetSheet = false
        showAddWishSheet = false
        pendingRecordParams = params
        showQuickRecordSheet = true
    }

    private func shortcutPresentationSignature(from params: RecordParams) -> String {
        let roundedAmount = params.amount.map { String(format: "%.2f", $0) } ?? "nil"
        let dateKey = params.date.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
        let noteKey = params.note?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "nil"
        let imageKey = params.imagePath ?? "nil"
        let eventKey = params.eventID ?? "nil"
        return [roundedAmount, params.categoryKey ?? "nil", noteKey, dateKey, imageKey, eventKey].joined(separator: "|")
    }
}
