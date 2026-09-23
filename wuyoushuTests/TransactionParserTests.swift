import XCTest
import CoreGraphics
@testable import AssetLife

final class TransactionParserTests: XCTestCase {

    var parser: MockTransactionParserService!

    override func setUp() {
        super.setUp()
        parser = MockTransactionParserService()
    }

    // MARK: - Amount Extraction

    func test_parseAmount_yuanSuffix() {
        let result = parseFirst("午餐35元")
        XCTAssertEqual(result?.amount, 35)
    }

    func test_parseAmount_currencyPrefix() {
        let result = parseFirst("¥35.5")
        XCTAssertEqual(result?.amount, 35.5)
    }

    func test_parseAmount_negativeCurrencyPrefix() {
        let result = parseFirst("-¥7.96")
        XCTAssertEqual(result?.amount, 7.96)
    }

    func test_parseAmount_keywordWithNegativeCurrency() {
        let result = parseFirst("今日结余 -¥7.96")
        XCTAssertEqual(result?.amount, 7.96)
    }

    func test_parseAmount_commaDecimal() {
        let result = parseFirst("订单金额 ¥7,96")
        XCTAssertEqual(result?.amount, 7.96)
    }

    func test_parseAmount_kuaiSuffix() {
        let result = parseFirst("打车28块")
        XCTAssertEqual(result?.amount, 28)
    }

    func test_parseAmount_bareNumber() {
        let result = parseFirst("午餐35")
        XCTAssertEqual(result?.amount, 35)
    }

    func test_parseAmount_largeNumber() {
        let result = parseFirst("工资10000元")
        XCTAssertEqual(result?.amount, 10000)
    }

    func test_parseAmount_orderDiscountNetAmount() {
        let text = """
        账单详情
        -5.94
        交易成功
        订单金额 6.00
        网商银行福利 -0.06
        金抵扣
        """
        let result = parseFirst(text)
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseAmount_orderDiscountDeriveNetWithoutHeader() {
        let text = """
        交易成功
        订单金额 6.00
        网商银行福利 -0.06
        金抵扣
        """
        let result = parseFirst(text)
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseText_merchantAutoCategoryAndNote() {
        let text = """
        账单详情
        张记生煎小笼包
        -5.94
        交易成功
        订单金额 6.00
        网商银行福利 -0.06
        金抵扣
        商品说明 经营码交易
        """
        let result = parseFirst(text)
        XCTAssertEqual(result?.categoryKey, "dining")
        XCTAssertEqual(result?.merchantName, "张记生煎小笼包")
        XCTAssertEqual(result?.note, "张记生煎小笼包")
    }

    func test_parseText_timeNoise_shouldStillPreferMerchantAsNote() {
        let text = """
        07:381：！
        账单详情
        张记生煎小笼包
        -5.94
        交易成功
        管理极速付款 极速付款
        订单金额 6.00
        网商银行福利-0.06
        金抵扣
        支付时间 2026-04-07 07:12:55
        付款方式 网商银行储蓄卡（8849）
        商品说明 经营码交易
        收款方全称*武（个人）
        """
        let result = parseFirst(text)
        XCTAssertEqual(result?.merchantName, "张记生煎小笼包")
        XCTAssertEqual(result?.note, "张记生煎小笼包")
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
    }

    func test_parseText_wechatBillDetail_statusBarNoise_shouldNotSplitIntoMultipleBills() {
        let text = """
        18:18 S
        星星充电微信支付分充电
        -10.32
        当前状态 支付成功
        支付时间 2026年4月4日 20:43:35
        商品 星星充电微信支付分充电
        商户全称 万帮星星充电科技有限公司
        收单机构 银联商务支付股份有限公司
        支付方式 招商银行储蓄卡(1302）
        交易单号 4200057901202604046939201615
        """

        let candidates = parser.parse(text)
        XCTAssertEqual(candidates.count, 1, "Expected one bill candidate after noise dedup")

        guard let first = candidates.first else {
            XCTFail("Expected first candidate")
            return
        }
        XCTAssertEqual(first.amount ?? 0, 10.32, accuracy: 0.0001)
        XCTAssertEqual(first.merchantName, "星星充电微信支付分充电")
    }

    func test_parseText_alipayShortcutText_prefersSettlementAmount() {
        let text = """
        支付宝
        账单详情
        支出¥49.95
        交易成功
        订单金额 50.00
        优惠金额 0.05
        今日支出 ¥339.08
        收款方 中国联通
        付款方式 花呗
        """

        let result = parseFirst(text)
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 49.95, accuracy: 0.0001)
        XCTAssertEqual(result?.billSource, .alipay)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseText_alipayTopNavNoise_shouldNotOverrideMerchantOrNote() {
        let text = """
        搜索
        支付宝
        支付成功
        ¥6.72
        长兴县商户_吴尧姣
        回首页
        交易单号 123456789
        """

        let result = parseFirst(text)
        XCTAssertEqual(result?.merchantName, "长兴县商户_吴尧姣")
        XCTAssertNotEqual(result?.note, "回首页")
        XCTAssertNotEqual(result?.note, "支 回首页")
        XCTAssertNotNil(result?.amount)
        XCTAssertEqual(result?.amount ?? 0, 6.72, accuracy: 0.0001)
    }

    func test_parseOCR_alipayPreferSettlementOverOrderAndSummary() {
        let result = parseFirst(
            makeOCRResult([
                "支付宝",
                "账单详情",
                "支出¥49.95",
                "交易成功",
                "订单金额 50.00",
                "优惠金额 0.05",
                "今日支出 ¥339.08",
                "收款方 中国联通",
                "付款方式 花呗"
            ])
        )

        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 49.95, accuracy: 0.0001)
        XCTAssertEqual(result?.billSource, .alipay)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseOCR_alipayTopNavNoise_shouldNotOverrideMerchantOrNote() {
        let result = parseFirst(
            makeOCRResult([
                "搜索",
                "支付宝",
                "支付成功",
                "¥6.72",
                "长兴县商户_吴尧姣",
                "回首页",
                "交易单号 123456789"
            ])
        )

        XCTAssertEqual(result?.merchantName, "长兴县商户_吴尧姣")
        XCTAssertNotEqual(result?.note, "回首页")
        XCTAssertNotEqual(result?.note, "支 回首页")
        XCTAssertNotNil(result?.amount)
        XCTAssertEqual(result?.amount ?? 0, 6.72, accuracy: 0.0001)
    }

    func test_parseText_alipayEnergyHint_shouldPreferMerchant() {
        let text = """
        搜索
        支付宝
        支付成功
        ¥6.72
        获得森林能量
        长兴县商户_吴尧姣
        碰友日立减 -¥0.28
        交易方式 余额宝(转出资金付款)
        完成
        """

        let result = parseFirst(text)
        XCTAssertEqual(result?.merchantName, "长兴县商户_吴尧姣")
        XCTAssertFalse(result?.note?.contains("森林能量") == true)
        XCTAssertFalse(result?.note?.contains("碰友日") == true)
        XCTAssertNotNil(result?.amount)
        XCTAssertEqual(result?.amount ?? 0, 6.72, accuracy: 0.0001)
    }

    func test_parseOCR_alipayEnergyHint_shouldPreferMerchant() {
        let result = parseFirst(
            makeOCRResult([
                "搜索",
                "支付宝",
                "支付成功",
                "¥6.72",
                "获得森林能量",
                "长兴县商户_吴尧姣",
                "碰友日立减 -¥0.28",
                "交易方式 余额宝(转出资金付款)",
                "完成"
            ])
        )

        XCTAssertEqual(result?.merchantName, "长兴县商户_吴尧姣")
        XCTAssertFalse(result?.note?.contains("森林能量") == true)
        XCTAssertFalse(result?.note?.contains("碰友日") == true)
        XCTAssertNotNil(result?.amount)
        XCTAssertEqual(result?.amount ?? 0, 6.72, accuracy: 0.0001)
    }

    func test_parseAmount_discountKeywordAmountShouldNotWin() {
        // Bug: "优惠金额 ¥0.06" contained "金额" keyword (score 100) which beat "¥5.94" (score 80)
        let text = """
        优惠金额 ¥0.06
        ¥5.94
        """
        let result = parseFirst(text)
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
    }

    func test_parseOCR_discountLineShouldNotBeAmount() {
        // Simulates a payment screenshot with discount info — must pick payment, not discount
        let result = parseFirst(
            makeOCRResult([
                "张记生煎小笼包",
                "¥5.94",
                "优惠金额 ¥0.06",
                "支付时间 2026-04-07 08:20"
            ])
        )
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount from OCR")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertEqual(result?.merchantName, "张记生煎小笼包")
    }

    func test_parseAmount_noNumber_returnsNil() {
        let result = parseFirst("午餐")
        XCTAssertNil(result?.amount)
    }

    func test_parseAmount_emptyString_returnsNil() {
        let candidates = parser.parse("")
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_parse_returnsArraySemantics_singleAndBestFirst() {
        let candidates = parser.parse("午餐35元")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.amount, 35)
        XCTAssertEqual(parser.bestCandidate(from: candidates)?.amount, 35)
    }

    func test_parse_multiCandidates_keepBestAtFirst() {
        let text = """
        微信支付
        交易时间 2026-04-07 20:18:30
        收款方 喜茶
        支付金额 -18.50
        合计 -18.50
        今日支出 ¥339.08
        """
        let candidates = parser.parse(text)
        XCTAssertFalse(candidates.isEmpty)
        let firstAmount = candidates.first?.amount
        XCTAssertNotNil(firstAmount)
        XCTAssertEqual(firstAmount ?? 0, 18.50, accuracy: 0.0001)
    }

    // MARK: - Category Detection

    func test_category_dining() {
        let result = parseFirst("午餐35元")
        XCTAssertEqual(result?.categoryKey, "dining")
    }

    func test_category_dining_keywords() {
        let keywords = ["早餐", "晚餐", "外卖", "奶茶", "咖啡", "吃"]
        for keyword in keywords {
            let result = parseFirst("\(keyword) 30元")
            XCTAssertEqual(result?.categoryKey, "dining", "Expected dining for keyword: \(keyword)")
        }
    }

    func test_category_transport() {
        let result = parseFirst("打车28元")
        XCTAssertEqual(result?.categoryKey, "transport")
    }

    func test_category_shopping() {
        let result = parseFirst("买了双鞋299")
        XCTAssertEqual(result?.categoryKey, "shopping")
    }

    func test_category_entertainment() {
        let result = parseFirst("看电影50")
        XCTAssertEqual(result?.categoryKey, "entertainment")
    }

    func test_category_housing() {
        let result = parseFirst("房租3000元")
        XCTAssertEqual(result?.categoryKey, "housing")
    }

    func test_category_medical() {
        let result = parseFirst("买药50元")
        XCTAssertEqual(result?.categoryKey, "medical")
    }

    func test_category_education() {
        let result = parseFirst("上课培训200")
        XCTAssertEqual(result?.categoryKey, "education")
    }

    func test_category_social() {
        let result = parseFirst("朋友结婚份子钱500")
        XCTAssertEqual(result?.categoryKey, "social")
    }

    func test_category_unknown_returnsNil() {
        let result = parseFirst("xyz 30")
        XCTAssertNil(result?.categoryKey)
    }

    // MARK: - Income Detection

    func test_income_salary() {
        let result = parseFirst("工资10000元")
        XCTAssertTrue(result?.isIncome == true)
    }

    func test_income_refund() {
        let result = parseFirst("退款50元")
        XCTAssertTrue(result?.isIncome == true)
    }

    func test_income_positiveSignedAmount() {
        let result = parseFirst("+¥88.00")
        XCTAssertTrue(result?.isIncome == true)
    }

    func test_income_bonus() {
        let result = parseFirst("奖金5000")
        XCTAssertTrue(result?.isIncome == true)
    }

    func test_expense_default() {
        let result = parseFirst("午餐35元")
        XCTAssertFalse(result?.isIncome == true)
    }

    // MARK: - Full Parse

    func test_fullParse_expense() {
        let result = parseFirst("午餐35元")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.amount, 35)
        XCTAssertEqual(result?.categoryKey, "dining")
        XCTAssertEqual(result?.note, "午餐35元")
        XCTAssertFalse(result!.isIncome)
    }

    func test_fullParse_income() {
        let result = parseFirst("收到工资10000元")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.amount, 10000)
        XCTAssertTrue(result!.isIncome)
        XCTAssertEqual(result?.note, "收到工资10000元")
    }

    // MARK: - OCR Parse

    func test_parseOCR_sourceMappingToCategory() {
        let result = parseFirst(
            makeOCRResult([
                "滴滴出行",
                "支付金额 -¥28.50",
                "交易时间 2026-04-06 17:20"
            ])
        )

        XCTAssertEqual(result?.billSource, .didi)
        XCTAssertEqual(result?.categoryKey, "transport")
        XCTAssertEqual(result?.amount, 28.5)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseOCR_remarkLabelPrefersNote() {
        let result = parseFirst(
            makeOCRResult([
                "支付宝",
                "收款方 喜茶",
                "实付 ¥19.00",
                "备注 午后加冰"
            ])
        )

        XCTAssertEqual(result?.merchantName, "喜茶")
        XCTAssertEqual(result?.note, "午后加冰")
    }

    func test_parseOCR_orderDiscountNetAmount() {
        let result = parseFirst(
            makeOCRResult([
                "账单详情",
                "-5.94",
                "交易成功",
                "订单金额 6.00",
                "网商银行福利 -0.06",
                "金抵扣"
            ])
        )

        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount from OCR")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseOCR_orderDiscountDeriveNetWithoutHeader() {
        let result = parseFirst(
            makeOCRResult([
                "交易成功",
                "订单金额 6.00",
                "网商银行福利 -0.06",
                "金抵扣"
            ])
        )

        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount from OCR")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseOCR_wechatPreferSettlementOverOrderAndSummary() {
        let result = parseFirst(
            makeOCRResult([
                "微信支付",
                "交易成功",
                "收款方 星巴克",
                "实付金额 -7.00",
                "订单金额 8.00",
                "优惠金额 -1.00",
                "今日支出 ¥339.08"
            ])
        )

        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount from OCR")
            return
        }
        XCTAssertEqual(amount, 7.00, accuracy: 0.0001)
        XCTAssertEqual(result?.billSource, .wechatPay)
    }

    func test_parseOCR_merchantAutoCategoryAndNote() {
        let result = parseFirst(
            makeOCRResult([
                "账单详情",
                "张记生煎小笼包",
                "-5.94",
                "交易成功",
                "订单金额 6.00",
                "网商银行福利 -0.06",
                "金抵扣",
                "商品说明 经营码交易"
            ])
        )

        XCTAssertEqual(result?.categoryKey, "dining")
        XCTAssertEqual(result?.merchantName, "张记生煎小笼包")
        XCTAssertEqual(result?.note, "张记生煎小笼包")
    }

    func test_parseOCR_timeNoise_shouldStillPreferMerchantAsNote() {
        let result = parseFirst(
            makeOCRResult([
                "07:381：！",
                "账单详情",
                "张记生煎小笼包",
                "-5.94",
                "交易成功",
                "管理极速付款 极速付款",
                "订单金额 6.00",
                "网商银行福利-0.06",
                "金抵扣",
                "支付时间 2026-04-07 07:12:55",
                "付款方式 网商银行储蓄卡（8849）",
                "商品说明 经营码交易",
                "收款方全称*武（个人）"
            ])
        )

        XCTAssertEqual(result?.merchantName, "张记生煎小笼包")
        XCTAssertEqual(result?.note, "张记生煎小笼包")
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount from OCR")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
    }

    // MARK: - Multi-transaction Alipay Notification

    func test_parseText_multiTransactionNotification_shouldPickFirstAmount() {
        // Simulates Alipay notification with multiple transactions + monthly summary
        let text = """
        张记生煎小笼包
        ¥5.94
        网商银行福利金抵扣 0.06
        盛马自动售货机
        ¥1.99
        4月统计支出 ¥221.13
        支付奖励+2积分
        """
        let result = parseFirst(text)
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseOCR_multiTransactionNotification_shouldPickFirstAmountAndMerchant() {
        let result = parseFirst(
            makeOCRResult([
                "张记生煎小笼包",
                "¥5.94",
                "网商银行福利金抵扣 0.06",
                "盛马自动售货机",
                "¥1.99",
                "4月统计支出 ¥221.13",
                "支付奖励+2积分"
            ])
        )
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount from OCR")
            return
        }
        XCTAssertEqual(amount, 5.94, accuracy: 0.0001)
        XCTAssertEqual(result?.merchantName, "张记生煎小笼包")
        XCTAssertFalse(result?.isIncome == true)
    }

    func test_parseText_monthlySummaryExcluded() {
        // Ensure monthly summary amount is never picked
        let text = """
        4月统计支出 ¥221.13
        """
        let result = parseFirst(text)
        XCTAssertNil(result?.amount)
    }

    func test_parseText_wechatShortcutText_usesPlatformParser() {
        let text = """
        微信支付
        交易时间 2026-04-07 20:18:30
        收款方 喜茶
        支付金额 -18.50
        """

        let result = parseFirst(text)
        XCTAssertEqual(result?.billSource, .wechatPay)
        guard let amount = result?.amount else {
            XCTFail("Expected parsed amount")
            return
        }
        XCTAssertEqual(amount, 18.50, accuracy: 0.0001)
        XCTAssertEqual(result?.merchantName, "喜茶")
        XCTAssertFalse(result?.isIncome == true)
    }

    // MARK: - WeChat Parser Tests

    func test_wechatParser_basic() {
        let text = """
        微信支付
        交易时间 2025-03-15 14:30:25
        收款方 张记生煎小笼包
        支付金额 -15.80
        备注 午餐
        """

        let transactions = WechatTransactionParser.parse(text: text)
        XCTAssertEqual(transactions.count, 1)
        guard let transaction = transactions.first else { return }

        XCTAssertEqual(transaction.amount, 15.80)
        XCTAssertEqual(transaction.billSource, .wechatPay)
        XCTAssertEqual(transaction.merchantName, "张记生煎小笼包")
        XCTAssertEqual(transaction.note, "午餐")
        XCTAssertFalse(transaction.isIncome)
    }

    func test_wechatParser_multipleAmounts() {
        let text = """
        微信支付
        交易时间 2025-03-15 14:30:25
        商品A -10.00
        商品B -5.80
        合计 -15.80
        """

        let transactions = WechatTransactionParser.parse(text: text)
        XCTAssertEqual(transactions.count, 3) // 应该检测到3个金额
        let total = transactions.reduce(0) { $0 + ($1.amount ?? 0) }
        XCTAssertEqual(total, 31.60, accuracy: 0.0001) // 10 + 5.8 + 15.8
    }

    func test_wechatParser_income() {
        let text = """
        微信转账
        交易时间 2025-03-15 14:30:25
        收款金额 +100.00
        付款方 张三
        """

        let transactions = WechatTransactionParser.parse(text: text)
        XCTAssertEqual(transactions.count, 1)
        guard let transaction = transactions.first else { return }

        XCTAssertEqual(transaction.amount, 100.00)
        XCTAssertTrue(transaction.isIncome)
        XCTAssertEqual(transaction.billSource, .wechatPay)
    }

    func test_wechatParser_dateTolerance_prefersCellDateWhenWithin30Seconds() {
        let text = """
        微信支付
        订单创建 2026-04-07 12:00:10
        支付时间 2026-04-07 12:00:35
        收款方 喜茶
        支付金额 -7.00
        """

        let transactions = WechatTransactionParser.parse(text: text)
        guard let transaction = transactions.first, let date = transaction.date else {
            XCTFail("Expected parsed transaction with date")
            return
        }

        let second = Calendar.current.component(.second, from: date)
        XCTAssertEqual(second, 35)
    }

    func test_alipayParser_zeroAmountFallbackToLastMeaningfulNumber() {
        let text = """
        支付宝
        支出¥0.00(实际49.95)
        交易成功
        收款方 喜茶
        """

        let transactions = AlipayTransactionParser.parse(text: text)
        guard let first = transactions.first, let amount = first.amount else {
            XCTFail("Expected parsed amount")
            return
        }

        XCTAssertEqual(amount, 49.95, accuracy: 0.0001)
    }

    private func parseFirst(_ text: String) -> ParsedTransaction? {
        parser.bestCandidate(from: parser.parse(text))
    }

    private func parseFirst(_ ocrResult: OCRResult) -> ParsedTransaction? {
        parser.bestCandidate(from: parser.parse(ocrResult))
    }

    private func makeOCRResult(_ lines: [String]) -> OCRResult {
        let lineItems: [OCRTextLine] = lines.enumerated().map { index, text in
            let obs = OCRTextObservation(text: text, confidence: 0.95, boundingBox: .zero)
            return OCRTextLine(text: text, observations: [obs], yMidpoint: CGFloat(index))
        }
        return OCRResult(fullText: lines.joined(separator: "\n"), observations: lineItems.flatMap { $0.observations }, lines: lineItems)
    }
}
