import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor extension AppModel {
    var slidesURL:URL{store.root.appendingPathComponent("slide-edits.json")}
    var currentSlideProject:SlideProject {slideEdits.projects[selectedID ?? ""] ?? SlideProject()}
    var currentSlidePage:Int {guard let view=activePDF,let page=view.currentPage,let pdf=view.document else{return selectedDocument?.page ?? 0};return pdf.index(for:page)}
    var currentSlideMarks:[SlideMark]{currentSlideProject.marks.filter{$0.page==currentSlidePage}}
    var selectedSlideMark:SlideMark?{currentSlideProject.marks.first{$0.id==selectedSlideMarkID}}
    var canUndoSlide:Bool{!(slideUndo[selectedID ?? ""] ?? []).isEmpty}
    var canRedoSlide:Bool{!(slideRedo[selectedID ?? ""] ?? []).isEmpty}
    func loadSlides(){
        guard FileManager.default.fileExists(atPath:slidesURL.path) else{return}
        do{slideEdits=try JSONDecoder().decode(SlideArchive.self,from:Data(contentsOf:slidesURL));guard slideEdits.version==1 else{throw ReaderError.message("课件编辑版本不兼容")}}
        catch{
            let previous=store.root.appendingPathComponent("slide-edits.previous.json")
            if let data=try? Data(contentsOf:previous),let old=try? JSONDecoder().decode(SlideArchive.self,from:data),old.version==1{try? FileManager.default.copyItem(at:slidesURL,to:store.root.appendingPathComponent("slide-edits-damaged-\(newID()).json"));slideEdits=old;status="课件批注已从备份恢复"}
            else{slidesWritable=false;errorMessage="课件批注无法读取，原文件已保留，请从备份恢复"}
        }
    }
    func saveSlides(){guard slidesWritable else{return};do{
        if let old=try? Data(contentsOf:slidesURL),(try? JSONDecoder().decode(SlideArchive.self,from:old)) != nil{try old.write(to:store.root.appendingPathComponent("slide-edits.previous.json"),options:.atomic)}
        try JSONEncoder().encode(slideEdits).write(to:slidesURL,options:.atomic);status="课件批注已保存到本机"
    }catch{errorMessage="课件批注保存失败："+error.localizedDescription}}
    func rememberSlideUndo(){guard let id=selectedID,slidesWritable else{return};slideUndo[id,default:[]].append(currentSlideProject);if slideUndo[id]!.count>40{slideUndo[id]!.removeFirst()};slideRedo[id]=[]}
    func undoSlideChange(){guard let id=selectedID,let old=slideUndo[id]?.popLast() else{return};slideRedo[id,default:[]].append(currentSlideProject);slideEdits.projects[id]=old;selectedSlideMarkID=nil;slideRevision+=1;saveSlides()}
    func redoSlideChange(){guard let id=selectedID,let next=slideRedo[id]?.popLast() else{return};slideUndo[id,default:[]].append(currentSlideProject);slideEdits.projects[id]=next;selectedSlideMarkID=nil;slideRevision+=1;saveSlides()}
    func enterSlideEditing(){guard selectedDocument?.kind=="pdf",slidesWritable else{return};slideEditing=true;showNotes=true;boxSelection=false}
    func selectSlideMark(_ id:String){selectedSlideMarkID=id;enterSlideEditing()}
    func slideBounds(_ page:Int)->CGRect{activePDF?.document?.page(at:page)?.bounds(for:.cropBox) ?? CGRect(x:0,y:0,width:960,height:720)}
    func clampedSlideMark(_ mark:SlideMark)->SlideMark {
        var m=mark;let b=slideBounds(m.page)
        m.width=min(max(20,m.width),b.width);m.height=min(max(20,m.height),b.height)
        m.x=min(max(b.minX,m.x),b.maxX-m.width);m.y=min(max(b.minY,m.y),b.maxY-m.height);m.fontSize=min(72,max(9,m.fontSize));return m
    }
    func addSlideMark(_ mark:SlideMark,remember:Bool=true){guard let id=selectedID,selectedDocument?.kind=="pdf",slidesWritable else{return};if remember{rememberSlideUndo()};slideEdits.projects[id,default:SlideProject()].marks.append(clampedSlideMark(mark));selectedSlideMarkID=mark.id;slideRevision+=1;enterSlideEditing();saveSlides()}
    func addSlideText(){let page=currentSlidePage,b=slideBounds(page);addSlideMark(SlideMark(kind:"text",text:"在右侧编辑这段批注",x:b.minX+30,y:b.midY,width:min(320,b.width-60),height:min(130,b.height/3),page:page))}
    func addSlideShape(_ kind:String){guard ["rectangle","ellipse","arrow"].contains(kind) else{return};let page=currentSlidePage,b=slideBounds(page);addSlideMark(SlideMark(kind:kind,x:b.midX-70,y:b.midY-40,width:140,height:80,page:page))}
    func updateSlideMark(id:String,text:String?=nil,color:String?=nil,fontSize:Double?=nil,width:Double?=nil,height:Double?=nil){
        guard let doc=selectedID,let i=slideEdits.projects[doc]?.marks.firstIndex(where:{$0.id==id}),slidesWritable else{return}
        rememberSlideUndo();var m=slideEdits.projects[doc]!.marks[i]
        if let text{m.text=String(text.prefix(12000))};if let color{m.color=color};if let fontSize,fontSize.isFinite{m.fontSize=fontSize};if let width,width.isFinite{m.width=width};if let height,height.isFinite{m.height=height}
        slideEdits.projects[doc]!.marks[i]=clampedSlideMark(m);slideRevision+=1;saveSlides()
    }
    func moveSlideMark(id:String,dx:Double,dy:Double){guard let mark=currentSlideProject.marks.first(where:{$0.id==id}) else{return};rememberSlideUndo();dragSlideMark(id:id,x:mark.x+dx,y:mark.y+dy,width:mark.width,height:mark.height);saveSlides()}
    func dragSlideMark(id:String,x:Double,y:Double,width:Double,height:Double){guard let doc=selectedID,let i=slideEdits.projects[doc]?.marks.firstIndex(where:{$0.id==id}),[x,y,width,height].allSatisfy(\.isFinite),slidesWritable else{return};var m=slideEdits.projects[doc]!.marks[i];m.x=x;m.y=y;m.width=width;m.height=height;slideEdits.projects[doc]!.marks[i]=clampedSlideMark(m);slideRevision+=1}
    func rotateSlideArrow(_ id:String){guard let doc=selectedID,let i=slideEdits.projects[doc]?.marks.firstIndex(where:{$0.id==id}) else{return};rememberSlideUndo();slideEdits.projects[doc]!.marks[i].rotation+=1;slideRevision+=1;saveSlides()}
    func deleteSlideMark(_ id:String){guard let doc=selectedID,slidesWritable else{return};rememberSlideUndo();slideEdits.projects[doc]?.marks.removeAll{$0.id==id};selectedSlideMarkID=nil;slideRevision+=1;saveSlides()}
    func importSlideImage(){guard selectedDocument?.kind=="pdf" else{return};let p=NSOpenPanel();p.allowedContentTypes=[.png,.jpeg,.tiff];p.allowsMultipleSelection=false
        if p.runModal() == .OK,let u=p.url{do{let info=try u.resourceValues(forKeys:[.fileSizeKey]);guard (info.fileSize ?? 0)<25_000_000,let image=NSImage(contentsOf:u) else{throw ReaderError.message("请选择小于25MB的图片")};try placeSlideImage(image,newPage:false)}catch{errorMessage=error.localizedDescription}}
    }
    func slideImage(_ asset:String?)->NSImage?{guard let asset,asset==(asset as NSString).lastPathComponent else{return nil};if let cached=slideImageCache[asset]{return cached};let image=NSImage(contentsOf:store.root.appendingPathComponent("slide-assets").appendingPathComponent(asset));if let image{slideImageCache[asset]=image};return image}
    func placeSlideImage(_ image:NSImage,newPage:Bool)throws{
        guard selectedDocument?.kind=="pdf",let id=selectedID,slidesWritable else{throw ReaderError.message("先打开PDF或PPT课件")}
        guard image.size.width>0,image.size.height>0 else{throw ReaderError.message("图片不可用")}
        let scale=min(1,2400/max(image.size.width,image.size.height));let scaled=NSImage(size:CGSize(width:image.size.width*scale,height:image.size.height*scale));scaled.lockFocus();image.draw(in:CGRect(origin:.zero,size:scaled.size));scaled.unlockFocus()
        guard let tiff=scaled.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else{throw ReaderError.message("图片无法保存")}
        let folder=store.root.appendingPathComponent("slide-assets");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let name=newID()+".png";try data.write(to:folder.appendingPathComponent(name),options:.atomic);slideImageCache[name]=scaled
        rememberSlideUndo();var page=currentSlidePage;var bounds=slideBounds(page)
        if newPage{let size=CGSize(width:960,height:min(1800,max(720,900*scaled.size.height/scaled.size.width+80)));page=appendSlidePage(size:size);bounds=CGRect(origin:.zero,size:size)}
        let maxW=newPage ? bounds.width-60:min(420,bounds.width*0.48),maxH=newPage ? bounds.height-80:bounds.height*0.6
        let fit=min(maxW/scaled.size.width,maxH/scaled.size.height);let w=scaled.size.width*fit,h=scaled.size.height*fit
        let m=SlideMark(kind:"image",x:newPage ? bounds.midX-w/2:bounds.maxX-w-24,y:newPage ? bounds.midY-h/2:bounds.minY+24,width:w,height:h,page:page,asset:name)
        // New pages are not mounted in PDFView yet, so use their known dimensions directly.
        slideEdits.projects[id,default:SlideProject()].marks.append(m);selectedSlideMarkID=m.id;slideRevision+=1;enterSlideEditing();saveSlides();command("page:\(page)")
    }
    func appendSlidePage(size:CGSize)->Int{guard let doc=selectedDocument else{return 0};let base=PDFDocument(url:store.url(for:doc))?.pageCount ?? 0;let index=base+currentSlideProject.pages.count;slideEdits.projects[doc.id,default:SlideProject()].pages.append(SlidePage(width:size.width,height:size.height));return index}
    func addBlankSlide(){guard selectedDocument?.kind=="pdf",slidesWritable else{return};rememberSlideUndo();let page=appendSlidePage(size:CGSize(width:960,height:720));slideRevision+=1;enterSlideEditing();saveSlides();command("page:\(page)")}
    func addStudySlide(topicID:String){
        guard let doc=selectedDocument,doc.kind=="pdf",let topic=currentStudyTopics.first(where:{$0.id==topicID}),topic.refined,slidesWritable else{return}
        rememberSlideUndo()
        var sections:[(String,String)]=[("核心理解",topic.summary)]+topic.points.map{("要点",$0)}+topic.confusions.map{("追问与澄清",$0)}
        if !topic.reviewQuestion.isEmpty{sections.append(("自测",topic.reviewQuestion))}
        if !topic.personalNote.isEmpty{sections.append(("我的补充",topic.personalNote))}
        var cards:[String]=[]
        for (heading,text) in sections{var remaining=text[...];while !remaining.isEmpty{let part=String(remaining.prefix(180));cards.append(heading+"\n"+part);remaining=remaining.dropFirst(part.count)}}
        var first:Int?
        for offset in stride(from:0,to:max(1,cards.count),by:6){let page=appendSlidePage(size:CGSize(width:960,height:720));if first==nil{first=page}
            var marks=[SlideMark(kind:"text",text:topic.title+(offset>0 ? " · 续":""),fontSize:28,x:40,y:642,width:880,height:54,page:page)]
            for (slot,text) in cards.dropFirst(offset).prefix(6).enumerated(){marks.append(SlideMark(kind:"text",text:text,fontSize:17,x:Double(40+(slot%2)*450),y:Double(466-(slot/2)*178),width:430,height:162,page:page))}
            let source=currentNotebook.turns.filter{topic.turnIDs.contains($0.id)}.map{String($0.page)}.joined(separator:", ")
            marks.append(SlideMark(kind:"text",text:"伴读讲解页 · 来源第 \(source) 页 · 所有卡片均可编辑",fontSize:11,x:40,y:20,width:880,height:36,page:page))
            slideEdits.projects[doc.id]!.marks += marks
        }
        slideRevision+=1;enterSlideEditing();saveSlides();if let first{command("page:\(first)")};studyWindow?.orderOut(nil);(NSApp.delegate as? AppDelegate)?.window.makeKeyAndOrderFront(nil)
    }
    func makeSlidePDF(document:ReaderDocument)->PDFDocument?{
        guard let pdf=PDFDocument(url:store.url(for:document)) else{return nil};let project=slideEdits.projects[document.id] ?? SlideProject()
        for extra in project.pages{if let page=SlidePDF.blank(CGSize(width:extra.width,height:extra.height)){pdf.insert(page,at:pdf.pageCount)}}
        for m in project.marks{pdf.page(at:m.page)?.addAnnotation(SlideAnnotation(mark:m,image:slideImage(m.asset)))}
        for h in highlights where h.documentID==document.id{for r in h.regions{let annotation=PDFAnnotation(bounds:CGRect(x:r.x,y:r.y,width:r.width,height:r.height),forType:.highlight,withProperties:nil);annotation.color=markColor(h.color);annotation.contents=h.note;pdf.page(at:r.page)?.addAnnotation(annotation)}}
        return pdf
    }
    func exportMarkedPDF(){guard let document=selectedDocument,document.kind=="pdf" else{return};let panel=NSSavePanel();panel.allowedContentTypes=[.pdf];panel.nameFieldStringValue=ObsidianSync().safeName(document.title)+" — 批注版.pdf"
        if panel.runModal() == .OK,let url=panel.url{do{guard url.standardizedFileURL != store.url(for:document).standardizedFileURL else{throw ReaderError.message("请选择新的导出文件，保留原课件")};guard let pdf=makeSlidePDF(document:document) else{throw ReaderError.message("无法打开课件")};try SlidePDF.export(pdf,to:url);status="已导出批注PDF；可继续在伴读中编辑"}catch{errorMessage=error.localizedDescription}}
    }
}
