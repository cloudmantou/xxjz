# 自定义分类与本地识别规则的 iCloud 同步

基线：`6643887`。本轮仅修改 iOS 客户端，不改变后端或管理后台。

## 设计与来源

- 沿用现有 `NSPersistentCloudKitContainer` 私有数据库、推送注册、同步开关与状态监控。参考 [Apple Core Data 同步示例](https://github.com/apple/sample-cloudkit-coredatasync)（MIT）。不另建 CloudKit 传输引擎。
- 对照 [CloudSyncSession](https://github.com/ryanashcraft/CloudSyncSession)（[MIT](https://github.com/ryanashcraft/CloudSyncSession/blob/main/LICENSE.md)，查询时最近 push 为 2026-08-12）：它将传输与存储分离，但本身不持久化状态；接入还需要自行实现变更 token、待上传队列及冲突持久化。本项目已有原生容器，因此不增加该依赖。
- 也检查了 [Harmony](https://github.com/aaronpearce/Harmony) 的 GRDB / iOS 17 方案；本项目同时存在 Core Data 和 SQLite.swift，并支持 iOS 15，不适合直接替换。没有复制这些项目的源码。
- [Apple 的远端记录说明](https://developer.apple.com/documentation/cloudkit/remote-records)及 [ifServerRecordUnchanged](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)说明可变记录冲突需要客户端处理。本方案使用不可变操作记录，让冲突双方都进入本地数据库，再由应用作确定性归并。

## 数据保留与迁移

1. 原来的八种账单/资产实体保持版本 hash 不变，新增 `SyncedPreferenceOperation`。旧模型冻结在 `AssetLifeLegacyV1.mom`；生成源位于 `scripts/generate-legacy-model.swift`，不可随新模型演进而修改。
2. 打开旧账单库前，使用 Core Data 的 `replacePersistentStore` 复制数据库到同目录下 `BeforePreferenceSync-<UUID>/AssetLife.sqlite`，包含 SQLite WAL 与外部二进制数据；备份失败就停止加载。随后进行原生轻量迁移，不重建账单库、不重置 CloudKit 元数据。
3. 首次迁移分类和本地规则时，先严格读取 UserDefaults / SQLite，再写 `Library/Application Support/PreferenceMigrationBackups/legacy-<摘要>.json`。读取/备份失败不会按空数据进行覆盖。
4. 分类保留原 UUID 和 `custom_<UUID>` 引用。规则新增可选 `syncID`；旧备份仍能解码，旧规则整条内容的确定性摘要用作迁移身份。不同设备的旧整数 ID 相同、内容不同，会保留成不同规则。
5. 一次保存所有初始操作，提交成功后再写数据库身份对应的迁移标记，最后更新原有读取缓存。重复迁移不会重复创建相同操作。旧 JSON / SQLite 不删除，继续作为可重建的读取缓存。
6. 本地规则的 SQLite 整数 ID 按设备分配，冲突时重新映射。规则包不参与 iCloud 同步；规则包重用本地规则的整数 ID 时先保留并移动本地规则及其匹配条件。

## 冲突规则

| 情况 | 结果 |
| --- | --- |
| 普通编辑 | 新操作引用已知父版本，替代这些版本 |
| 两台设备并发编辑 | 确定性选取一个展示版本，保留双方内容，在设置页选择 |
| 删除与离线编辑并发 | 删除优先，编辑内容仍保留，可显式恢复 |
| 老设备迟到的迁移快照 | 不覆盖已有编辑或删除记录 |
| 显式恢复/选择版本 | 产生新操作，仅确认用户看过的版本；未见的新编辑仍会显示冲突 |
| CloudKit 分批下载，父版本未到 | 暂停更新缓存与写入，保留当前可读数据，后续下载/前台刷新时重试 |
| 未知格式、损坏操作、循环或跨项目父引用 | 不按空结果投影；提示错误并保留缓存 |
| CloudKit 重复记录 | 相同操作 ID 与相同内容去重；同 ID 不同内容拒绝覆盖 |

不依赖设备时钟决定胜负。删除标记与冲突历史不自动清理，避免长期离线设备导致复活。已删除分类的历史名称仍可用于现有账单，不出现在新记账的分类列表中。

设置入口：**我的 → iCloud 同步 → 分类与规则同步**。可查看冲突、选择版本、恢复已删除项目。收到远端变更后重建分类缓存并通知识别规则引擎重新加载；账单及统计页面观察分类变化。

## 本地备份与失败处理

- 操作时间单独编码为完整精度的参考时间秒数，不受外层日期编码策略影响（正式备份为毫秒时间戳，兼容性测试另外覆盖 ISO-8601）；同 ID 的比对忽略仅用于展示的日期精度变化，仍严格检查内容及因果引用。
- 新备份额外包含可选的同步历史；旧格式缺少该字段仍可读取，未设置 `syncID` 的旧规则编码保持兼容。
- 恢复备份时，分类/规则操作与账单替换在同一个 Core Data context 中提交。账单保存失败会回滚尚未提交的操作，并补偿恢复 SQLite 与分类缓存，不提前向 iCloud 发布恢复结果。
- 操作保存成功后，即使缓存更新失败，操作也保留在 Core Data，后续可重试缓存重建；不把已经提交的操作回滚成数据丢失。
- `PreferenceSyncDiagnostics.json` 只保存就绪状态和数量，不记录分类名、规则文本、账单内容或账户身份。

## 验证

- 完整模拟器测试：195 项，共 **194 通过、0 失败、1 跳过**。跳过项仍是缺少本机截图 fixture 的既有测试。
- 新增 21 项测试：旧库轻量迁移和备份、账单/引用/历史/store identity 保留；迁移幂等与失败保留；独立数据库离线合并；删除优先与显式恢复；重复操作、坏图和未来格式拒绝；分批下载缓存保留；SQLite ID 撞号与规则包保护；真实 save 抛错后 rollback；恢复事务回滚；旧备份兼容及外层 ISO-8601 编码下的操作身份稳定性。
- iPhone 13 Pro Max 的 Debug 签名构建通过；已签名产物的 CloudKit container、APNs、后台通知能力检查通过。
- 已覆盖安装并启动上述 iPhone，未卸载 App。升级前后 180 条账单、1 项资产的业务字段完全一致（仅 Core Data 内部 `Z_OPT` 修订计数变化）；50 条内置规则及匹配条件逐字段一致。手机生成了旧账单库备份和偏好迁移 JSON。
- 14:06 真机诊断：偏好模块 `ready=true`、`hasError=false`；CloudKit 账户可用，setup / upload / download 均完成，错误列表为空。手机原有自定义分类和本地规则都是 0，因此这只证明升级/就绪和通用 CloudKit 通道，不能证明新增偏好的真实跨设备传输。
- 两份独立数据库测试不等同于两台物理设备通过 iCloud 完成端到端同步。Production/TestFlight schema 发布及跨设备增删改验收仍需单独完成。

## 发布与后续边界

新增 CloudKit 实体需要在发布 TestFlight/App Store 前检查并部署 Development → Production schema；本轮不自动发布生产 schema。所有设备应升级后使用新增分类/规则同步功能。关闭同步时继续本地保存操作，重新开启重启后由原生容器同步。

当前操作历史不压缩，偏好数量很大时需要另行做性能/存储评估，不能在缺少离线设备确认机制时直接删除旧操作或删除标记。账户切换、云端整区删除和生产环境恢复不包含在本轮实测结论内。
