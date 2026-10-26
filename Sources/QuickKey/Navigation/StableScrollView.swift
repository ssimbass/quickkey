import AppKit
import SwiftUI

/// A persistent scroller lane keeps the document width identical with short and long content.
struct StableScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FixedGutterScrollView()
        scroll.configureGutter()
        scroll.setContent(content, transaction: context.transaction)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll as? FixedGutterScrollView)?.setContent(content, transaction: context.transaction)
    }
}

@MainActor
final class FixedGutterScrollView: NSScrollView {
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
