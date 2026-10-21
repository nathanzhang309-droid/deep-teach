import AppKit
import PDFKit
import WebKit
@MainActor enum SlideTests {
 static func run(model:AppModel,window:NSWindow)async {
    guard ProcessInfo.processInfo.environment["SHIYE_DATA_DIR"] != nil else{return}
    var checks:[String:Bool]=[:];var error=""
    func pause(_ seconds:Double=0.4)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    func webs(_ v:NSView)->[WKWebView]{(v as? WKWebView).map{[$0]} ?? v.subviews.flatMap{webs($0)}}
    do {
        model.autoSync=false;model.study.autoEnabled=false
        let original=PDFDocument();original.insert(SlidePDF.blank(CGSize(width:960,height:720))!,at:0)
        let base=SlideMark(kind:"text",text:"条件概率 · 原始课件\nP(A|B) = P(A∩B) / P(B)\n先确定条件，再看目标。",fontSize:28,x:60,y:450,width:800,height:200,page:0)
        original.page(at:0)!.addAnnotation(SlideAnnotation(mark:base))
        let source=model.store.root.appendingPathComponent("source.pdf");try SlidePDF.export(original,to:source)
        let bytes=try Data(contentsOf:source),id=newID(),folder=try model.store.folder(id)
        let file=folder.appendingPathComponent("document.pdf");try bytes.write(to:file)
        let doc=ReaderDocument(id:id,title:"条件概率 · 课件编辑验证",kind:"pdf",createdAt:Date(),lastOpenedAt:Date(),relativePath:"documents/\(id)/document.pdf",digest:sha256(bytes))
        model.store.state.documents.insert(doc,at:0);try model.store.save();model.library=model.store.state.documents;model.selectDocument(id);await pause(1)
        model.enterSlideEditing();model.addSlideText();let textID=model.selectedSlideMarkID!
        model.updateSlideMark(id:textID,text:"我的批注：已知 B 后，分母用 P(B)。",color:"#B5533C",fontSize:23)
        model.moveSlideMark(id:textID,dx:50,dy:-150)
        let placed=model.selectedSlideMark!;model.moveSlideMark(id:textID,dx:99999,dy:-99999)
        let clamped=model.selectedSlideMark!;checks["movement_clamps_to_page"]=clamped.rect.maxX<=960 && clamped.rect.minY>=0
        model.undoSlideChange();checks["undo_restores_position"]=model.currentSlideProject.marks.first{$0.id==textID}?.x==placed.x
        model.redoSlideChange();checks["redo_restores_position"]=model.currentSlideProject.marks.first{$0.id==textID}?.x==clamped.x
        model.undoSlideChange();model.selectSlideMark(textID)
        model.updateSlideMark(id:textID,width:600,height:90)
        model.addSlideShape("arrow");let arrowID=model.selectedSlideMarkID!;model.moveSlideMark(id:arrowID,dx:-270,dy:10);model.rotateSlideArrow(arrowID)
        model.addSlideShape("ellipse");let circleID=model.selectedSlideMarkID!;model.moveSlideMark(id:circleID,dx:150,dy:10)
        model.deleteSlideMark(circleID);checks["delete_object"] = !model.currentSlideProject.marks.contains{$0.id==circleID};model.undoSlideChange()
        let image=NSImage(size:CGSize(width:280,height:140));image.lockFocus();NSColor.systemBlue.setFill();CGRect(x:0,y:0,width:280,height:140).fill();("A ∩ B" as NSString).draw(at:CGPoint(x:70,y:45),withAttributes:[.font:NSFont.systemFont(ofSize:35),.foregroundColor:NSColor.white]);image.unlockFocus()
        try model.placeSlideImage(image,newPage:true);await pause()
        checks["image_adds_page"]=model.currentSlideProject.pages.count==1 && model.activePDF?.document?.pageCount==2
        let topic=StudyTopic(id:"test-topic",title:"条件概率：先确定条件",summary:"已知 B 发生后，把参照范围缩小到 B。",points:["分子：A 与 B 同时发生。","分母：条件 B 的概率。"],confusions:["P(A|B) 与 P(B|A) 的条件不同。"],reviewQuestion:"为什么分母是 P(B)？",turnIDs:["test-turn"],personalNote:"我的记忆口诀：先看竖线右边。",refined:true)
        model.study.notebooks[id]=StudyNotebook(topics:[topic],turns:[StudyTurn(id:"test-turn",question:"为什么分母变了？",answer:"因为参照范围变了。",page:1,state:"done",topicID:topic.id)])
        model.addStudySlide(topicID:topic.id);await pause()
        checks["topic_creates_editable_cards"]=model.currentSlideProject.pages.count==2 && model.currentSlideProject.marks.filter{$0.page==2 && $0.kind=="text"}.count>=6
        let persisted=try JSONDecoder().decode(SlideArchive.self,from:Data(contentsOf:model.slidesURL))
        checks["edits_persist"]=persisted.projects[id]?.marks.count==model.currentSlideProject.marks.count
        model.slideEdits=SlideArchive();model.loadSlides();checks["edits_reload"]=model.currentSlideProject.marks.count==persisted.projects[id]?.marks.count
        checks["original_pdf_unchanged"]=try Data(contentsOf:file)==bytes
        model.slideEditing=false;model.showTutor=true;model.showNotes=true
        let visual="下面这张图可以贴回课件。\n\n$$\nP(A\\mid B)=\\frac{P(A\\cap B)}{P(B)}\n$$\n\n```dsh-ui\n{\"type\":\"echart\",\"title\":\"条件范围内的比例\",\"data\":[{\"label\":\"A与B\",\"value\":30},{\"label\":\"B其余部分\",\"value\":70}]}\n```"
        model.teaching.conversations[id]=[TeacherMessage(id:"visual-test",role:"assistant",text:visual,page:1,completed:true)];model.tutorRevision+=1;await pause(3)
        if let web=webs(window.contentView!).first {
            checks["formula_and_chart_actions_render"]=(try await web.evaluateJavaScript("document.querySelectorAll('.visual-clip-actions button').length===4 && document.querySelectorAll('.katex').length>0 && document.querySelectorAll('canvas').length>0") as? Bool)==true
            _=try await web.evaluateJavaScript("document.querySelector('.visual-clip-actions button')?.click()")
            await pause(1.5)
            checks["formula_snapshot_added"]=model.slideEditing && model.currentSlideProject.marks.last?.kind=="image"
            if let asset=model.currentSlideProject.marks.last?.asset,let image=model.slideImage(asset),let data=image.tiffRepresentation,let rep=NSBitmapImageRep(data:data){try rep.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent("formula-capture.png"))}
        }
        model.slideEditing=false;await pause(1)
        if let web=webs(window.contentView!).first {
            _=try await web.evaluateJavaScript("document.querySelectorAll('.visual-clip-actions button')[3]?.click()")
            await pause(1.5)
            checks["chart_snapshot_adds_page"]=model.currentSlideProject.pages.count==3 && model.slideEditing
        }
        guard let pdf=model.makeSlidePDF(document:doc) else{throw ReaderError.message("PDF assembly failed")}
        let output=model.store.root.appendingPathComponent("annotated-validation.pdf");try SlidePDF.export(pdf,to:output)
        let reopened=PDFDocument(url:output)!
        checks["export_contains_all_pages"]=reopened.pageCount==4
        checks["export_contains_annotation_text"]=reopened.string?.contains("我的批注")==true && reopened.string?.contains("先看竖线右边")==true
        model.command("page:0");model.selectSlideMark(textID);await pause()
        checks["editor_intercepts_pointer"]=model.activePDF?.subviews.compactMap{$0 as? SlideOverlay}.first?.hitTest(CGPoint(x:100,y:100)) != nil
        model.slideEditing=false;model.showTutor=false;model.showNotes=false;model.command("page:0");await pause()
        if let view=model.activePDF,let page=view.document?.page(at:0),let overlay=view.subviews.compactMap({$0 as? BoxOverlay}).first {
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);model.startBoxSelection();await pause();view.go(to:page);await pause();checks["selection_mode_enabled"]=model.boxSelection && !model.slideEditing
            let visible=view.convert(page.bounds(for:.cropBox),from:page).intersection(view.bounds);let region=CGRect(x:visible.midX-100,y:visible.midY-50,width:200,height:100);let box=overlay.convert(region,from:view)
            let messageCount=model.tutorMessages.count;overlay.capture(box);await pause(1)
            checks["selection_opens_chat_without_sending"]=model.showTutor && model.showNotes && model.tutorMessages.count==messageCount && !model.tutorBusy
            checks["selection_stays_on_page"]=model.selectedImageRegion != nil && overlay.persistentBox != nil && !model.boxSelection
            if let web=webs(window.contentView!).first {
                let focus=try await web.evaluateJavaScript("JSON.stringify({active:document.activeElement?.tagName,placeholder:document.querySelector('textarea')?.placeholder,focused:document.hasFocus()})")
                try String(describing:focus).write(to:model.store.root.appendingPathComponent("focus-diagnostic.txt"),atomically:true,encoding:.utf8)
                checks["selection_composer_focused"]=(try await web.evaluateJavaScript("document.activeElement?.tagName==='TEXTAREA' && document.querySelector('textarea')?.placeholder==='想问这部分什么？'") as? Bool)==true
                checks["selection_actions_visible"]=(try await web.evaluateJavaScript("document.querySelector('.selection-bar')?.innerText.includes('讲解所选区域')") as? Bool)==true
                let before=overlay.persistentBox?.width ?? 0;let stored=model.selectedImageRegion;view.zoomIn(nil);await pause()
                checks["selection_tracks_zoom"]=(overlay.persistentBox?.width ?? 0)>before && model.selectedImageRegion==stored
                _=try await web.evaluateJavaScript("document.querySelectorAll('.selection-ghost')[1]?.click()")
                await pause();checks["selection_cancel_clears_context"]=model.selectedImage==nil && model.selectedImageRegion==nil && overlay.persistentBox==nil
            }
        }
        model.enterSlideEditing();model.selectSlideMark(textID)
        if ProcessInfo.processInfo.environment["BANDU_SCIENCE_TEST"]=="1"{await ScienceTests.run(model:model,window:window)}
        model.slideEditing=true;model.command("page:0");model.selectSlideMark(textID);await pause()
        if let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent("editor-view.png"))}
        model.saveStudy(sync:false);model.saveTeaching();model.persist(sync:false)
    }catch let e{error=e.localizedDescription}
    let result:[String:Any]=["checks":checks,"error":error,"passed":error.isEmpty && !checks.values.contains(false)]
    if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:model.store.root.appendingPathComponent("slide-validation.json"))}
 }
}
