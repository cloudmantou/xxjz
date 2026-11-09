# iCloud 同步审计与修复

审计基线：`c8235f2`。范围为 iOS 客户端的 CloudKit 配置、状态反馈和本地存储退化路径；没有修改云端 schema 或删除本机/云端数据。

## 已修复

| 问题 | 修复与验证 |
| --- | --- |
| 签名包有 CloudKit 容器权限，但缺少 APNs entitlement；Info.plist 没有 remote-notification | 补 aps-environment 和后台远程通知模式；启动/回前台注册静默通知，显示注册失败。真机签名包检查通过，不请求提示音/角标/横幅权限 |
| 设置页只显示 UserDefaults 偏好，容易把开启开关误认作同步成功 | 显示配置生效状态、账户状态、同步活动、上传/下载成功时间和错误；修改开关明确提示重启前仍是旧配置 |
| loadPersistentStores 成功被视为同步可用，后续异步失败不可见 | 在加载 store 前监听该 container 的 CloudKit setup/import/export 事件。数据库加载、账户可用均不被视为传输成功 |
| 加载 CloudKit store 失败后退回本地，却丢弃原始错误 | 保留安全的错误分类并显示“已退回本地”；重试/退化前移除旧 store，避免同一 SQLite 同时由多个 mirroring delegate 管理 |
| 同步失败被无关操作或乱序完成事件覆盖 | 每阶段分别保存结果；开始重试不清除失败，只有该阶段更新的成功结果才清除；并发活动按事件 ID 计数 |
| 账户检查迟到、账户切换和超时 | 请求代次隔离、账户切换清理旧状态、20 秒超时并可再次检查 |
| 关闭同步时不再配置 persistent history | 非内存 store 始终启用历史跟踪，保留以后开启同步需要的本地变更。磁盘重开测试验证账单和历史均保留 |
| 无可读取的同步诊断 | 写入 Library/Caches/CloudSyncDiagnostics.json，仅保存阶段时间、开关状态、账户状态枚举和错误 domain/code；不保存账单内容、账户标识、令牌或原始错误描述 |
| XcodeGen 与已签名工程的 team 不一致 | project.yml 对齐当前各 target 已使用的 W5DCNSYG76，避免重新生成工程时退回另一团队；现有 target 的签名设置不变 |

`aps-environment` 源文件采用 Xcode 开发配置惯例；发布导出时以分发 provisioning profile 重新签名后的 entitlement 为准。脚本 `scripts/verify-cloudkit-signing.py /path/to/AssetLife.app` 检查最终包，而非只检查源码。

“检查账户状态”只查询账户，不声称强制上传。Core Data / CloudKit 传输仍由系统调度。上传完成也不代表另一台设备已完成下载。

## 数据范围与独立后续项

当前 CloudKit store 包含账单、预算、资产及其费用/出售记录、心愿及其价格记录。自定义分类在 UserDefaults，本地识别规则在独立 SQLite；它们没有加入 CloudKit。设置页已明确范围，避免把账单同步解释成完整应用备份。

分类与规则的云端迁移仍需独立设计：旧格式迁移、跨设备相同 ID 合并、删除墓碑、分类引用一致性、备份恢复与回滚，以及版本兼容。不能用一次整体覆盖 UserDefaults 冒充可靠的多设备合并。本轮不改这些数据模型。

## 参考与取舍

按仓库要求先检索许可证与维护情况，未复制第三方实现，也未增加包依赖：

- [fatbobman/iCloudSyncStatusKit](https://github.com/fatbobman/iCloudSyncStatusKit)：MIT，未归档，最近推送 2026-01-06。提供账户、网络、同步事件分层监控；现代 API 要求 Swift 6.2 / iOS 17，legacy API 要求 Swift 6，公开 issue 包含 iOS 16 支持问题。借鉴分层状态设计，当前工程保留 Swift 5.9 / iOS 15 的原生实现。
- [ggruen/CloudKitSyncMonitor](https://github.com/ggruen/CloudKitSyncMonitor)：MIT，最近推送 2025-06-02；分开跟踪 setup/import/export。公开 issue 涉及账户状态不准、部分错误漏报和 TestFlight 未知状态，因此补充请求代次、失败保留和乱序测试，不把第三方汇总状态直接当成功依据。
- [Apple Core Data Sync 示例](https://github.com/apple/sample-cloudkit-coredatasync)：MIT，最近推送 2022-02-01，作为官方接线参考，不声称近期活跃。
- [Apple：设置 Core Data + CloudKit](https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit)、[TN3164 同步诊断](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)：核对 entitlement、后台通知、事件观测与系统调度语义。

## 验证证据

- 本地全量：174 total = 173 passed / 0 failed / 1 skipped。新增 16 个同步回归测试；旧 skip 仍是依赖开发机截图路径的测试。
- 真机 Debug 构建通过；最终签名包 CloudKit container / services、APNs entitlement、background notification 五项检查通过。
- 已覆盖安装到 iPhone 13 Pro Max，iOS 18.7.8。2026-11-09 13:03:10（北京时间）setup 成功，13:03:12 upload 和 download 成功；账户状态 available，错误数组为空。证据来自新安装应用实际发出的 CloudKit 事件，不是模拟器或伪造事件。
- 真机成功事件可包含没有新增记录的传输，不据此声称所有历史账单均已上传或另一台设备已经收到。
- 尚未完成第二台设备的增删改互相同步、卸载后恢复、离线后重连、账户切换、TestFlight Production 环境与 schema 的端到端验收。模拟器和 XCTest 继续禁用 CloudKit，避免访问个人云端数据；单元测试绿灯不代替这些实测。
