// UI design: Claude Opus 5.5.
import SwiftUI

// MARK: - 主题配色（纸白 / 暖纸 / 夜读）

private struct SNPalette {
    let bg: Color, panel: Color, ink: Color, muted: Color, accent: Color, line: Color
    let dark: Bool

    static func make(_ theme: String) -> SNPalette {
        let t = theme.lowercased()
        if t.contains("night") || t.contains("dark") || t.contains("夜") {
            return SNPalette(bg: snHex(0x1C1B19), panel: snHex(0x262420), ink: snHex(0xE7E3D9),
                             muted: snHex(0x9A958A), accent: snHex(0x8FAE94), line: snHex(0x38352F), dark: true)
        }
        if t.contains("warm") || t.contains("sepia") || t.contains("暖") {
            return SNPalette(bg: snHex(0xF4ECDD), panel: snHex(0xEADFCB), ink: snHex(0x2E2820),
                             muted: snHex(0x7A6F5E), accent: snHex(0x5C7658), line: snHex(0xD9CCB4), dark: false)
        }
        return SNPalette(bg: snHex(0xF9F8F4), panel: snHex(0xEFEDE6), ink: snHex(0x24221F),
                         muted: snHex(0x6E6A62), accent: snHex(0x55735B), line: snHex(0xDEDBD2), dark: false)
    }
}

private func snHex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255,
          green: Double((v >> 8) & 0xFF) / 255,
          blue: Double(v & 0xFF) / 255)
}

// MARK: - 学习笔记

@MainActor
struct StudyNotesView: View {
    @ObservedObject var model: AppModel
    let compact: Bool

    @State private var selectedID: String?
    @State private var query = ""
    @State private var focusOnly = false

    private static let rawID = "__unsorted_turns__"

    init(model: AppModel, compact: Bool) {
        _model = ObservedObject(wrappedValue: model)
        self.compact = compact
    }

    // MARK: 数据

    private var p: SNPalette { .make(model.theme) }
    private var notebook: StudyNotebook { model.currentNotebook }
    private var topics: [StudyTopic] { model.currentStudyTopics }

    private func turns(of topic: StudyTopic) -> [StudyTurn] {
        let ids = Set(topic.turnIDs)
        return notebook.turns.filter { ids.contains($0.id) || $0.topicID == topic.id }
    }

    private func askCount(_ topic: StudyTopic) -> Int {
        max(topic.turnIDs.count, turns(of: topic).count)
    }

    /// 同一知识点被追问 2 次及以上即为重点；次数只代表关注度，不代表掌握。
    private func isFocus(_ topic: StudyTopic) -> Bool { askCount(topic) >= 2 }

    private var unsorted: [StudyTurn] {
        let ids = Set(topics.map(\.id))
        return notebook.turns.filter { !ids.contains($0.topicID) }
    }

    private var pendingCount: Int { notebook.turns.filter { $0.state == "pending" }.count }
    private var errorCount: Int { notebook.turns.filter { $0.state == "error" }.count }

    private var statusText: String {
        if model.studyBusy { return model.studyStatus.isEmpty ? L("老师正在整理…") : model.studyStatus }
        if errorCount > 0 { return L("{0} 条整理失败，原始问答已保留", String(describing: errorCount)) }
        if pendingCount > 0 { return L("{0} 条问答待整理", String(describing: pendingCount)) }
        if !model.studyStatus.isEmpty { return model.studyStatus }
        return notebook.turns.isEmpty ? L("还没有提问") : L("已整理")
    }

    private var filtered: [StudyTopic] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return topics.filter { t in
            if focusOnly && !isFocus(t) { return false }
            if q.isEmpty { return true }
            let hay = ([t.title, t.summary, t.personalNote, t.reviewQuestion] + t.points + t.confusions
                       + turns(of: t).map(\.question)).joined(separator: "\n").lowercased()
            return hay.contains(q)
        }
    }

    private var currentTopic: StudyTopic? {
        guard let id = selectedID else { return filtered.first }
        return topics.first { $0.id == id }
    }

    // MARK: 绑定（直接读当前模型值，避免切换主题时串写）

    private var autoBinding: Binding<Bool> {
        Binding(get: { model.study.autoEnabled }, set: { model.setStudyAuto($0) })
    }

    private func masteredBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { model.currentStudyTopics.first { $0.id == id }?.mastered ?? false },
                set: { model.setStudyMastered(topicID: id, value: $0) })
    }

    private func noteBinding(_ id: String) -> Binding<String> {
        Binding(get: { model.currentStudyTopics.first { $0.id == id }?.personalNote ?? "" },
                set: { model.setStudyPersonalNote(topicID: id, text: $0) })
    }

    // MARK: Body

    var body: some View {
        Group {
            if compact { compactView } else { reviewView }
        }
        .foregroundColor(p.ink)
        .tint(p.accent)
        .background(p.bg)
        .onChange(of: model.studyReviewRequest) { _ in selectedID = model.studyReviewTopicID ?? filtered.first?.id }
        .onChange(of: model.selectedID) { _ in selectedID = nil; query = ""; focusOnly = false }
        .onChange(of: filtered.map(\.id)) { ids in
            if let selectedID, !ids.contains(selectedID), selectedID != Self.rawID { self.selectedID = ids.first }
        }
        .environment(\.colorScheme, p.dark ? .dark : .light)
    }

    // MARK: 右栏 compact

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(L("学习笔记")).font(.headline)
                Spacer()
                if model.studyBusy { ProgressView().controlSize(.small) }
                organizeMenu { Image(systemName: "ellipsis.circle") }
            }
            .padding(12)
            Divider()

            if model.selectedDocument == nil {
                emptyState(L("打开一份课件"), L("阅读时向老师提问，问答会自动归入知识点，整理成这份课件的学习笔记。"))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        progressCard
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(L("自动整理"), isOn: autoBinding).toggleStyle(.switch)
                            Text(L("老师在同一订阅后台整理问答；整理失败不会丢失原始问答。"))
                                .font(.caption).foregroundColor(p.muted)
                        }
                        focusSection
                    }
                    .padding(12)
                }
                Divider()
                HStack {
                    Button(L("大屏复习")) { model.openStudyReview() }.help(L("学习笔记 · 大屏复习"))
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    completeButton
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selectedDocument?.title ?? "")
                .font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(L("阅读位置 {0}% · {1} 个知识点 · {2} 条问答", String(describing: Int((model.selectedDocument?.progress ?? 0) * 100)), String(describing: topics.count), String(describing: notebook.turns.count)))
                .font(.caption).foregroundColor(p.muted)
            HStack(spacing: 6) {
                Circle().fill(errorCount > 0 ? Color.orange : p.accent).frame(width: 6, height: 6)
                Text(statusText).font(.caption).foregroundColor(p.muted).lineLimit(2)
            }
            if notebook.completed {
                Text(L("已标记学习完成（由你主动标记，不代表已掌握）"))
                    .font(.caption).foregroundColor(p.accent)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.panel)
        .cornerRadius(8)
    }

    private var focusSection: some View {
        let focus = topics.filter(isFocus)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("重点追问")).font(.subheadline.weight(.semibold)).foregroundColor(p.accent)
            if focus.isEmpty {
                Text(notebook.turns.isEmpty
                     ? L("向老师提问后，问答会自动归入知识点。也可以从菜单补录已有对话。")
                     : L("同一知识点被第二次追问时，会出现在这里。"))
                    .font(.caption).foregroundColor(p.muted)
            } else {
                ForEach(Array(focus.prefix(4))) { t in
                    Button { model.openStudyReview(topicID:t.id) } label: { focusCard(t) }
                        .buttonStyle(.plain)
                }
                if focus.count > 4 {
                    Text(L("还有 {0} 个重点，可在大屏复习中查看。", String(describing: focus.count - 4)))
                        .font(.caption).foregroundColor(p.muted)
                }
                Text(L("提问次数表示关注度，不代表掌握情况。"))
                    .font(.caption2).foregroundColor(p.muted)
            }
        }
    }

    private func focusCard(_ t: StudyTopic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.title.isEmpty ? L("未命名知识点") : t.title)
                .font(.callout.weight(.medium)).lineLimit(2)
            Text(t.refined ? t.summary : L("原始问答 · 待整理"))
                .font(.caption).foregroundColor(p.muted).lineLimit(3)
            HStack(spacing: 6) {
                Text(L("{0} 次提问", String(describing: askCount(t))))
                if t.mastered { Text(L("· 已自己标记掌握")) }
            }
            .font(.caption2).foregroundColor(p.accent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.panel)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    // MARK: 大屏复习

    private var reviewView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedDocument?.title ?? L("学习笔记"))
                        .font(.title3.weight(.semibold)).lineLimit(1)
                    Text(statusText).font(.caption).foregroundColor(p.muted)
                }
                Spacer()
                if model.studyBusy { ProgressView().controlSize(.small) }
                Toggle(L("自动整理"), isOn: autoBinding).toggleStyle(.switch)
                organizeMenu { Text(L("整理")) }
                Button(L("导出 Markdown")) { model.exportStudyMarkdown() }
                Button(L("同步")) { model.syncNow() }
                completeButton
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(p.panel)
            Divider()

            if model.selectedDocument == nil {
                emptyState(L("还没有打开课件"), L("回到阅读窗口打开一份课件，这里会显示它的学习笔记。"))
            } else if topics.isEmpty && notebook.turns.isEmpty {
                emptyState(L("还没有学习笔记"), L("在阅读窗口向老师提问，或从「整理」菜单补录已有对话。"))
            } else {
                HSplitView {
                    sidebar.frame(minWidth: 240, idealWidth: 290, maxWidth: 420)
                    detail.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
        .onAppear {
            if selectedID == nil {
                selectedID = model.studyReviewTopicID ?? filtered.first?.id ?? (unsorted.isEmpty ? nil : Self.rawID)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            TextField(L("搜索知识点、问题、笔记"), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10).padding(.top, 10)
            Picker("", selection: $focusOnly) {
                Text(L("全部")).tag(false)
                Text(L("重点追问")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 10)

            List(selection: $selectedID) {
                Section(L("知识点")) {
                    ForEach(filtered) { t in
                        topicRow(t).tag(Optional(t.id))
                    }
                }
                if !unsorted.isEmpty && !focusOnly {
                    Section(L("未归类")) {
                        Text(L("原始问答（{0}）", String(describing: unsorted.count))).tag(Optional(Self.rawID))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty && (focusOnly || unsorted.isEmpty) {
                    Text(focusOnly ? L("暂无重点追问") : L("没有匹配的知识点"))
                        .font(.callout).foregroundColor(p.muted)
                }
            }
        }
        .background(p.panel)
    }

    private func topicRow(_ t: StudyTopic) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(t.title.isEmpty ? L("未命名知识点") : t.title).lineLimit(2)
                Spacer(minLength: 4)
                if isFocus(t) { Image(systemName: "star.fill").font(.caption2).foregroundColor(p.accent) }
                if t.mastered { Image(systemName: "checkmark.circle").font(.caption2).foregroundColor(p.accent) }
            }
            Text(t.refined ? L("{0} 次提问", String(describing: askCount(t))) : L("原始问答 · 待整理"))
                .font(.caption).foregroundColor(p.muted)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var detail: some View {
        if selectedID == Self.rawID {
            rawDetail
        } else if let t = currentTopic {
            topicDetail(t)
        } else {
            emptyState(L("选择一个知识点"), L("左侧列表按知识点归纳了你的问题，选中后在这里复习。"))
        }
    }

    private func topicDetail(_ t: StudyTopic) -> some View {
        let list = turns(of: t)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.title.isEmpty ? L("未命名知识点") : t.title)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                    HStack(spacing: 8) {
                        chip(isFocus(t) ? L("重点追问 · {0} 次提问", String(describing: askCount(t))) : L("{0} 次提问", String(describing: askCount(t))))
                        chip(t.refined ? L("已整理") : L("原始问答 · 待整理"))
                        Spacer()
                        if model.selectedDocument?.kind == "pdf" && t.refined {
                            Button(L("加入讲解页")) { model.addStudySlide(topicID:t.id) }
                        }
                        Toggle(L("我已掌握"), isOn: masteredBinding(t.id)).toggleStyle(.checkbox)
                            .help(L("由你自己判断并标记，与提问次数无关"))
                    }
                    if isFocus(t) {
                        Text(L("多次追问说明这里值得复习，不代表掌握程度。"))
                            .font(.caption).foregroundColor(p.muted)
                    }
                }

                if t.refined {
                    if !t.summary.isEmpty {
                        block(L("摘要")) { md(t.summary) }
                    }
                    if !t.points.isEmpty {
                        block(L("要点")) { bullets(t.points) }
                    }
                    if !t.confusions.isEmpty {
                        block(L("追问与困惑")) { bullets(t.confusions) }
                    }
                    if !t.reviewQuestion.isEmpty {
                        block(L("复习自测")) {
                            md(t.reviewQuestion)
                            Text(L("先自己回答，再展开下方原始问答对照。"))
                                .font(.caption).foregroundColor(p.muted)
                        }
                    }
                } else {
                    Text(L("老师会在同一订阅后台整理这个知识点；整理完成前，原始问答完整保留在下方。"))
                        .font(.callout).foregroundColor(p.muted)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.panel).cornerRadius(8)
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if list.isEmpty {
                            Text(L("暂无原始问答")).font(.callout).foregroundColor(p.muted)
                        }
                        ForEach(list) { turnView($0) }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L("原始问答（{0}）", String(describing: list.count))).font(.headline).foregroundColor(p.accent)
                }

                block(L("我的笔记")) {
                    TextEditor(text: noteBinding(t.id))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 150)
                        .background(p.panel)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.line))
                        .id(t.id)
                    Text(L("这里只保存你亲手写的内容，AI 整理不会改动。"))
                        .font(.caption).foregroundColor(p.muted)
                }
            }
            .textSelection(.enabled)
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var rawDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("未归类问答")).font(.system(size: 24, weight: .semibold, design: .serif))
                Text(L("这些问答还没有归入知识点，可在「整理」菜单中重试。问答本身不会丢失。"))
                    .font(.callout).foregroundColor(p.muted)
                ForEach(unsorted) { turnView($0) }
            }
            .textSelection(.enabled)
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func turnView(_ turn: StudyTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if turn.page >= 1 {
                    Button(L("第 {0} 页 · 回到原文", String(describing: turn.page))) { model.jumpToStudySource(page: turn.page) }
                        .buttonStyle(.link)
                }
                Spacer()
                stateLabel(turn.state)
            }
            Text(turn.question).font(.callout.weight(.semibold))
            if turn.answer.isEmpty {
                Text(L("（等待回答）")).font(.callout).foregroundColor(p.muted)
            } else {
                md(turn.answer).font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.panel)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func stateLabel(_ state: String) -> some View {
        switch state {
        case "pending": Text(L("待整理")).font(.caption).foregroundColor(p.muted)
        case "error": Text(L("整理失败 · 问答已保留")).font(.caption).foregroundColor(.orange)
        default: Text(L("已整理")).font(.caption).foregroundColor(p.accent)
        }
    }

    // MARK: 通用小部件

    private var completeButton: some View {
        Button {
            model.setStudyCompleted(!notebook.completed)
        } label: {
            Label(notebook.completed ? L("已完成学习") : L("学习完成"),
                  systemImage: notebook.completed ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .help(L("记录你主动标记的学习进度，不代表已掌握知识"))
    }

    private func organizeMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Button(L("补录已有对话")) { model.importStudyHistory() }
            Button(L("重试整理")) { model.retryStudyNotes() }
                .disabled(model.studyBusy)
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.selectedDocument == nil)
    }

    private func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundColor(p.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundColor(p.accent)
                    md(s)
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(p.accent.opacity(0.12))
            .foregroundColor(p.accent)
            .clipShape(Capsule())
    }

    private func md(_ s: String) -> Text {
        Text(LocalizedStringKey(s))
    }

    private func emptyState(_ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(message)
                .font(.callout).foregroundColor(p.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
