import AppKit
import SwiftUI

@MainActor
enum NavigationGeometryChecks {
    static func run() async throws -> String {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = FixedGutterScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        scroll.configureGutter()
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.close() }
        var count = 0
        var baseline: CGFloat?
        for preferred in [NSScroller.Style.overlay, .legacy] {
            scroll.scrollerStyle = preferred
            scroll.configureGutter()
            for height in [CGFloat(100), 1400, 120, 1800] {
                scroll.setContent(Text("滚动条几何检查").frame(maxWidth: .infinity, alignment: .trailing).frame(height: height))
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                scroll.layoutSubtreeIfNeeded()
                let width = scroll.contentView.bounds.width
                guard width > 200, width < 320, scroll.scrollerStyle == .legacy,
                      let document = scroll.documentView, abs(document.frame.width - width) < 1,
                      abs(document.frame.height - height) < 2 else {
                    throw GeometryError.failed("滚动区尺寸异常：clip=\(width)，document=\(scroll.documentView?.frame ?? .zero)")
                }
                if let baseline, abs(baseline - width) > 0.5 {
                    throw GeometryError.failed("滚动条切换导致可用宽度从 \(baseline) 变为 \(width)")
                }
                baseline = width
                if height > 1000 {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 220))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    try await Task.sleep(for: .milliseconds(50))
                    guard scroll.contentView.bounds.origin.y > 100,
                          abs(document.frame.origin.y) < 1 else {
                        throw GeometryError.failed("长列表未能保持正常滚动，或文档原点发生漂移。")
                    }
                }
                count += 1
            }
        }
        return "导航几何检查通过 \(count) 项：短/长内容、滚动条样式切换时，内容宽度恒定为 \(Int(baseline ?? 0))pt。"
    }

    private enum GeometryError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case let .failed(message) = self { return message }; return nil }
    }
}
