import SwiftUI

struct PreferenceSyncSettingsView: View {
    @ObservedObject private var sync = PreferenceSyncCoordinator.shared
    @State private var selected: PreferenceResolution?
    var body: some View {
        List {
            Section {
                Text(sync.isReady ? "分类与本地规则已保存在本机，将随 iCloud 同步设置上传。" : "分类与规则同步尚未就绪。")
                if let error = sync.errorMessage { Text(error).foregroundStyle(.orange) }
                Button("重新检查") { sync.refresh() }
            }
            Section(header: Text("需要确认的版本"), footer: Text("多台设备同时修改时，各个版本都会保留。删除与编辑冲突时暂时保留删除；选择一个版本后，会将你的选择同步到其他设备。")) {
                if sync.conflicts.isEmpty { Text("暂无冲突").foregroundStyle(.secondary) }
                ForEach(sync.conflicts) { state in
                    Button { selected = state } label: {
                        Label(title(state), systemImage: state.winner.kind == .category ? "square.grid.2x2" : "text.magnifyingglass")
                    }
                }
            }
            Section(header: Text("已删除，可恢复")) {
                if sync.deletedItems.isEmpty { Text("暂无已删除项目").foregroundStyle(.secondary) }
                ForEach(sync.deletedItems) { state in
                    Button(title(state)) { selected = state }
                }
            }
        }
        .navigationTitle("分类与规则同步")
        .onAppear { sync.refresh() }
        .sheet(item: $selected) { state in
            NavigationView {
                List {
                    Section(footer: Text("选择需要保留的版本。历史账单的分类标识不会改变。")) {
                        ForEach(versions(state)) { version in
                            Button {
                                if sync.resolve(state, choosing: version) { selected = nil }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(version.label)
                                    if let payload = version.payload {
                                        if version.kind == .category, let category = try? JSONDecoder().decode(CustomCategory.self, from: payload) {
                                            Text("\(category.emoji) · \(category.isIncome ? "收入" : "支出") · \(category.colorHex)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        } else if let rule = try? JSONDecoder().decode(KeywordRule.self, from: payload) {
                                            Text(ruleSummary(rule)).font(.caption).foregroundStyle(.secondary)
                                            ForEach(Array((rule.searchTexts ?? []).enumerated()), id: \.offset) { _, text in
                                                Text(conditionSummary(text)).font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    if !version.isSeed {
                                        Text(version.date, format: .dateTime.year().month().day().hour().minute().second())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if let error = sync.errorMessage { Text(error).foregroundStyle(.orange) }
                    }
                }
                .navigationTitle("选择保留的版本")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { selected = nil } } }
            }
        }
    }
    private func ruleSummary(_ rule: KeywordRule) -> String {
        let type = rule.type == .income ? "收入" : rule.type == .transfer ? "转账" : "支出"
        let category = AutoBillRuleEngine.shared.categoryKey(from: rule.memberCateId)
            .flatMap { BookkeepingCategory.find(key: $0)?.name } ?? "未识别分类（\(rule.memberCateId)）"
        let account = KeywordRule.fundAccountName(from: rule.fundAccountId) ?? "未指定账户"
        return "\(type) · \(category) · \(account)"
    }
    private func conditionSummary(_ text: AutoBillSearchText) -> String {
        let match: String
        switch text.matchType {
        case .exact: match = "精确"
        case .contains: match = "包含"
        case .prefix: match = "前缀"
        case .regex: match = "正则"
        }
        let source = text.billSource == .wechat ? "微信" : text.billSource == .alipay ? "支付宝" : "通用"
        return "\(source) · \(match)：\(text.key ?? "账单文本") · 阈值 \(text.minMatchValue)\(text.isFuzzy ? " · 模糊匹配" : "")\(text.isOptional ? " · 可选" : "")"
    }
    private func title(_ state: PreferenceResolution) -> String {
        state.heads.first(where: { $0.payload != nil })?.label ?? state.history.last(where: { $0.payload != nil })?.label ?? "已删除项目"
    }
    private func versions(_ state: PreferenceResolution) -> [PreferenceOperation] {
        let candidates = state.winner.payload == nil ? state.heads + state.history.reversed() : state.heads
        var seen: Set<Data?> = []
        return candidates.filter { seen.insert($0.payload).inserted }
    }
}
