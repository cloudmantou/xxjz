# iOS 15 兼容迁移方案（AssetLife）

## 现状冲突
- 当前项目依赖 `SwiftData`（iOS 17+）和 `Swift Charts`（iOS 16+）。
- 因此在不改技术栈的前提下，**无法实现 iOS 15 全量支持**。

## 目标
- 支持 iOS 15+ 设备安装与核心功能可用（资产 / 心愿 / 统计 / 表单）。

## 迁移策略（建议两阶段）
1. 阶段 A：数据层迁移到 Core Data
- 将 `@Model` 实体改为 `NSManagedObject`。
- 把 `@Query` 查询替换为 `@FetchRequest` 或 ViewModel + Repository。
- 保留现有业务计算 Service（公式层不变）。

2. 阶段 B：图表能力兼容
- iOS 16+：继续使用 `Swift Charts`。
- iOS 15：提供降级视图（列表化趋势 + 关键统计卡）或接入第三方图表库。

## 工程改造清单
- `project.yml` 最低版本改为 iOS 15。
- 引入 `PersistenceController`（Core Data 栈）。
- 建立 `Repository` 层，隔离存储实现，避免未来再次大迁移。
- 用 `#available(iOS 16, *)` 包裹图表组件。
- 单元测试补齐：仓储层 + 迁移映射 + 核心公式回归。

## 风险点
- 数据模型字段升级（尤其数组/关系）需要设计迁移策略。
- 图表降级会影响 Dashboard 视觉一致性。
- 预计需要一次完整回归测试（录入、编辑、删除、统计、转资产）。

## 建议排期
- 第 1 周：Core Data 基础层 + 模型迁移。
- 第 2 周：列表/详情/表单适配。
- 第 3 周：图表降级与测试补齐。

## 当前进度（2026-03-28）
- 已完成：SwiftData -> Core Data 模型替换（`NSManagedObject` + 关系定义）。
- 已完成：`PersistenceController`（程序化模型 + 持久化容器 + Preview 数据）。
- 已完成：App 入口改为 `managedObjectContext` 注入，列表查询改为 `@FetchRequest`。
- 已完成：图表降级（iOS 15 fallback 视图）+ `#available(iOS 16, *)` 包裹 Chart 组件。
- 已完成：`NavigationStack`/`navigationDestination`/`PhotosPicker` 替换为 iOS 15 兼容实现。
- 已完成：`project.yml` 最低版本下调至 iOS 15 并重新生成工程。
- 待完成：在完整 Xcode 环境执行一次真机构建与 CI 测试回归。
