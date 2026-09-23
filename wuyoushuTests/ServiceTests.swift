import XCTest
import UIKit
import AppIntents
import UniformTypeIdentifiers
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
