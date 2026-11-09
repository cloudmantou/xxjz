import SwiftUI
import CoreData
import CloudKit

struct LedgerPicker: View {
    @ObservedObject private var store = LedgerStore.shared
    @State private var showsManagement = false
    var body: some View {
        Menu {
            ForEach(store.ledgers.filter { !$0.archived }) { ledger in
                Button { store.select(ledger) } label: {
                    Label("\(ledger.emoji) \(ledger.name)", systemImage: store.selected == ledger ? "checkmark.circle.fill" : "book.closed")
                }
            }
            Divider()
            Button { showsManagement = true } label: { Label("管理账本 / 共同攒钱", systemImage: "books.vertical") }
        } label: {
            HStack(spacing: 5) {
                Text("\(store.selected?.emoji ?? "📒") \(store.selectedName)").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .accessibilityLabel("切换账本，当前\(store.selectedName)")
        .sheet(isPresented: $showsManagement) {
            NavigationView { LedgerManagementView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showsManagement = false } } } }
                .navigationViewStyle(.stack)
        }
    }
}

struct LedgerManagementView: View {
    @ObservedObject private var store = LedgerStore.shared
    @AppStorage("ledger.memberName") private var nickname = ""
    @State private var showsCreate = false
    var body: some View {
        List {
            Section {
                TextField("记账昵称（供成员区分记录）", text: $nickname)
                    .onChange(of: nickname) { nickname = String($0.prefix(30)) }
                Text("每个账本独立统计和预算。个人资产、心愿单与识别规则保持私密。昵称用于记录展示，不代表 iCloud 身份。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("我的账本") {
                ForEach(store.ledgers.filter { !$0.archived }) { ledger in
                    NavigationLink { LedgerDetailView(ledger: ledger) } label: { row(ledger) }
                }
                Button { showsCreate = true } label: { Label("新建账本", systemImage: "plus.circle") }
            }
            if store.ledgers.contains(where: \.archived) {
                Section("已归档") {
                    ForEach(store.ledgers.filter(\.archived)) { ledger in
                        NavigationLink { LedgerDetailView(ledger: ledger) } label: { row(ledger) }
                    }
                }
            }
            Section {
                NavigationLink("共享安全副本") { LedgerSafetyCopiesView() }
                Text("共享需要每位成员使用自己的 iCloud 账户。账本所有者邀请成员并管理权限；可编辑成员可修改全部账单。同步由系统调度，离线改动会在联网后同步。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("账本与共同攒钱")
        .sheet(isPresented: $showsCreate) { NavigationView { LedgerEditorView(ledger: nil) }.navigationViewStyle(.stack) }
        .onAppear { store.refresh() }
    }
    private func row(_ ledger: Ledger) -> some View {
        HStack {
            Text(ledger.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(ledger.name)
                Text(ledger.isPersonalDefault ? "私密 · 原有数据" : store.isShared(ledger) ? "iCloud 共享" : "私密账本")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.selected == ledger { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
        }
    }
}

struct LedgerEditorView: View {
    let ledger: Ledger?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "📚"
    @State private var goal = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var archived = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("账本信息") {
                TextField("如：我们的家 / 旅行基金", text: $name)
                Picker("图标", selection: $emoji) {
                    ForEach(["📚", "📒", "🏡", "💞", "🐷", "✈️", "🎓", "🚗"], id: \.self) { Text($0).tag($0) }
                }
            }
            Section("共同攒钱（可选）") {
                TextField("目标金额（人民币）", text: $goal).keyboardType(.decimalPad)
                Toggle("设置目标日期", isOn: $hasDeadline)
                if hasDeadline { DatePicker("目标日期", selection: $deadline, displayedComponents: .date) }
                Text("账本累计收入减支出作为攒钱进度；转账不计入。存入和取出仅用于记账，不会实际划转资金。留空可作为普通账本。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let ledger, !ledger.isPersonalDefault {
                Section { Toggle("归档账本", isOn: $archived) } footer: { Text("归档后保留所有数据，暂停记账；共享成员也会看到归档状态。") }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(ledger == nil ? "新建账本" : "账本设置")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
        .onAppear {
            guard let ledger else { return }
            name = ledger.name; emoji = ledger.emoji; archived = ledger.archived
            goal = ledger.targetCents > 0 ? NSDecimalNumber(decimal: Decimal(ledger.targetCents) / 100).stringValue : ""
            hasDeadline = ledger.targetDate != nil; deadline = ledger.targetDate ?? Date()
        }
    }
    private func save() {
        do {
            let cents = goal.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : try LedgerMoney.cents(goal)
            if let ledger {
                try LedgerStore.shared.update(ledger, name: name, emoji: emoji, targetCents: cents,
                    targetDate: hasDeadline ? deadline : nil, archived: archived)
            } else {
                _ = try LedgerStore.shared.create(name: name, emoji: emoji, targetCents: cents, targetDate: hasDeadline ? deadline : nil)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct LedgerDetailView: View {
    @ObservedObject var ledger: Ledger
    @ObservedObject private var store = LedgerStore.shared
    @Environment(\.managedObjectContext) private var context
    @State private var editing = false
    @State private var preparing = false
    @State private var sharing: LedgerSharingSession?
    @State private var share: CKShare?
    @State private var amount = ""
    @State private var total: Decimal = 0
    @State private var activity: [LedgerActivity] = []
    @State private var pendingRevision: LedgerActivity?
    @State private var confirmsRevision = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button(store.selected == ledger ? "正在使用此账本" : "切换到此账本") { store.select(ledger) }
                    .disabled(ledger.archived)
                Text(ledger.archived ? "已归档" : store.canEdit(ledger) ? "可编辑" : "仅可查看")
                    .foregroundStyle(.secondary)
                Button("名称、目标与归档设置") { editing = true }
                    .disabled(!store.hasWritePermission(for: ledger))
            }
            if ledger.targetCents > 0 {
                Section("共同攒钱") {
                    Text("已攒 \(currency(total)) / \(currency(Decimal(ledger.targetCents) / 100))").font(.headline)
                    ProgressView(value: max(0, min(1, NSDecimalNumber(decimal: total * 100 / Decimal(ledger.targetCents)).doubleValue)))
                    if let date = ledger.targetDate { Text("目标日期：\(date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
                    TextField("本次金额（人民币）", text: $amount).keyboardType(.decimalPad)
                    HStack {
                        Button("记一笔存入") { recordSavings(income: true) }
                        Spacer()
                        Button("记一笔取出") { recordSavings(income: false) }
                    }.disabled(!store.canEdit(ledger))
                    Text("按本账本累计收支计算，可能为负数。不实际划转资金。记录会显示记账昵称。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("一起记账") {
                if ledger.isPersonalDefault {
                    Text("此账本保留原有个人数据。新建一个家庭或情侣账本即可邀请成员。")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Button { prepareShare() } label: {
                        HStack { Label(share == nil ? "通过 iCloud 邀请成员" : "管理成员与共享权限", systemImage: "person.2.fill"); if preparing { Spacer(); ProgressView() } }
                    }.disabled(preparing || ledger.archived)
                    if let share {
                        ForEach(Array(share.participants.enumerated()), id: \.offset) { _, participant in
                            HStack {
                                Text(participantName(participant))
                                Spacer()
                                Text(participant.role == .owner ? "所有者" : participant.permission == .readWrite ? "可编辑" : "可查看")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("仅邀请指定的 iCloud 用户。可编辑成员可修改全部账单；历史版本可在下方恢复。退出或停止共享会保留个人副本；若系统已移除数据，可从共享安全副本恢复上次管理时的版本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("最近记录与历史版本") {
                if activity.isEmpty { Text("记账后会显示记录历史").foregroundStyle(.secondary) }
                ForEach(activity) { item in
                    Button {
                        pendingRevision = item; confirmsRevision = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.author) · \(item.action)").foregroundStyle(.primary)
                            if let data = item.snapshot, let revision = try? JSONDecoder().decode(LedgerRevision.self, from: data) {
                                Text("\(revision.categoryNameSnapshot ?? revision.categoryKey) · ¥\(revision.amount, specifier: "%.2f")\(revision.isTrashed ? " · 已删除" : "")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(!store.canEdit(ledger))
                }
                if activity.count == 100 { Text("显示最近 100 个版本").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("\(ledger.emoji) \(ledger.name)")
        .sheet(isPresented: $editing, onDismiss: reload) { NavigationView { LedgerEditorView(ledger: ledger) }.navigationViewStyle(.stack) }
        .sheet(item: $sharing, onDismiss: reload) { LedgerCloudSharingView(session: $0) }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in reload() }
        .confirmationDialog("将这笔账单恢复为所选版本？", isPresented: $confirmsRevision, titleVisibility: .visible) {
            Button("恢复这个版本") {
                guard let pendingRevision else { return }
                do { try store.restoreRevision(pendingRevision); reload() }
                catch { message = error.localizedDescription }
                self.pendingRevision = nil
            }
        } message: { Text("会保留现有版本并新增一条修改记录。所选版本为删除状态时，该账单将保持删除。") }
        .alert("账本", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
    private func currency(_ value: Decimal) -> String { String(format: "¥%.2f", NSDecimalNumber(decimal: value).doubleValue) }
    private func participantName(_ p: CKShare.Participant) -> String {
        let name = p.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? "iCloud 成员"
        return name + (p.acceptanceStatus == .pending ? "（待接受）" : "")
    }
    private func reload() {
        guard !ledger.isDeleted else { return }
        do {
            let request = BookkeepingTransaction.fetchRequest(); store.scope(for: ledger).apply(request)
            total = LedgerMoney.total(try context.fetch(request))
            let history = LedgerActivity.fetchRequest(); history.predicate = NSPredicate(format: "ledgerRaw == %@", ledger)
            history.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]; history.fetchLimit = 100
            activity = try context.fetch(history)
            share = try store.share(for: ledger)
        } catch { message = "账本信息暂不可用，请稍后重试。" }
    }
    private func prepareShare() {
        preparing = true
        Task { @MainActor in
            defer { preparing = false }
            do { sharing = try await LedgerSharingService.shared.prepare(ledger) }
            catch { message = (error as? LedgerError)?.localizedDescription ?? CloudSyncState.Failure.from(error).message }
        }
    }
    private func recordSavings(income: Bool) {
        do {
            let cents = try LedgerMoney.cents(amount)
            guard cents > 0 else { throw LedgerError.invalidAmount }
            try store.requireWritable(store.scope(for: ledger), in: context)
            let tx = BookkeepingTransaction(context: context, amount: Double(cents) / 100,
                categoryKey: income ? "other_income" : "other", note: income ? "共同攒钱 · 存入" : "共同攒钱 · 取出", isIncome: income)
            try store.scope(for: ledger).attach(tx, in: context)
            if let error = PersistenceSaveCoordinator.save(context) { message = error }
            else { amount = ""; reload() }
        } catch { context.rollback(); message = error.localizedDescription }
    }
}

struct LedgerSafetyCopiesView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var archives: [LedgerArchive] = []
    @State private var pending: LedgerArchive?
    @State private var confirms = false
    @State private var message: String?
    var body: some View {
        List {
            Section { Text("邀请、管理成员或停止共享时保存在本机的安全副本。恢复会新建个人账本，不影响其他成员。系统尚未下载的记录不会包含在副本中。")
                .font(.caption).foregroundStyle(.secondary) }
            ForEach(archives) { archive in
                Button {
                    pending = archive; confirms = true
                } label: {
                    VStack(alignment: .leading) {
                        Text(archive.ledger.name)
                        Text("\(archive.transactions.count) 笔 · \(archive.createdAt.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if archives.isEmpty { Text("暂无安全副本") }
        }
        .navigationTitle("共享安全副本")
        .onAppear { do { archives = try LedgerSharingService.shared.safetyCopies() } catch { message = "无法读取安全副本。" } }
        .confirmationDialog("恢复为新的个人账本？", isPresented: $confirms, titleVisibility: .visible) {
            Button("恢复个人副本") {
                guard let pending, let store = LedgerStore.shared.privateStore else { return }
                do {
                    let copy = try pending.restorePersonalCopy(in: context, store: store)
                    LedgerStore.shared.refresh(); LedgerStore.shared.select(copy); message = "个人副本已恢复。"
                } catch { message = error.localizedDescription }
            }
        }
        .alert("安全副本", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
}
