# 多账本、共同攒钱与 iCloud 版本备份

## 产品调研与取舍

调研日期：2026-11-09。首版支持 iPhone/iPad，每位成员使用自己的 iCloud 账户。

| 参考 | 已核对的设计 | 本次采用与边界 |
| --- | --- | --- |
| [钱迹共享账本](https://docs.qianjiapp.com/vip/vip_book_share.html) | 默认账本不共享；独立账本邀请成员；管理员与普通成员有不同权限 | 保留原有个人账本，新建家庭/情侣/旅行账本再分享；不照搬其“只能编辑自己账单”的权限模型 |
| [Splitwise 权限说明](https://kb.splitwise.com/groups/can-i-prevent-group-members-from-changing-expenses-or-set-permissions) | 群组成员可修改共享费用，并有活动记录 | 可编辑成员能修改整个共享账本，保留账单修改前后版本供恢复 |
| [Honeydue 隐私说明](https://support.honeydue.com/en/articles/3283211-how-to-change-what-my-partner-can-see) | 个人财务信息可选择共享范围 | 以账本作为边界；资产、心愿单、个人识别规则不进入共享图 |
| [Spliit](https://github.com/spliit-app/spliit) / [MIT](https://github.com/spliit-app/spliit/blob/main/LICENSE) | 维护活跃（检查时未归档，最近 push 为 2026-11-05）；群组、费用、余额、结算、活动记录 | 借鉴群组边界和活动记录；其 Next.js/Prisma/PostgreSQL 服务端栈不作为原生离线客户端依赖。首版不做 AA 债务结算 |
| [Apple CloudKit sharing sample](https://github.com/apple/sample-cloudkit-sharing) / [许可证](https://github.com/apple/sample-cloudkit-sharing/blob/main/LICENSE.md) | Swift + CloudKit + UICloudSharingController、分享接受回调；MIT 条款 | 借鉴原生邀请流程，不复制源码。官方教学示例不能视为高频维护的成品账本 |
| [Apple Core Data sharing 文档](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users) | private/shared 双 store；分享遍历关系图；显式 store 分配；系统调度同步；停止共享与 purge | 采用 NSPersistentCloudKitContainer，避免自行维护一套服务器同步协议 |

未引入第三方依赖，未复制上述开源项目代码。界面沿用现有应用组件并使用系统共享管理器。

## 已实现的行为

- 首页与快速记账页切换账本；“我的 → 账本与共同攒钱”新建、修改名称、设置攒钱目标、归档/取消归档。
- 账单、预算、统计、导入查重、导出、小组件按当前账本过滤。导入开始前捕获目标账本，切换界面不会改变正在导入的数据归属。
- 默认个人账本保留旧数据且不允许分享。命名账本可由系统分享面板邀请指定用户、查看成员、管理查看/编辑权限和停止共享。不提供公开分享。
- 可编辑成员能修改全部账单；UI 与保存前检查只读权限，共享元数据缺失时拒绝写入。昵称是展示信息，不是身份认证或安全审计凭据。
- 账单软删除；每次本地修改与删除在同一保存中记录修改前后快照。最近 100 个历史版本可恢复，恢复本身再次留痕。
- 一个账本可设置一个人民币攒钱目标，金额目标以 Int64 分存储。进度为累计收入减支出，转账不计入；存入/取出按钮只记账，不进行资金划转。多个目标可使用多个账本。
- 自定义分类名称/图标随账单快照展示，其他成员不需要拥有相同的私人分类配置。全局分类与识别规则继续使用此前的私人同步日志，不分享给账本成员。

## 数据模型与迁移

`Private` store 继续使用原来的 `AssetLife.sqlite`；`Shared` store 使用新建的 `AssetLifeShared.sqlite`。共享 store 只包含 `Ledger`、`BookkeepingTransaction`、`BudgetEntry`、`LedgerActivity`。Ledger 的关系图只通往后三者，不能通过关系遍历访问资产、心愿单或全局偏好。

新增的账本关系均可空，保留旧实体与字段，执行轻量迁移。保留 V1 源模型，新增冻结的 V2 源模型 `AssetLifeLegacyV2.mom` 及生成脚本。迁移前通过 Core Data 复制原始 SQLite store，包含 WAL 状态。未知源模型拒绝继续，不以空库替换。

旧账单/预算归入固定逻辑标识的私人默认账本。多台旧设备离线升级可能各自创建默认根；保留所有根及关系，只在 UI 合并展示，查询涵盖全部个人根，不做破坏性去重。命名账本用 objectID + 所属 store 确定作用域。

账单金额继续使用已有字段，本次没有进行全量 Int64 金额迁移。

## 同步、冲突与停止共享

CloudKit/NSPersistentCloudKitContainer 负责离线队列、远程导入与存储合并；不是实时通信，也没有承诺逐条强一致。多人同时编辑同一账单时，最终展示由系统合并决定；各设备正常保存的完整账单快照会单独同步，用户可查看并恢复所需版本。历史记录不是不可篡改日志，可编辑成员持有整个分享的写权限。

私人与共享 store 的同步状态分别保留；一个 store 成功不能清除另一个 store 尚未恢复的错误。

分享前在 Application Support/SharedLedgerSafetyCopies 保存一份本地安全副本。停止/退出共享回调优先抓取当时可见数据，创建新的私人副本，再清理原共享区域。若系统已移除本地共享图，则使用进入管理页前的副本。恢复失败可在“共享安全副本”页面重试。副本仅包含当时已下载内容；所有者从另一台设备移除成员后，不能保证被移除设备仍能获取最新记录。

接受分享支持冷启动、运行中的 scene 回调与应用回调，重复接受请求去重。分享准备请求去重并有 UI 超时处理；超时后系统仍可能完成操作，再次进入管理会查询实际分享状态。

## iCloud 备份与恢复

实时同步与版本备份分开。版本备份使用用户自己的 private database，独立 zone `XXJZBackups_v1`，记录类型 `XXJZBackupSnapshot`，CKAsset 保存完整 JSON，附带格式版本、时间、大小和 SHA-256。列表只请求元数据，通过 zone changes 获取，不要求配置查询索引，也不下载全部 CKAsset。

单文件上限 100 MB。手动上传、下载预览、校验后恢复，以及逐份确认删除。自动备份默认关闭，开启后在 App 打开/激活时检查，间隔至少 24 小时；失败间隔至少 10 分钟重试；满 20 份时暂停，不自动删除。它不是保证后台执行的定时任务。自动备份绑定启用时的 iCloud 账户，更换账户后暂停。预览与恢复绑定当前账户，预览之后更换账户也会拒绝恢复。

完整备份格式升级到 V2，继续读取 V1；新增账本、归属、软删除状态、攒钱目标和历史。恢复前自动保存本地回退文件，入口在“完整数据备份”。

恢复操作先严格读取共享元数据：现有 joined shared store 数据和所有者 private store 中已分享的账本均保留。元数据查询失败则停止恢复。备份里的共享账本创建新的私人账本，重建账单/历史标识，不复用 CKShare、不恢复成员权限、不覆盖他人正在编辑的数据。

## 验证证据与待验证范围

- 全量模拟器测试：220 项，219 通过、0 失败、1 跳过；新增 25 项账本/备份测试。跳过项仍是缺少本机截图 fixture 的原有测试。
- 新增测试覆盖 V2 SQLite 迁移、原数据标识保留、重复默认根、账本作用域、捕获导入作用域、归档写入拒绝、账单历史恢复、共享图隔离、安全副本恢复、joined/owner 共享账本恢复保护、不完整共享图拒绝备份、金额精度、备份上传失败/损坏/账户切换/保留上限和双 store 错误展示。
- 真机签名构建通过，CloudKit/APNs/container/background notification entitlement 检查通过。
- 2026-11-09 真机覆盖安装并启动；升级前后核对 181 笔账单、1 项资产、1 条偏好同步日志的全部原有业务字段一致（不比较 Core Data 内部 Z_OPT/Z_ENT/Z_PK）。181 笔账单均归入个人账本，0 笔软删除，SQLite quick_check 为 ok。迁移前自动备份及新 shared store 已落盘。
- 真机新运行周期 CloudKit setup 08:21:51Z、download 08:21:53Z、upload 08:21:56Z 成功，错误列表为空。这证明当前真机的通用同步运行，不代表两账户共享或自定义备份 zone 已实测。
- 模拟器编译、测试、启动及首页账本入口截图通过。当前自动点击工具未触发实际操作，桌面 UI 后备工具也发生超时；尚不能声称完整交互冒烟测试通过。
- 两个独立 iCloud 账户的邀请/接受、双向增删改、断网并发修改、只读参与者、撤销权限、双方退出、云端 CKAsset 上传下载恢复仍需联测。目前第二台真实 iPad 不在线。
- TestFlight/App Store 发布前需要在 CloudKit Dashboard 检查并部署新增 Core Data schema 和自定义备份 record type 到 Production，再使用 Production 环境验收。本代码不在启动时调用 initializeCloudKitSchema，也没有自动发布生产 schema。

## 两账户验收步骤

1. A 保持个人旧账本，新建“家庭”；确认私人资产、心愿和规则不出现在共享账本图里。
2. A 邀请 B，B 使用另一 iCloud 账户接受；等待系统导入后分别记账，检查独立统计和预算。
3. B 改为只读后尝试记账、导入、恢复版本、修改目标，确认被拒绝且 UI/本地数据无残留改动。
4. 双方离线编辑同一账单后联网，检查最终值及双方历史快照；显式恢复一版后再次同步。
5. A/B 分别导出与恢复完整备份；当前共享账本不被覆盖，只出现新的私人副本。
6. 测试移除成员、退出和停止共享；核对安全副本入口、私人副本和其他共享账本不受影响。
7. 上传两份云端备份，下载校验、恢复、删除其中一份；切换 iCloud 账户验证旧列表/旧操作不可跨账户执行。
