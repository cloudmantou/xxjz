import SwiftUI

struct CloudSyncSettingsView: View {
    @ObservedObject private var preferences = PreferenceSyncCoordinator.shared
    @ObservedObject var monitor: CloudSyncMonitor
    @AppStorage(Constants.ICloud.cloudSyncPreferenceKey) private var preference = true
    @State private var showRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $preference) {
                Label("iCloud 同步", systemImage: "icloud")
                    .font(.subheadline)
            }
            .tint(Color.warmTeal)
            .onChange(of: preference) { _ in showRestartAlert = true }

            Text(monitor.statusText(preference: preference))
                .font(.caption)
                .foregroundStyle(monitor.failures.isEmpty ? Color.secondary : Color.orange)
                .accessibilityIdentifier("cloudSync.status")

            ForEach(Array(monitor.failures.enumerated()), id: \.offset) { _, failure in
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if monitor.isEnabled {
                timestamp("最近上传完成（本次启动）", date: monitor.state.activities[.upload]?.lastSuccess)
                timestamp("最近下载完成（本次启动）", date: monitor.state.activities[.download]?.lastSuccess)
                Button(monitor.isCheckingAccount ? "正在检查账户…" : "检查账户状态") {
                    monitor.refreshAccountStatus()
                }
                .font(.caption)
                .disabled(monitor.isCheckingAccount)
            }

            Text("同步范围：账单、预算、资产、心愿、自定义分类和本地识别规则。应用设置与内置规则包不参与同步。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            NavigationLink(destination: PreferenceSyncSettingsView()) {
                Label("分类与规则同步", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            if let error = preferences.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Text("同步由系统在网络和账户可用时调度；上传完成不表示另一台设备已下载。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .onAppear { monitor.refreshAccountStatus() }
        .alert("重启后生效", isPresented: $showRestartAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(preference
                 ? "已保存开启设置。请退出并重新打开 App；实际同步状态会在此处显示。"
                 : "已保存关闭设置。请退出并重新打开 App，重启前仍使用当前同步配置。本机数据会保留。")
        }
    }

    @ViewBuilder
    private func timestamp(_ title: String, date: Date?) -> some View {
        if let date {
            HStack {
                Text(title)
                Spacer()
                Text(date, format: .dateTime.month().day().hour().minute())
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
