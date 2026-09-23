// 默认配置数据
// 对应AChai的ocrRegDict结构

module.exports = {
  // OCR正则配置
  ocrRegDict: {
    // 支付宝出现关键词（aliAppearWords）
    aliAppearWords: [
      "支付宝", "支付宝支付", "花呗", "余额宝", "蚂蚁森林",
      "芝麻信用", "网商银行", "支付宝转账", "支付宝红包"
    ],
    // 微信出现关键词（weAppearWords）
    weAppearWords: [
      "微信支付", "微信转账", "WeChat Pay", "微信红包",
      "微信支付凭证", "微信付款", "微信零钱"
    ],
    // 支付宝收入关键词（aliIncomeWords）
    aliIncomeWords: [
      "收款", "收到", "到账", "转入", "退款", "退回",
      "红包", "奖励", "收益", "利息", "报销", "工资"
    ],
    // 微信收入关键词（weIncomeWords）
    weIncomeWords: [
      "收款", "收到", "转账收款", "退款", "红包",
      "奖励", "报销", "工资", "收入"
    ],
    // 金额正则（按优先级排序）
    amountRegex: [
      "(?:支出|收入|转账)?\\s*[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)",
      "¥\\s*([0-9]+(?:\\.[0-9]{1,2})?)",
      "￥\\s*([0-9]+(?:\\.[0-9]{1,2})?)",
      "([0-9]+\\.[0-9]{2})"
    ],
    // 日期正则（按优先级排序）
    dateRegex: [
      "(\\d{4}[-/]\\d{1,2}[-/]\\d{1,2}\\s+\\d{1,2}[：:]\\d{2}[：:]\\d{2})",
      "(\\d{4}[-/]\\d{1,2}[-/]\\d{1,2}\\s+\\d{1,2}[：:]\\d{2})",
      "(\\d{1,2}[-/]\\d{1,2}\\s+\\d{1,2}[：:]\\d{2})",
      "(今天|昨天|前天)\\s*(\\d{1,2}[：:]\\d{2})"
    ],
    // 分类关键词映射
    categoryKeywords: {
      "餐饮": ["外卖", "餐饮", "美食", "饿了么", "美团", "麦当劳", "肯德基", "星巴克", "瑞幸", "海底捞", "必胜客", "食堂", "早餐", "午餐", "晚餐", "宵夜", "夜宵"],
      "交通出行": ["滴滴", "出行", "加油", "停车", "地铁", "公交", "高铁", "机票", "打车", "出租", "ETC", "高速", "火车", "航空", "铁路"],
      "购物": ["淘宝", "京东", "拼多多", "超市", "商场", "购物", "亚马逊", "天猫", "唯品会", "苏宁", "网易严选", "小米有品"],
      "娱乐休闲": ["电影", "游戏", "KTV", "旅游", "酒店", "美团", "携程", "飞猪", "去哪儿", "同程", "途牛", "景点", "门票"],
      "生活缴费": ["电费", "水费", "燃气", "话费", "宽带", "物业", "房租", "暖气", "有线电视", "垃圾处理"],
      "医疗健康": ["医院", "药店", "体检", "挂号", "门诊", "医保", "牙科", "眼科", "诊所"],
      "教育": ["学费", "培训", "课程", "书籍", "教材", "考试", "学校", "培训班"],
      "转账": ["转账", "转给", "收到转账", "红包"],
      "理财": ["余额宝", "基金", "理财", "保险", "股票", "定期"],
      "信用还款": ["花呗", "信用卡", "还款", "分期", "信用购"],
      "通讯": ["中国移动", "中国联通", "中国电信", "话费充值", "流量"],
      "美容美发": ["美容", "美发", "美甲", "护肤", "洗发", "造型"]
    },
    // 版本号
    version: 1
  },

  // 快捷记账模板
  shortcutTemplates: [
    { id: "breakfast", name: "早餐", icon: " ", categoryId: "餐饮", defaultAmount: 15 },
    { id: "lunch", name: "午餐", icon: " ", categoryId: "餐饮", defaultAmount: 30 },
    { id: "dinner", name: "晚餐", icon: " ", categoryId: "餐饮", defaultAmount: 50 },
    { id: "coffee", name: "咖啡", icon: "☕️", categoryId: "餐饮", defaultAmount: 20 },
    { id: "subway", name: "地铁", icon: " ", categoryId: "交通出行", defaultAmount: 5 },
    { id: "didi", name: "打车", icon: " ", categoryId: "交通出行", defaultAmount: 25 },
    { id: "snack", name: "零食", icon: " ", categoryId: "购物", defaultAmount: 15 },
    { id: "phone_bill", name: "话费", icon: " ", categoryId: "通讯", defaultAmount: 50 }
  ],

  // 分类列表
  categories: [
    { id: "catering", name: "餐饮", icon: " ", type: "expense" },
    { id: "transport", name: "交通出行", icon: " ", type: "expense" },
    { id: "shopping", name: "购物", icon: " ", type: "expense" },
    { id: "entertainment", name: "娱乐休闲", icon: " ", type: "expense" },
    { id: "utilities", name: "生活缴费", icon: " ", type: "expense" },
    { id: "medical", name: "医疗健康", icon: " ", type: "expense" },
    { id: "education", name: "教育", icon: " ", type: "expense" },
    { id: "transfer", name: "转账", icon: " ", type: "expense" },
    { id: "investment", name: "理财", icon: " ", type: "expense" },
    { id: "credit_repayment", name: "信用还款", icon: " ", type: "expense" },
    { id: "telecom", name: "通讯", icon: " ", type: "expense" },
    { id: "beauty", name: "美容美发", icon: " ", type: "expense" },
    { id: "other_expense", name: "其他支出", icon: " ", type: "expense" },
    { id: "salary", name: "工资", icon: " ", type: "income" },
    { id: "bonus", name: "奖金", icon: " ", type: "income" },
    { id: "refund", name: "退款", icon: " ", type: "income" },
    { id: "red_packet", name: "红包", icon: " ", type: "income" },
    { id: "transfer_income", name: "转账收入", icon: " ", type: "income" },
    { id: "investment_income", name: "投资收益", icon: " ", type: "income" },
    { id: "other_income", name: "其他收入", icon: " ", type: "income" }
  ],

  // App 设置（可通过热更新下发）
  appSettings: {
    privacyPolicyURL: "https://xx.cloudmantoua.top/privacy",
    adminPanelURL: "https://xx.cloudmantoua.top/admin",
    profileLinks: [
      {
        id: "douyin-home",
        name: "抖音主页",
        platform: "douyin",
        url: "",
        enabled: false,
        symbolName: "play.rectangle.fill",
        openInExternalBrowser: true
      },
      {
        id: "xiaohongshu-home",
        name: "小红书主页",
        platform: "xiaohongshu",
        url: "",
        enabled: false,
        symbolName: "book.fill",
        openInExternalBrowser: true
      },
      {
        id: "wechat-official-account",
        name: "公众号",
        platform: "wechat",
        url: "",
        enabled: false,
        symbolName: "message.fill",
        openInExternalBrowser: true
      },
      {
        id: "bilibili-home",
        name: "哔哩哔哩主页",
        platform: "bilibili",
        url: "",
        enabled: false,
        symbolName: "tv.fill",
        openInExternalBrowser: true
      }
    ]
  },

  // 功能开关
  featureFlags: {
    enableOCR: true,
    enableWeChatParser: true,
    enableAlipayParser: true,
    enableFuzzyMatch: true,
    enableLCSAlignment: true,
    enableSpatialAnalysis: true,
    enableHotUpdate: true
  }
};
