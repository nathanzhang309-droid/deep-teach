import Foundation
import AppKit
import PDFKit

struct TeacherContext:Codable {
    var documentID:String; var title:String; var page:Int; var totalPages:Int
    var inkCanvas:InkCanvas?;var anchor:SelectionAnchor?; var images:[String]; var text:String; var outline:String
}
struct TeacherMessage:Codable,Identifiable {
    var id:String;var role:String;var text:String;var page:Int;var saved:Bool=false
    var context:TeacherContext?;var failed:Bool=false;var completed:Bool?;var inkApplied:Bool?
}
struct TeachingArchive:Codable {
    var conversations:[String:[TeacherMessage]]=[:];var provider="codex";var level="学过但模糊"
}
@MainActor final class TeacherProcess {
    var process:Process?;var input:Pipe?;var output:Pipe?;var buffer=Data();var onEvent:(([String:Any])->Void)?
    func start(_ request:[String:Any],event:@escaping([String:Any])->Void)throws {
        onEvent=event
        let dir=Bundle.main.resourceURL!.appendingPathComponent("Teacher")
        let p=Process(),out=Pipe(),stdin=Pipe();p.executableURL=dir.appendingPathComponent("runtime/node");p.arguments=[dir.appendingPathComponent("runner.mjs").path];p.currentDirectoryURL=FileManager.default.temporaryDirectory
        var env=ProcessInfo.processInfo.environment
        for key in ["OPENAI_API_KEY","CODEX_API_KEY","ANTHROPIC_API_KEY","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_BASE_URL"]{env.removeValue(forKey:key)}
        p.environment=env;p.standardInput=stdin;p.standardOutput=out;p.standardError=FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler={ [weak self] h in let data=h.availableData;guard !data.isEmpty else{h.readabilityHandler=nil;return};Task{@MainActor in self?.consume(data)}}
        p.terminationHandler={ [weak self] p in Task{@MainActor in
            // All lines queued by the pipe handler are processed before completion.
            try? await Task.sleep(nanoseconds:100_000_000)
            self?.onEvent?(["type":"exit","code":Int(p.terminationStatus)])
        }}
        self.process=p;self.input=stdin;self.output=out;try p.run()
        let bytes=try JSONSerialization.data(withJSONObject:request)
        // Pipe writes can exceed the OS buffer. Never block the main/UI thread.
        DispatchQueue.global(qos:.userInitiated).async{try? stdin.fileHandleForWriting.write(contentsOf:bytes);try? stdin.fileHandleForWriting.close()}
    }
    func consume(_ data:Data){buffer.append(data);while let r=buffer.firstRange(of:Data([10])){let line=buffer[..<r.lowerBound];buffer.removeSubrange(..<r.upperBound);if let e=try? JSONSerialization.jsonObject(with:line) as? [String:Any]{onEvent?(e)}}}
    func stop(){if process?.isRunning==true{process?.terminate()}}
    deinit{output?.fileHandleForReading.readabilityHandler=nil;if process?.isRunning==true{process?.terminate()}}
}
func imageURL(_ image:NSImage)->String? {
    guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else{return nil}
    return "data:image/png;base64,"+png.base64EncodedString()
}
@MainActor extension AppModel {
    var tutorMessages:[TeacherMessage]{teaching.conversations[selectedID ?? ""] ?? []}
    var teachingURL:URL{store.root.appendingPathComponent("teaching.json")}
    func loadTeaching(){
        guard FileManager.default.fileExists(atPath:teachingURL.path) else{return}
        do{teaching=try JSONDecoder().decode(TeachingArchive.self,from:Data(contentsOf:teachingURL));tutorProvider=teaching.provider;tutorLevel=teaching.level}
        catch{let backup=store.root.appendingPathComponent("teaching.previous.json");if let data=try? Data(contentsOf:backup),let old=try? JSONDecoder().decode(TeachingArchive.self,from:data){teaching=old;tutorProvider=old.provider;tutorLevel=old.level;tutorStatus=L("讲解记录已从备份恢复")}else{tutorStatus=L("讲解记录无法读取，原文件已保留")};try? FileManager.default.copyItem(at:teachingURL,to:store.root.appendingPathComponent("teaching-damaged-"+newID()+".json"))}
    }
    func saveTeaching(){teaching.provider=tutorProvider;teaching.level=tutorLevel
        do{let bytes=try JSONEncoder().encode(teaching);if let old=try? Data(contentsOf:teachingURL),(try? JSONDecoder().decode(TeachingArchive.self,from:old)) != nil{try old.write(to:store.root.appendingPathComponent("teaching.previous.json"),options:.atomic)};try bytes.write(to:teachingURL,options:.atomic)}catch{tutorStatus=L("讲解保存失败：")+error.localizedDescription};tutorRevision+=1
    }
    func captureContext()async throws->TeacherContext {
        guard let d=selectedDocument else{throw ReaderError.message(L("先打开一份资料"))}
        var c=TeacherContext(documentID:d.id,title:d.title,page:d.page+1,totalPages:1,anchor:pending,images:[],text:"",outline:"")
        if d.kind=="pdf" {
            guard let pdf=activePDF?.document ?? PDFDocument(url:store.url(for:d)) else{throw ReaderError.message(L("无法读取课件"))}
            let p=min(max(0,selectedImagePage ?? pending?.regions.first?.page ?? d.page),pdf.pageCount-1);c.page=p+1;c.totalPages=pdf.pageCount
            if let page=pdf.page(at:p){c.inkCanvas=InkCanvas.capture(page:page,region:selectedImageRegion ?? c.anchor?.regions.first(where:{$0.page==p}))}
            if let selectedImage{c.images.append(selectedImage)}
            if let page=pdf.page(at:p),let preview=SlidePDF.renderedImage(page),let full=imageURL(preview){c.images.append(full)}
            c.text=(max(0,p-1)...min(pdf.pageCount-1,p+1)).map{L("第 {0} 页：\n", String(describing: $0+1))+(pdf.page(at:$0)?.string ?? L("[图片页]"))}.joined(separator:"\n\n")
            c.outline=(0..<min(500,pdf.pageCount)).map{L("第 {0} 页：", String(describing: $0+1))+String((pdf.page(at:$0)?.string ?? "").prefix(200))}.joined(separator:"\n")
        }else{
            let html=try String(contentsOf:store.url(for:d),encoding:.utf8);let article=try await processor.extract(html)
            let ns=article.text as NSString;let at=c.anchor?.start ?? Int(Double(ns.length)*d.progress);let start=max(0,min(ns.length,at)-6000);c.text=ns.substring(with:NSRange(location:start,length:min(24000,ns.length-start)));c.outline=String(article.text.prefix(6000))
        }
        c.text=String(c.text.prefix(28000));c.outline=String(c.outline.prefix(18000));return c
    }
    func askTeacher(){sendTeacher(L("请讲解我选中的内容；如果没有选区，就从当前页或文章开始，一次讲清楚一个知识点。"))}
    func sendTeacher(_ question:String){
        guard !tutorBusy,!question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,question.trimmingCharacters(in:.whitespacesAndNewlines).unicodeScalars.count<=5000 else{return}
        pausePracticeProcess();pauseStudyProcess();showTutor=true;showNotes=true;tutorBusy=true;tutorStatus=L("正在准备当前内容…")
        let requestID=UUID();teacherRequestID=requestID;let responseLanguage=AppLanguage.code
        Task {do{
            guard teacherRequestID==requestID else{return}
            let context=try await captureContext();guard teacherRequestID==requestID else{return};let docID=context.documentID;let userID=newID(),answerID=newID()
            let history=(teaching.conversations[docID] ?? []).filter{!$0.failed && $0.completed != false}.suffix(16).map{["role":$0.role,"text":$0.text,"page":$0.page] as [String:Any]}
            teaching.conversations[docID,default:[]].append(TeacherMessage(id:userID,role:"user",text:question,page:context.page,context:context))
            teaching.conversations[docID,default:[]].append(TeacherMessage(id:answerID,role:"assistant",text:"",page:context.page,context:context,completed:false));saveTeaching()
            activeTeacherAnswer=(docID,answerID)
            var request:[String:Any]=["language":responseLanguage,"provider":tutorProvider,"level":tutorLevel,"documentName":context.title,"question":question,"selectedText":context.anchor?.quote ?? "","page":context.page,"totalPages":context.totalPages,"images":context.images,"pageText":context.text,"outline":context.outline,"notes":highlights.filter{$0.documentID==docID}.map{$0.note}.joined(separator:"\n"),"history":history]
            if let canvas=context.inkCanvas,let bytes=try? JSONEncoder().encode(canvas),let object=try? JSONSerialization.jsonObject(with:bytes){request["inkCanvas"]=object}
            let runner=TeacherProcess();teacherProcess=runner
            try runner.start(request){[weak self,weak runner] event in guard let self,self.teacherRequestID==requestID,self.teacherProcess===runner else{return};let type=event["type"] as? String ?? ""
                if type=="delta",let text=event["text"] as? String,let i=self.teaching.conversations[docID]?.firstIndex(where:{$0.id==answerID}){if self.teaching.conversations[docID]![i].text.utf8.count+text.utf8.count>240_000 {self.stopTeacher();self.tutorStatus=L("输出过长，请重试");return};self.teaching.conversations[docID]![i].text+=text;self.tutorRevision+=1}
                if type=="status"{self.tutorStatus=event["text"] as? String ?? L("老师正在讲解…")}
                if type=="error"{self.tutorStatus=event["error"] as? String ?? L("讲解未完成");if let i=self.teaching.conversations[docID]?.firstIndex(where:{$0.id==answerID}){self.teaching.conversations[docID]![i].failed=true}}
                if type=="done"{if let i=self.teaching.conversations[docID]?.firstIndex(where:{$0.id==answerID}),self.teaching.conversations[docID]![i].failed==false{self.teaching.conversations[docID]![i].completed=true;let count=self.applyTeacherInk(documentID:docID,answerID:answerID);self.teaching.conversations[docID]![i].text=InkPlan.visibleText(self.teaching.conversations[docID]![i].text);self.tutorStatus=count>0 ? L("已在课件上标注，可编辑或撤销"):L("讲解已保存");self.recordStudyTurn(documentID:docID,answerID:answerID)};self.saveTeaching()}
                if type=="exit"{
                    if let i=self.teaching.conversations[docID]?.firstIndex(where:{$0.id==answerID}),self.teaching.conversations[docID]![i].completed != true,!self.teaching.conversations[docID]![i].failed {self.teaching.conversations[docID]![i].failed=true;self.tutorStatus=L("原始问答已保留，请重新提问。")}
                    self.teacherRequestID=nil;self.activeTeacherAnswer=nil;self.teacherProcess=nil;self.tutorBusy=false;self.saveTeaching();self.processStudyQueue()
                }
            }
        }catch{guard teacherRequestID==requestID else{return};teacherRequestID=nil;activeTeacherAnswer=nil;tutorBusy=false;tutorStatus=error.localizedDescription;saveTeaching();processStudyQueue()}}
    }
    func stopTeacher(){
        teacherRequestID=nil
        if let (doc,id)=activeTeacherAnswer,let i=teaching.conversations[doc]?.firstIndex(where:{$0.id==id}),teaching.conversations[doc]![i].completed != true {teaching.conversations[doc]![i].failed=true}
        activeTeacherAnswer=nil;teacherProcess?.stop();teacherProcess=nil;tutorBusy=false;tutorStatus=L("已停止，已生成内容仍保留");saveTeaching()}
    func saveTeacherAnswer(_ id:String){guard let docID=selectedID,let i=teaching.conversations[docID]?.firstIndex(where:{$0.id==id}),let message=teaching.conversations[docID]?[i],message.role=="assistant",!message.text.isEmpty,!message.saved else{return}
        let c=message.context,a=c?.anchor;let h=Highlight(id:newID(),documentID:docID,quote:a?.quote.isEmpty==false ? a!.quote:L("第 {0} 页 · 伴读讲解", String(describing: message.page)),note:message.text,tags:"伴读 讲解",color:"green",createdAt:Date(),page:selectedDocument?.kind=="pdf" ? message.page-1:nil,regions:a?.regions ?? [],start:a?.start,end:a?.end,prefix:a?.prefix,suffix:a?.suffix)
        highlights.append(h);teaching.conversations[docID]![i].saved=true;persist();saveTeaching();readerRevision+=1;tutorStatus=L("已收进批注，按当前设置同步到 Obsidian")
    }
}
