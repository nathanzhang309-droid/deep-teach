import AppKit
import Foundation
@MainActor enum StudyTests {
 static func run(model:AppModel,window:NSWindow) async {
    guard ProcessInfo.processInfo.environment["SHIYE_DATA_DIR"] != nil else{return}
    var checks:[String:Bool]=[:];var error=""
    func pause(_ seconds:Double=0.3) async {try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    func turn(_ id:String,_ question:String,_ answer:String,_ page:Int=2)->(TeacherMessage,TeacherMessage) {
        (TeacherMessage(id:"u-"+id,role:"user",text:question,page:page),TeacherMessage(id:id,role:"assistant",text:answer,page:page,completed:true))
    }
    func refine(_ target:String="")->StudyRefinement {StudyRefinement(topicID:target,title:"条件概率：先确定条件",summary:"条件概率把样本空间缩小到条件事件中，再计算其中目标事件所占的比例。",points:["P(A|B)=P(A∩B)/P(B)，前提是P(B)>0。"],confusions:["P(A|B)和P(B|A)的条件不同，分母也不同。"],reviewQuestion:"如果知道某人属于B组，求他同时属于A组的概率，应使用哪个分母？")}
    do {
        model.autoSync=false;model.study.autoEnabled=false
        var book=StudyNotebook()
        let one=turn("one","为什么条件概率的分母变成P(B)？","已知B后，样本空间限定在B里，所以P(A|B)=P(A∩B)/P(B)。")
        let two=turn("two","还是没懂P(A|B)和P(B|A)有什么不同？","两者条件不同，分母分别是P(B)和P(A)，一般不相同。")
        checks["first_turn_recorded"]=StudyEngine.record(&book,question:one.0,answer:one.1)
        checks["record_idempotent"] = !StudyEngine.record(&book,question:one.0,answer:one.1)
        var partial=one.1;partial.id="partial";partial.completed=false
        checks["partial_answer_not_recorded"] = !StudyEngine.record(&book,question:one.0,answer:partial)
        var failed=one.1;failed.id="failed";failed.failed=true
        checks["failed_answer_not_recorded"] = !StudyEngine.record(&book,question:one.0,answer:failed)
        try StudyEngine.apply(refine(),turnID:"one",to:&book)
        let originalID=book.topics[0].id;book.topics[0].personalNote="这是我写的，不要覆盖。";book.topics[0].mastered=true
        _=StudyEngine.record(&book,question:two.0,answer:two.1)
        let before=book.topics.count
        do { try StudyEngine.apply(refine("other-document-topic"),turnID:"two",to:&book);checks["foreign_topic_rejected"]=false } catch {checks["foreign_topic_rejected"]=book.topics.count==before}
        try StudyEngine.apply(refine(originalID),turnID:"two",to:&book)
        checks["followup_merged_and_counted"] = book.topics.count==1 && book.topics[0].turnIDs.count==2 && book.turns.count==2
        checks["manual_note_preserved"] = book.topics[0].personalNote=="这是我写的，不要覆盖。"
        checks["self_assessed_mastery_preserved"] = book.topics[0].mastered
        try StudyEngine.apply(refine(originalID),turnID:"two",to:&book)
        checks["refinement_idempotent"] = book.topics[0].turnIDs.count==2
        let d=try model.store.addArticle(title:"概率 · 个性化学习笔记验证",html:"<h1>条件概率</h1><p>P(A|B)=P(A∩B)/P(B)，P(B)>0。P(A|B)一般不等于P(B|A)。</p>",text:"条件概率",kind:"html")
        model.library=model.store.state.documents;model.selectDocument(d.id);model.study.notebooks[d.id]=book
        model.teaching.conversations[d.id]=[one.0,one.1,two.0,two.1];model.saveTeaching();model.saveStudy(sync:false)
        let saved=try JSONDecoder().decode(StudyArchive.self,from:Data(contentsOf:model.studyURL))
        checks["notebook_persists"]=saved.notebooks[d.id]?.topics.first?.personalNote==book.topics.first?.personalNote
        let vault=model.store.root.appendingPathComponent("test-vault");try FileManager.default.createDirectory(at:vault,withIntermediateDirectories:true)
        model.vaultPath=vault.path;model.syncNow()
        let dir=vault.appendingPathComponent(ObsidianSync.subfolder)
        let file=try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).first{$0.pathExtension=="md"}!
        var markdown=try String(contentsOf:file)
        checks["personalized_notes_sync"] = markdown.contains("重点追问") && markdown.contains("这是我写的") && markdown.contains("?page=2")
        markdown += "\n用户在Obsidian写的补充\n";try markdown.write(to:file,atomically:true,encoding:.utf8)
        model.setStudyMastered(topicID:originalID,value:true);model.syncNow()
        checks["obsidian_freeform_preserved"] = try String(contentsOf:file).contains("用户在Obsidian写的补充")
        let protected=try String(contentsOf:file).replacingOccurrences(of:"条件概率：先确定条件",with:"我手改了自动区域")
        try protected.write(to:file,atomically:true,encoding:.utf8)
        model.setStudyMastered(topicID:originalID,value:false);model.syncNow()
        checks["obsidian_managed_edit_conflict_protected"] = try String(contentsOf:file).contains("我手改了自动区域") && model.syncStatus.contains("待合并")
        if ProcessInfo.processInfo.environment["BANDU_STUDY_LIVE_TEST"] == "1" {
            // Rebuild solely from synthetic questions; no real course files are sent.
            model.study.notebooks[d.id]=StudyNotebook();model.study.autoEnabled=true
            model.recordStudyTurn(documentID:d.id,answerID:"one")
            for _ in 0..<210 { if !model.studyBusy {break};await pause(1) }
            checks["live_first_summary"] = model.currentNotebook.turns.first?.state=="done" && model.currentStudyTopics.first?.refined==true
            model.recordStudyTurn(documentID:d.id,answerID:"two")
            for _ in 0..<210 { if !model.studyBusy {break};await pause(1) }
            checks["live_semantic_followup_merge"] = model.currentStudyTopics.count==1 && model.currentStudyTopics.first?.turnIDs.count==2 && model.currentNotebook.turns.allSatisfy{$0.state=="done"}
            if !checks["live_semantic_followup_merge"]! {error=model.studyStatus}
        }
        model.showTutor=false;model.showStudyNotes=true;model.showNotes=true
        model.setStudyCompleted(true);await pause(0.8)
        checks["review_window_is_independent_and_resizable"] = model.studyWindow?.isVisible==true && model.studyWindow?.styleMask.contains(.resizable)==true && model.currentNotebook.completed
    } catch let e {error=e.localizedDescription}
    let result:[String:Any]=["checks":checks,"error":error,"passed":error.isEmpty && !checks.values.contains(false)]
    if let bytes=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? bytes.write(to:model.store.root.appendingPathComponent("study-validation.json"))}
 }
}
