import AppKit
import SwiftUI

/// A persistent scroller lane keeps the document width identical with short and long content.
struct StableScrollView<Content: View>: NSViewRepresentable {
    let scrollToRect: CGRect?
    let scrollTrigger: Int
    let content: Content

    init(scrollToRect: CGRect? = nil, scrollTrigger: Int = 0, @ViewBuilder content: () -> Content) {
        self.scrollToRect = scrollToRect
        self.scrollTrigger = scrollTrigger
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FixedGutterScrollView()
        scroll.configureGutter()
        scroll.setContent(content, transaction: context.transaction)
        scroll.scrollToVisibleIfNeeded(scrollToRect, trigger: scrollTrigger)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let fixed = scroll as? FixedGutterScrollView else { return }
        fixed.setContent(content, transaction: context.transaction)
        fixed.scrollToVisibleIfNeeded(scrollToRect, trigger: scrollTrigger)
    }
}

@MainActor
final class FixedGutterScrollView: NSScrollView {
    private var lastScrollTrigger = 0

    func setContent<Content: View>(_ content: Content, transaction: Transaction = Transaction()) {
        let root = AnyView(content.frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true).transaction { $0 = transaction })
        if let host = documentView as? NSHostingView<AnyView> {
            host.rootView = root
        } else {
            let host = NSHostingView(rootView: root)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.sizingOptions = [.intrinsicContentSize]
            documentView = host
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                host.topAnchor.constraint(equalTo: contentView.topAnchor),
                host.widthAnchor.constraint(equalTo: contentView.widthAnchor)
            ])
        }
    }

    func scrollToVisibleIfNeeded(_ rect: CGRect?, trigger: Int) {
        guard trigger != lastScrollTrigger, let rect, let documentView else { return }
        lastScrollTrigger = trigger
        DispatchQueue.main.async {
            documentView.scrollToVisible(rect.insetBy(dx: 0, dy: -8))
        }
    }

    func configureGutter() {
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = false
        scrollerStyle = .legacy
        verticalScroller?.controlSize = .small
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .automatic
    }
}
