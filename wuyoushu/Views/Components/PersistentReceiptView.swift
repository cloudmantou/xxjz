import SwiftUI
import UIKit

/// 常驻小票容器 — ScrollView 包装器，自动滚动到底部（最新打印行）
struct PersistentReceiptView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    let selectedDayTransactions: [BookkeepingTransaction]
    let isTodayContext: Bool
    let forcePrintTriggerID: UUID
    let forcePrintTargetURI: URL?
    var onRowTap: ((BookkeepingTransaction) -> Void)?
    var onDeleteRow: ((BookkeepingTransaction) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        TopOverscrollClampRepresentable()
                            .frame(width: 0, height: 0)

                        Color.clear
                            .frame(height: 1)
                            .id("receiptTop")

                        ReceiptCardView(
                            selectedDayTransactions: selectedDayTransactions,
                            isTodayContext: isTodayContext,
                            forcePrintTriggerID: forcePrintTriggerID,
                            forcePrintTargetURI: forcePrintTargetURI,
                            onRowTap: onRowTap,
                            onDeleteRow: onDeleteRow
                        )
                        .padding(.bottom, 8)
                    }
                    .padding(.bottom, bottomBarInset)
                }
                .onChange(of: selectedDayTransactions.count) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("receiptTop", anchor: .top)
                        }
                    }
                }
                .onChange(of: forcePrintTriggerID) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                        withAnimation(.easeOut(duration: 0.28)) {
                            proxy.scrollTo("receiptTop", anchor: .top)
                        }
                    }
                }
                
                // 底部 SafeArea bar（自适应暗/亮）
                Color.appPageBackground
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct TopOverscrollClampRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TopOverscrollClampView {
        TopOverscrollClampView()
    }

    func updateUIView(_ uiView: TopOverscrollClampView, context: Context) {
        uiView.attachIfNeeded()
    }
}

private final class TopOverscrollClampView: UIView {
    private weak var observedScrollView: UIScrollView?
    private var observation: NSKeyValueObservation?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachIfNeeded()
    }

    deinit {
        observation?.invalidate()
    }

    func attachIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let scrollView = self.enclosingScrollView() else { return }
            guard observedScrollView !== scrollView else { return }

            observation?.invalidate()
            observedScrollView = scrollView
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.clampTopOverscroll(scrollView)
            }
        }
    }

    private func clampTopOverscroll(_ scrollView: UIScrollView) {
        let minYOffset = -scrollView.adjustedContentInset.top
        guard scrollView.contentOffset.y < minYOffset else { return }
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: minYOffset)
    }

    private func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let superview = current?.superview {
            if let scroll = superview as? UIScrollView {
                return scroll
            }
            current = superview
        }
        return nil
    }
}
