# 无忧书（AssetLife）

一款专注于个人财务管理的 iOS 原生应用，支持智能记账、资产管理、心愿单追踪与数据统计。

---

## 目录

- [功能概览](#功能概览)
- [技术架构](#技术架构)
- [项目结构](#项目结构)
- [核心功能详解](#核心功能详解)
  - [记账模块](#记账模块)
  - [资产管理模块](#资产管理模块)
  - [心愿单模块](#心愿单模块)
  - [首页仪表盘](#首页仪表盘)
- [扩展功能](#扩展功能)
  - [Share Extension](#share-extension)
  - [Widget 桌面小组件](#widget-桌面小组件)
  - [Siri & 快捷指令](#siri--快捷指令)
- [智能识别与自动化](#智能识别与自动化)
- [后端服务](#后端服务)
- [数据模型](#数据模型)
- [开发与构建](#开发与构建)

---

## 功能概览

| 模块 | 功能 |
|------|------|
| 📒 记账 | 快速记录收支、智能识别账单截图、自动分类、预算管理、导入/导出 |
| 🏷️ 资产管理 | 追踪个人资产全生命周期（购入→维护→出售）、统计每日成本 |
| ❤️ 心愿单 | 记录心仪商品、多平台比价、价格历史趋势 |
| 📊 首页仪表盘 | 资产总览、分类分布图表、月度趋势分析 |
| 🔗 快捷指令 | Siri 语音记账、iOS 快捷指令自动化 |
| 🪟 桌面小组件 | 今日收支快览 |

---

## 技术架构

- **平台**: iOS 17.0+
- **UI 框架**: SwiftUI
- **数据存储**: CoreData（记账/资产数据）+ SwiftData（心愿单数据）
- **架构模式**: MVVM
- **图表**: Swift Charts（iOS 16+ 内置）
- **本地化**: 中文简体（zh-Hans）、英文（en）
- **后端**: Node.js + Express（规则热更新配置服务）

---

## 项目结构

```
xijz/
├── wuyoushu/                    # iOS 主应用
│   ├── wuyoushuApp.swift        # App 入口
│   ├── Models/                  # 数据模型（CoreData + Swift Struct）
│   ├── ViewModels/              # ViewModel 层
│   ├── Views/
│   │   ├── Home/                # 首页仪表盘
│   │   ├── Bookkeeping/         # 记账模块
│   │   ├── Asset/               # 资产管理模块
│   │   ├── Wish/                # 心愿单模块
│   │   ├── Profile/             # 个人设置
│   │   ├── Settings/            # 外观等设置
│   │   └── MainTabView.swift    # 主 TabView 导航
│   ├── Services/                # 业务服务层
│   ├── Extensions/              # Swift 扩展
│   └── Utilities/               # 通用工具/常量
├── backend/                     # 后端规则热更新服务（Node.js）
├── BookkeepingWidget/           # 桌面小组件 Extension
├── BookkeepingIntentsExtension/ # Siri/快捷指令 Extension
├── ShareExtension/              # 分享扩展
├── ShortcutTemplates/           # 快捷指令模板文件
├── SPEC.md                      # 产品规格文档
└── project.yml                  # XcodeGen 项目配置
```

---

## 核心功能详解

### 记账模块

#### 快速记账（QuickRecordView）

- 支持 **支出 / 收入 / 转账** 三种类型切换
- 选择分类与子分类（支持自定义分类）
- 选择资金账户（现金、微信、支付宝、储蓄卡、信用卡、花呗）
- 备注、日期自定义
- 是否计入预算开关

#### 账单分类

**支出分类**

| 分类 | 子分类示例 |
|------|-----------|
| 🍽️ 餐饮 | 早餐、午餐、晚餐、外卖、夜宵、聚餐 |
| 🚗 交通 | 公交、地铁、出租车、加油、停车、高铁、飞机 |
| 🛍️ 购物 | 衣服、鞋子、数码、日用品、家居 |
| 🎮 娱乐 | 电影、游戏、音乐、KTV、运动、旅行 |
| 🏠 居住 | 房租、水电、物业、网费、维修 |
| 🏥 医疗 | 门诊、药品、体检、牙科 |
| 📚 教育 | 书籍、课程、培训、考试 |
| 🎁 人情 | 红包、礼物、请客、婚礼 |
| 💸 转账 | 微信、支付宝、银行、现金 |
| 📦 其他 | 杂费、丢失、罚款 |

**收入分类**：工资、兼职、理财收益、红包、退款、其他收入

> 支持用户自定义分类，保存至本地

#### 预算管理（BudgetManagementView）

- 按月、按分类设置预算上限
- 实时对比实际消费与预算

#### 账单统计（StatisticsHomeView / TransactionStatsView）

- 月度/年度收支汇总
- 分类消费占比图表
- 自定义时间范围筛选

#### 导入账单（ImportView）

支持从 CSV / 电子表格文件导入历史账单，流程：

1. 选择文件
2. 预览数据
3. 字段匹配
4. 确认导入

#### 导出账单（ExportView）

将记录导出为标准 CSV 格式，可用于备份或迁移。

---

### 资产管理模块

追踪个人资产从购入到处置的完整生命周期。

**核心功能**：
- 添加/编辑资产（名称、分类、购入日期、购入价、当前估值）
- 记录额外费用（维修、保险、升级等）
- 记录出售记录（出售价格、平台、盈亏计算）
- 资产统计总览（AssetsStatisticsView）
- 批量管理（AssetBatchManagementView）
- 导入/导出资产数据

**计算指标**：
- 持有天数
- 每日折旧成本 = (购入价 + 额外成本) / 持有天数
- 生命周期进度
- 出售盈亏

---

### 心愿单模块

记录想买但未购入的商品，支持多平台比价。

**核心功能**：
- 添加心愿商品（名称、分类、目标价格、优先级 1-5）
- 多平台价格录入（京东、淘宝、拼多多等任意平台 + 链接）
- 价格历史记录与趋势图表
- 按优先级排序/筛选

---

### 首页仪表盘

- 资产总价值卡片
- 资产状态分布图（活跃/已售/已处置）
- 资产分类分布图
- 每日成本 Top 5 资产排行
- 月度消费趋势折线图

---

## 扩展功能

### Share Extension

通过 iOS 系统「分享」功能将支付宝、微信账单页面的截图直接共享到无忧书，自动触发 OCR 识别与记账。

### Widget 桌面小组件

在 iOS 桌面展示今日收支快览，无需打开 App 即可了解当日财务状态。

### Siri & 快捷指令

- 支持通过 Siri 语音触发快速记账
- 提供官方快捷指令模板（`ShortcutTemplates/`）：
  - `xiaoxi-auto-bill-official.shortcut` — 自动账单识别主流程
  - `xiaoxi-auto-bill-text-fallback.shortcut` — 文本回退识别流程
  - `xiaoxi-open-record-official.shortcut` — 快速打开记账界面

---

## 智能识别与自动化

### OCR 账单识别

- 自动检测用户截图（`ScreenshotDetector`）
- 识别支付宝、微信账单截图（`AlipayTransactionParser` / `WechatTransactionParser`）
- 空间 OCR 分析（`SpatialOCRAnalyzer`）：基于文字坐标位置解析账单结构
- 语音识别（`SpeechRecognitionService`）：支持语音输入金额和备注

### 自动分类规则引擎（AutoBillRuleEngine）

基于关键词匹配规则自动将识别到的账单归类：

- **模糊匹配**（`FuzzyTextMatcher`）：支持近似词匹配，处理 OCR 误识别
- **LCS 行对齐**（`LCSStepAligner`）：多行账单文本对齐算法
- **规则热更新**（`RuleUpdateService` + 后端服务）：从服务端拉取最新规则，无需发版即可优化自动分类

### AI 分析服务（AIAnalysisService）

- 收据图片分析（商家、金额、日期、商品明细）
- 商品分类智能建议

### 配置热更新（ConfigHotUpdateService）

从服务端拉取配置，包含：
- OCR 正则表达式字典（金额、日期、关键词）
- 商品视觉规则配置
- 版本控制与 AES 加密传输

---

## 后端服务

详见 [`backend/README.md`](./backend/README.md)

后端是一个轻量级 Node.js 服务，负责：

1. **规则发布管理**：发布关键词匹配规则版本，支持全量/增量发布、回滚、紧急屏蔽
2. **配置热更新**：下发 OCR 配置、分类规则等，客户端通过版本号做差量更新
3. **Admin 鉴权**：写操作需要 API Key 认证

**主要 API**：

| 路径 | 方法 | 描述 |
|------|------|------|
| `GET /health` | 公开 | 健康检查 |
| `GET /api/config/get` | 公开 | 获取最新配置 |
| `GET /api/config/version` | 公开 | 获取配置版本号 |
| `GET /api/Config/GetV2` | 公开 | 获取配置（兼容旧版） |
| `GET /api/KeyWordMatchingRule/List` | 公开 | 获取最新规则列表 |
| `GET /api/admin/rules/releases` | 🔒 Admin | 查看所有规则版本 |
| `POST /api/admin/rules/releases/full` | 🔒 Admin | 发布全量规则 |
| `POST /api/admin/rules/releases/patch` | 🔒 Admin | 发布增量规则 |
| `POST /api/admin/rules/releases/:id/publish` | 🔒 Admin | 发布草稿版本 |

---

## 数据模型

### BookkeepingTransaction（记账记录）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| amount | Double | 金额（绝对值） |
| categoryKey | String | 分类键（如 `dining`） |
| subcategoryKey | String? | 子分类键（如 `lunch`） |
| note | String? | 备注 |
| date | Date | 交易日期 |
| isIncome | Bool | 是否为收入 |
| fundAccountKey | String? | 资金账户（如 `wechat`） |
| notInBudget | Bool | 是否排除预算统计 |
| billSource | String? | 账单来源（支付宝/微信等） |
| merchantName | String? | 商家名称 |

### BudgetEntry（预算条目）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| categoryKey | String | 分类键 |
| monthlyAmount | Double | 月度预算金额 |
| month | Date | 预算月份 |

### AssetItem（资产）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| name | String | 资产名称 |
| category | String | 分类 |
| purchaseDate | Date | 购入日期 |
| purchasePrice | Double | 购入价格 |
| currentValue | Double | 当前估值 |
| status | AssetStatus | active / sold / disposed |

### WishlistItem（心愿商品）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| name | String | 商品名称 |
| targetPrice | Double | 目标价格 |
| priority | Int | 优先级（1-5） |
| isPurchased | Bool | 是否已购买 |

---

## 开发与构建

### 环境要求

- Xcode 15+
- iOS 17.0+ 模拟器或真机
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（用于生成 `.xcodeproj`）

### 生成项目

```bash
xcodegen generate
```

### 运行后端

```bash
cd backend
cp .env.example .env   # 填写配置
docker-compose up -d   # 启动 PostgreSQL
npm install
npm run db:migrate     # 初始化数据库
npm run dev            # 启动开发服务器
```

### 测试

```bash
# iOS 单元测试
cd wuyoushuTests && xcodebuild test

# 后端测试
cd backend && npm test
```
