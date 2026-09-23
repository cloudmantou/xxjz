# AChai vs 我们的App — OCR横向对比分析

## 2026-04-08 对齐进度（本轮落地）

| 项目 | 当前状态 | 说明 |
|------|----------|------|
| 多账单主链路 | ✅ 已完成 | `TransactionParserService` 主接口已改为 `[ParsedTransaction]`，并统一候选去重+排序。 |
| 规则前移排序 | ✅ 已完成 | 候选排序阶段已引入规则匹配分；不再“先选一笔再套规则”。 |
| 分类高分强覆盖 | ✅ 已完成 | 规则分 `>= 0.80` 且可映射分类时，强覆盖 parser 分类。 |
| memberCateId 映射 | ✅ 已完成 | `AutoBillRuleEngine` 支持“可注入映射 + 本地默认映射”。 |
| 动态规则骨架 | ✅ 已完成 | `RuleUpdateService` 已支持可配置 `baseURL/aesKey/aesIV`，占位配置自动降级本地，不发无效请求。 |
| 启动安全刷新 | ✅ 已完成 | App 激活时触发规则刷新，服务层自带节流。 |
| 微信 30 秒日期容差 | ✅ 已完成 | 已接入“全文日期 + cells日期”双源校验与容差合并。 |
| 支付宝 0 金额 fallback | ✅ 已完成 | 已补齐 `extractLastMeaningfulNumber` 级别兜底。 |
| 快捷指令多笔确认 | ✅ 已完成 | 多笔候选通过 `ShortcutStorage` 传入 `QuickRecord`，不再直接自动入账。 |
| Legacy Intent 多笔策略 | ✅ 已完成 | 单笔继续自动入账；多笔改为进入候选确认页。 |

## 一、整体架构对比

| 维度 | AChai (阿柴记账) | 我们的App | 差距 |
|------|------------------|-----------|------|
| **OCR引擎** | VNRecognizeTextRequest (iOS Vision) | 同左 | ✅ 持平 |
| **空间分析** | MYTextObservation 2D网格 + 8方向邻居图 | SpatialOCRAnalyzer 9-zone分区 + 8方向图 | 🔶 架构相似，细节有差距 |
| **规则系统** | MYAutoBillRuleHelper 三层规则 (auto/common/local) | RuleEngine 三层规则 + SQLite searchTexts 表驱动 | 🔶 仍有细节差距 |
| **平台专用解析器** | `wechatBillsWithSortedLines:` + `alipayBillsWithSortedLines:` | `WechatTransactionParser` + `AlipayTransactionParser` | 🔶 已实现，功能有差距 |
| **多账单支持** | 一次截图返回 `AutoBillModel[]` | 主链路返回 `[ParsedTransaction]` | ✅ 已对齐 |
| **类别映射** | SQLite `keywordRules` 表 | 可注入映射 + 本地兜底映射 | 🔶 已基本对齐 |
| **金额优先级** | 3层规则 + 空间对齐评分 | 平台上下文 + 规则分 + 结构化奖励 | ✅ 已对齐 |

---

## 二、支付宝解析差距

### 2.1 AChai的 `alipayBillsWithSortedLines` 算法（反向工程结果）

```
Phase 1: 日期提取
  - 遍历 searchObject.candidates (candidateType==2 && matchType==4)
  - 通过 keyObservation.firstCandidateString 获取文本
  - 用正则提取日期组件

Phase 2: 单元格匹配
  - 遍历 searchObject.cells (结构化键值对)
  - 按 type/match 过滤

Phase 3: 构建 AutoBillModel
  - 用正则提取4个子字符串 (rangeAtIndex 0-3)
  - 长度验证: alipay >= 4, wechat >= 5
  - 日期容差: 30秒内相同 → 匹配成功
  - 空间验证: isAlignLeft/Right

Phase 4: 后处理
  - 如果 money==0 或 toBiz 匹配金额格式 → extractLastNumberFromString
  - removeOutliersFromData: Y坐标距离去异常
  - 按Y位置排序结果
```

### 2.2 我们的差距

| 差距项 | AChai实现 | 我们的实现 | 影响 |
|--------|-----------|-----------|------|
| **alipayCellStatus检测** | 基于 `alipayCellStatus` 方法，有完整的状态机 | `detectAlipayCellStatus()` 简化版 | 🔶 高 - 影响收入/支出/转账判断 |
| **结构化Cells匹配** | candidateType + matchType 多层过滤 | 基于 label 关键词匹配 | 🔶 高 - 影响金额/商户/备注精度 |
| **30秒日期容差** | `datesMatchWithTolerance: 30` | ❌ 无 | ❌ 中 - 影响多字段日期一致性验证 |
| **extractLastNumberFromString** | money==0时的fallback，从文本末尾提取最后一个有效数字 | ❌ 无（仅在WechatParser有部分实现） | 🔶 高 - 影响0金额误识别 |
| **fundName (资金账户)** | 提取"余额"/"花呗"/"信用卡"等 | ❌ 无 | ❌ 中 - 缺少资金来源字段 |
| **originalMoney/discountMoney** | 分离原价和优惠金额 | ❌ 无 | 🔶 中 - 影响优惠场景 |
| **Y排序 + 去异常** | `removeOutliersFromData` + 按Y排序 | 有 `removeOutliers()` 但未在AlipayParser中使用 | 🔶 中 |
| **多账单返回** | `AutoBillModel[]` 数组 | `[ParsedTransaction]` 但只返回第一个 | ❌ 高 |
| **Cell状态验证** | `alipayCellStatus` 关联 cells 结构验证 | ❌ 无 | 🔶 中 |

### 2.3 支付宝具体功能差距

```swift
// AChai的AutoBillModel完整字段:
struct AutoBillModel {
    money: NSDecimalNumber           ✅ 我们有
    date: NSDate                     ✅ 我们有
    cate: NSString                   ✅ 我们有
    desc: NSString                   ✅ 我们有 (merchantName)
    remark: NSString                 ✅ 我们有
    fundName: NSString               ❌ 无 (余额/花呗/信用卡)
    toBiz: NSString                  ✅ 我们有 (counterparty)
    billType: NSUInteger             ✅ 我们有 (isIncome)
    billSource: NSUInteger           ✅ 我们有
    originalMoney: NSDecimalNumber   ❌ 无
    discountMoney: NSDecimalNumber   ❌ 无
    status: NSUInteger               ❌ 无
    ruleKind: NSUInteger             ❌ 无
}
```

---

## 三、微信解析差距

### 3.1 AChai的 `wechatBillsWithSortedLines` 算法（反向工程结果）

```
1. cleanText = recognizedStringCleaning(searchObject)
2. regex = NSRegularExpression(pattern: 7-group-date-pattern)
3. match = regex.firstMatch(cleanText)
4. if match.numberOfRanges != 7 → return nil
5. 提取7个日期组件，验证范围 (year 2000-2099, month 1-12, day 1-实际天数)
6. 无效日期 → fallback到当天
7. 返回 NSCalendar.dateFromComponents(components)
```

### 3.2 我们的差距

| 差距项 | AChai实现 | 我们的实现 | 影响 |
|--------|-----------|-----------|------|
| **日期正则** | 7组日期正则，精确验证7个分量 | `datePattern` 相同，但验证逻辑相似 | ✅ 基本持平 |
| **Day范围验证** | `calendar.range(of: .day, in: .month)` 获取实际天数 | 我们也做了此验证 | ✅ 持平 |
| **无效日期fallback** | fallback到当前日期 | `?? Date()` 相同 | ✅ 持平 |
| **30秒日期容差** | 比较两个日期是否在30秒内 | ❌ 无 | 🔶 中 |
| **多账单** | 返回 `AutoBillModel[]` | 只返回第一个 | ❌ 高 |
| **空间对齐验证** | isAlignLeft/isAlignRight 用于验证金额-商户关系 | `calculateAlignmentScore()` 有部分实现 | 🔶 中 |
| **extractLastNumberFromString** | money==0时的fallback | ❌ 无 | 🔶 高 |
| **Cell结构化匹配** | candidateType==2 && matchType==4 | 基于label匹配 | 🔶 高 |

### 3.3 微信具体功能差距

```swift
// 微信特有差距:

1. 多账单提取:
   AChai: 能从微信聊天记录截图提取多个交易
   我们: 只能提取1个

2. 空间对齐分数:
   AChai: calculateAlignmentScore 在上下3行内检查同对齐元素
   我们: 有实现但未被TransactionParserService调用

3. toBiz (交易对象):
   AChai: 从左对齐观察结果提取toBiz
   我们: 从merchantLabels提取，可能不一致
```

---

## 四、通用OCR能力差距

### 4.1 规则系统 (最大差距)

```swift
// AChai的MYAutoBillRuleHelper
class MYAutoBillRuleHelper {
    // 三层规则:
    autoBillRules: [AutoBillSearchObject]  // 自动记账规则
    commomRules: [AutoBillSearchObject]    // 通用规则
    localRules: [AutoBillSearchObject]     // 本地规则

    // AutoBillSearchObject 结构:
    ruleId: String
    ruleKind: NSUInteger
    billSource: NSUInteger  // WeChat/Alipay/Generic
    minMatchValue: Double
    texts: [AutoBillSearchText]  // 搜索文本数组
}

// AutoBillSearchText 结构:
key: String
candidateType: Int       // 1=key观察, 2=text观察
matchType: Int           // 1=精确, 2=包含, 3=前缀, 4=正则
isFuzzy: Bool
isOptional: Bool
columnCount: Int
```

**我们的差距**: 完全缺少规则系统，所有匹配都是硬编码的正则表达式。

### 4.2 关键词-类别映射

```sql
-- AChai的SQLite映射表
CREATE TABLE keywordRules (
    keyWord TEXT,
    memberCateId INTEGER,
    ...
);

-- 查询示例: 关键词 → 类别ID
SELECT memberCateId FROM keywordRules WHERE keyWord LIKE '%餐饮%'
```

**我们的差距**: 使用硬编码 `categoryKeywords` 字典，无法动态更新。

### 4.3 空间9方向邻居图

```swift
// AChai的MYTextObservation 9-zone grid:
//           topLeft    topCenter    topRight
//          middleLeft  middleCenter middleRight
//          bottomLeft bottomCenter  bottomRight

// 8个方向导航:
rightTextObservation
topLeftAlignedTextObservation
topCenterAlignedTextObservation
bottomLeftAlignedTextObservation
// ... 等等

// 我们的实现:
SpatialGraph.Direction: left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight, center
```

**差距**: 架构类似，但AChai的实现经过更多边界case处理。

---

## 五、金额提取优先级对比

### AChai的优先级（基于代码分析）:

```
1. settlement labels (实付/应付/支付金额/交易金额) - 最高分
2. header signed amount (如 "-5.94" 在账单详情页顶部) - 高分
3. net amount by discount (订单金额 - 抵扣/优惠) - 中分
4. generic amount (2位小数金额) - 低分
5. extractLastNumberFromString (0金额fallback) - 最低
```

### 我们的优先级（TransactionParserService）:

```
1. settlementKeywordScores (实付:260, 应付:250, ...)
2. headerSettlementAmount (账单详情页signed amount)
3. netAmountByDiscount (订单金额 - 优惠)
4. generic amount patterns (currency/trailing/signed/2decimal)
5. fallbackNumberPattern - 最低
```

**结论**: 优先级逻辑基本一致 ✅

---

## 六、文本清理对比

### AChai的 `recognizedStringCleaning`:

```swift
// 我们的实现:
func cleanRecognizedText(_ text: String) -> String {
    // 清除零宽字符:
    \u{200B} zero-width space
    \u{FEFF} BOM
    \u{200C} zero-width non-joiner
    \u{200D} zero-width joiner
    \u{00AD} soft hyphen
    // 规范化换行
    // 清除控制字符
}
```

**结论**: 实现基本一致 ✅

---

## 七、优先级改进建议

### 高优先级（影响准确率）:

1. **Rule系统** - 3层规则 + SQLite keywordRules表
   - 影响: 类别匹配准确率、平台适应性
   - 工作量: 中

2. **Multi-bill支持** - 返回数组而非单一结果
   - 影响: 微信聊天记录等多账单场景
   - 工作量: 中

3. **extractLastNumberFromString** - 0金额fallback
   - 影响: 微信/支付宝特定页面
   - 工作量: 小

4. **alipayCellStatus完整实现**
   - 影响: 支付宝收入/支出/转账判断
   - 工作量: 小

### 中优先级:

5. **fundName (资金账户)** - 余额/花呗/信用卡提取
   - 影响: 资金来源区分
   - 工作量: 小

6. **originalMoney/discountMoney** - 原价和优惠分离
   - 影响: 优惠场景金额准确性
   - 工作量: 小

7. **30秒日期容差验证**
   - 影响: 多字段日期一致性
   - 工作量: 小

8. **Y排序 + 去异常后处理**
   - 影响: 多元素时的最终排序
   - 工作量: 小

### 低优先级（锦上添花）:

9. **8方向空间导航精细化** - 匹配AChai边界case
10. **Cell结构化匹配增强** - candidateType/matchType多层过滤

---

## 八、总结

### 已追平的功能:
- ✅ OCR引擎 (VNRecognizeTextRequest)
- ✅ 空间分析架构 (9-zone + 8-direction graph)
- ✅ 平台专用解析器 (WeChat + Alipay)
- ✅ 金额提取优先级逻辑
- ✅ 日期解析 (含相对日期: 今天/昨天/前天)
- ✅ 文本清理 (零宽字符、规范化)
- ✅ 行分组算法

### 核心差距:
1. **规则系统** - AChai的MYAutoBillRuleHelper是核心竞争力，我们无法通过简单改进追平
2. **Multi-bill** - 多账单场景完全不支持
3. **fundName/originalMoney/discountMoney** - 字段不完整

### 评估:
我们的实现已达到AChai约 **70-80%** 的功能覆盖度，核心金额/日期/商户提取已经可用，但在复杂场景（多账单、规则匹配、资金账户）上有明显差距。
