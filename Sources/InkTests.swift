import AppKit
import PDFKit
import WebKit
@MainActor enum InkTests {
 static func run(model:AppModel,window:NSWindow)async {
    guard ProcessInfo.processInfo.environment["SHIYE_DATA_DIR"] != nil else{return}
    var checks:[String:Bool]=[:];var failure=""
    func pause(_ seconds:Double=0.5)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    func webs(_ v:NSView)->[WKWebView]{(v as? WKWebView).map{[$0]} ?? v.subviews.flatMap{webs($0)}}
    do {
        model.autoSync=false;model.study.autoEnabled=false;model.showNotes=true;model.showTutor=true
        let original=PDFDocument()
        for i in 0..<3{original.insert(SlidePDF.blank(CGSize(width:960,height:720))!,at:i)}
        original.page(at:0)!.addAnnotation(SlideAnnotation(mark:SlideMark(kind:"text",text:"Conditional probability\nP(A|B) = P(A∩B) / P(B)\nGiven B, restrict the sample space to B.",color:"#222222",fontSize:28,x:80,y:460,width:800,height:180,page:0)))
        let source=model.store.root.appendingPathComponent("source.pdf");try SlidePDF.export(original,to:source)
        let bytes=try Data(contentsOf:source),id=newID(),folder=try model.store.folder(id),file=folder.appendingPathComponent("document.pdf");try bytes.write(to:file)
        let doc=ReaderDocument(id:id,title:"红笔自动批注验证",kind:"pdf",createdAt:Date(),lastOpenedAt:Date(),relativePath:"documents/\(id)/document.pdf",digest:sha256(bytes))
        model.store.state.documents.insert(doc,at:0);try model.store.save();model.library=model.store.state.documents;model.selectDocument(id);await pause(1)
        guard let view=model.activePDF,let page=view.document?.page(at:0),let overlay=view.subviews.compactMap({$0 as? SlideOverlay}).first else{throw ReaderError.message("No PDF view")}
        let region=PDFRegion(page:0,x:80,y:460,width:790,height:180)
        var context=TeacherContext(documentID:id,title:doc.title,page:1,totalPages:3,anchor:nil,images:[],text:"",outline:"")
        context.inkCanvas=InkCanvas.capture(page:page,region:region)
        let answer="已知 B 后，分母只计算 B 的概率。\n\n```bandu-ink\n{\"marks\":[{\"kind\":\"ellipse\",\"x\":0.08,\"y\":0.11,\"w\":0.84,\"h\":0.26},{\"kind\":\"label\",\"x\":0.15,\"y\":0.12,\"w\":0.32,\"h\":0.08,\"text\":\"分母：条件 B 的概率\"},{\"kind\":\"underline\",\"x\":0.12,\"y\":0.28,\"w\":0.35,\"h\":0.01}]}\n```"
        model.teaching.conversations[id]=[TeacherMessage(id:"auto",role:"assistant",text:answer,page:1,context:context,completed:true)]
        let before=model.currentSlideProject.marks.count
        checks["automatic_batch_added"]=model.applyTeacherInk(documentID:id,answerID:"auto")==3 && model.currentSlideProject.marks.count==before+3
        checks["chat_stays_open_without_editor"]=model.showTutor && !model.slideEditing
        checks["idempotent_completion"]=model.applyTeacherInk(documentID:id,answerID:"auto")==0 && model.currentSlideProject.marks.count==before+3
        checks["metadata_removed_from_answer"]=model.tutorMessages.first?.text=="已知 B 后，分母只计算 B 的概率。"
        let label=model.currentSlideProject.marks.first{$0.kind=="label"}!
        let lines=page.selection(for:page.bounds(for:.cropBox))!.selectionsByLine().map{$0.bounds(for:page)}
        checks["label_avoids_original_text"]=(!lines.contains{$0.intersects(label.rect)}) && label.color=="#C23B2E"
        model.removeTeacherInk("auto");checks["remove_only_this_answer"]=model.currentSlideProject.marks.count==before
        model.undoSlideChange();checks["undo_restores_ink_batch"]=model.currentSlideProject.marks.count==before+3
        // Rendering must clip even legacy objects outside the page and annotations partially scrolled offscreen.
        let oversized=SlideMark(kind:"ellipse",color:"#C23B2E",x:-100,y:-130,width:1200,height:1000,page:0)
        model.slideEdits.projects[id]!.marks.append(oversized);model.slideRevision+=1;await pause()
        func sample(_ name:String)throws->(Int,Int) {
            let margin:CGFloat=40,size=CGSize(width:overlay.bounds.width+80,height:overlay.bounds.height+80),image=NSImage(size:size)
            image.lockFocus();NSColor.white.setFill();CGRect(origin:.zero,size:size).fill();NSGraphicsContext.current!.cgContext.translateBy(x:margin,y:margin);overlay.draw(overlay.bounds);image.unlockFocus()
            let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!;try bitmap.representation(using:.png,properties:[:])!.write(to:model.store.root.appendingPathComponent(name+".png"))
            let pageRect=overlay.convert(view.convert(page.bounds(for:.cropBox),from:page),from:view)
            var allowed=overlay.bounds.intersection(pageRect)
            if let clip=view.documentView?.enclosingScrollView?.contentView{allowed=allowed.intersection(overlay.convert(clip.bounds,from:clip))}
            let sx=CGFloat(bitmap.pixelsWide)/size.width,sy=CGFloat(bitmap.pixelsHigh)/size.height
            var inside=0,outside=0
            for y in stride(from:0,to:bitmap.pixelsHigh,by:2){for x in stride(from:0,to:bitmap.pixelsWide,by:2){
                guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.redComponent-c.greenComponent>0.2,c.redComponent-c.blueComponent>0.2 else{continue}
                let p=CGPoint(x:(CGFloat(x)+0.5)/sx-margin,y:size.height-(CGFloat(y)+0.5)/sy-margin)
                if allowed.insetBy(dx:-1,dy:-1).contains(p){inside+=1}else{outside+=1}
            }};return(inside,outside)
        }
        view.scaleFactor=1;view.go(to:PDFDestination(page:page,at:CGPoint(x:0,y:470)));await pause()
        let a=try sample("ink-scroll");try "scroll=\(a) bounds=\(overlay.bounds) page=\(overlay.convert(view.convert(page.bounds(for:.cropBox),from:page),from:view)) flipped=\(overlay.isFlipped)".write(to:model.store.root.appendingPathComponent("clip-diagnostic.txt"),atomically:true,encoding:.utf8);checks["scroll_clips_to_viewport_and_page"]=a.0>10 && a.1==0
        view.zoomOut(nil);await pause();let b=try sample("ink-zoom");try "zoom=\(b) bounds=\(overlay.bounds) page=\(overlay.convert(view.convert(page.bounds(for:.cropBox),from:page),from:view))".write(to:model.store.root.appendingPathComponent("zoom-diagnostic.txt"),atomically:true,encoding:.utf8);checks["zoom_keeps_page_clipping"]=b.0>10 && b.1==0
        model.slideEdits.projects[id]!.marks.removeAll{$0.id==oversized.id};model.slideRevision+=1
        // Switching documents while a response is running must not redirect its marks.
        model.selectedID="other-doc"
        model.teaching.conversations[id]!.append(TeacherMessage(id:"captured",role:"assistant",text:answer,page:1,context:context,completed:true))
        checks["captured_document_target"]=model.applyTeacherInk(documentID:id,answerID:"captured")>0 && model.slideEdits.projects["other-doc"]==nil
        model.selectedID=id
        model.teaching.conversations[id]!.append(TeacherMessage(id:"failed",role:"assistant",text:answer,page:1,context:context,failed:true,completed:true))
        checks["failed_answer_does_not_annotate"]=model.applyTeacherInk(documentID:id,answerID:"failed")==0
        model.teaching.conversations[id]!.append(TeacherMessage(id:"partial",role:"assistant",text:answer,page:1,context:context,completed:false))
        checks["partial_answer_does_not_annotate"]=model.applyTeacherInk(documentID:id,answerID:"partial")==0
        let bad="answer\n```bandu-ink\n{\"marks\":[{\"kind\":\"image\",\"x\":0,\"y\":0,\"w\":1,\"h\":1},{\"kind\":\"ellipse\",\"x\":-10,\"y\":0,\"w\":100,\"h\":1}]}\n```"
        model.teaching.conversations[id]!.append(TeacherMessage(id:"invalid",role:"assistant",text:bad,page:1,context:context,completed:true))
        checks["invalid_types_and_coordinates_rejected"]=model.applyTeacherInk(documentID:id,answerID:"invalid")==0
        let saved=try JSONDecoder().decode(SlideArchive.self,from:Data(contentsOf:model.slidesURL));checks["ink_persists_with_answer_origin"]=saved.projects[id]?.marks.contains{$0.answerID=="auto"}==true
        let legacy="{\"id\":\"old\",\"kind\":\"text\",\"text\":\"legacy\",\"color\":\"#55735B\",\"fontSize\":18,\"x\":1,\"y\":1,\"width\":20,\"height\":20,\"page\":0,\"rotation\":0}"
        checks["legacy_marks_decode"]=(try? JSONDecoder().decode(SlideMark.self,from:Data(legacy.utf8)))?.answerID==nil
        model.slideEdits.projects[id]!.marks.removeAll{$0.answerID=="captured"};model.slideRevision+=1;model.saveSlides()
        // Exercise the real normal send/done path against a synthetic lesson, no private course data.
        model.teaching.conversations[id]=[];model.command("page:0");model.clearImageSelection();await pause()
        model.tutorProvider="codex";model.sendTeacher("解释这页条件概率中为什么分母是 P(B)，请直接红笔圈出公式并写一条短旁注。")
        for _ in 0..<240{await pause(0.5);if !model.tutorBusy{break}}
        let live=model.tutorMessages.last
        checks["real_subscription_answer_completed"]=live?.completed==true && live?.failed==false
        checks["real_answer_auto_ink_without_paste"]=live.map{m in model.currentSlideProject.marks.contains{$0.answerID==m.id}} ?? false
        checks["real_answer_chat_remains_visible"]=model.showTutor && !model.slideEditing
        model.tutorRevision+=1;await pause(2)
        if let web=webs(window.contentView!).first {
            checks["chat_shows_undo_without_json"]=(try await web.evaluateJavaScript("document.body.innerText.includes('撤销批注') && !document.body.innerText.includes('bandu-ink')") as? Bool)==true
        }
        let exported=model.store.root.appendingPathComponent("red-pen-validation.pdf");try SlidePDF.export(model.makeSlidePDF(document:doc)!,to:exported)
        let unchanged=try Data(contentsOf:file)==bytes
        checks["export_preserves_original_and_red_text"]=PDFDocument(url:exported)?.string?.filter{!$0.isWhitespace}.contains("分母：条件B的概率")==true && unchanged
        if let content=window.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds){content.cacheDisplay(in:content.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent("native-window.png"))}
        model.saveTeaching();model.saveSlides();model.persist(sync:false)
    }catch{failure=error.localizedDescription}
    let result:[String:Any]=["checks":checks,"error":failure,"passed":failure.isEmpty && !checks.values.contains(false)]
    if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:model.store.root.appendingPathComponent("ink-validation.json"))}
 }
}
