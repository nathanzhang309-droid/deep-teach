// UI design: Claude Opus 5.5.
//  SlideInspector.swift
//  伴读 · 课件批注侧栏（macOS 13 / Swift 5）
//
//  编辑的是 PDF 副本上的叠加层：原始 PPT 不被修改，新增讲解页追加在页尾。
//  图片/公式图保留为图片，可移动缩放；文字与图形可编辑。

import SwiftUI

// MARK: - 主题

private struct SlidePalette {
    let background: Color
    let surface: Color
    let line: Color
    let ink: Color
    let secondary: Color
    let accent: Color
    let accentSoft: Color
    let isNight: Bool

    static func of(_ theme: String) -> SlidePalette {
        let key = theme.lowercased()
        if key.contains("night") || key.contains("dark") || key.contains("夜") {
            return SlidePalette(
                background: slideHexColor("#1E1F1C"),
                surface: slideHexColor("#272925"),
                line: slideHexColor("#3A3D37"),
                ink: slideHexColor("#E6E3DA"),
                secondary: slideHexColor("#9C9A92"),
                accent: slideHexColor("#8FAE92"),
                accentSoft: slideHexColor("#8FAE92").opacity(0.18),
                isNight: true
            )
        }
        if key.contains("warm") || key.contains("sepia") || key.contains("暖") {
            return SlidePalette(
                background: slideHexColor("#F4ECDD"),
                surface: slideHexColor("#FAF4E8"),
                line: slideHexColor("#E2D6C0"),
                ink: slideHexColor("#3B352C"),
                secondary: slideHexColor("#8A7F6E"),
                accent: slideHexColor("#55735B"),
                accentSoft: slideHexColor("#55735B").opacity(0.12),
                isNight: false
            )
        }
        return SlidePalette(
            background: slideHexColor("#FBFAF7"),
            surface: slideHexColor("#FFFFFF"),
            line: slideHexColor("#E6E4DE"),
            ink: slideHexColor("#2B2B28"),
            secondary: slideHexColor("#85837C"),
            accent: slideHexColor("#55735B"),
            accentSoft: slideHexColor("#55735B").opacity(0.10),
            isNight: false
        )
    }
}

fileprivate func slideHexColor(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt64(s, radix: 16) else { return .gray }
    return Color(
        red: Double((v >> 16) & 0xFF) / 255.0,
        green: Double((v >> 8) & 0xFF) / 255.0,
        blue: Double(v & 0xFF) / 255.0
    )
}

/// 固定五色：鼠尾草绿、砖红、靛蓝、琥珀、墨色
private let slideMarkColors: [(hex: String, name: String)] = [
    ("#55735B", "鼠尾草绿"),
    ("#B5533C", "砖红"),
    ("#2F5D8A", "靛蓝"),
    ("#C8962E", "琥珀"),
    ("#2B2B28", "墨色")
]

private func slideKindName(_ kind: String) -> String {
    switch kind {
    case "label": return "红笔文字"
    case "underline": return "下划线"
    case "text": return "文字"
    case "rectangle": return "矩形"
    case "ellipse": return "圆圈"
    case "arrow": return "箭头"
    case "image": return "图片"
    default: return "对象"
    }
}

private func slideKindSymbol(_ kind: String) -> String {
    switch kind {
    case "text": return "textformat"
    case "rectangle": return "rectangle"
    case "ellipse": return "circle"
    case "arrow": return "arrow.up.right"
    case "image": return "photo"
    default: return "square.dashed"
    }
}

// MARK: - 侧栏

struct SlideInspector: View {
    @ObservedObject var model: AppModel
    @State private var nudgeStep: Double = 5

    init(model: AppModel) {
        self.model = model
    }

    private var palette: SlidePalette { SlidePalette.of(model.theme) }
    private var hasDocument: Bool { model.selectedDocument != nil }

    var body: some View {
        let p = palette
        VStack(spacing: 0) {
            header(p)
            Divider().overlay(p.line)

            if hasDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        createSection(p)
                        layerNote(p)
                        objectListSection(p)
                        if let mark = model.selectedSlideMark {
                            propertySection(mark, p)
                        }
                    }
                    .padding(14)
                }
            } else {
                emptyDocument(p)
            }

            Divider().overlay(p.line)
            footer(p)
        }
        .frame(minWidth: 300, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
        .foregroundColor(p.ink)
        .environment(\.colorScheme, p.isNight ? .dark : .light)
    }

    // MARK: 顶栏

    private func header(_ p: SlidePalette) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("课件批注")
                    .font(.headline)
                if !model.pageLabel.isEmpty {
                    Text(model.pageLabel)
                        .font(.caption)
                        .foregroundColor(p.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            Button {
                model.undoSlideChange()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canUndoSlide)
            .help("撤销")

            Button {
                model.redoSlideChange()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canRedoSlide)
            .help("重做")

            Button("完成") {
                model.slideEditing = false
            }
            .buttonStyle(.borderedProminent)
            .tint(p.accent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 新建对象

    private func createSection(_ p: SlidePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("添加到本页", p)
            HStack(spacing: 8) {
                toolButton("文字", "textformat", p) { model.addSlideText() }
                toolButton("矩形", "rectangle", p) { model.addSlideShape("rectangle") }
                toolButton("圆圈", "circle", p) { model.addSlideShape("ellipse") }
            }
            HStack(spacing: 8) {
                toolButton("箭头", "arrow.up.right", p) { model.addSlideShape("arrow") }
                toolButton("图片", "photo", p) { model.importSlideImage() }
                newPageMenu(p)
            }
        }
    }

    private func toolButton(_ title: String, _ symbol: String, _ p: SlidePalette,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(p.accent)
                Text(title)
                    .font(.caption)
                    .foregroundColor(p.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(tileBackground(p))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("添加\(title)")
    }

    private func newPageMenu(_ p: SlidePalette) -> some View {
        Menu {
            Button("空白讲解页") { model.addBlankSlide() }
            Divider()
            if model.currentStudyTopics.filter({ $0.refined }).isEmpty {
                Text("暂无已整理的知识点，可先在学习笔记中整理")
            } else {
                Section("由已整理知识点生成图解页") {
                    ForEach(model.currentStudyTopics.filter { $0.refined }, id: \.id) { topic in
                        Button(topic.title) { model.addStudySlide(topicID: topic.id) }
                    }
                }
            }
        } label: {
            Label("新页", systemImage: "doc.badge.plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(tileBackground(p))
        .help("在页尾追加讲解页")
    }

    private func tileBackground(_ p: SlidePalette) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(p.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(p.line, lineWidth: 1)
            )
    }

    private func layerNote(_ p: SlidePalette) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(p.accent)
            Text("页上拖动对象，右下角手柄缩放。批注在课件副本的叠加层上，原始 PPT 不改动，新页追加在页尾。图片/公式图保留为图片，可移动缩放；文字与图形可编辑。")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundColor(p.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.accentSoft)
        )
    }

    // MARK: 当前页对象

    private func objectListSection(_ p: SlidePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("本页对象", p)
            if model.currentSlideMarks.isEmpty {
                Text("本页还没有批注。用上方按钮添加，或在课件上直接点选。")
                    .font(.caption)
                    .foregroundColor(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.currentSlideMarks) { mark in
                        objectRow(mark, p)
                    }
                }
                .padding(4)
                .background(tileBackground(p))
            }
        }
    }

    private func objectRow(_ mark: SlideMark, _ p: SlidePalette) -> some View {
        let selected = model.selectedSlideMarkID == mark.id
        let trimmed = mark.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? slideKindName(mark.kind) : trimmed
        return Button {
            model.selectSlideMark(mark.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: slideKindSymbol(mark.kind))
                    .frame(width: 18)
                    .foregroundColor(mark.kind == "image" ? p.secondary : slideHexColor(mark.color))
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(slideKindName(mark.kind))
                    .font(.caption2)
                    .foregroundColor(p.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? p.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除", role: .destructive) { model.deleteSlideMark(mark.id) }
        }
    }

    // MARK: 属性

    private func propertySection(_ mark: SlideMark, _ p: SlidePalette) -> some View {
        let id = mark.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("\(slideKindName(mark.kind))属性", p)
                Spacer()
                Button(role: .destructive) {
                    model.deleteSlideMark(id)
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("删除对象（⌘⌫）")
            }

            if mark.kind == "text" || mark.kind == "label" {
                TextEditor(text: textBinding(id))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 80, maxHeight: 150)
                    .background(tileBackground(p))
                    .id(id) // 切换对象时重建，避免把输入写到别的对象

                Stepper(value: fontSizeBinding(id), in: 9...72, step: 1) {
                    propertyLabel("字号", "\(Int(mark.fontSize.rounded())) pt", p)
                }
            }

            if mark.kind == "arrow" { Button("转向箭头") { model.rotateSlideArrow(id) } }
            if mark.kind == "image" {
                Text("图片保持原样，可移动和缩放。")
                    .font(.caption)
                    .foregroundColor(p.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("颜色").font(.caption).foregroundColor(p.secondary)
                    HStack(spacing: 10) {
                        ForEach(slideMarkColors, id: \.hex) { item in
                            colorSwatch(item.hex, item.name,
                                        selected: mark.color.uppercased() == item.hex.uppercased(),
                                        p) {
                                model.updateSlideMark(id: id, color: item.hex)
                            }
                        }
                    }
                }
            }

            Stepper(value: sizeBinding(id, \.width), in: 20...2000, step: 10) {
                propertyLabel("宽", "\(Int(mark.width.rounded()))", p)
            }
            Stepper(value: sizeBinding(id, \.height), in: 20...2000, step: 10) {
                propertyLabel("高", "\(Int(mark.height.rounded()))", p)
            }

            nudgePad(id, p)
        }
        .padding(12)
        .background(tileBackground(p))
    }

    private func propertyLabel(_ title: String, _ value: String, _ p: SlidePalette) -> some View {
        HStack {
            Text(title).foregroundColor(p.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func colorSwatch(_ hex: String, _ name: String, selected: Bool, _ p: SlidePalette,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(slideHexColor(hex))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(selected ? p.ink : p.line, lineWidth: selected ? 2 : 1)
                        .padding(-3)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func nudgePad(_ id: String, _ p: SlidePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("位置微调").font(.caption).foregroundColor(p.secondary)
                Spacer()
                Picker("步长", selection: $nudgeStep) {
                    Text("1").tag(1.0)
                    Text("5").tag(5.0)
                    Text("20").tag(20.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    nudgeButton("chevron.up", "上移", p) { model.moveSlideMark(id: id, dx: 0, dy: nudgeStep) }
                    HStack(spacing: 4) {
                        nudgeButton("chevron.left", "左移", p) { model.moveSlideMark(id: id, dx: -nudgeStep, dy: 0) }
                        nudgeButton("chevron.down", "下移", p) { model.moveSlideMark(id: id, dx: 0, dy: -nudgeStep) }
                        nudgeButton("chevron.right", "右移", p) { model.moveSlideMark(id: id, dx: nudgeStep, dy: 0) }
                    }
                }
                Spacer()
            }
        }
    }

    private func nudgeButton(_ symbol: String, _ help: String, _ p: SlidePalette,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(p.accent)
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(p.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(p.line, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 绑定（按 id 读写，只作用于该对象）

    private func currentMark(_ id: String) -> SlideMark? {
        model.currentSlideMarks.first { $0.id == id }
    }

    private func textBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { currentMark(id)?.text ?? "" },
            set: { newValue in
                guard currentMark(id) != nil else { return }
                model.updateSlideMark(id: id, text: newValue)
            }
        )
    }

    private func fontSizeBinding(_ id: String) -> Binding<Double> {
        Binding(
            get: { currentMark(id)?.fontSize ?? 16 },
            set: { model.updateSlideMark(id: id, fontSize: $0) }
        )
    }

    private func sizeBinding(_ id: String, _ key: KeyPath<SlideMark, Double>) -> Binding<Double> {
        Binding(
            get: { currentMark(id)?[keyPath: key] ?? 20 },
            set: { newValue in
                let v = min(max(newValue, 20), 2000)
                if key == \SlideMark.width {
                    model.updateSlideMark(id: id, width: v)
                } else {
                    model.updateSlideMark(id: id, height: v)
                }
            }
        )
    }

    // MARK: 空状态 / 底栏

    private func emptyDocument(_ p: SlidePalette) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 28))
                .foregroundColor(p.secondary)
            Text("先打开一份课件")
                .font(.callout)
            Text("PPT 会转换为 PDF 副本后再批注，原文件保持不变。")
                .font(.caption)
                .foregroundColor(p.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func footer(_ p: SlidePalette) -> some View {
        VStack(spacing: 6) {
            Button {
                model.exportMarkedPDF()
            } label: {
                Label("导出含批注的 PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(p.accent)
            .disabled(!hasDocument)

            Text("包含批注与页尾新增讲解页，原始 PPT 不变")
                .font(.caption2)
                .foregroundColor(p.secondary)
        }
        .padding(14)
    }

    private func sectionTitle(_ title: String, _ p: SlidePalette) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(p.ink)
    }
}
