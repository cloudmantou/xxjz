import XCTest
import UIKit
import AppIntents
import UniformTypeIdentifiers
import CoreData
@testable import AssetLife

final class ServiceTests: XCTestCase {

    // MARK: - OCR Service Tests

    func test_mockOCRService_recognizeText_returnsExpectedText() async {
        let service = MockOCRService.shared
        let image = UIImage()

        do {
            let result = try await service.recognizeText(from: image)
            XCTAssertTrue(result.contains("iPhone"))
            XCTAssertTrue(result.contains("9999"))
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }

    // MARK: - AI Analysis Service Tests

    func test_mockAIAnalysisService_analyzeReceipt_returnsValidAnalysis() async {
        let service = MockAIAnalysisService.shared
        let image = UIImage()

        do {
            let result = try await service.analyzeReceipt(image: image)
            XCTAssertFalse(result.merchant.isEmpty)
            XCTAssertTrue(result.total > 0)
            XCTAssertFalse(result.items.isEmpty)
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }

    func test_mockAIAnalysisService_suggestCategory_electronics_returnsElectronics() async {
        let service = MockAIAnalysisService.shared

        do {
            let result = try await service.suggestCategory(itemName: "iPhone 15")
            XCTAssertEqual(result, "电子产品")
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }

    func test_mockAIAnalysisService_suggestCategory_unknown_returnsOther() async {
        let service = MockAIAnalysisService.shared

        do {
            let result = try await service.suggestCategory(itemName: "未知商品XYZ")
            XCTAssertEqual(result, "其他")
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }

    // MARK: - Screenshot Shortcut Intent Tests

    @available(iOS 16.0, *)
    func test_recordFromScreenshotIntent_withLocalSampleImage_setsPendingRecordParams() async throws {
        let sampleImagePath = "/Users/mantou/Downloads/IMG_5794.PNG"
        guard FileManager.default.fileExists(atPath: sampleImagePath) else {
            throw XCTSkip("Local sample image not found at \(sampleImagePath)")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: sampleImagePath))
        var intent = RecordFromScreenshotIntent()
        intent.screenshot = IntentFile(data: data, filename: "IMG_5794.PNG", type: .png)

        _ = try await intent.perform()

        XCTAssertEqual(ShortcutStorage.pendingAction, .addRecord)
        XCTAssertNotNil(ShortcutStorage.pendingRecordParams)

        ShortcutStorage.clearPendingAction()
    }

    // MARK: - Rule Package State Tests

    func test_rulePackageStatus_persistsAfterDefaultRulesActivation() {
        let service = RuleUpdateService.shared
        service.debugResetPackageStateForTests()
        defer { service.debugResetPackageStateForTests() }

        service.loadDefaultRules()

        let status = service.packageStatus
        XCTAssertGreaterThanOrEqual(status.baseRulesVersion, 1)
        XCTAssertGreaterThanOrEqual(status.patchRulesVersion, 1)
        XCTAssertFalse(status.activeRulesChecksum.isEmpty)
        XCTAssertFalse(service.currentRules.isEmpty)
    }

    func test_rulePackageActivation_invalidChecksum_rollsBack() {
        let service = RuleUpdateService.shared
        service.debugResetPackageStateForTests()
        defer { service.debugResetPackageStateForTests() }

        let baseline = [makeRule(ruleId: 9901, keyword: "测试初始规则")]
        XCTAssertTrue(service.debugApplyRulesForTests(baseline, baseVersion: 11, patchVersion: 11))
        let next = [makeRule(ruleId: 9902, keyword: "测试新规则")]
        XCTAssertFalse(service.debugApplyRulesForTests(next, baseVersion: 12, patchVersion: 12, expectedChecksum: "bad-checksum"))

        let activeRuleIds = Set(service.currentRules.map(\.ruleId))
        XCTAssertFalse(activeRuleIds.contains(9902))
        XCTAssertFalse(service.packageStatus.activeRulesChecksum.isEmpty)
        XCTAssertTrue(service.packageStatus.isRollingBack)
    }

    @MainActor
    func test_deleteLocalRule_onlyDeletesRequestedRule() {
        let service = RuleUpdateService.shared
        let firstID = Int.random(in: 10_000_000...20_000_000)
        let deletedID = firstID + 1
        let thirdID = firstID + 2
        defer {
            _ = service.deleteLocalRule(ruleId: firstID)
            _ = service.deleteLocalRule(ruleId: deletedID)
            _ = service.deleteLocalRule(ruleId: thirdID)
        }

        XCTAssertTrue(service.insertLocalRule(makeRule(ruleId: firstID, keyword: "本地规则A", ruleKind: .local)))
        XCTAssertTrue(service.insertLocalRule(makeRule(ruleId: deletedID, keyword: "本地规则B", ruleKind: .local)))
        XCTAssertTrue(service.insertLocalRule(makeRule(ruleId: thirdID, keyword: "本地规则C", ruleKind: .local)))

        XCTAssertTrue(service.deleteLocalRule(ruleId: deletedID))

        let remainingIDs = Set(KeywordRulesTable.shared.fetchAllRules().map(\.ruleId))
        XCTAssertTrue(remainingIDs.contains(firstID))
        XCTAssertFalse(remainingIDs.contains(deletedID))
        XCTAssertTrue(remainingIDs.contains(thirdID))
    }

    @MainActor
    func test_assetExportAndCount_excludeSoftDeletedAssets() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        _ = AssetItem(context: context, name: "正常资产", category: "电子产品", purchasePrice: 100)
        _ = AssetItem(
            context: context,
            name: "回收站资产",
            category: "电子产品",
            purchasePrice: 200,
            status: .deleted
        )
        try context.save()

        let normalListRequest: NSFetchRequest<AssetItem> = AssetItem.fetchRequest()
        normalListRequest.predicate = AssetStatus.normalRecordsPredicate
        let normalListAssets = try context.fetch(normalListRequest)
        XCTAssertEqual(normalListAssets.map(\.name), ["正常资产"])

        let service = AssetImportExportService(context: context)
        XCTAssertEqual(service.assetCount, 1)

        let exportURL = try XCTUnwrap(service.exportAllAssetsCSV())
        defer { try? FileManager.default.removeItem(at: exportURL) }
        let csv = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("正常资产"))
        XCTAssertFalse(csv.contains("回收站资产"))
        XCTAssertFalse(csv.contains(AssetStatus.deleted.rawValue))
    }

    func test_csvCodec_roundTripsEscapedQuotesAndMultilineFields() throws {
        let value = "今天买了\"咖啡\", 备注如下\n第二行"
        let csv = "备注\n\(CSVCodec.escapeField(value))\n"

        let rows = try CsvParser.parseCSVText(csv)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].first, value)
    }

    @MainActor
    func test_invalidImportDate_isSkippedAndCounted() {
        let controller = PersistenceController(inMemory: true)
        let service = ImportExportService(context: controller.container.viewContext)
        let mapping = ColumnMapping(dateColumn: 0, amountColumn: 1, categoryColumn: 2)

        let records = service.convertToBillRecords(
            rows: [
                ["2024-06-12", "10.00", "餐饮"],
                ["这不是日期", "20.00", "餐饮"]
            ],
            columnMapping: mapping
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(service.invalidDateRowCount, 1)
        XCTAssertEqual(Calendar.current.component(.year, from: records[0].date), 2024)
    }

    @MainActor
    func test_importedFingerprint_isConfirmedAndSkipped() async throws {
        let controller = PersistenceController(inMemory: true)
        let service = ImportExportService(context: controller.container.viewContext)
        let record = makeImportBillRecord()

        let firstBatch = try await service.executeImport(records: [record])
        XCTAssertEqual(firstBatch.importedCount, 1)

        let preview = try service.duplicateCountPreview(records: [record])
        XCTAssertEqual(preview.confirmedCount, 1)
        XCTAssertEqual(preview.suspectedCount, 0)

        let secondBatch = try await service.executeImport(records: [record])
        XCTAssertEqual(secondBatch.importedCount, 0)
        XCTAssertEqual(secondBatch.duplicateCount, 1)
    }

    @MainActor
    func test_legacySimilarTransaction_isOnlySuspectedAndCanBeImported() async throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let service = ImportExportService(context: context)
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let record = makeImportBillRecord(date: date)
        _ = BookkeepingTransaction(
            context: context,
            amount: record.amount,
            categoryKey: "dining",
            note: record.note,
            date: date,
            isIncome: false,
            merchantName: record.merchantName
        )
        try context.save()

        let preview = try service.duplicateCountPreview(records: [record])
        XCTAssertEqual(preview.confirmedCount, 0)
        XCTAssertEqual(preview.suspectedCount, 1)

        let batch = try await service.executeImport(
            records: [record],
            skipSuspectedDuplicates: false
        )
        XCTAssertEqual(batch.importedCount, 1)
        XCTAssertEqual(batch.duplicateCount, 0)
    }

    @MainActor
    func test_identicalRows_followExplicitSuspectedDuplicatePolicy() async throws {
        let record = makeImportBillRecord(date: Date(timeIntervalSince1970: 1_750_000_000))
        let records = [record, makeImportBillRecord(date: record.date)]

        let importAllController = PersistenceController(inMemory: true)
        let importAllService = ImportExportService(context: importAllController.container.viewContext)
        let preview = try importAllService.duplicateCountPreview(records: records)
        XCTAssertEqual(preview.confirmedCount, 0)
        XCTAssertEqual(preview.suspectedCount, 1)

        let importAllBatch = try await importAllService.executeImport(
            records: records,
            skipSuspectedDuplicates: false
        )
        XCTAssertEqual(importAllBatch.importedCount, 2)
        XCTAssertEqual(importAllBatch.duplicateCount, 0)

        let skipController = PersistenceController(inMemory: true)
        let skipService = ImportExportService(context: skipController.container.viewContext)
        let skipBatch = try await skipService.executeImport(records: records)
        XCTAssertEqual(skipBatch.importedCount, 1)
        XCTAssertEqual(skipBatch.duplicateCount, 1)
    }

    @MainActor
    func test_saveFailure_rollsBackAssetEdits() throws {
        enum ExpectedFailure: Error { case save }

        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let asset = AssetItem(context: context, name: "原名称", category: "电子产品", purchasePrice: 100)
        try context.save()
        asset.name = "未保存的新名称"

        let message = PersistenceSaveCoordinator.save(context) {
            throw ExpectedFailure.save
        }

        XCTAssertNotNil(message)
        XCTAssertEqual(asset.name, "原名称")
        XCTAssertFalse(context.hasChanges)
    }

    private func makeImportBillRecord(
        date: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> ImportBillRecord {
        var record = ImportBillRecord(
            date: date,
            amount: 35,
            isIncome: false,
            categoryName: "餐饮",
            note: "午饭",
            merchantName: "小饭馆",
            importRowIndex: 1
        )
        record.matchedCategoryKey = "dining"
        return record
    }

    func test_rulePatchMerge_upsertDeleteAndPriorityAdjustment() {
        let service = RuleUpdateService.shared
        service.debugResetPackageStateForTests()
        defer { service.debugResetPackageStateForTests() }

        let baseRuleA = makeRule(ruleId: 9101, keyword: "基础A")
        let baseRuleB = makeRule(ruleId: 9102, keyword: "基础B")
        XCTAssertTrue(service.debugApplyRulesForTests([baseRuleA, baseRuleB], baseVersion: 21, patchVersion: 21))

        let upsertedRule = makeRule(ruleId: 9101, keyword: "补丁A")
        let patch: [String: Any] = [
            "upsert": [ruleJSON(upsertedRule)],
            "deleteRuleIds": [9102],
            "priorityAdjustments": [
                ["ruleId": 9101, "minMatchValueDelta": 8]
            ]
        ]
        XCTAssertTrue(
            service.debugApplyPatchJSONForTests(
                patch,
                baseRules: service.currentRules,
                baseVersion: 21,
                patchVersion: 22,
                configVersion: 22
            )
        )

        let active = Dictionary(uniqueKeysWithValues: service.currentRules.map { ($0.ruleId, $0) })
        XCTAssertEqual(active[9101]?.keyWord, "补丁A")
        XCTAssertNil(active[9102])
        XCTAssertEqual(active[9101]?.searchTexts?.first?.minMatchValue ?? -1, 8, accuracy: 0.0001)
        XCTAssertEqual(service.packageStatus.patchRulesVersion, 22)
        XCTAssertEqual(service.packageStatus.configVersion, 22)
    }

    func test_rulePatchDelete_tombstonePreventsResurrection() {
        let service = RuleUpdateService.shared
        service.debugResetPackageStateForTests()
        defer { service.debugResetPackageStateForTests() }

        let deleteTarget = makeRule(ruleId: 9201, keyword: "可删除规则")
        let keepRule = makeRule(ruleId: 9202, keyword: "保留规则")
        XCTAssertTrue(service.debugApplyRulesForTests([deleteTarget, keepRule], baseVersion: 30, patchVersion: 30))

        XCTAssertTrue(
            service.debugApplyPatchJSONForTests(
                ["deleteRuleIds": [9201]],
                baseRules: service.currentRules,
                baseVersion: 30,
                patchVersion: 31,
                configVersion: 31
            )
        )
        XCTAssertFalse(service.currentRules.contains(where: { $0.ruleId == 9201 }))
        XCTAssertTrue(service.currentRules.contains(where: { $0.ruleId == 9202 }))

        let resurrected = makeRule(ruleId: 9201, keyword: "尝试复活")
        XCTAssertTrue(
            service.debugApplyPatchJSONForTests(
                ["upsert": [ruleJSON(resurrected)]],
                baseRules: service.currentRules,
                baseVersion: 30,
                patchVersion: 32,
                configVersion: 32
            )
        )
        XCTAssertFalse(service.currentRules.contains(where: { $0.ruleId == 9201 }))
    }

    func test_rulePatchEmergencyDisable_overridesPatchAndBase() {
        let service = RuleUpdateService.shared
        service.debugResetPackageStateForTests()
        defer { service.debugResetPackageStateForTests() }

        let blockedRule = makeRule(ruleId: 9301, keyword: "应急禁用目标")
        let keepRule = makeRule(ruleId: 9302, keyword: "应保留规则")
        XCTAssertTrue(service.debugApplyRulesForTests([blockedRule, keepRule], baseVersion: 40, patchVersion: 40))
        let fingerprint = service.debugIdentityFingerprintForRule(blockedRule)
        service.debugSetEmergencyDisabledFingerprintsForTests([fingerprint])

        let patchRule = makeRule(ruleId: 9301, keyword: "补丁尝试恢复")
        XCTAssertTrue(
            service.debugApplyPatchJSONForTests(
                ["upsert": [ruleJSON(patchRule)]],
                baseRules: service.currentRules,
                baseVersion: 40,
                patchVersion: 41,
                configVersion: 41
            )
        )

        XCTAssertFalse(service.currentRules.contains(where: { $0.ruleId == 9301 }))
        XCTAssertTrue(service.currentRules.contains(where: { $0.ruleId == 9302 }))
    }

    func test_rulePatchNoiseKeywordDelta_updatesDynamicNoiseDictionary() {
        let service = RuleUpdateService.shared
        service.debugResetPackageStateForTests()
        defer { service.debugResetPackageStateForTests() }

        let baseRule = makeRule(ruleId: 9401, keyword: "基础规则")
        XCTAssertTrue(service.debugApplyRulesForTests([baseRule], baseVersion: 50, patchVersion: 50))

        let patch: [String: Any] = [
            "noiseKeywords": [
                "add": ["回首页", "获得森林能量"],
                "remove": ["不存在词"]
            ]
        ]
        XCTAssertTrue(
            service.debugApplyPatchJSONForTests(
                patch,
                baseRules: service.currentRules,
                baseVersion: 50,
                patchVersion: 51,
                configVersion: 51
            )
        )

        let runtimeNoise = service.dynamicNoiseKeywords()
        XCTAssertTrue(runtimeNoise.contains("回首页"))
        XCTAssertTrue(runtimeNoise.contains("获得森林能量"))
    }

    private func makeRule(
        ruleId: Int,
        keyword: String,
        type: RuleTransactionType = .expense,
        source: KeywordListType = .aliAppear,
        billSource: RuleBillSource = .alipay,
        ruleKind: RuleKind = .auto,
        minMatchValue: Double = 0
    ) -> KeywordRule {
        KeywordRule(
            ruleId: ruleId,
            keyWord: keyword,
            type: type,
            memberCateId: 1,
            billsBookId: 0,
            keyWordSource: source,
            fundAccountId: 2,
            searchTexts: [
                AutoBillSearchText(
                    ruleId: ruleId,
                    ruleKind: ruleKind,
                    billSource: billSource,
                    minMatchValue: minMatchValue,
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
    }

    private func ruleJSON(_ rule: KeywordRule) -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(rule),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }
}
