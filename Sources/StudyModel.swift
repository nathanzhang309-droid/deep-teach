import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor extension AppModel {
    var studyURL: URL { store.root.appendingPathComponent("study-notes.json") }
    var currentNotebook: StudyNotebook { study.notebooks[selectedID ?? ""] ?? StudyNotebook() }
    var currentStudyTopics: [StudyTopic] { currentNotebook.topics.sorted { a,b in a.turnIDs.count == b.turnIDs.count ? a.title < b.title : a.turnIDs.count > b.turnIDs.count } }
    func loadStudy() {
        guard FileManager.default.fileExists(atPath:studyURL.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(StudyArchive.self,from:Data(contentsOf:studyURL))
            guard loaded.version == 1 else { throw ReaderError.message("学习笔记版本不兼容") }
            study = loaded
        } catch {
            let previous = store.root.appendingPathComponent("study-notes.previous.json")
            if let bytes = try? Data(contentsOf:previous), let old = try? JSONDecoder().decode(StudyArchive.self,from:bytes), old.version == 1 {
                try? FileManager.default.copyItem(at:studyURL,to:store.root.appendingPathComponent("study-notes-damaged-\(newID()).json"))
                study = old; studyStatus = "学习笔记已从备份恢复"
            } else { studyWritable = false; studyStatus = "学习笔记无法读取，原文件已保留，请从备份恢复" }
        }
    }
    @discardableResult func saveStudy(sync: Bool = true) -> Bool {
        guard studyWritable else { return false }
        do {
            let bytes = try JSONEncoder().encode(study)
            if let old = try? Data(contentsOf:studyURL), (try? JSONDecoder().decode(StudyArchive.self,from:old)) != nil {
                try old.write(to:store.root.appendingPathComponent("study-notes.previous.json"),options:.atomic)
            }
            try bytes.write(to:studyURL,options:.atomic)
            if sync && autoSync { scheduleSync() }
            return true
        } catch { studyStatus = "学习笔记保存失败：" + error.localizedDescription; return false }
    }
    func recordStudyTurn(documentID: String, answerID: String) {
        guard studyWritable, let messages = teaching.conversations[documentID],
              let i = messages.firstIndex(where:{$0.id == answerID}), i > 0 else { return }
        var book = study.notebooks[documentID] ?? StudyNotebook()
        if StudyEngine.record(&book,question:messages[i-1],answer:messages[i]) {
            study.notebooks[documentID] = book
            studyStatus = study.autoEnabled ? "问答已记录，等待整理" : "问答已记录，自动整理已关闭"
            if saveStudy() { processStudyQueue() }
        }
    }
    func importStudyHistory() {
        guard let id = selectedID, studyWritable else { return }
        let messages = teaching.conversations[id] ?? []
        var book = study.notebooks[id] ?? StudyNotebook(); var count = 0
        for i in messages.indices where i > 0 {
            if StudyEngine.record(&book,question:messages[i-1],answer:messages[i]) { count += 1 }
        }
        study.notebooks[id] = book
        studyStatus = count > 0 ? "已补录 \(count) 轮问答" : "没有尚未记录的完整问答"
        if saveStudy() { studyManualDocument = id; processStudyQueue() }
    }
    func retryStudyNotes() {
        guard let id=selectedID, studyWritable else { return }
        if var book=study.notebooks[id] {
            for i in book.turns.indices where book.turns[i].state == "error" { book.turns[i].state = "pending" }
            study.notebooks[id]=book
        }
        if saveStudy(sync:false) { studyManualDocument=id; processStudyQueue() }
    }
    func pauseStudyProcess() {
        let runner=studyProcess; studyProcess=nil; studyBusy=false; runner?.stop()
    }
    func setStudyAuto(_ enabled: Bool) {
        study.autoEnabled=enabled; studyManualDocument=nil
        if !enabled { pauseStudyProcess(); studyStatus="自动整理已关闭，问答仍会在本地记录" }
        if saveStudy(sync:false), enabled { processStudyQueue() }
    }
    func processStudyQueue() {
        guard studyWritable, !tutorBusy, !studyBusy, study.autoEnabled || studyManualDocument != nil else { return }
        let docIDs=studyManualDocument.map{[$0]} ?? study.notebooks.keys.sorted()
        var task: (String,StudyTurn)?
        for id in docIDs { if let turn=study.notebooks[id]?.turns.first(where:{$0.state == "pending"}) { task=(id,turn);break } }
        guard let (docID,turn)=task, let book=study.notebooks[docID], let document=library.first(where:{$0.id==docID}) else { studyManualDocument=nil; return }
        let topics=book.topics.filter{$0.refined}.map { ["id":$0.id,"title":$0.title,"summary":$0.summary,"points":$0.points] as [String:Any] }
        let recent=book.turns.filter{$0.state == "done"}.suffix(4).map{["question":String($0.question.prefix(1500)),"answer":String($0.answer.prefix(2500)),"topicID":$0.topicID,"page":$0.page] as [String:Any]}
        let source=teaching.conversations[docID]?.first(where:{$0.id==turn.id})?.context?.text ?? ""
        let request:[String:Any] = ["mode":"study","provider":tutorProvider,"documentName":document.title,"question":turn.question,"answer":turn.answer,"page":turn.page,"sourceText":source,"topics":topics,"recent":recent]
        let runner=TeacherProcess();studyProcess=runner;studyBusy=true;studyStatus="正在整理《\(document.title)》的学习笔记…"
        var output="";var finalized=false
        func fail(_ message:String) {
            if let i=self.study.notebooks[docID]?.turns.firstIndex(where:{$0.id==turn.id}) { self.study.notebooks[docID]!.turns[i].state="error" }
            self.studyStatus="整理未完成，原问答已保留。\(message)";_ = self.saveStudy(sync:false)
        }
        do { try runner.start(request) { [weak self,weak runner] event in
            guard let self, let runner, self.studyProcess === runner else { return }
            let type=event["type"] as? String ?? ""
            if type == "delta", let chunk=event["text"] as? String { output += chunk; if output.count > 120000 { fail("输出过长，请重试");finalized=true;runner.stop() } }
            if type == "error" { fail(event["error"] as? String ?? "请重试");finalized=true }
            if type == "done", !finalized {
                do {
                    let raw=output.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard let start=raw.firstIndex(of:"{"), let end=raw.lastIndex(of:"}"), start <= end else { throw ReaderError.message("模型未返回可用笔记") }
                    let refined=try JSONDecoder().decode(StudyRefinement.self,from:Data(raw[start...end].utf8))
                    guard var latest=self.study.notebooks[docID] else { throw ReaderError.message("笔记不存在") }
                    try StudyEngine.apply(refined,turnID:turn.id,to:&latest)
                    self.study.notebooks[docID]=latest;self.studyStatus="《\(document.title)》学习笔记已更新"
                    _ = self.saveStudy()
                } catch { fail(error.localizedDescription) }
                finalized=true
            }
            if type == "exit" {
                if !finalized { fail("整理意外中断，请重试") }
                self.studyBusy=false;self.studyProcess=nil;self.processStudyQueue()
            }
        }} catch { fail(error.localizedDescription);studyBusy=false;studyProcess=nil }
    }
    func setStudyCompleted(_ value:Bool) {
        guard let id=selectedID,studyWritable else { return }
        study.notebooks[id,default:StudyNotebook()].completed=value
        if saveStudy() { if value { openStudyReview() };processStudyQueue() }
    }
    func setStudyMastered(topicID:String,value:Bool) {
        guard let id=selectedID,let i=study.notebooks[id]?.topics.firstIndex(where:{$0.id==topicID}) else{return}
        study.notebooks[id]!.topics[i].mastered=value;saveStudy()
    }
    func setStudyPersonalNote(topicID:String,text:String) {
        guard let id=selectedID,let i=study.notebooks[id]?.topics.firstIndex(where:{$0.id==topicID}), text.count<=50000 else{return}
        study.notebooks[id]!.topics[i].personalNote=text;saveStudy()
    }
    func recordStudyPage(_ page:Int) {
        guard let id=selectedID,studyWritable,selectedDocument?.isWelcome == false else{return}
        var book=study.notebooks[id] ?? StudyNotebook();guard !book.visitedPages.contains(page) else{return}
        book.visitedPages.append(page);book.visitedPages.sort();study.notebooks[id]=book;saveStudy(sync:false)
    }
    func openStudyReview(topicID:String?=nil) {
        guard selectedDocument != nil else { return }
        studyReviewTopicID=topicID;studyReviewRequest=UUID()
        if studyWindow == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:1320,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            w.minSize=NSSize(width:960,height:650);w.isReleasedWhenClosed=false;w.collectionBehavior.insert(.fullScreenPrimary)
            if !w.setFrameUsingName("BanduStudyReview"){w.center()};w.setFrameAutosaveName("BanduStudyReview")
            w.contentView=NSHostingView(rootView:StudyNotesView(model:self,compact:false));studyWindow=w
        }
        studyWindow?.title="学习笔记 · \(selectedDocument?.title ?? "")";studyWindow?.makeKeyAndOrderFront(nil)
    }
    func jumpToStudySource(page:Int) {
        guard let document=selectedDocument else{return}
        if document.kind == "pdf" { command("page:\(max(0,page-1))") }
        (NSApp.delegate as? AppDelegate)?.window.makeKeyAndOrderFront(nil)
    }
    func exportStudyMarkdown() {
        guard let document=selectedDocument else{return}
        let panel=NSSavePanel();panel.nameFieldStringValue=ObsidianSync().safeName(document.title)+" — 学习笔记.md";panel.allowedContentTypes=[UTType(filenameExtension:"md") ?? .plainText]
        if panel.runModal() == .OK,let url=panel.url {
            do{try ("# \(document.title)\n\n"+StudyEngine.markdown(currentNotebook,document:document)).write(to:url,atomically:true,encoding:.utf8)}catch{errorMessage=error.localizedDescription}
        }
    }
    var studySyncBlocks:[String:String] {
        var result:[String:String]=[:]
        for doc in library {if let book=study.notebooks[doc.id], !book.turns.isEmpty || book.completed {result[doc.id]=StudyEngine.markdown(book,document:doc)}}
        return result
    }
}
