import SwiftUI
import AppKit
import ShortcutCore

struct ShortcutDetailView: View {
    let shortcut: Shortcut
    let catalog: ShortcutCatalog
    @ObservedObject var practice: PracticeController
    @ObservedObject var userState: UserLibraryState
    @AppStorage("showWindowsEquivalent") private var showWindowsEquivalent = true
    @ViewState private var textVersion = UUID()
    @ViewState private var showSteps = false
    @ViewState private var showQuestions = false
    @ViewState private var showReferences = false

    private var isText: Bool { shortcut.practice == .textEditing }
    private var automatic: Bool { PracticeController.automaticallyVerifies(shortcut) }
    private var active: Bool { practice.activeShortcutID == shortcut.id }
    private var prepared: Bool { active && practice.isPrepared }
    private var needsEnvironment: Bool { PracticeConfiguration.needsEnvironment(for: shortcut) }
    private var isFavorite: Bool { userState.isFavorite(shortcut.id) }
    private var isPracticed: Bool { userState.isPracticed(shortcut.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label(shortcut.scope.title + " / " + shortcut.section, systemImage: shortcut.scope.symbol)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if isPracticed {
                    Label(L10n.text("已练习"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(.green)
                }
                Spacer()
                Button {
                    userState.toggleFavorite(shortcut.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(isFavorite ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? L10n.text("取消收藏") : L10n.text("收藏快捷键"))
                .accessibilityLabel(isFavorite ? L10n.text("取消收藏") : L10n.text("收藏快捷键"))
            }
            .padding(.bottom, 14)
            Text(shortcut.title).font(.system(size: 27, weight: .medium)).padding(.bottom, 18)
            KeyCaps(keys: shortcut.keys, large: true).padding(.bottom, 11)
            Text(shortcut.englishKeys).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(shortcut.summary).font(.system(size: 13)).padding(.top, 21)
            Text(shortcut.prerequisite).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 7)
            if showWindowsEquivalent, let equivalent = shortcut.windowsEquivalent {
                Text("Windows: \(equivalent)").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 11)
            }
            Divider().padding(.vertical, 24)
            practiceSection
            Divider().padding(.top, 24).padding(.bottom, 15)
            DisclosureGroup(L10n.text("操作步骤"), isExpanded: $showSteps) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(shortcut.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                            Text(step)
                        }
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            DisclosureGroup(L10n.text("使用提示"), isExpanded: $showQuestions) {
                VStack(alignment: .leading, spacing: 8) {
                    if shortcut.customizable {
                        Text(L10n.text("此处显示默认绑定，修改过快捷键时请使用系统或应用当前的设置。"))
                    }
                    ForEach(Array(shortcut.notes.enumerated()), id: \.offset) { _, note in Text(note) }
                    if let directory = practice.practiceDirectory, active {
                        Text(L10n.text("练习文件保存在独立目录中。重新准备会新建目录，保留旧文件。"))
                        Button(L10n.text("在 Finder 中显示练习目录")) { NSWorkspace.shared.open(directory) }.buttonStyle(.link)
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            DisclosureGroup(L10n.text("官方来源"), isExpanded: $showReferences) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(catalog.sources.filter { shortcut.sourceIDs.contains($0.id) }) { source in
                        Link(destination: source.url) { Label(source.title, systemImage: "arrow.up.right.square") }
                    }
                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .disclosureGroupStyle(DetailDisclosureStyle())
        .accessibilityIdentifier("shortcut-content-" + shortcut.id)
    }

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Text(automatic ? L10n.text("练习") : L10n.text("试一下")).font(.system(size: 14, weight: .medium))
                if automatic {
                    Label(L10n.text("自动检测"), systemImage: "checkmark.circle")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if !isText {
                    Button(practice.hasFloatingHint ? L10n.text("收起提示") : L10n.text("悬浮提示"), systemImage: "rectangle.topthird.inset.filled") {
                        if practice.hasFloatingHint { practice.hideFloatingHint() } else { showHint() }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if isText {
                NativeTextPractice(shortcut: shortcut, onResult: practice.reportTextResult).id(textVersion)
                HStack {
                    if active && practice.status.isSuccess {
                        feedback(success: true, message: practice.status.message)
                    } else if active && practice.status.isFailure {
                        feedback(success: false, message: practice.status.message)
                    }
                    Spacer(minLength: 5)
                    Button(L10n.text("重置"), systemImage: "arrow.counterclockwise") {
                        textVersion = UUID(); practice.reset(shortcut)
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                if !automatic {
                    Text(shortcut.expectedResult).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                if let hint = PracticeConfiguration.preparationHint(for: shortcut.id) {
                    Text(hint).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if needsEnvironment {
                    HStack(spacing: 12) {
                        Button {
                            practice.prepare(shortcut)
                            if !practice.status.isFailure { showHint() }
                        } label: {
                            Label(prepared ? L10n.text("重新准备") : prepareTitle, systemImage: prepared ? "arrow.counterclockwise" : prepareSymbol)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                        .disabled(practice.isPreparing)
                        if practice.isPreparing { ProgressView().controlSize(.small) }
                        if prepared && !automatic {
                            Text(L10n.text("样例已准备")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                if active && practice.status.isFailure {
                    feedback(success: false, message: practice.status.message)
                } else if prepared && practice.status.isSuccess {
                    feedback(success: true, message: practice.status.message)
                } else if automatic && prepared {
                    Label(liveWaitingMessage, systemImage: "circle.dashed")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func feedback(success: Bool, message: String) -> some View {
        Label {
            Text(message).textSelection(.enabled)
        } icon: { Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle") }
            .font(.system(size: 12)).foregroundStyle(success ? Color.green : Color.red)
            .accessibilityElement(children: .combine)
    }

    private var liveWaitingMessage: String {
        if shortcut.practice == .trashFile,
           practice.status.message == L10n.text("样例文件已离开练习目录；请查看废纸篓。") {
            return practice.status.message
        }
        return waitingMessage
    }

    private var waitingMessage: String {
        switch shortcut.practice {
        case .newFolder: L10n.text("等待练习目录中出现新文件夹…")
        case .renameFile: L10n.text("等待「练习笔记.txt」的名称改变…")
        case .duplicateFile: L10n.text("等待练习目录中出现文件副本…")
        case .trashFile: L10n.text("等待样例文件移入废纸篓…")
        case .minimizeWindow: L10n.text("等待独立练习窗口最小化…")
        case .closeWindow: L10n.text("等待独立练习窗口关闭…")
        case .hideApp: L10n.text("等待应用隐藏；点击 Dock 中的“快捷”即可返回。")
        default: L10n.text("等待实际操作结果…")
        }
    }

    private var prepareTitle: String {
        switch shortcut.practice {
        case .newFolder: L10n.text("打开练习文件夹")
        case .renameFile, .duplicateFile, .trashFile, .quickLook, .fileInfo, .openFile: L10n.text("打开样例文件")
        case .minimizeWindow, .closeWindow, .hideApp: L10n.text("打开练习窗口")
        case .browserAddress, .browserPage: L10n.format("打开 {0} 练习页", String(describing: shortcut.scope.title))
        default: shortcut.scope == .finder ? L10n.text("打开练习文件夹") : L10n.format("打开 {0} 练习页", String(describing: shortcut.scope.title))
        }
    }

    private var prepareSymbol: String {
        switch shortcut.practice {
        case .minimizeWindow, .closeWindow, .hideApp: "macwindow.badge.plus"
        case .browserAddress, .browserPage: "arrow.up.right.square"
        default: "folder"
        }
    }

    private func showHint() { practice.showFloatingHint(for: shortcut, onReturn: {}) }
}

private struct DetailDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? L10n.text("已展开") : L10n.text("已收起"))

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
