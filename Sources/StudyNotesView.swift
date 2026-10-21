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
        if model.studyBusy { return model.studyStatus.isEmpty ? "老师正在整理…" : model.studyStatus }
        if errorCount > 0 { return "\(errorCount) 条整理失败，原始问答已保留" }
        if pendingCount > 0 { return "\(pendingCount) 条问答待整理" }
        if !model.studyStatus.isEmpty { return model.studyStatus }
        return notebook.turns.isEmpty ? "还没有提问" : "已整理"
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
                Text("学习笔记").font(.headline)
                Spacer()
                if model.studyBusy { ProgressView().controlSize(.small) }
                organizeMenu { Image(systemName: "ellipsis.circle") }
            }
            .padding(12)
            Divider()

            if model.selectedDocument == nil {
                emptyState("打开一份课件", "阅读时向老师提问，问答会自动归入知识点，整理成这份课件的学习笔记。")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        progressCard
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("自动整理", isOn: autoBinding).toggleStyle(.switch)
                            Text("老师在同一订阅后台整理问答；整理失败不会丢失原始问答。")
                                .font(.caption).foregroundColor(p.muted)
                        }
                        focusSection
                    }
                    .padding(12)
                }
                Divider()
                HStack {
                    Button("大屏复习") { model.openStudyReview() }
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
            Text("阅读位置 \(Int((model.selectedDocument?.progress ?? 0) * 100))% · \(topics.count) 个知识点 · \(notebook.turns.count) 条问答")
                .font(.caption).foregroundColor(p.muted)
            HStack(spacing: 6) {
                Circle().fill(errorCount > 0 ? Color.orange : p.accent).frame(width: 6, height: 6)
                Text(statusText).font(.caption).foregroundColor(p.muted).lineLimit(2)
            }
            if notebook.completed {
                Text("已标记学习完成（由你主动标记，不代表已掌握）")
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
            Text("重点追问").font(.subheadline.weight(.semibold)).foregroundColor(p.accent)
            if focus.isEmpty {
                Text(notebook.turns.isEmpty
                     ? "向老师提问后，问答会自动归入知识点。也可以从菜单补录已有对话。"
                     : "同一知识点被第二次追问时，会出现在这里。")
                    .font(.caption).foregroundColor(p.muted)
            } else {
                ForEach(Array(focus.prefix(4))) { t in
                    Button { model.openStudyReview(topicID:t.id) } label: { focusCard(t) }
                        .buttonStyle(.plain)
                }
                if focus.count > 4 {
                    Text("还有 \(focus.count - 4) 个重点，可在大屏复习中查看。")
                        .font(.caption).foregroundColor(p.muted)
                }
                Text("提问次数表示关注度，不代表掌握情况。")
                    .font(.caption2).foregroundColor(p.muted)
            }
        }
    }

    private func focusCard(_ t: StudyTopic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.title.isEmpty ? "未命名知识点" : t.title)
                .font(.callout.weight(.medium)).lineLimit(2)
            Text(t.refined ? t.summary : "原始问答 · 待整理")
                .font(.caption).foregroundColor(p.muted).lineLimit(3)
            HStack(spacing: 6) {
                Text("\(askCount(t)) 次提问")
                if t.mastered { Text("· 已自己标记掌握") }
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
                    Text(model.selectedDocument?.title ?? "学习笔记")
                        .font(.title3.weight(.semibold)).lineLimit(1)
                    Text(statusText).font(.caption).foregroundColor(p.muted)
                }
                Spacer()
                if model.studyBusy { ProgressView().controlSize(.small) }
                Toggle("自动整理", isOn: autoBinding).toggleStyle(.switch)
                organizeMenu { Text("整理") }
                Button("导出 Markdown") { model.exportStudyMarkdown() }
                Button("同步") { model.syncNow() }
                completeButton
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(p.panel)
            Divider()

            if model.selectedDocument == nil {
                emptyState("还没有打开课件", "回到阅读窗口打开一份课件，这里会显示它的学习笔记。")
            } else if topics.isEmpty && notebook.turns.isEmpty {
                emptyState("还没有学习笔记", "在阅读窗口向老师提问，或从「整理」菜单补录已有对话。")
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
            TextField("搜索知识点、问题、笔记", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10).padding(.top, 10)
            Picker("", selection: $focusOnly) {
                Text("全部").tag(false)
                Text("重点追问").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 10)

            List(selection: $selectedID) {
                Section("知识点") {
                    ForEach(filtered) { t in
                        topicRow(t).tag(Optional(t.id))
                    }
                }
                if !unsorted.isEmpty && !focusOnly {
                    Section("未归类") {
                        Text("原始问答（\(unsorted.count)）").tag(Optional(Self.rawID))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty && (focusOnly || unsorted.isEmpty) {
                    Text(focusOnly ? "暂无重点追问" : "没有匹配的知识点")
                        .font(.callout).foregroundColor(p.muted)
                }
            }
        }
        .background(p.panel)
    }

    private func topicRow(_ t: StudyTopic) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(t.title.isEmpty ? "未命名知识点" : t.title).lineLimit(2)
                Spacer(minLength: 4)
                if isFocus(t) { Image(systemName: "star.fill").font(.caption2).foregroundColor(p.accent) }
                if t.mastered { Image(systemName: "checkmark.circle").font(.caption2).foregroundColor(p.accent) }
            }
            Text(t.refined ? "\(askCount(t)) 次提问" : "原始问答 · 待整理")
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
            emptyState("选择一个知识点", "左侧列表按知识点归纳了你的问题，选中后在这里复习。")
        }
    }

    private func topicDetail(_ t: StudyTopic) -> some View {
        let list = turns(of: t)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.title.isEmpty ? "未命名知识点" : t.title)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                    HStack(spacing: 8) {
                        chip(isFocus(t) ? "重点追问 · \(askCount(t)) 次提问" : "\(askCount(t)) 次提问")
                        chip(t.refined ? "已整理" : "原始问答 · 待整理")
                        Spacer()
                        if model.selectedDocument?.kind == "pdf" && t.refined {
                            Button("加入讲解页") { model.addStudySlide(topicID:t.id) }
                        }
                        Toggle("我已掌握", isOn: masteredBinding(t.id)).toggleStyle(.checkbox)
                            .help("由你自己判断并标记，与提问次数无关")
                    }
                    if isFocus(t) {
                        Text("多次追问说明这里值得复习，不代表掌握程度。")
                            .font(.caption).foregroundColor(p.muted)
                    }
                }

                if t.refined {
                    if !t.summary.isEmpty {
                        block("摘要") { md(t.summary) }
                    }
                    if !t.points.isEmpty {
                        block("要点") { bullets(t.points) }
                    }
                    if !t.confusions.isEmpty {
                        block("追问与困惑") { bullets(t.confusions) }
                    }
                    if !t.reviewQuestion.isEmpty {
                        block("复习自测") {
                            md(t.reviewQuestion)
                            Text("先自己回答，再展开下方原始问答对照。")
                                .font(.caption).foregroundColor(p.muted)
                        }
                    }
                } else {
                    Text("老师会在同一订阅后台整理这个知识点；整理完成前，原始问答完整保留在下方。")
                        .font(.callout).foregroundColor(p.muted)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.panel).cornerRadius(8)
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if list.isEmpty {
                            Text("暂无原始问答").font(.callout).foregroundColor(p.muted)
                        }
                        ForEach(list) { turnView($0) }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("原始问答（\(list.count)）").font(.headline).foregroundColor(p.accent)
                }

                block("我的笔记") {
                    TextEditor(text: noteBinding(t.id))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 150)
                        .background(p.panel)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.line))
                        .id(t.id)
                    Text("这里只保存你亲手写的内容，AI 整理不会改动。")
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
                Text("未归类问答").font(.system(size: 24, weight: .semibold, design: .serif))
                Text("这些问答还没有归入知识点，可在「整理」菜单中重试。问答本身不会丢失。")
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
                    Button("第 \(turn.page) 页 · 回到原文") { model.jumpToStudySource(page: turn.page) }
                        .buttonStyle(.link)
                }
                Spacer()
                stateLabel(turn.state)
            }
            Text(turn.question).font(.callout.weight(.semibold))
            if turn.answer.isEmpty {
                Text("（等待回答）").font(.callout).foregroundColor(p.muted)
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
        case "pending": Text("待整理").font(.caption).foregroundColor(p.muted)
        case "error": Text("整理失败 · 问答已保留").font(.caption).foregroundColor(.orange)
        default: Text("已整理").font(.caption).foregroundColor(p.accent)
        }
    }

    // MARK: 通用小部件

    private var completeButton: some View {
        Button {
            model.setStudyCompleted(!notebook.completed)
        } label: {
            Label(notebook.completed ? "已完成学习" : "学习完成",
                  systemImage: notebook.completed ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .help("记录你主动标记的学习进度，不代表已掌握知识")
    }

    private func organizeMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            Button("补录已有对话") { model.importStudyHistory() }
            Button("重试整理") { model.retryStudyNotes() }
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
