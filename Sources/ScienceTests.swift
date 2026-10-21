import AppKit
import WebKit
import PDFKit
@MainActor enum ScienceTests {
 static func run(model:AppModel,window:NSWindow)async {
    var checks:[String:Bool]=[:];var error=""
    func pause(_ seconds:Double=1)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    func webs(_ v:NSView)->[WKWebView]{(v as? WKWebView).map{[$0]} ?? v.subviews.flatMap{webs($0)}}
    do{
        guard let fixture=Bundle.main.url(forResource:"science-fixture",withExtension:"json"),let id=model.selectedID,let doc=model.selectedDocument else{throw ReaderError.message("Missing isolated science fixture")}
        let blocks=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture)) as! [[String:Any]]
        for block in blocks {
            guard let type=block["type"] as? String,["derivation","lewis","conceptmap"].contains(type) else{continue}
            let json=String(data:try JSONSerialization.data(withJSONObject:block),encoding:.utf8)!
            model.teaching.conversations[id]=[TeacherMessage(id:"science-"+type,role:"assistant",text:"```dsh-ui\n"+json+"\n```",page:1,completed:true)]
            model.tutorRevision+=1;model.slideEditing=false;model.showTutor=true;model.showNotes=true;await pause(2)
            if let web=webs(window.contentView!).first {
                checks[type+"_renders"]=(try await web.evaluateJavaScript("document.querySelector('.bd-card')!==null && document.querySelector('[role=alert]')===null") as? Bool)==true
                let count=model.currentSlideProject.pages.count
                _=try await web.evaluateJavaScript("document.querySelectorAll('.visual-clip-actions button')[1]?.click()")
                await pause(1.5);checks[type+"_adds_page"]=model.currentSlideProject.pages.count==count+1
                if let asset=model.currentSlideProject.marks.last?.asset,let image=model.slideImage(asset),let data=image.tiffRepresentation,let rep=NSBitmapImageRep(data:data){try rep.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent(type+"-capture.png"))}
            }
        }
        if let pdf=model.makeSlidePDF(document:doc){try SlidePDF.export(pdf,to:model.store.root.appendingPathComponent("science-validation.pdf"));checks["science_pdf_pages"]=pdf.pageCount>=7}
    }catch let e{error=e.localizedDescription}
    if let data=try? JSONSerialization.data(withJSONObject:["checks":checks,"error":error,"passed":checks.count==7 && error.isEmpty && !checks.values.contains(false)],options:[.prettyPrinted,.sortedKeys]){try? data.write(to:model.store.root.appendingPathComponent("science-validation.json"))}
 }
}
