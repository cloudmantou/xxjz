# 解析基线修复与截图快速记账

## 问题与规则

原 main `5c285f7` 的完整测试为 141 passed / 10 failed / 1 skipped。10 个失败均来自 TransactionParserTests；本次保留原断言，修复实现，没有新增 skip。

| 失败场景 | 修复行为 |
| --- | --- |
| “午餐35元”“收到工资10000元”的备注为空 | 有明确备注时优先使用；否则保留可信商户或有意义的原始短句 |
| 支付宝商户 `长兴县商户_吴尧姣` 被截成 `_吴尧姣` | 标签只从字段开头匹配，并优先匹配较长标签，避免把商户名称中间的“商户”当标签 |
| “金抵扣”等优惠文本成为备注 | 过滤优惠文案；无显式备注时优先回退到可信商户 |
| 微信详情页被拆成两笔同额交易 | 商户名包含“微信支付”仍可有效；只把独立的平台标题过滤掉，使平台与通用候选按原有商户/金额/日期规则去重 |
| 没有坐标的支付宝 OCR 丢失商户 | 直接按文本行解析，避免伪坐标经过重聚类把多行串成一行 |

截图链路继续使用本机 Vision → 平台/通用解析器 → 候选 payload → 可编辑快速记账表单。此次补充：

- 向 Vision 传递 UIImage 的旋转/镜像方向，识别坐标与文字同步纠正。
- 兼容 Vision 将 `2026-04-04 12:30:00` 输出为 `2026-04-0412:30:00` 的情况。
- 自动/通用规则只补全缺失资金账户；已从截图识别出的“余额”等账户不再被平台默认账户覆盖。用户本地规则仍可主动覆盖。
- 快速记账表单和批量保存共用 `suggestedNote`，优先保留解析出的显式备注，再回退到商户。
- 保留现有用户确认及编辑流程。

## 开源实现与文档调研

调研日期：2026-11-09。查看仓库维护时间、许可证、README 及公开问题；仅借鉴设计，没有引入或复制第三方代码。

| 项目 | 维护与许可 | 实现思路、依赖与限制 | 本项目选择 |
| --- | --- | --- | --- |
| [Cosmichomeless/RECEIPT-SCANNER](https://github.com/Cosmichomeless/RECEIPT-SCANNER) | MIT，最近推送 2026-10-14，未归档 | Vision/VisionKit 本地识别，识别、字段解析、人工复核分开；SwiftData 存储。项目仍为 MVP，设备发布验证及图片/PDF 导入仍有待办，不能视为成熟准确率标杆 | 采用分层处理和可编辑复核思路；保留现有 Core Data 与导入入口 |
| [PaddlePaddle/PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | Apache-2.0，最近推送 2026-09-16，未归档 | OCR、版面分析及信息提取能力丰富，但涉及 Python/Paddle/模型资源；公开问题包含版本兼容、MKLDNN 执行等环境相关失败 | 当前 iOS 本地优先链路继续使用原生 Vision，避免为本轮字段修复引入额外推理栈；未来复杂票据版式可单独评估 |

Apple [VNImageRequestHandler](https://developer.apple.com/documentation/vision/vnimagerequesthandler) 提供带 orientation 的图像输入接口；[CGImagePropertyOrientation](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation) 定义八种旋转/镜像方向。UIImage 的方向元数据必须在取出 CGImage 后显式传递。

## 验证范围

- 保留原有 58 个解析测试的预期，包括同页多金额、优惠后实付金额、导航/状态栏噪声等场景。
- 新增长标签、显式备注优先、紧连日期时间、默认账户与用户本地规则优先级回归。
- 新增八种 UIImage 方向映射检查。
- 新增程序生成的无个人信息账单图片，实际经过 Vision 识别、解析、候选 payload 往返；验证正向及旋转图片的金额、收支、来源、商户、备注、账户和日期时间。这不是预制 OCR 文本测试。
- 原 `/Users/mantou/Downloads/IMG_5794.PNG` 开发机样图测试仍可因文件缺失 skip；新增 Vision 测试不依赖它。

该合成样图验证覆盖特定排版，不代表所有银行、支付应用版本、低清晰度或长截图的准确率，也不替代真机相册导入和最终表单交互验收。识别结果应由用户检查后保存。
