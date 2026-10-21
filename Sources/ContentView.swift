import SwiftUI
import AppKit

// MARK: - Palette

private struct ShiyePalette {
    let background: Color
    let sidebar: Color
    let card: Color
    let ink: Color
    let secondary: Color
    let tertiary: Color
    let hairline: Color
    let accent: Color
    let accentSoft: Color
    let isDark: Bool

    static let themes = ["纸白", "暖纸", "夜读"]

    static func forTheme(_ theme: String) -> ShiyePalette {
        switch theme {
        case "暖纸":
            return ShiyePalette(
                background: Color(shiyeHex: 0xF4EDDE), sidebar: Color(shiyeHex: 0xECE3D0), card: Color(shiyeHex: 0xF9F4E8),
                ink: Color(shiyeHex: 0x2D271F), secondary: Color(shiyeHex: 0x645949), tertiary: Color(shiyeHex: 0x8A7E69),
                hairline: Color(shiyeHex: 0xDACDB4), accent: Color(shiyeHex: 0x52704C), accentSoft: Color(shiyeHex: 0x52704C, alpha: 0.13),
                isDark: false)
        case "夜读":
            return ShiyePalette(
                background: Color(shiyeHex: 0x1B1C1A), sidebar: Color(shiyeHex: 0x222320), card: Color(shiyeHex: 0x2A2B28),
                ink: Color(shiyeHex: 0xE4E0D6), secondary: Color(shiyeHex: 0xABA69B), tertiary: Color(shiyeHex: 0x87837A),
                hairline: Color(shiyeHex: 0x393A36), accent: Color(shiyeHex: 0x93B496), accentSoft: Color(shiyeHex: 0x93B496, alpha: 0.16),
                isDark: true)
        default:
            return ShiyePalette(
                background: Color(shiyeHex: 0xF9F8F4), sidebar: Color(shiyeHex: 0xF2F0EA), card: Color(shiyeHex: 0xFFFFFF),
                ink: Color(shiyeHex: 0x24221F), secondary: Color(shiyeHex: 0x625D55), tertiary: Color(shiyeHex: 0x8A847A),
                hairline: Color(shiyeHex: 0xE2DED5), accent: Color(shiyeHex: 0x55735B), accentSoft: Color(shiyeHex: 0x55735B, alpha: 0.12),
                isDark: false)
        }
    }
}

fileprivate extension Color {
    init(shiyeHex hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

private enum InkMark {
    static let all = ["yellow", "green", "blue", "pink"]

    static func color(_ name: String) -> Color {
        switch name {
        case "green": return Color(shiyeHex: 0x9CB88C)
        case "blue": return Color(shiyeHex: 0x8EAFCB)
        case "pink": return Color(shiyeHex: 0xDFA2AE)
        default: return Color(shiyeHex: 0xE5C46A)
        }
    }

    static func label(_ name: String) -> String {
        switch name {
        case "green": return L("绿色")
        case "blue": return L("蓝色")
        case "pink": return L("粉色")
        default: return L("黄色")
        }
    }
}

private enum LibraryFilters {
    static let all = ["全部", "未读", "读完", "归档"]
}

private enum DocMeta {
    static func kindLabel(_ doc: ReaderDocument) -> String {
        if doc.isWelcome { return L("指南") }
        switch doc.kind {
        case "pdf": return "PDF"
        case "epub": return "EPUB"
        case "html": return L("网页")
        case "markdown": return "Markdown"
        case "text": return L("文本")
        default: return L("文档")
        }
    }

    static func kindIcon(_ doc: ReaderDocument) -> String {
        if doc.isWelcome { return "bookmark" }
        switch doc.kind {
        case "pdf": return "doc.richtext"
        case "epub": return "book.closed"
        case "html": return "globe"
        case "markdown": return "text.alignleft"
        case "text": return "doc.plaintext"
        default: return "doc"
        }
    }

    static func origin(_ doc: ReaderDocument) -> String {
        if doc.isWelcome { return L("伴读") }
        if let source = doc.sourceURL, let host = URL(string: source)?.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return L("本地文件")
    }

    static func progressText(_ progress: Double) -> String {
        if progress <= 0.005 { return L("未读") }
        if progress >= 0.99 { return L("读完") }
        return "\(Int((progress * 100).rounded()))%"
    }

    static func percent(_ progress: Double) -> String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.locale
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.locale=AppLanguage.locale; formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    static func when(_ date: Date) -> String {
        relative.locale=AppLanguage.locale;day.locale=AppLanguage.locale;day.setLocalizedDateFormatFromTemplate("MMMd")
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func shortDate(_ date: Date) -> String {
        day.locale=AppLanguage.locale;day.setLocalizedDateFormatFromTemplate("MMMd")
        return day.string(from: date)
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var sidebarVisible = true
    @ObservedObject private var layout: PaneLayout

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _layout = ObservedObject(wrappedValue: model.layout)
    }

    var body: some View {
        let palette = ShiyePalette.forTheme(model.theme)
        GeometryReader { geometry in
            let total = geometry.size.width
            let right: PaneLayout.Pane? = model.showNotes ? ((model.showTutor || model.slideEditing) ? .tutor : .notes) : nil
            let widths = layout.widths(total: total, libraryVisible: sidebarVisible, right: right)
            HStack(spacing: 0) {
                if sidebarVisible {
                    LibrarySidebar(model: model, palette: palette)
                        .frame(width: widths.library)
                    resizeHandle(.library, title: L("书房宽度"), width: widths.library, total: total, right: right, palette: palette)
                }
                ReaderColumn(model: model, palette: palette, sidebarVisible: $sidebarVisible)
                    .frame(width: widths.reader)
                    .frame(maxHeight: .infinity)
                if let right {
                    resizeHandle(right, title: model.slideEditing ? L("课件工具宽度") : (model.showTutor ? L("老师宽度") : L("批注宽度")), width: widths.right, total: total, right: right, palette: palette)
                    Group { if model.slideEditing { SlideInspector(model:model) } else if model.showTutor { TeacherPanel(model:model) } else { NotesInspector(model: model, palette: palette) } }
                        .frame(width: widths.right)
                }
            }
            .frame(width: total, height: geometry.size.height)
        }
        .frame(minHeight: 560)
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .tint(palette.accent)
        .navigationTitle(model.selectedDocument?.title ?? L("伴读"))
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet(model: model, palette: palette)
                .preferredColorScheme(palette.isDark ? .dark : .light)
        }
        .sheet(isPresented: $model.showURLImport) {
            URLImportSheet(model: model, palette: palette)
                .preferredColorScheme(palette.isDark ? .dark : .light)
        }
        .onChange(of: model.showSettings) { isOpen in
            if !isOpen { model.saveSettings() }
        }
        .onChange(of: model.theme) { _ in model.saveSettings() }
        .onChange(of: model.fontSize) { _ in model.saveSettings() }
        .onChange(of: model.autoSync) { _ in model.saveSettings() }
        .alert(L("出了点问题"), isPresented: errorBinding) {
            Button(L("好")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func resizeHandle(_ pane: PaneLayout.Pane, title: String, width: CGFloat, total: CGFloat, right: PaneLayout.Pane?, palette: ShiyePalette) -> some View {
        PaneDivider(lineColor: palette.hairline, accentColor: palette.accent, label: title, valueDescription: L("{0} 点", String(describing: Int(width))), accessibilityDirection: pane == .library ? 1 : -1,
            onDelta: { delta in
                layout.adjust(pane, by: pane == .library ? delta : -delta, total: total, libraryVisible: sidebarVisible, right: right)
            }, onReset: { layout.reset(pane) }, onDragEnded: { layout.save() })
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct Hairline: View {
    let palette: ShiyePalette
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - Library sidebar

private struct LibrarySidebar: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(model: model, palette: palette)
            SidebarSearchField(text: $model.search, palette: palette)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            Picker(L("筛选"), selection: $model.filter) {
                ForEach(LibraryFilters.all, id: \.self) { Text(L($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Hairline(palette: palette)
            DocumentList(model: model, palette: palette)
            Hairline(palette: palette)
            SidebarFooter(model: model, palette: palette)
        }
        .background(palette.sidebar)
    }
}

private struct SidebarHeader: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment:.leading,spacing:2) {
                Text(L("伴读"))
                    .font(.system(size:20,weight:.semibold,design:.serif))
                    .foregroundColor(palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                Text(L("本地书房")).font(.system(size:11)).foregroundColor(palette.tertiary)
            }
            Spacer(minLength: 4)
            ToolIcon(symbol: "link", help: L("保存网页文章"), palette: palette) {
                model.showURLImport = true
            }
            ToolIcon(symbol: "plus", help: L("导入文件 (⌘O)"), palette: palette) {
                model.importFiles()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String
    let palette: ShiyePalette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.tertiary)
            TextField(L("搜索标题"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(palette.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("清除搜索"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairline, lineWidth: 1))
    }
}

private struct DocumentList: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        let docs = model.visibleDocuments
        Group {
            if docs.isEmpty {
                LibraryEmptyState(model: model, palette: palette)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(docs) { doc in
                            DocumentRow(doc: doc, selected: doc.id == model.selectedID, palette: palette) {
                                model.selectDocument(doc.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DocumentRow: View {
    let doc: ReaderDocument
    let selected: Bool
    let palette: ShiyePalette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: DocMeta.kindIcon(doc))
                    .font(.system(size: 12))
                    .foregroundColor(selected ? palette.accent : palette.tertiary)
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.title.isEmpty ? L("未命名") : doc.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundColor(palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(DocMeta.kindLabel(doc))
                        Text("·")
                        Text(DocMeta.when(doc.lastOpenedAt)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(DocMeta.progressText(doc.progress)).monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(palette.tertiary)
                    ProgressHairline(progress: doc.progress, palette: palette)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(rowFill))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if selected { return palette.accentSoft }
        return hovering ? palette.hairline.opacity(0.45) : Color.clear
    }
}

private struct ProgressHairline: View {
    let progress: Double
    let palette: ShiyePalette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.hairline)
                Capsule()
                    .fill(palette.accent.opacity(0.75))
                    .frame(width: CGFloat(min(max(progress, 0), 1)) * geo.size.width)
            }
        }
        .frame(height: 2)
    }
}

private struct LibraryEmptyState: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(palette.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.secondary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(palette.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if showsImport {
                HStack(spacing: 8) {
                    Button(L("导入文件")) { model.importFiles() }
                    Button(L("保存网页")) { model.showURLImport = true }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var query: String { model.search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !query.isEmpty }
    private var showsImport: Bool { model.library.isEmpty && !searching }

    private var icon: String {
        if searching { return "magnifyingglass" }
        return model.library.isEmpty ? "books.vertical" : "tray"
    }

    private var title: String {
        if searching { return L("没有找到“{0}”", String(describing: query)) }
        if model.library.isEmpty { return L("书房还是空的") }
        switch model.filter {
        case "未读": return L("没有未读的文档")
        case "读完": return L("还没有读完的文档")
        case "归档": return L("归档是空的")
        default: return L("这里没有文档")
        }
    }

    private var detail: String {
        if searching { return L("换个关键词，或切换到“全部”。") }
        if model.library.isEmpty { return L("导入 PDF、EPUB、Markdown 或文本文件，也可以保存一篇网页文章。") }
        if model.filter == "归档" { return L("不想再出现在书房里的文档，可以从“更多”菜单归档。") }
        return L("切换到“全部”查看其他文档。")
    }
}

private struct SidebarFooter: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.vaultPath.isEmpty ? palette.tertiary.opacity(0.6) : palette.accent)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("Obsidian")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.secondary)
                Text(syncLine)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            ToolIcon(symbol: "arrow.triangle.2.circlepath", help: L("立即同步到 Obsidian"), palette: palette) {
                model.syncNow()
            }
            .disabled(model.vaultPath.isEmpty || model.busy)
            ToolIcon(symbol: "gearshape", help: L("设置"), palette: palette) {
                model.showSettings = true
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 46)
    }

    private var syncLine: String {
        if model.vaultPath.isEmpty { return L("未连接 · 在设置中选择库") }
        if !model.syncStatus.isEmpty { return model.syncStatus }
        return model.autoSync ? L("自动同步已开启") : L("手动同步")
    }
}

// MARK: - Reader column

private struct ReaderColumn: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette
    @Binding var sidebarVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            ReaderHeader(model: model, palette: palette, sidebarVisible: $sidebarVisible)
            Hairline(palette: palette)
            Group {
                if model.selectedDocument != nil {
                    ReaderSurface(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ReaderPlaceholder(model: model, palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            Hairline(palette: palette)
            StatusBar(model: model, palette: palette)
        }
    }
}

private struct ReaderHeader: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette
    @Binding var sidebarVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            TitleRow(model: model, palette: palette)
                .frame(height: 46)
            ToolRow(model: model, palette: palette, sidebarVisible: $sidebarVisible)
                .frame(height: 36)
        }
        .padding(.horizontal, 14)
        .background(palette.background)
    }
}

private struct TitleRow: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.tertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            Spacer(minLength: 12)
            if let doc = model.selectedDocument {
                ReadingPosition(pageLabel: model.pageLabel, progress: doc.progress, palette: palette)
            }
        }
        .padding(.top, 6)
    }

    private var title: String {
        guard let doc = model.selectedDocument else { return L("伴读") }
        return doc.title.isEmpty ? L("未命名") : doc.title
    }

    private var subtitle: String {
        guard let doc = model.selectedDocument else { return L("选择一份文档开始阅读") }
        var parts = [DocMeta.kindLabel(doc), DocMeta.origin(doc)]
        if doc.archived { parts.append(L("已归档")) }
        return parts.joined(separator: " · ")
    }
}

private struct ReadingPosition: View {
    let pageLabel: String
    let progress: Double
    let palette: ShiyePalette

    var body: some View {
        HStack(spacing: 8) {
            if !pageLabel.isEmpty {
                Text(pageLabel)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            ProgressHairline(progress: progress, palette: palette)
                .frame(width: 60)
            Text(DocMeta.percent(progress))
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)
        }
        .font(.system(size: 11.5))
        .foregroundColor(palette.secondary)
        .fixedSize()
        .help(L("阅读位置"))
    }
}

private struct ToolRow: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette
    @Binding var sidebarVisible: Bool
    @State private var showFind = false

    var body: some View {
        let hasDocument = model.selectedDocument != nil
        HStack(spacing: 8) {
            ToolIcon(symbol: "sidebar.left", help: sidebarVisible ? L("隐藏书房") : L("显示书房"), active: sidebarVisible, palette: palette) {
                sidebarVisible.toggle()
            }
            ToolSeparator(palette: palette)
            HighlightControl(model: model, palette: palette)
                .disabled(!hasDocument)
            ToolSeparator(palette: palette)
            ToolIcon(symbol: "magnifyingglass", help: L("在本文中查找 (⌘F)"), active: showFind, palette: palette) {
                showFind.toggle()
            }
            .keyboardShortcut("f")
            .popover(isPresented: $showFind, arrowEdge: .bottom) {
                FindPopover(model: model)
            }
            .disabled(!hasDocument)
            FontSizeControl(model: model, palette: palette)
                .disabled(!hasDocument)
            // 插入位置：FontSizeControl 之后、Spacer(minLength: 6) 之前
            ToolSeparator(palette: palette)
            if model.selectedDocument?.kind == "pdf" {
                ToolIcon(symbol: "pencil.tip.crop.circle", help: L("在课件上编辑批注、新增讲解页并导出 PDF"), active: model.slideEditing, palette: palette) {
                    if model.slideEditing { model.slideEditing=false } else { model.enterSlideEditing() }
                }
                ToolIcon(symbol: "viewfinder", help: model.boxSelection ? L("退出框图") : L("框图：在 PDF 上框出公式、图表或段落"), active: model.boxSelection, palette: palette) {
                    if model.boxSelection { model.boxSelection=false } else { model.startBoxSelection() }
                }
                .disabled(!hasDocument)
            }
            Button {
                model.askTeacher()
            } label: {
                Label(L("问老师"), systemImage: "graduationcap")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L("问老师：讲解当前选区，没有选区时讲当前页/文章"))
            .disabled(!hasDocument)
            ToolIcon(symbol: "person.crop.rectangle", help: model.showTutor ? L("收起老师") : L("打开老师"), active: model.showTutor && model.showNotes, palette: palette) {
                model.showTutor.toggle()
                model.showNotes = true
            }
            Spacer(minLength: 6)
            ThemeMenu(model: model)
            ToolSeparator(palette: palette)
            MoreMenu(model: model)
            ToolIcon(symbol: "sidebar.right", help: model.showNotes ? L("隐藏笔记") : L("显示笔记"), active: model.showNotes, palette: palette) {
                model.showNotes.toggle()
            }
        }
        .padding(.bottom, 4)
    }
}

private struct ToolIcon: View {
    let symbol: String
    let help: String
    var active = false
    let palette: ShiyePalette
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(active ? .white : palette.secondary)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color(red:0.29,green:0.39,blue:0.31) : hovering && isEnabled ? palette.hairline.opacity(0.6) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help(help)
        .accessibilityAddTraits(active ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

private struct ToolSeparator: View {
    let palette: ShiyePalette

    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(width: 1, height: 16)
    }
}

private struct ColorDot: View {
    let name: String
    let selected: Bool
    var size: CGFloat = 11
    let palette: ShiyePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(InkMark.color(name))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(palette.ink.opacity(selected ? 0.65 : 0), lineWidth: 1.5)
                        .padding(-2.5)
                )
                .frame(width: size + 8, height: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(InkMark.label(name))
    }
}

private struct HighlightControl: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let canMark = !model.selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 6) {
            Button { model.addHighlight() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "highlighter")
                    Text(L("划线"))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(canMark ? palette.ink : palette.tertiary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(canMark ? InkMark.color(model.highlightColor).opacity(palette.isDark ? 0.32 : 0.45) : palette.hairline.opacity(0.5))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canMark)
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .help(canMark ? L("为选中的文字划线 (⇧⌘H)") : L("先在正文中选中一段文字"))
            HStack(spacing: 0) {
                ForEach(InkMark.all, id: \.self) { name in
                    ColorDot(name: name, selected: model.highlightColor == name, size: 10, palette: palette) {
                        model.highlightColor = name
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct FontSizeControl: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        HStack(spacing: 0) {
            ToolIcon(symbol: "textformat.size.smaller", help: L("缩小字号 (⌘-)"), palette: palette) {
                model.readerZoom(-1)
            }
            .keyboardShortcut("-")
            Text("\(Int(model.fontSize.rounded()))")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundColor(palette.secondary)
                .frame(width: 22)
                .help(L("字号"))
            ToolIcon(symbol: "textformat.size.larger", help: L("放大字号 (⌘=)"), palette: palette) {
                model.readerZoom(1)
            }
            .keyboardShortcut("=")
        }
    }
}

private struct ThemeMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Menu {
            Picker(L("阅读主题"), selection: $model.theme) {
                ForEach(ShiyePalette.themes, id: \.self) { Text(L($0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(L(model.theme), systemImage: "circle.lefthalf.filled")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("阅读主题"))
    }
}

private struct MoreMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let doc = model.selectedDocument
        Menu {
            Button(doc?.sourceURL == nil ? L("打开原文件") : L("打开原网页")) { model.openSource() }
                .disabled(doc == nil || doc?.isWelcome == true)
            Button(doc?.archived == true ? L("移出归档") : L("归档")) { model.archiveSelected() }
                .disabled(doc == nil)
            Divider()
            Button(L("同步到 Obsidian")) { model.syncNow() }
                .disabled(model.vaultPath.isEmpty)
            Button(L("在访达中显示资料")) { model.revealDataFolder() }
            Divider()
            Button(L("设置…")) { model.showSettings = true }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("更多"))
    }
}

@MainActor
private struct FindPopover: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L("在本文中查找"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { run() }
                    .frame(width: 200)
                Button(L("查找")) { run() }
                    .disabled(trimmed.isEmpty)
            }
            Text(L("按回车跳到下一处"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func run() {
        guard !trimmed.isEmpty else { return }
        model.findInDocument(trimmed)
    }
}

private struct ReaderPlaceholder: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        VStack(spacing: 12) {
            Text(L("伴读"))
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundColor(palette.ink)
            Text(model.library.isEmpty ? L("拾起每一页值得细读的文字。") : L("从左侧书房选择一份文档，继续读下去。"))
                .font(.system(size: 14, design: .serif))
                .foregroundColor(palette.secondary)
            HStack(spacing: 10) {
                Button { model.importFiles() } label: {
                    Label(L("导入文件"), systemImage: "doc.badge.plus")
                }
                Button { model.showURLImport = true } label: {
                    Label(L("保存网页文章"), systemImage: "link")
                }
            }
            .controlSize(.large)
            .padding(.top, 8)
            Text(L("文档、划线与笔记都只保存在这台 Mac 上。"))
                .font(.system(size: 11.5))
                .foregroundColor(palette.tertiary)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatusBar: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        HStack(spacing: 8) {
            if model.busy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            }
            Text(model.status.isEmpty ? L("就绪") : model.status)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if model.totalHighlights > 0 {
                Text(L("共 {0} 条划线", String(describing: model.totalHighlights)))
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Image(systemName: "lock")
                    .font(.system(size: 9.5))
                Text(L("本地保存"))
            }
            .help(L("所有内容只保存在这台 Mac 上"))
        }
        .font(.system(size: 11))
        .foregroundColor(palette.tertiary)
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(palette.background)
    }
}

// MARK: - Notes inspector

private struct NotesInspector: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("笔记类型"), selection: $model.showStudyNotes) {
                Text(L("学习笔记")).tag(true)
                Text(L("划线批注")).tag(false)
            }.pickerStyle(.segmented).labelsHidden().padding(10)
            if model.showStudyNotes { StudyNotesView(model: model, compact: true) }
            else { annotations }
        }.background(palette.sidebar)
    }
    private var annotations: some View {
        let items = model.currentHighlights
        return VStack(spacing: 0) {
            NotesHeader(count: items.count, hasDocument: model.selectedDocument != nil, palette: palette)
                .frame(height: 82)
            Hairline(palette: palette)
            if items.isEmpty {
                NotesEmptyState(hasDocument: model.selectedDocument != nil, palette: palette)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(items) { highlight in
                                HighlightCard(
                                    model: model,
                                    highlight: highlight,
                                    palette: palette,
                                    isSelected: model.selectedHighlightID == highlight.id
                                )
                                .id(highlight.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: model.selectedHighlightID) { id in
                        guard let id = id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
    }
}

private struct NotesHeader: View {
    let count: Int
    let hasDocument: Bool
    let palette: ShiyePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("笔记"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(palette.ink)
                Spacer()
                if hasDocument {
                    Text(L("{0} 条划线", String(describing: count)))
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundColor(palette.secondary)
                }
            }
            Text(L("选中文字后按 ⇧⌘H 划线 · 笔记自动保存"))
                .font(.system(size: 11))
                .foregroundColor(palette.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotesEmptyState: View {
    let hasDocument: Bool
    let palette: ShiyePalette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "highlighter")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(palette.tertiary)
            Text(hasDocument ? L("还没有划线") : L("没有打开的文档"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.secondary)
            Text(hasDocument
                 ? L("在正文中选中一段文字，按 ⇧⌘H 或点击“划线”。\n划线和你的想法会收在这里，也可以同步到 Obsidian。")
                 : L("打开一份文档后，这里会收集你的划线与想法。"))
                .font(.system(size: 11.5))
                .foregroundColor(palette.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct HighlightCard: View {
    let model: AppModel
    let highlight: Highlight
    let palette: ShiyePalette
    let isSelected: Bool

    @State private var note: String
    @State private var tags: String
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var deleted = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case note, tags }

    init(model: AppModel, highlight: Highlight, palette: ShiyePalette, isSelected: Bool) {
        self.model = model
        self.highlight = highlight
        self.palette = palette
        self.isSelected = isSelected
        _note = State(initialValue: highlight.note)
        _tags = State(initialValue: highlight.tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            quoteBlock
            noteEditor
            tagsField
            footer
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? palette.accent.opacity(0.7) : palette.hairline, lineWidth: isSelected ? 1.5 : 1)
        )
        .onChange(of: highlight.note) { newValue in
            if focus != .note && newValue != note { note = newValue }
        }
        .onChange(of: highlight.tags) { newValue in
            if focus != .tags && newValue != tags { tags = newValue }
        }
        .onChange(of: note) { _ in scheduleSave() }
        .onChange(of: tags) { _ in scheduleSave() }
        .onChange(of: focus) { _ in commit() }
        .onDisappear { commit() }
        .confirmationDialog(L("删除这条划线？"), isPresented: $confirmDelete) {
            Button(L("删除"), role: .destructive) {
                deleted = true
                saveTask?.cancel()
                model.deleteHighlight(highlight.id)
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("划线和它的笔记会一起删除，无法撤销。"))
        }
    }

    private var quoteBlock: some View {
        Button { model.goToHighlight(highlight) } label: {
            Text(highlight.quote)
                .font(.system(size: 13, design: .serif))
                .foregroundColor(palette.ink)
                .lineSpacing(3)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 11)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(InkMark.color(highlight.color))
                        .frame(width: 3)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("回到原文位置"))
    }

    private var fieldFill: Color {
        palette.background.opacity(palette.isDark ? 0.6 : 0.85)
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $note)
                .font(.system(size: 12.5))
                .foregroundColor(palette.ink)
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .note)
                .padding(.horizontal, 3)
                .padding(.vertical, 5)
            if note.isEmpty {
                Text(L("写下想法…"))
                    .font(.system(size: 12.5))
                    .foregroundColor(palette.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 54, idealHeight: 72, maxHeight: 140)
        .background(RoundedRectangle(cornerRadius: 6).fill(fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(focus == .note ? palette.accent.opacity(0.6) : palette.hairline, lineWidth: 1)
        )
    }

    private var tagsField: some View {
        HStack(spacing: 6) {
            Image(systemName: "number")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(palette.tertiary)
            TextField(L("标签，用空格分隔"), text: $tags)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(palette.ink)
                .focused($focus, equals: .tags)
                .onSubmit { commit() }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(focus == .tags ? palette.accent.opacity(0.6) : palette.hairline, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(InkMark.all, id: \.self) { name in
                    ColorDot(name: name, selected: highlight.color == name, size: 9, palette: palette) {
                        model.setHighlightColor(highlight.id, color: name)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(meta)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundColor(palette.tertiary)
                .lineLimit(1)
            ToolIcon(symbol: "arrow.uturn.backward", help: L("回到原文"), palette: palette) {
                model.goToHighlight(highlight)
            }
            ToolIcon(symbol: "trash", help: L("删除划线"), palette: palette) {
                confirmDelete = true
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let page = highlight.page { parts.append(L("第 {0} 页", String(describing: page + 1))) }
        parts.append(DocMeta.shortDate(highlight.createdAt))
        return parts.joined(separator: " · ")
    }

    private var isDirty: Bool {
        note != highlight.note || tags != highlight.tags
    }

    private func scheduleSave() {
        // Persist locally immediately; only the Obsidian export is debounced.
        commit()
    }

    private func commit() {
        saveTask?.cancel()
        saveTask = nil
        guard !deleted, isDirty else { return }
        model.updateHighlight(id: highlight.id, note: note, tags: tags)
    }
}

// MARK: - Sheets

private struct SettingsSection<Content: View>: View {
    let title: String
    let palette: ShiyePalette
    let content: Content

    init(title: String, palette: ShiyePalette, @ViewBuilder content: () -> Content) {
        self.title = title
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.tertiary)
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline, lineWidth: 1))
        }
        .padding(.bottom, 16)
    }
}

private struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("设置"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(palette.ink)
                .padding(.bottom, 18)
            SettingsSection(title: "语言 / Language", palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L("语言"), selection: Binding(get:{model.language},set:{model.setLanguage($0)})) {
                        Text(L("跟随系统")).tag("system")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(L("界面和新讲解使用所选语言；已有课件、笔记与对话保留原文。"))
                        .font(.system(size:11.5)).foregroundColor(palette.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                }
            }
            SettingsSection(title: L("OBSIDIAN 同步"), palette: palette) {
                VaultSettings(model: model, palette: palette)
            }
            SettingsSection(title: L("本地数据"), palette: palette) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button { model.exportBackup() } label: {
                            Label(L("导出备份…"), systemImage: "archivebox")
                        }
                        Button { model.revealDataFolder() } label: {
                            Label(L("在访达中显示"), systemImage: "folder")
                        }
                    }
                    Text(L("阅读和笔记保存在这台 Mac 上。问老师时，相关文字与图片会发给所选模型，使用现有订阅额度。保存网页时会下载文章。"))
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(L("完成")) { model.showSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 500)
        .background(palette.background)
        .onChange(of: model.vaultPath) { _ in model.saveSettings() }
    }
}

private struct VaultSettings: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(palette.tertiary)
                Text(model.vaultPath.isEmpty ? L("尚未选择 Obsidian 库") : model.vaultPath)
                    .font(.system(size: 12))
                    .foregroundColor(model.vaultPath.isEmpty ? palette.tertiary : palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button(model.vaultPath.isEmpty ? L("选择库…") : L("更换…")) { model.chooseVault() }
            }
            Toggle(L("划线或修改笔记后自动同步"), isOn: $model.autoSync)
                .toggleStyle(.checkbox)
                .disabled(model.vaultPath.isEmpty)
            HStack(alignment: .center, spacing: 8) {
                Text(model.syncStatus.isEmpty ? L("划线与笔记会以 Markdown 文件写入所选的库。") : model.syncStatus)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(L("立即同步")) { model.syncNow() }
                    .disabled(model.vaultPath.isEmpty || model.busy)
            }
        }
    }
}

@MainActor
private struct URLImportSheet: View {
    @ObservedObject var model: AppModel
    let palette: ShiyePalette
    @State private var submitting = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(palette.accent)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("保存网页文章"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.ink)
                    Text(L("伴读会提取正文并保存在本地，之后离线也能阅读和划线。"))
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("https://", text: $model.importURLText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($fieldFocused)
                .onSubmit { submit() }
                .disabled(working)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                Text(L("仅适用于公开文章。需要登录或付费才能查看的页面无法读取。"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5))
            .foregroundColor(palette.tertiary)
            HStack(spacing: 8) {
                if working {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("正在保存…"))
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondary)
                }
                Spacer()
                Button(L("取消")) { model.showURLImport = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("保存")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 460)
        .background(palette.background)
        .onAppear {
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    private var working: Bool { submitting || model.busy }

    private var canSubmit: Bool {
        !working && !model.importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        submitting = true
        Task {
            await model.importWebURL()
            submitting = false
        }
    }
}
