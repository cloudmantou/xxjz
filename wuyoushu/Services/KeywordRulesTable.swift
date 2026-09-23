import Foundation
import SQLite

/// SQLite-based keyword rules storage
/// Mirrors AChai's keywordRules table structure
final class KeywordRulesTable {

    static let shared = KeywordRulesTable()

    // MARK: - Table Definition

    private let table = Table("keywordRules")
    private let searchTextTable = Table("keywordRuleSearchTexts")

    // Column definitions (matching AChai's schema)
    // NOTE: avoid `literal:` here; quoted identifiers from SQLite metadata can mismatch and
    // trigger "No such column" at row decoding time in some existing local DBs.
    private let colRuleId = SQLite.Expression<Int64>("ruleId")
    private let colKeyWord = SQLite.Expression<String?>("keyWord")
    private let colMemberId = SQLite.Expression<String?>("memberId")
    private let colType = SQLite.Expression<Int64>("type")
    private let colMemberCateId = SQLite.Expression<Int64>("memberCateId")
    private let colBillsBookId = SQLite.Expression<Int64>("billsBookId")
    private let colKeyWordSource = SQLite.Expression<Int64>("keyWordSource")
    private let colFundAccountId = SQLite.Expression<Int64>("fundAccountId")
    private let colMemberTagIds = SQLite.Expression<String?>("memberTagIds")
    private let colCreateDate = SQLite.Expression<String?>("createDate")
    private let colUpdateDate = SQLite.Expression<String?>("updateDate")

    // Search text table columns
    private let stColId = SQLite.Expression<Int64>("id")
    private let stColRuleId = SQLite.Expression<Int64>("ruleId")
    private let stColKey = SQLite.Expression<String?>("searchKey")
    private let stColIndex = SQLite.Expression<Int64>("searchIndex")
    private let stColRuleKind = SQLite.Expression<Int64>("ruleKind")
    private let stColBillSource = SQLite.Expression<Int64>("billSource")
    private let stColMinMatchValue = SQLite.Expression<Double>("minMatchValue")
    private let stColMatchType = SQLite.Expression<Int64>("matchType")
    private let stColIsFuzzy = SQLite.Expression<Int64>("isFuzzy")
    private let stColIsFuzzyLastValue = SQLite.Expression<Int64>("isFuzzyLastValue")
    private let stColIsOptional = SQLite.Expression<Int64>("isOptional")
    private let stColIsMutableLine = SQLite.Expression<Int64>("isMutableLine")
    private let stColColumnCount = SQLite.Expression<Int64>("columnCount")
    private let stColAlignment = SQLite.Expression<Int64>("alignment")
    private let stColCandidateType = SQLite.Expression<Int64>("candidateType")
    private let stColSubCandidateType = SQLite.Expression<Int64>("subCandidateType")

    // MARK: - Initialization

    private var db: Connection?

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("keywordRules.sqlite3").path
            db = try Connection(dbPath)
            createTableIfNeeded()
        } catch {
            print("[KeywordRulesTable] Database setup failed: \(error)")
        }
    }

    private func createTableIfNeeded() {
        guard let db = db else { return }

        do {
            try db.run(table.create(ifNotExists: true) { t in
                t.column(colRuleId, primaryKey: true)
                t.column(colKeyWord)
                t.column(colMemberId)
                t.column(colType, defaultValue: 0)
                t.column(colMemberCateId, defaultValue: 0)
                t.column(colBillsBookId, defaultValue: 0)
                t.column(colKeyWordSource, defaultValue: 0)
                t.column(colFundAccountId, defaultValue: 0)
                t.column(colMemberTagIds)
                t.column(colCreateDate)
                t.column(colUpdateDate)
            })

            try db.run(searchTextTable.create(ifNotExists: true) { t in
                t.column(stColId, primaryKey: true)
                t.column(stColRuleId)
                t.column(stColKey)
                t.column(stColIndex, defaultValue: 0)
                t.column(stColRuleKind, defaultValue: 0)
                t.column(stColBillSource, defaultValue: 0)
                t.column(stColMinMatchValue, defaultValue: 0)
                t.column(stColMatchType, defaultValue: 2)
                t.column(stColIsFuzzy, defaultValue: 0)
                t.column(stColIsFuzzyLastValue, defaultValue: 0)
                t.column(stColIsOptional, defaultValue: 0)
                t.column(stColIsMutableLine, defaultValue: 0)
                t.column(stColColumnCount, defaultValue: 1)
                t.column(stColAlignment, defaultValue: 0)
                t.column(stColCandidateType, defaultValue: 2)
                t.column(stColSubCandidateType, defaultValue: 0)
            })

            // Create indexes for common queries
            try db.run(table.createIndex(colKeyWord, ifNotExists: true))
            try db.run(table.createIndex(colMemberId, ifNotExists: true))
            try db.run(table.createIndex(colType, ifNotExists: true))
            try db.run(table.createIndex(colMemberCateId, ifNotExists: true))
            try db.run(table.createIndex(colKeyWordSource, ifNotExists: true))
            try db.run(table.createIndex(colFundAccountId, ifNotExists: true))
            try db.run(searchTextTable.createIndex(stColRuleId, ifNotExists: true))
            try db.run(searchTextTable.createIndex(stColIndex, ifNotExists: true))
        } catch {
            print("[KeywordRulesTable] Table creation failed: \(error)")
        }
    }

    // MARK: - CRUD Operations

    /// Insert or replace a rule
    func upsertRule(_ rule: KeywordRule) {
        guard let db = db else { return }

        do {
            try db.transaction {
                let insert = table.insert(or: .replace,
                    colRuleId <- Int64(rule.ruleId),
                    colKeyWord <- rule.keyWord,
                    colMemberId <- rule.memberId,
                    colType <- Int64(rule.type.rawValue),
                    colMemberCateId <- Int64(rule.memberCateId),
                    colBillsBookId <- Int64(rule.billsBookId),
                    colKeyWordSource <- Int64(rule.keyWordSource.rawValue),
                    colFundAccountId <- Int64(rule.fundAccountId),
                    colMemberTagIds <- rule.memberTagIds,
                    colCreateDate <- rule.createDate,
                    colUpdateDate <- rule.updateDate
                )
                try db.run(insert)
                if let searchTexts = rule.searchTexts {
                    try replaceSearchTexts(searchTexts, forRuleId: rule.ruleId, in: db)
                }
            }
        } catch {
            print("[KeywordRulesTable] Upsert failed: \(error)")
        }
    }

    /// Batch insert rules (for API sync)
    func upsertRules(_ rules: [KeywordRule]) {
        guard let db = db else { return }

        do {
            try db.transaction {
                for rule in rules {
                    let insert = table.insert(or: .replace,
                        colRuleId <- Int64(rule.ruleId),
                        colKeyWord <- rule.keyWord,
                        colMemberId <- rule.memberId,
                        colType <- Int64(rule.type.rawValue),
                        colMemberCateId <- Int64(rule.memberCateId),
                        colBillsBookId <- Int64(rule.billsBookId),
                        colKeyWordSource <- Int64(rule.keyWordSource.rawValue),
                        colFundAccountId <- Int64(rule.fundAccountId),
                        colMemberTagIds <- rule.memberTagIds,
                        colCreateDate <- rule.createDate,
                        colUpdateDate <- rule.updateDate
                    )
                    try db.run(insert)
                    if let searchTexts = rule.searchTexts {
                        try replaceSearchTexts(searchTexts, forRuleId: rule.ruleId, in: db)
                    }
                }
            }
        } catch {
            print("[KeywordRulesTable] Batch upsert failed: \(error)")
        }
    }

    /// Get rules by type (expense/income)
    func fetchRules(byType type: RuleTransactionType) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let query = table.filter(colType == Int64(type.rawValue))
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch by type failed: \(error)")
            return []
        }
    }

    /// Get rules by keyword source (which keyword list)
    func fetchRules(byKeywordSource source: KeywordListType) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let query = table.filter(colKeyWordSource == Int64(source.rawValue))
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch by keyword source failed: \(error)")
            return []
        }
    }

    /// Get rules by fund account (wechat/alipay/huabei)
    func fetchRules(byFundAccountId fundAccountId: Int) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let query = table.filter(colFundAccountId == Int64(fundAccountId))
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch by fund account failed: \(error)")
            return []
        }
    }

    /// Get rules by bill source (wechat/alipay)
    func fetchRules(byBillSource source: RuleBillSource) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            // Filter by keyWordSource matching the bill source
            let sourceValue: Int64
            switch source {
            case .wechat:
                sourceValue = Int64(KeywordListType.weAppear.rawValue)
            case .alipay:
                sourceValue = Int64(KeywordListType.aliAppear.rawValue)
            default:
                return []
            }

            let query = table.filter(colKeyWordSource >= sourceValue && colKeyWordSource < sourceValue + 4)
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch by bill source failed: \(error)")
            return []
        }
    }

    /// Get all rules
    func fetchAllRules() -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let query = table.order(colKeyWordSource.asc, colRuleId.asc)
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch all failed: \(error)")
            return []
        }
    }

    /// 获取匹配用规则（对齐AChai SQL）
    /// SELECT * FROM keywordRules WHERE (memberId IS NULL OR memberId='' OR memberId=?) ORDER BY keyWordSource
    func fetchRulesForMatching(memberId: String?) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let normalizedMemberId = memberId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isNilScope: SQLite.Expression<Bool> = ((colMemberId == nil) ?? false)
            let isEmptyScope: SQLite.Expression<Bool> = ((colMemberId == "") ?? false)
            let sharedScope = isNilScope || isEmptyScope
            let scope: SQLite.Expression<Bool>

            if let normalizedMemberId, !normalizedMemberId.isEmpty {
                let ownScope: SQLite.Expression<Bool> = ((colMemberId == normalizedMemberId) ?? false)
                scope = sharedScope || ownScope
            } else {
                scope = sharedScope
            }

            let query = table
                .filter(scope)
                .order(colKeyWordSource.asc, colRuleId.asc)

            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch rules for matching failed: \(error)")
            return []
        }
    }

    /// Delete all rules (for full sync)
    func deleteAllRules() {
        guard let db = db else { return }

        do {
            try db.transaction {
                try db.run(table.delete())
                try db.run(searchTextTable.delete())
            }
        } catch {
            print("[KeywordRulesTable] Delete all failed: \(error)")
        }
    }

    /// Get rule count
    func ruleCount() -> Int {
        guard let db = db else { return 0 }
        return (try? db.scalar(table.count)) ?? 0
    }

    /// Search rules by keyword (LIKE query)
    func searchRules(keyword: String) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let query = table.filter(colKeyWord.like("%\(keyword)%"))
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Search failed: \(error)")
            return []
        }
    }

    /// Fetch rules by ruleId
    func fetchRule(byId ruleId: Int) -> KeywordRule? {
        guard let db = db else { return nil }

        do {
            let query = table.filter(colRuleId == Int64(ruleId))
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db).first
        } catch {
            print("[KeywordRulesTable] Fetch by id failed: \(error)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func rowToKeywordRule(_ row: Row) -> KeywordRule {
        KeywordRule(
            ruleId: Int(row[colRuleId]),
            keyWord: row[colKeyWord] ?? "",
            memberId: row[colMemberId],
            type: RuleTransactionType(rawValue: Int(row[colType])) ?? .expense,
            memberCateId: Int(row[colMemberCateId]),
            billsBookId: Int(row[colBillsBookId]),
            keyWordSource: KeywordListType(rawValue: Int(row[colKeyWordSource])) ?? .aliAppear,
            fundAccountId: Int(row[colFundAccountId]),
            memberTagIds: row[colMemberTagIds],
            createDate: row[colCreateDate],
            updateDate: row[colUpdateDate],
            searchTexts: nil
        )
    }

    private func enrichRulesWithSearchTexts(_ rules: [KeywordRule], in db: Connection) -> [KeywordRule] {
        guard !rules.isEmpty else { return rules }
        let searchTextMap = fetchSearchTextMap(forRuleIds: rules.map(\.ruleId), in: db)

        return rules.map { rule in
            var updated = rule
            updated.searchTexts = searchTextMap[rule.ruleId]
            return updated
        }
    }

    private func fetchSearchTextMap(
        forRuleIds ruleIds: [Int],
        in db: Connection
    ) -> [Int: [AutoBillSearchText]] {
        var map: [Int: [AutoBillSearchText]] = [:]
        let uniqueIds = Array(Set(ruleIds))
        guard !uniqueIds.isEmpty else { return map }

        for ruleId in uniqueIds {
            do {
                let query = searchTextTable
                    .filter(stColRuleId == Int64(ruleId))
                    .order(stColIndex.asc, stColId.asc)
                let rows = try db.prepare(query)
                let searchTexts = rows.map { rowToSearchText($0) }
                if !searchTexts.isEmpty {
                    map[ruleId] = searchTexts
                }
            } catch {
                print("[KeywordRulesTable] Fetch searchTexts failed for rule \(ruleId): \(error)")
            }
        }

        return map
    }

    private func rowToSearchText(_ row: Row) -> AutoBillSearchText {
        AutoBillSearchText(
            key: row[stColKey],
            index: Int(row[stColIndex]),
            ruleId: Int(row[stColRuleId]),
            ruleKind: RuleKind(rawValue: Int(row[stColRuleKind])) ?? .auto,
            billSource: RuleBillSource(rawValue: Int(row[stColBillSource])) ?? .generic,
            minMatchValue: row[stColMinMatchValue],
            matchType: MatchType(rawValue: Int(row[stColMatchType])) ?? .contains,
            isFuzzy: row[stColIsFuzzy] == 1,
            isFuzzyLastValue: row[stColIsFuzzyLastValue] == 1,
            isOptional: row[stColIsOptional] == 1,
            isMutableLine: row[stColIsMutableLine] == 1,
            columnCount: Int(row[stColColumnCount]),
            alignment: SearchAlignment(rawValue: Int(row[stColAlignment])) ?? .automatic,
            candidateType: CandidateType(rawValue: Int(row[stColCandidateType])) ?? .textObservation,
            subCandidateType: Int(row[stColSubCandidateType])
        )
    }

    private func replaceSearchTexts(
        _ searchTexts: [AutoBillSearchText],
        forRuleId ruleId: Int,
        in db: Connection
    ) throws {
        let scoped = searchTextTable.filter(stColRuleId == Int64(ruleId))
        try db.run(scoped.delete())

        for (offset, searchText) in searchTexts.enumerated() {
            let resolvedIndex = searchText.index != 0 ? searchText.index : offset
            let normalizedKey = searchText.key?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let insert = searchTextTable.insert(
                stColRuleId <- Int64(ruleId),
                stColKey <- normalizedKey?.isEmpty == true ? nil : normalizedKey,
                stColIndex <- Int64(resolvedIndex),
                stColRuleKind <- Int64(searchText.ruleKind.rawValue),
                stColBillSource <- Int64(searchText.billSource.rawValue),
                stColMinMatchValue <- searchText.minMatchValue,
                stColMatchType <- Int64(searchText.matchType.rawValue),
                stColIsFuzzy <- (searchText.isFuzzy ? 1 : 0),
                stColIsFuzzyLastValue <- (searchText.isFuzzyLastValue ? 1 : 0),
                stColIsOptional <- (searchText.isOptional ? 1 : 0),
                stColIsMutableLine <- (searchText.isMutableLine ? 1 : 0),
                stColColumnCount <- Int64(max(1, searchText.columnCount)),
                stColAlignment <- Int64(searchText.alignment.rawValue),
                stColCandidateType <- Int64(searchText.candidateType.rawValue),
                stColSubCandidateType <- Int64(searchText.subCandidateType)
            )
            try db.run(insert)
        }
    }
}

// MARK: - Convenience Methods for Common Queries

extension KeywordRulesTable {

    /// Fetch all expense rules
    func fetchExpenseRules() -> [KeywordRule] {
        return fetchRules(byType: .expense)
    }

    /// Fetch all income rules
    func fetchIncomeRules() -> [KeywordRule] {
        return fetchRules(byType: .income)
    }

    /// Fetch rules for a specific category
    func fetchRules(byCategoryId cateId: Int) -> [KeywordRule] {
        guard let db = db else { return [] }

        do {
            let query = table.filter(colMemberCateId == Int64(cateId))
            let rules = try db.prepare(query).map { row in
                rowToKeywordRule(row)
            }
            return enrichRulesWithSearchTexts(rules, in: db)
        } catch {
            print("[KeywordRulesTable] Fetch by category failed: \(error)")
            return []
        }
    }
}
