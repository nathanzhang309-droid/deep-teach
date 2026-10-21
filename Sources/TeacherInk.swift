import AppKit
import PDFKit

// Coordinates are normalized to the displayed full-page image, with a top-left origin.
struct InkCanvas:Codable {
    var width:Double;var height:Double;var selection:[Double]?
    @MainActor static func capture(page:PDFPage,region:PDFRegion?)->InkCanvas {
        let crop=page.bounds(for:.cropBox),rotated=abs(page.rotation)%180==90
        let size=rotated ? CGSize(width:crop.height,height:crop.width):crop.size
        var result=InkCanvas(width:size.width,height:size.height)
        if let region,let ref=page.pageRef {
            let t=ref.getDrawingTransform(.cropBox,rect:CGRect(origin:.zero,size:size),rotate:0,preserveAspectRatio:true)
            let r=CGRect(x:region.x,y:region.y,width:region.width,height:region.height).applying(t)
            result.selection=[r.minX/size.width,1-r.maxY/size.height,r.width/size.width,r.height/size.height]
        };return result
    }
}
struct InkInstruction:Decodable {var kind:String;var x:Double;var y:Double;var w:Double;var h:Double;var text:String?;var rotation:Int?}
struct InkPlan:Decodable {
    var marks:[InkInstruction]
    static func parse(_ text:String)->InkPlan? {
        guard text.utf8.count<250_000,let start=text.range(of:"```bandu-ink\n",options:.backwards),let end=text.range(of:"```",range:start.upperBound..<text.endIndex),text[end.upperBound...].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
        let json=String(text[start.upperBound..<end.lowerBound]);guard json.utf8.count<16_000 else{return nil}
        return try? JSONDecoder().decode(InkPlan.self,from:Data(json.utf8))
    }
    static func visibleText(_ text:String)->String {
        guard let range=text.range(of:"```bandu-ink") else{return text};return String(text[..<range.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
@MainActor extension AppModel {
    // Apply only a completed answer, once, to its captured document/page. Never change the active pane.
    @discardableResult func applyTeacherInk(documentID:String,answerID:String)->Int {
        guard slidesWritable,let index=teaching.conversations[documentID]?.firstIndex(where:{$0.id==answerID}),
              let message=teaching.conversations[documentID]?[index],message.role=="assistant",message.completed==true,!message.failed,message.inkApplied != true,
              let context=message.context,context.documentID==documentID,context.inkCanvas != nil,
              let document=library.first(where:{$0.id==documentID}),document.kind=="pdf",
              let pdf=makeSlidePDF(document:document),let page=pdf.page(at:context.page-1),let ref=page.pageRef else{return 0}
        let plan=InkPlan.parse(message.text)
        teaching.conversations[documentID]![index].inkApplied=true
        teaching.conversations[documentID]![index].text=InkPlan.visibleText(message.text)
        let crop=page.bounds(for:.cropBox),canvas=InkCanvas.capture(page:page,region:nil),size=CGSize(width:canvas.width,height:canvas.height)
        let transform=ref.getDrawingTransform(.cropBox,rect:CGRect(origin:.zero,size:size),rotate:0,preserveAspectRatio:true),inverse=transform.inverted()
        var marks:[SlideMark]=[]
        // Prefer the known selection for fallback; never invent a target from a failed/malformed plan.
        if plan==nil,let r=context.inkCanvas?.selection,r.count==4 {
            let rect=CGRect(x:r[0]*size.width,y:(1-r[1]-r[3])*size.height,width:r[2]*size.width,height:r[3]*size.height).applying(inverse).intersection(crop)
            if !rect.isEmpty{marks.append(SlideMark(kind:"ellipse",color:"#C23B2E",x:rect.minX,y:rect.minY,width:rect.width,height:rect.height,page:context.page-1,answerID:answerID))}
        }
        let lines=(page.selection(for:crop)?.selectionsByLine() ?? []).map{$0.bounds(for:page).insetBy(dx:-3,dy:-3)}
        let old=slideEdits.projects[documentID] ?? SlideProject()
        var occupied=lines+old.marks.filter{$0.page==context.page-1 && ["label","text","image"].contains($0.kind)}.map{$0.rect.insetBy(dx:-4,dy:-4)}
        for item in (plan?.marks ?? []).prefix(10) {
            guard ["ellipse","rectangle","arrow","underline","label"].contains(item.kind),[item.x,item.y,item.w,item.h].allSatisfy({$0.isFinite && $0>=0 && $0<=1}),item.w>0,item.h>0,item.x+item.w<=1.001,item.y+item.h<=1.001 else{continue}
            var rect=CGRect(x:item.x*size.width,y:(1-item.y-item.h)*size.height,width:item.w*size.width,height:item.h*size.height).applying(inverse).intersection(crop)
            guard rect.width>=4,rect.height>=2 else{continue}
            var text="";let font=max(11,min(20,min(crop.width,crop.height)*0.023))
            if item.kind=="label" {
                text=String((item.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines).prefix(60));guard !text.isEmpty else{continue}
                // Keep short notes readable, and move them into whitespace instead of covering slide text.
                rect.size.width=min(crop.width*0.38,max(rect.width,min(crop.width*0.38,CGFloat(text.count)*font*0.6+14)))
                let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping;paragraph.lineSpacing=3
                let measured=(text as NSString).boundingRect(with:CGSize(width:rect.width-10,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:NSFont.systemFont(ofSize:font,weight:.medium),.paragraphStyle:paragraph])
                rect.size.height=max(28,ceil(measured.height)+14)
                guard rect.height<crop.height*0.24 else{continue}
                rect.origin.x=min(max(crop.minX+8,rect.minX),crop.maxX-rect.width-8);rect.origin.y=min(max(crop.minY+8,rect.minY),crop.maxY-rect.height-8)
                func fits(_ r:CGRect)->Bool{crop.insetBy(dx:6,dy:6).contains(r) && !occupied.contains{$0.intersects(r)}}
                if !fits(rect) {
                    var free:CGRect?
                    for y in stride(from:crop.maxY-rect.height-10,through:crop.minY+10,by:-max(16,font)) {
                        for x in stride(from:crop.minX+10,through:crop.maxX-rect.width-10,by:max(20,crop.width/12)) {
                            let candidate=CGRect(x:x,y:y,width:rect.width,height:rect.height)
                            if fits(candidate){free=candidate;break}
                        };if free != nil{break}
                    }
                    guard let free else{continue};rect=free
                }
                occupied.append(rect.insetBy(dx:-4,dy:-4))
            }
            marks.append(SlideMark(kind:item.kind,text:text,color:"#C23B2E",fontSize:font,x:rect.minX,y:rect.minY,width:rect.width,height:rect.height,page:context.page-1,rotation:max(0,min(3,item.rotation ?? 0)),answerID:answerID))
        }
        guard !marks.isEmpty else{return 0}
        slideUndo[documentID,default:[]].append(old);if slideUndo[documentID]!.count>40{slideUndo[documentID]!.removeFirst()};slideRedo[documentID]=[]
        slideEdits.projects[documentID,default:SlideProject()].marks += marks
        slideRevision+=1;saveSlides();return marks.count
    }
    func removeTeacherInk(_ answerID:String){
        guard let doc=selectedID,slidesWritable,currentSlideProject.marks.contains(where:{$0.answerID==answerID}) else{return}
        rememberSlideUndo();slideEdits.projects[doc]?.marks.removeAll{$0.answerID==answerID};selectedSlideMarkID=nil;slideRevision+=1;saveSlides();tutorRevision+=1;tutorStatus="已撤销这次红笔批注，讲解仍保留"
    }
}
