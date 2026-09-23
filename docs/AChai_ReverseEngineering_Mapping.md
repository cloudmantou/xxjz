# AChai 反编译结构映射（代码对齐基线）

更新时间：2026-04-08

## 1. 核心对象映射

| AChai 反编译对象/方法 | 我们当前实现 | 说明 |
|---|---|---|
| `MYAutoBillManager` | `TransactionParserService` + `WechatTransactionParser` + `AlipayTransactionParser` | 主入口负责 OCR 文本解析、候选打分、规则增强。 |
| `AutoBillSearchObject(texts/cells/candidates)` | `AutoBillRuleEngine` + 平台 parser 的 `buildStructuredCells/findAmountCandidates` | `texts` 由规则引擎消费，`cells/candidates` 在平台解析中构建。 |
| `AutoBillSearchText` (`isMutableLine/isFuzzyLastValue/isOptional`) | `AutoBillSearchText` 模型 + `AutoBillRuleEngine.chooseBestCandidate` | 已接入候选重排与可选项顺序匹配。 |
| `AutoBillCandidate` 链式重排 | `AutoBillRuleEngine` 内 `MatchedCandidate` + `sequenceContinuityBonus` | 通过行序约束与连续性分实现候选链路排序。 |
| `CCKeyWordRuleDataController` | `RuleUpdateService` + `KeywordRulesTable` | 支持规则拉取、SQLite 落地、内存缓存同步。 |
| `keywordRules` + `searchTexts` 表 | `KeywordRulesTable` (`keywordRules` + `searchTexts`) | 已使用 SQLite 表驱动，不再仅依赖内存结构。 |
| `extractLastNumberFromString` | `WechatTransactionParser.extractLastMeaningfulNumber` + `AlipayTransactionParser.extractLastMeaningfulNumber` | 金额为 0 / 异常时从尾部反向兜底。 |
| `removeOutliersFromData` | `WechatTransactionParser` / `AlipayTransactionParser` outlier 过滤链路 | 已用于行级与候选级异常剔除。 |

## 2. 规则链路映射

| AChai 逻辑 | 我们当前实现 | 状态 |
|---|---|---|
| 规则驱动候选排序 | `TransactionParserService.rankAndEnhanceCandidates` | 已完成 |
| 规则后写入字段（fund/toBiz/ruleKind） | `AutoBillRuleEngine.applyRules` | 已完成 |
| 高置信分类覆盖 | `matchScore >= 0.80` 强覆盖分类 | 已完成 |
| 动态规则热更新入口 | `RuleUpdateService.fetchLatestRules` + App 激活刷新 | 已完成（配置骨架） |

## 3. 平台能力映射

| AChai 能力 | 我们当前实现 | 状态 |
|---|---|---|
| 微信日期双源容差（30s） | 全文日期 + cells 日期合并 | 已完成 |
| 支付宝 0 金额 fallback | 尾部金额兜底 | 已完成 |
| 多账单返回数组 | 主接口返回 `[ParsedTransaction]` | 已完成 |
| Legacy Intent 多账单不自动入账 | 多候选跳转确认页 | 已完成 |

## 4. 保留差距（后续可继续深入）

- `cells/candidates/removeOutliers` 的更细粒度异常特征仍可继续贴近 AChai（例如列簇稳定性、跨页头噪声策略）。
- 远端规则服务仍是“可配置骨架”模式，待后端地址和密钥到位后再切生产。
- 分类映射注入目前主要来自本地配置，尚未接入真正的后端字典下发。
