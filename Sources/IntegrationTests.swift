import Foundation
import AppKit
import PDFKit
import WebKit
@MainActor enum IntegrationTests {
 static func run(model:AppModel,window:NSWindow)async {
    await NativeTests.run(model:model,window:window)
    var checks:[String:Bool]=[:];var error=""
    func pause(_ seconds:Double)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    do{
        guard let pdf=model.library.first(where:{$0.kind=="pdf"}) else{throw ReaderError.message("Missing fixture")}
        model.selectDocument(pdf.id);await pause(0.8)
        let context=try await model.captureContext();checks["pdf_context_includes_image_and_text"] = !context.images.isEmpty && context.text.contains("Local reading")
        if let view=model.activePDF,let page=view.document?.page(at:0),let selection=page.selection(for:NSRange(location:0,length:13)),let overlay=view.subviews.compactMap({$0 as? BoxOverlay}).first {
            let pageRect=selection.bounds(for:page).insetBy(dx:-3,dy:-3);let viewRect=view.convert(pageRect,from:page);let box=overlay.convert(viewRect,from:view)
            model.boxSelection=true;checks["crop_mode_intercepts_pointer"]=overlay.hitTest(CGPoint(x:box.midX,y:box.midY))===overlay
            overlay.capture(box);checks["crop_extracts_correct_region"]=model.selectedImage?.hasPrefix("data:image/png;base64,")==true && model.pending?.quote.contains("Local reading")==true && model.selectedImagePage==0
            checks["crop_mode_releases_pointer"]=overlay.hitTest(CGPoint(x:box.midX,y:box.midY))==nil
            if let image=model.selectedImage?.components(separatedBy:",").last,let data=Data(base64Encoded:image){try data.write(to:model.store.root.appendingPathComponent("crop-preview.png"))}
        }

        let bytes=try Data(contentsOf:model.store.url(for:pdf));let legacy:[String:Any]=["format":"bandu-backup","version":1,"lectures":[["id":sha256(bytes),"name":"Legacy fixture","bytes":bytes.base64EncodedString(),"page":1,"updated":Date().timeIntervalSince1970*1000,"notes":[["id":"migration-note","page":1,"text":"迁移笔记","quote":"Local reading","created":Date().timeIntervalSince1970*1000]],"messages":[["id":"migration-message","role":"assistant","text":"迁移回答","page":1]]]]]
        let file=model.store.root.appendingPathComponent("migration-fixture.bandu");try JSONSerialization.data(withJSONObject:legacy).write(to:file)
        let count=model.library.count;try model.importLegacy(file);try model.importLegacy(file)
        checks["migration_deduplicates_pdf_and_records"]=model.library.count==count && model.highlights.filter{$0.note=="迁移笔记"}.count==1 && model.tutorMessages.filter{$0.text=="迁移回答"}.count==1
        checks["migration_keeps_original_backup"]=FileManager.default.fileExists(atPath:model.store.root.appendingPathComponent("迁移备份").path)
        if ProcessInfo.processInfo.environment["BANDU_LIVE_TEST"]=="1" {
            model.sendTeacher("只用一句中文回答：图中的英文句子是什么意思？不要出测验。")
            for _ in 0..<200 {await pause(1);if !model.tutorBusy{break}}
            let answer=model.tutorMessages.last
            checks["real_subscription_vision_answer"]=answer?.role=="assistant" && !(answer?.text.isEmpty ?? true) && answer?.failed==false && !model.tutorBusy
            if let answer,!answer.text.isEmpty{model.saveTeacherAnswer(answer.id);model.saveTeacherAnswer(answer.id);model.syncNow();checks["answer_to_annotation_once"]=model.highlights.filter{$0.note==answer.text}.count==1;checks["answer_sync_to_obsidian"]=model.syncStatus.contains("已同步")}
            else{error=model.tutorStatus}
        }
        model.saveTeaching();let data=try Data(contentsOf:model.teachingURL);let persisted=try JSONDecoder().decode(TeachingArchive.self,from:data);checks["conversations_persist"] = !persisted.conversations.isEmpty
        model.showTutor=true;model.showNotes=true
        let visual="公式：$x^2$\n\n```dsh-ui\n{\"type\":\"quiz\",\"question\":\"2+2=?\",\"options\":[{\"label\":\"4\",\"correct\":true},{\"label\":\"5\",\"correct\":false}]}\n```"
        if let id=model.selectedID{model.teaching.conversations[id,default:[]].append(TeacherMessage(id:newID(),role:"assistant",text:visual,page:1));model.tutorRevision+=1}
        await pause(1)
        func descendants(_ v:NSView)->[WKWebView]{(v as? WKWebView).map{[$0]} ?? v.subviews.flatMap{descendants($0)}}
        if let web=descendants(window.contentView!).first {
            checks["formula_and_quiz_render"]=(try await web.evaluateJavaScript("document.querySelectorAll('.katex').length>0 && document.querySelectorAll('.quiz-option').length===2") as? Bool)==true
            _=try await web.evaluateJavaScript("document.querySelector('.quiz-option')?.click()")
            checks["quiz_feedback_is_interactive"]=(try await web.evaluateJavaScript("document.body.innerText.includes('答对了')") as? Bool)==true
            model.tutorStatus="显示状态更新测试";await pause(0.3)
            checks["quiz_answer_survives_unrelated_update"]=(try await web.evaluateJavaScript("document.body.innerText.includes('答对了')") as? Bool)==true
        }
    }catch let e{error=e.localizedDescription}
    let result:[String:Any]=["checks":checks,"error":error,"passed":error.isEmpty && !checks.values.contains(false)]
    if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:model.store.root.appendingPathComponent("integration-test.json"))}
 }
}
