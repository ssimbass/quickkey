import AppKit
import ShortcutCore
import SwiftUI

@MainActor
final class HintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct FloatingHintView: View {
    let shortcut: Shortcut
    let onReturn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shortcut.scope.symbol)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 37, height: 37)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(shortcut.scope.title) · \(shortcut.title)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(L10n.text("请按 ") + shortcut.keys.joined(separator: " "))
                    .font(.system(size: 17, weight: .medium))
            }
            Spacer(minLength: 10)
            Button(action: onReturn) {
                Label(L10n.text("返回教学页"), systemImage: "arrow.up.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 470, height: 76)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1)))
    }
}

struct PracticeWindowView: View {
    let shortcut: Shortcut

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "macwindow")
                .font(.system(size: 32, weight: .light)).foregroundStyle(.blue)
            Text(shortcut.title).font(.title3.weight(.medium))
            Text(shortcut.keys.joined(separator: "  "))
                .font(.system(size: 27, weight: .medium))
            Text(shortcut.practice == .hideApp
                 ? L10n.text("隐藏后，点击 Dock 中的“快捷”图标返回。")
                 : shortcut.practice == .minimizeWindow
                 ? L10n.text("最小化后，点击 Dock 中的窗口缩略图恢复。")
                 : L10n.text("关闭这个练习窗口后，教学主窗口会保留。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(25)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum BrowserPracticePage {
    static var main: String { AppLanguage.current == .english ? mainEnglish : mainChinese }
    static var next: String { AppLanguage.current == .english ? nextEnglish : nextChinese }

    private static let mainEnglish = """
    <!doctype html>
    <html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>QuickKey · Browser Practice</title><style>
    :root{color-scheme:light dark}body{font:16px/1.8 -apple-system,BlinkMacSystemFont,sans-serif;max-width:740px;margin:72px auto;padding:0 24px;color:light-dark(#252831,#eee);background:light-dark(#fafbfc,#202126)}
    h1{font-size:32px;font-weight:500}h2{font-size:21px;font-weight:500;margin-top:42px}p{color:light-dark(#626877,#aab0bc)}a{color:light-dark(#176ee0,#7bb3ff)}input,textarea{font:inherit;width:100%;box-sizing:border-box;padding:12px;border:1px solid light-dark(#d8dce5,#4b4f59);border-radius:8px;background:light-dark(white,#2b2d34);color:inherit}
    .mark{font-size:12px;color:light-dark(#748091,#a4adba)}section{margin:40px 0}footer{margin-top:80px;font-size:13px;color:light-dark(#748091,#a4adba)}
    </style></head><body>
    <span class="mark">QuickKey / Real browser practice</span><h1>Let your keyboard take the next step.</h1>
    <p>This local practice page does not run shortcuts automatically. Press the keys yourself and observe your browser's response.</p>
    <section><h2>Address bar and Find</h2><p>Press ⌘ L to focus the address bar, or ⌘ F to find “shortcut practice”. You can also try zooming, print preview, and saving the page.</p>
    <p>Search target: shortcut practice. Another occurrence: shortcut practice.</p></section>
    <section><h2>Navigation and tabs</h2><p><a href="Next Page.html">Next page</a>: follow this link, then try your browser's Back and Forward shortcuts. Press ⌘ T for a new tab. Return to QuickKey after closing the practice tab.</p></section>
    <section><h2>Text and focus</h2><label>Selectable practice text<textarea rows="3">Put shortcuts to work in real tasks. Select this text and try copying or cutting it yourself.</textarea></label><p><label>Paste area<input placeholder="Click here, then press ⌘ V"></label></p></section>
    <section><h2>Reading and scrolling</h2><p>Use this long page to practice scrolling. Press Space to scroll down and Shift + Space to scroll up. Try Command + Up Arrow or Down Arrow to go to the top or bottom.</p></section>
    <section><h2>Finish practice</h2><p>Shortcut practice. Observe the expected result, then click Back to reference on the floating hint or select QuickKey in the Dock.</p></section>
    <footer>QuickKey creates this page in a dedicated practice folder. Preparing again creates a new folder and keeps earlier files. You press every shortcut yourself.</footer>
    </body></html>
    """

    private static let nextEnglish = """
    <!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>QuickKey · Next Page</title><style>:root{color-scheme:light dark}body{font:17px/1.8 -apple-system,BlinkMacSystemFont,sans-serif;max-width:700px;margin:100px auto;padding:24px}h1{font-weight:500}a{color:light-dark(#176ee0,#7bb3ff)}</style></head><body><h1>You opened the next page.</h1><p>Use your browser's Back shortcut and watch the previous practice page reappear.</p><p><a href="Shortcut Practice.html">Return to practice home</a></p></body></html>
    """

    static let mainChinese = """
    <!doctype html>
    <html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>快捷 · 浏览器练习页</title><style>
    :root{color-scheme:light dark}body{font:16px/1.8 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;max-width:740px;margin:72px auto;padding:0 24px;color:light-dark(#252831,#eee);background:light-dark(#fafbfc,#202126)}
    h1{font-size:32px;font-weight:500}h2{font-size:21px;font-weight:500;margin-top:42px}p{color:light-dark(#626877,#aab0bc)}a{color:light-dark(#176ee0,#7bb3ff)}input,textarea{font:inherit;width:100%;box-sizing:border-box;padding:12px;border:1px solid light-dark(#d8dce5,#4b4f59);border-radius:8px;background:light-dark(white,#2b2d34);color:inherit}
    .mark{font-size:12px;color:light-dark(#748091,#a4adba)}section{margin:40px 0}footer{margin-top:80px;font-size:13px;color:light-dark(#748091,#a4adba)}
    </style></head><body>
    <span class="mark">快捷 / 真实浏览器练习</span><h1>让键盘，接管下一步。</h1>
    <p>这是一张位于本机的练习网页，不会自动执行快捷键。请亲手操作，并观察浏览器的真实响应。</p>
    <section><h2>地址栏与查找</h2><p>按 ⌘ L 聚焦地址栏，或用 ⌘ F 查找“快捷练习”。你也可以在这里练习缩放、打印预览与保存网页。</p>
    <p>查找目标：快捷练习。下一处目标也叫：快捷练习。</p></section>
    <section><h2>导航与标签页</h2><p><a href="下一页.html">打开练习下一页</a>，再用浏览器的后退、前进快捷键返回。用 ⌘ T 打开新标签页；关闭练习标签页后，可以回到教学应用。</p></section>
    <section><h2>文本与焦点</h2><label>可选中的练习文本<textarea rows="3">把快捷键，用在真正的操作里。选中这一段文字，亲手复制或剪切。</textarea></label><p><label>粘贴区域<input placeholder="点击这里再按 ⌘ V"></label></p></section>
    <section><h2>阅读与滚动</h2><p>这段内容用于练习页面滚动。按空格向下翻页，按 Shift + 空格向上翻页。你也可以使用 Command + 上下方向键，观察页面回到顶部或底部。</p></section>
    <section><h2>练习完成</h2><p>快捷练习。观察到预期现象即可；点击悬浮提示条的“返回教学页”，或从 Dock 返回“快捷”继续查看。</p></section>
    <footer>此页由“快捷”在专用练习目录生成。重新准备会创建新目录，保留之前的练习文件。所有快捷键都由你亲自按下。</footer>
    </body></html>
    """

    static let nextChinese = """
    <!doctype html><html lang="zh-CN"><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>快捷 · 练习下一页</title><style>:root{color-scheme:light dark}body{font:17px/1.8 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;max-width:700px;margin:100px auto;padding:24px}h1{font-weight:500}a{color:light-dark(#176ee0,#7bb3ff)}</style><h1>你已经打开了下一页。</h1><p>现在亲手使用浏览器的后退快捷键，观察上一张练习网页出现。</p><p><a href="快捷键练习.html">返回练习首页</a></p></html>
    """
}
