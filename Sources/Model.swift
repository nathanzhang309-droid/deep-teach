import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct SelectionAnchor:Codable {var quote:String;var regions:[PDFRegion]=[];var start:Int?;var end:Int?;var prefix:String?;var suffix:String?}
@MainActor final class AppModel:ObservableObject {
    static var shared:AppModel!
    @Published var slideEdits=SlideArchive();@Published var slideEditing=false;@Published var selectedSlideMarkID:String?;@Published var slideRevision=0
    var slideUndo:[String:[SlideProject]]=[:];var slideRedo:[String:[SlideProject]]=[:];var slideImageCache:[String:NSImage]=[:];var slidesWritable=true
    @Published var study=StudyArchive(); @Published var studyStatus="讲解结束后自动记录，持续整理你的学习笔记"
    @Published var studyBusy=false; @Published var showStudyNotes=true
    @Published var studyReviewRequest=UUID();var studyReviewTopicID:String?
    var studyProcess:TeacherProcess?; var studyManualDocument:String?;var studyWritable=true;var studyWindow:NSWindow?
    @Published var selectedImageRegion:PDFRegion?;@Published var selectionRequest=UUID();
    @Published var showTutor=false; @Published var boxSelection=false
    @Published var tutorBusy=false; @Published var tutorStatus="选中文字或框住图表，再问老师"
    @Published var tutorRevision=0; @Published var tutorProvider="codex"; @Published var tutorLevel="学过但模糊"
    var teaching=TeachingArchive(); var teacherProcess:TeacherProcess?
    var selectedImage:String?; var selectedImagePage:Int?
    weak var activePDF:PDFView?

    @Published var library:[ReaderDocument]=[];@Published var highlights:[Highlight]=[]
    @Published var selectedID:String?;@Published var search="";@Published var filter="全部";@Published var status="所有资料仅保存在本机";@Published var busy=false
    @Published var showSettings=false;@Published var showURLImport=false;@Published var importURLText="";@Published var showNotes=true
    @Published var theme="纸白";@Published var fontSize:Double=19;@Published var selectionText="";@Published var highlightColor="yellow";@Published var selectedHighlightID:String?
    @Published var vaultPath="";@Published var autoSync=true;@Published var syncStatus="尚未同步";@Published var pageLabel="";@Published var errorMessage:String?
    @Published var readerRevision=0;@Published var jumpID:String?;@Published var commandID=UUID();var readerCommand="";var pending:SelectionAnchor?
    let layout:PaneLayout;let store:LibraryStore;let processor=ArticleProcessor();var syncTask:Task<Void,Never>?;var progressTask:Task<Void,Never>?
    var selectedDocument:ReaderDocument? {library.first{$0.id==selectedID}}
    var currentHighlights:[Highlight]{highlights.filter{$0.documentID==selectedID}.sorted{a,b in if a.page != b.page{return (a.page ?? 0)<(b.page ?? 0)};if a.start != b.start{return (a.start ?? 0)<(b.start ?? 0)};return a.createdAt<b.createdAt}}
    var totalHighlights:Int {highlights.count}
    var visibleDocuments:[ReaderDocument]{library.filter{d in
        let category=filter=="归档" ? d.archived : !d.archived && (filter=="未读" ? d.progress<0.95:filter=="读完" ? d.progress>=0.95:true)
        let match=search.isEmpty || d.title.localizedCaseInsensitiveContains(search) || highlights.contains{$0.documentID==d.id&&($0.quote.localizedCaseInsensitiveContains(search)||$0.note.localizedCaseInsensitiveContains(search)||$0.tags.localizedCaseInsensitiveContains(search))}
        return category&&match
    }.sorted{$0.lastOpenedAt>$1.lastOpenedAt}}
    init(store:LibraryStore){self.store=store;self.layout=PaneLayout(root:store.root);library=store.state.documents;highlights=store.state.highlights;let p=store.state.preferences;vaultPath=p.vaultPath;autoSync=p.autoSync;theme=p.theme;fontSize=p.fontSize;Self.shared=self
        if library.isEmpty {do{_ = try store.addArticle(title:"让读过的内容，成为自己的知识",html:Self.welcome,text:"欢迎使用伴读，本地阅读、划线批注、同步 Obsidian。",kind:"html",isWelcome:true);library=store.state.documents}catch{errorMessage=error.localizedDescription}}
        loadTeaching();loadStudy();loadSlides();selectedID=library.sorted{$0.lastOpenedAt>$1.lastOpenedAt}.first?.id;status=store.recoveryNotice ?? "资料已保存在本机"
    }
    static let welcome="""
    <p>一本书里打动你的句子，一篇文章里想反复琢磨的观点，都值得留在自己的知识库。</p>
    <h2>从一段划线开始</h2><p>用鼠标选中这段文字，然后点击上方的划线按钮，或按 ⌘⇧H。批注会出现在右侧，可以补上自己的理解、添加标签，再随时跳回原文。</p>
    <blockquote>阅读的价值，不只是看过多少，而是留下多少真正属于自己的理解。</blockquote>
    <h2>看不懂，问老师</h2><p>选中文字后点击「问老师」，或在 PDF 中点击「框图」再框住图表。老师支持追问、公式和测验；有用的回答可以存入批注并同步到 Obsidian。</p><h2>把资料带进来</h2><p>导入 PDF、EPUB、Markdown、文本或 HTML。也可以粘贴公开文章的网址，提取干净正文并保存到本机。打开后可断网阅读；长文记住阅读位置。</p>
    <h2>与你的 Obsidian 放在一起</h2><p>在设置里选择知识库。批注会自动同步到「Myknowledge / 2-Areas / 阅读笔记 / 拾页」。每条批注都带有回到原文的链接。</p><p>同步文件底部的「我的笔记」留给你自由书写。如果你改动了自动生成的内容，伴读会保留原文件，把新内容放到「待合并」，不会悄悄覆盖你的文字。</p>
    <h2>一切在本机</h2><p>阅读不需要账号、订阅或 API Key。阅读无需模型。提问时，相关文字与图片发送给你选择的 Claude 或 Codex，使用已有订阅额度。开启自动学习笔记时，同一订阅还会在后台整理已完成的问答；可在学习笔记中关闭。定期在设置里导出资料库备份，就能把原文和笔记一起带走。</p><p>现在，试着划下你喜欢的一句话。</p>
    """
    func selectDocument(_ id:String){slideEditing=false;selectedSlideMarkID=nil;selectedImage=nil;selectedImagePage=nil;selectedImageRegion=nil;boxSelection=false;selectedID=id;selectedHighlightID=nil;jumpID=nil;pending=nil;selectionText="";pageLabel="";if let i=library.firstIndex(where:{$0.id==id}){library[i].lastOpenedAt=Date()};persist(sync:false)}
    func persist(sync:Bool=true){store.state.documents=library;store.state.highlights=highlights;do{try store.save();status="已保存到本机";if sync&&autoSync{scheduleSync()}}catch{errorMessage="保存失败：\(error.localizedDescription)";status="保存失败，请先导出备份"}}
    func saveSettings(){fontSize=min(30,max(14,fontSize));store.state.preferences=Preferences(vaultPath:vaultPath,syncSubfolder:store.state.preferences.syncSubfolder,autoSync:autoSync,theme:theme,fontSize:fontSize);persist(sync:false);readerRevision+=1;if autoSync{scheduleSync()}}
    func scheduleSync(){syncTask?.cancel();syncTask=Task{try? await Task.sleep(nanoseconds:900_000_000);if !Task.isCancelled{syncNow()}}}
    func syncNow(){guard !vaultPath.isEmpty else{showSettings=true;return};do{store.state.documents=library;store.state.highlights=highlights;let r=try ObsidianSync().sync(state:store.state,vault:URL(fileURLWithPath:vaultPath),studyBlocks:studySyncBlocks);syncStatus=r.conflicts>0 ? "\(r.conflicts) 篇待合并，原文已保留":"已同步 · \(r.written) 篇更新";status=r.conflicts>0 ? "Obsidian 中有手写修改，新内容在拾页/待合并":"Obsidian 与本机批注已同步"}catch{syncStatus="同步未完成";status="同步未完成：\(error.localizedDescription)"}}
    func receiveSelection(_ anchor:SelectionAnchor?){selectedImage=nil;selectedImagePage=nil;selectedImageRegion=nil;pending=anchor;selectionText=anchor?.quote ?? ""}
    func clearImageSelection(){receiveSelection(nil);boxSelection=false;command("clearSelection");tutorStatus="选区已取消"}
    func startBoxSelection(){clearImageSelection();slideEditing=false;boxSelection=true;status="拖动框住想问的区域 · Esc 退出";activePDF?.window?.makeFirstResponder(activePDF?.subviews.compactMap{$0 as? BoxOverlay}.first)}
    func addHighlight(){guard let d=selectedDocument,let p=pending,!p.quote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        guard p.quote.count<=20000 else{errorMessage="选中的内容太长，请分段划线。";return}
        let h=Highlight(id:newID(),documentID:d.id,quote:p.quote,color:highlightColor,createdAt:Date(),page:p.regions.first?.page,regions:p.regions,start:p.start,end:p.end,prefix:p.prefix,suffix:p.suffix)
        highlights.append(h);selectedHighlightID=h.id;pending=nil;selectionText="";showNotes=true;showTutor=false;showStudyNotes=false;persist();readerRevision+=1;command("clearSelection")
    }
    func updateHighlight(id:String,note:String,tags:String){guard let i=highlights.firstIndex(where:{$0.id==id}) else{return};guard highlights[i].note != note || highlights[i].tags != tags else{return};highlights[i].note=note;highlights[i].tags=tags;persist()}
    func setHighlightColor(_ id:String,color:String){guard let i=highlights.firstIndex(where:{$0.id==id}),["yellow","green","blue","pink"].contains(color) else{return};highlights[i].color=color;persist();readerRevision+=1}
    func deleteHighlight(_ id:String){highlights.removeAll{$0.id==id};persist();readerRevision+=1}
    func goToHighlight(_ h:Highlight){if selectedID != h.documentID{selectDocument(h.documentID)};selectedHighlightID=h.id;showStudyNotes=false;jumpID=h.id;command("jump")}
    func command(_ value:String){readerCommand=value;commandID=UUID()}
    func readerZoom(_ delta:Int){if selectedDocument?.kind=="pdf"{command(delta>0 ? "zoomIn":"zoomOut")}else{fontSize=min(30,max(14,fontSize+Double(delta)));saveSettings()}}
    func findInDocument(_ query:String){command("find:"+query)}
    func markProgress(_ p:Double,page:Int?=nil){guard let i=library.firstIndex(where:{$0.id==selectedID}) else{return};library[i].progress=min(1,max(0,p));if let page{library[i].page=page;recordStudyPage(page+1)};progressTask?.cancel();progressTask=Task{try? await Task.sleep(nanoseconds:500_000_000);if !Task.isCancelled{persist(sync:false)}}}
    func archiveSelected(){guard let i=library.firstIndex(where:{$0.id==selectedID}) else{return};library[i].archived.toggle();persist(sync:false)}
    func openSource(){guard let s=selectedDocument?.sourceURL,let u=URL(string:s),["http","https"].contains(u.scheme ?? "") else{return};NSWorkspace.shared.open(u)}
    func importFiles(){let p=NSOpenPanel();p.allowsMultipleSelection=true;p.canChooseDirectories=false;p.allowedContentTypes=[.pdf,.epub,.html,.plainText]+["md","ppt","pptx","bandu"].compactMap{UTType(filenameExtension:$0)};if p.runModal() == .OK{Task{await importURLs(p.urls)}}}
    func importURLs(_ urls:[URL])async {guard !busy else{status="请等当前导入完成";return};busy=true;defer{busy=false};var errors:[String]=[]
        for u in urls {do{if u.pathExtension.lowercased()=="bandu"{try importLegacy(u);continue};let d=try await importFile(u);library=store.state.documents;selectDocument(d.id);status="已导入：\(d.title)"}catch{errors.append("\(u.lastPathComponent)：\(error.localizedDescription)")}}
        if !errors.isEmpty{errorMessage=errors.joined(separator:"\n")}
    }
    func importFile(_ u:URL)async throws->ReaderDocument {
        let ext=u.pathExtension.lowercased();let access=u.startAccessingSecurityScopedResource();defer{if access{u.stopAccessingSecurityScopedResource()}}
        let size=(try? u.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;guard size<=250_000_000 else{throw ReaderError.message("文件超过 250 MB，请拆分后导入。")}
        if ext=="ppt" || ext=="pptx" { return try await importPowerPoint(u) }
        if ext=="pdf"{
            guard let pdf=PDFDocument(url:u),pdf.pageCount>0,!pdf.isLocked else{throw ReaderError.message("PDF 无法读取或需要密码，请先导出未加密副本。")}
            let data=try Data(contentsOf:u),digest=sha256(data)
            if let d=store.state.documents.first(where:{$0.digest==digest}){return d}
            let id=newID(),folder=try store.folder(id);try data.write(to:folder.appendingPathComponent("original.pdf"),options:.atomic)
            let d=ReaderDocument(id:id,title:u.deletingPathExtension().lastPathComponent,kind:"pdf",createdAt:Date(),lastOpenedAt:Date(),relativePath:"documents/\(id)/original.pdf",digest:digest)
            store.state.documents.insert(d,at:0);try store.save();return d
        }
        var raw="",title=u.deletingPathExtension().lastPathComponent,kind="text"
        switch ext {
        case "epub":let item=try EPUBReader(file:u).load();title=item.0;raw=item.1;kind="epub"
        case "html","htm":raw=try decodeText(Data(contentsOf:u));kind="html"
        case "md","markdown":raw=try await processor.renderMarkdown(decodeText(Data(contentsOf:u)));kind="markdown"
        case "txt","text":raw=try decodeText(Data(contentsOf:u)).components(separatedBy:"\n\n").map{"<p>"+htmlEscape($0).replacingOccurrences(of:"\n",with:"<br>")+"</p>"}.joined();kind="text"
        default:throw ReaderError.message("支持 PDF、EPUB、HTML、Markdown 和 TXT。")
        }
        let article=try await processor.extract(raw);return try store.addArticle(title:article.title.isEmpty ? title:article.title,html:article.html,text:article.text,kind:kind)
    }
    func importWebURL()async {guard !busy else{return};guard let u=URL(string:importURLText.trimmingCharacters(in:.whitespacesAndNewlines)),["https","http"].contains(u.scheme ?? ""),u.host != nil,u.user==nil,u.password==nil else{errorMessage="请输入完整的 http 或 https 文章网址。";return}
        busy=true;status="正在提取文章…";defer{busy=false}
        do{let config=URLSessionConfiguration.ephemeral;config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.timeoutIntervalForRequest=25;let session=URLSession(configuration:config);defer{session.invalidateAndCancel()}
            var request=URLRequest(url:u);request.setValue("Mozilla/5.0 ShiyeLocalReader/1.0",forHTTPHeaderField:"User-Agent")
            let(data,response)=try await session.data(for:request);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),data.count<15_000_000 else{throw ReaderError.message("网页无法读取或过大。可在浏览器中保存为 PDF 后导入。")}
            let final=response.url ?? u
            var article=try await processor.extract(decodeText(data),base:final.absoluteString,readable:true)
            for src in article.images {
                guard let imageURL=URL(string:src),["https","http"].contains(imageURL.scheme ?? "") else{continue}
                var replacement=""
                if let (bytes,r)=try? await session.data(from:imageURL),bytes.count<4_000_000,let mime=r.mimeType,["image/png","image/jpeg","image/gif","image/webp"].contains(mime){replacement="data:\(mime);base64,\(bytes.base64EncodedString())"}
                article.html=article.html.replacingOccurrences(of:htmlEscape(src),with:replacement).replacingOccurrences(of:src,with:replacement)
            }
            let d=try store.addArticle(title:article.title,html:article.html,text:article.text,kind:"html",sourceURL:final.absoluteString);library=store.state.documents;selectDocument(d.id);showURLImport=false;importURLText="";status="文章已存到本机，可离线阅读"
        }catch{errorMessage="导入失败：\(error.localizedDescription)";status="导入未完成"}
    }
    func chooseVault(){let p=NSOpenPanel();p.canChooseFiles=false;p.canChooseDirectories=true;p.message="选择 Obsidian 知识库根文件夹";if p.runModal() == .OK,let u=p.url{vaultPath=u.path;saveSettings()}}
    func exportBackup(){let p=NSOpenPanel();p.canChooseFiles=false;p.canChooseDirectories=true;p.canCreateDirectories=true;p.message="选择备份保存位置";if p.runModal() == .OK,let base=p.url{do{persist(sync:false);saveTeaching();let f=DateFormatter();f.dateFormat="yyyyMMdd-HHmmss";let dest=base.appendingPathComponent("伴读备份-"+f.string(from:Date()));guard !dest.path.hasPrefix(store.root.path+"/") else{throw ReaderError.message("请选择资料库以外的备份位置。")};try FileManager.default.copyItem(at:store.root,to:dest);status="备份已保存：\(dest.lastPathComponent)";NSWorkspace.shared.selectFile(dest.path,inFileViewerRootedAtPath:base.path)}catch{errorMessage=error.localizedDescription}}}
    func revealDataFolder(){NSWorkspace.shared.open(store.root)}
    func handleDeepLink(_ u:URL){guard u.scheme=="shiye",u.host=="document",let id=u.pathComponents.last,library.contains(where:{$0.id==id}) else{errorMessage="这条链接对应的文档不在当前资料库中。";return};filter="全部";search="";selectDocument(id);if let pageText=URLComponents(url:u,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="page"})?.value,let page=Int(pageText),page>0,let i=library.firstIndex(where:{$0.id==id}){library[i].page=page-1;command("page:\(page-1)")};if let hi=URLComponents(url:u,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="highlight"})?.value,let h=highlights.first(where:{$0.id==hi&&$0.documentID==id}){goToHighlight(h)}}
}
