import SwiftUI
import SafariServices

struct ShortcutTutorialView: View {
    @State private var expandAssistiveTouch = true
    @State private var expandBackTap = true
    @State private var safariURL: URL?

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var horizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topGuideCard

                tutorialMethodCard(
                    title: "方法一：通过“辅助触控（小白点）”触发",
                    isExpanded: $expandAssistiveTouch,
                    steps: [
                        "在手机【设置】中点击【辅助功能】→【触控】→【辅助触控】并开启。",
                        "在【自定操作】里将「单点/轻点两下/长按」任一动作设置为「小西记账-自动记账」。",
                        "完成设置后，账单支付成功后通过该触发方式即可自动记账。"
                    ],
                    videoURL: Constants.ShortcutsTutorial.methodOneVideoURL
                )

                tutorialMethodCard(
                    title: "方法二：使用轻触“手机背部”触发",
                    isExpanded: $expandBackTap,
                    steps: [
                        "在手机【设置】中点击【辅助功能】→【触控】，滑动到底部找到【轻点背面】。",
                        "进入【轻点背面】后，选择【轻点两下/轻点三下】并绑定「小西记账-自动记账」。",
                        "设置完成后，支付成功后轻点背部即可自动记账。"
                    ],
                    videoURL: Constants.ShortcutsTutorial.methodTwoVideoURL
                )

                faqCard
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 12)
        }
        .background(Color.appPageBackground)
        .navigationTitle("自动记账")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: safariSheetBinding) { item in
            InAppSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private var topGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何开启自动记账？")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.warmCoral)
                    .padding(.top, 3)
                Text("第一步 添加「小西记账-自动记账」快捷指令")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Button {
                safariURL = Constants.ShortcutsTutorial.installShortcutURL
            } label: {
                Text("点我添加快捷指令")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.warmTeal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.warmCoral)
                    .padding(.top, 3)
                Text("第二步 设置触发方式并使用下方视频/文档教程。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            NavigationLink {
                ShortcutTutorialManualView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 13))
                    Text("文档教程（使用手册）")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.warmTeal)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.warmTeal.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardStyle()
    }

    private func tutorialMethodCard(
        title: String,
        isExpanded: Binding<Bool>,
        steps: [String],
        videoURL: URL?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.warmCoral)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Text(isExpanded.wrappedValue ? "收起" : "展开")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                        Text("\(index + 1). \(text)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    safariURL = videoURL
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 13))
                        Text("视频教程")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.warmTeal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.warmTeal.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .cardStyle(variant: .flat, radius: 14)
    }

    private var faqCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常见问题")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            faqItem(
                question: "自动记账是什么？",
                answer: "通过快捷指令在支付成功后快速抓取订单信息并回到小西记账完成自动填充，你只需确认一次即可保存。"
            )
            faqItem(
                question: "自动记账是否安全？",
                answer: "自动记账在你本机执行，不会上传支付账号密码等敏感信息；你可随时关闭自动化。"
            )
            faqItem(
                question: "支持哪些账单场景？",
                answer: "支持微信、支付宝主流支付账单截图识别，同时支持手动补充分类、备注和日期。"
            )
        }
        .padding(16)
        .cardStyle()
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.warmCoral)
                    .padding(.top, 4)
                Text(question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text(answer)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 18)
        }
    }

    private var safariSheetBinding: Binding<SafariSheetItem?> {
        Binding<SafariSheetItem?>(
            get: {
                guard let safariURL else { return nil }
                return SafariSheetItem(url: safariURL)
            },
            set: { item in
                safariURL = item?.url
            }
        )
    }
}

private struct SafariSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color.warmTeal)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct ShortcutTutorialManualView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("小西记账自动记账使用手册")
                    .font(.system(size: 18, weight: .bold))

                manualSection(
                    title: "一、添加快捷指令",
                    rows: [
                        "在“自动记账教程”页点击「点我添加快捷指令」。",
                        "跳转 iCloud 页面后，点击添加到快捷指令。"
                    ]
                )

                manualSection(
                    title: "二、设置触发方式",
                    rows: [
                        "可选方式：辅助触控（小白点）或轻点手机背面。",
                        "建议在支付成功页停留 1~2 秒后再触发，识别更稳定。"
                    ]
                )

                manualSection(
                    title: "三、完成自动记账",
                    rows: [
                        "触发后自动返回小西记账并填充金额、分类、备注。",
                        "你可以继续修改分类、日期、预算开关后再保存。"
                    ]
                )
            }
            .padding(16)
            .cardStyle()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appPageBackground)
        .navigationTitle("使用手册")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func manualSection(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Text("\(index + 1). \(row)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .cardStyle(variant: .flat, radius: 12)
    }
}

#Preview {
    NavigationView {
        ShortcutTutorialView()
    }
}
