import SwiftUI

struct ICloudBackupView: View {
    @ObservedObject private var service = ICloudBackupService.shared
    @Environment(\.managedObjectContext) private var context
    @State private var pending: LocalBackupEnvelope?
    @State private var deleting: CloudBackupItem?
    @State private var confirmsRestore = false
    @State private var confirmsDelete = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("iCloud 版本备份") {
                Text("备份独立于 iCloud 同步，可恢复到保存时的版本。包含全部已下载账本、资产、心愿单、自定义分类与规则，仅存入你自己的 iCloud。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { @MainActor in
                        do {
                            let data = try LocalBackupService.shared.exportBackup(from: context)
                            try await service.createBackup(data: data)
                            message = "备份已上传到 iCloud。"
                        } catch { service.report(error) }
                    }
                } label: { Label("立即备份", systemImage: "icloud.and.arrow.up") }
                Toggle("每天自动备份", isOn: Binding(get: { service.automaticEnabled }, set: { enabled in
                    Task { await service.setAutomatic(enabled); await service.automaticBackupIfNeeded(from: context) }
                }))
                Text("开启后在打开 App 时检查，每天最多备份一次；已保留 20 份时暂停，供你手动管理。不会自动删除旧版本。更换 iCloud 账户后需重新开启。")
                    .font(.caption).foregroundStyle(.secondary)
                if let last = service.lastBackupAt { Text("本机上次成功：\(last.formatted())").font(.caption) }
            }.disabled(service.isBusy)
            if service.isBusy { Section { HStack { ProgressView(); Text("正在处理 iCloud 备份…") } } }
            if let error = service.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            if let pending {
                Section("恢复预览") {
                    Text(pending.exportedAt.formatted())
                    Text("\(pending.payload.ledgers?.count ?? 1) 个账本 · \(pending.transactionCount) 笔账单 · \(pending.assetCount) 项资产")
                    Text("\(pending.customCategoryCount) 个自定义分类 · \(pending.customRuleCount) 条本地规则")
                    Text("会替换个人账本和其他个人数据；正在共享的账本保留，备份中的共享账本恢复为个人副本。恢复前自动保存本地回退备份。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("确认恢复此版本", role: .destructive) { confirmsRestore = true }.disabled(service.isBusy)
                }
            }
            Section("云端版本") {
                Button("刷新版本列表") { Task { await service.refresh() } }.disabled(service.isBusy)
                if service.backups.isEmpty && !service.isBusy { Text("暂无已加载的备份").foregroundStyle(.secondary) }
                ForEach(service.backups) { item in
                    HStack {
                        Button {
                            Task { @MainActor in
                                do { pending = try await service.preview(item) }
                                catch { service.report(error) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.createdAt.formatted())
                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.borderless)
                        Spacer()
                        Button(role: .destructive) { deleting = item; confirmsDelete = true } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel("删除此云端备份")
                    }.disabled(service.isBusy)
                }
            }
            Section { NavigationLink("本地文件备份与回退版本") { LocalBackupView() } }
        }
        .navigationTitle("iCloud 备份")
        .task { await service.refresh() }
        .confirmationDialog("恢复此版本并替换个人数据？", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("保存回退备份并恢复", role: .destructive) {
                guard let pending else { return }
                Task { @MainActor in
                    do { try await service.restorePreview(pending, into: context); self.pending = nil; message = "恢复完成。正在共享的账本未被覆盖。" }
                    catch { service.report(error) }
                }
            }
        } message: { Text("账单、预算、资产、心愿单、自定义分类和规则会恢复到所选版本。共享账本只创建个人副本。") }
        .confirmationDialog("永久删除这个云端备份？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("删除云端备份", role: .destructive) {
                guard let deleting else { return }
                Task { do { try await service.delete(deleting) } catch { service.report(error) } }
            }
        } message: { Text("仅删除所选备份版本，不影响当前账单或 iCloud 同步数据。") }
        .alert("iCloud 备份", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
}
