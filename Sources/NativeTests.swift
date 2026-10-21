import Foundation
import AppKit
import PDFKit
import WebKit
@MainActor enum NativeTests {
 static func run(model:AppModel,window:NSWindow)async {
    let reportURL=model.store.root.appendingPathComponent("native-test.json")
    var checks:[String:Bool]=[:];var details:[String:String]=[:]
    func pause(_ seconds:Double)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    func descendants<T:NSView>(_ v:NSView,_ type:T.Type)->[T]{(v as? T).map{[$0]} ?? v.subviews.flatMap{descendants($0,type)}}
    do{
        model.autoSync=false;model.vaultPath=model.store.root.appendingPathComponent("test-vault").path;try FileManager.default.createDirectory(atPath:model.vaultPath,withIntermediateDirectories:true)
        await pause(2)
        if let fixtures=ProcessInfo.processInfo.environment["SHIYE_TEST_FIXTURES"] {
            let folder=URL(fileURLWithPath:fixtures)
            let md=try await model.importFile(folder.appendingPathComponent("阅读测试.md"))
            let mdHTML=try String(contentsOf:model.store.root.appendingPathComponent(md.relativePath),encoding:.utf8)
            checks["markdown_structural_import"]=md.kind=="markdown" && mdHTML.contains("<strong>粗体</strong>") && mdHTML.contains("<ul>") && mdHTML.contains("<code")
            let epub=try await model.importFile(folder.appendingPathComponent("双章节测试.epub"))
            let epubHTML=try String(contentsOf:model.store.root.appendingPathComponent(epub.relativePath),encoding:.utf8)
            checks["epub_order_and_sanitization"]=epub.kind=="epub" && epubHTML.contains("第一章正文") && epubHTML.contains("第二章正文") && !epubHTML.contains("<script") && epubHTML.range(of:"第一章正文")!.lowerBound < epubHTML.range(of:"第二章正文")!.lowerBound
        }
        if let webURL=ProcessInfo.processInfo.environment["SHIYE_TEST_WEB_URL"] {
            model.importURLText=webURL;await model.importWebURL()
            checks["public_url_import"]=model.selectedDocument?.sourceURL==webURL && model.errorMessage==nil
            if let error=model.errorMessage{details["web_error"]=error;model.errorMessage=nil}
        }
        let malicious="<html><title>阅读测试</title><body><h2>Chapter One</h2><p>Alpha beta gamma 中文阅读测试。稳定批注应该在重新打开之后准确恢复。</p><p>Second paragraph for annotation anchoring.</p><script>window.EVIL=true</script><img src=x onerror='alert(1)'></body></html>"
        let article=try await model.processor.extract(malicious)
        checks["sanitize_script_and_event"]=(!article.html.contains("<script") && !article.html.contains("onerror"))
        let d=try model.store.addArticle(title:"阅读与批注验证",html:article.html,text:article.text,kind:"html");model.library=model.store.state.documents;model.selectDocument(d.id)
        await pause(1.2)
        guard let web=descendants(window.contentView!,WKWebView.self).first else{throw ReaderError.message("没有找到文章 WebView")}
        let selectJS="const r=document.createRange();const n=document.querySelector('#article-body p').firstChild;r.setStart(n,0);r.setEnd(n,16);getSelection().removeAllRanges();getSelection().addRange(r);true"
        _=try await web.evaluateJavaScript(selectJS);await pause(0.3);checks["web_selection_bridge"]=model.selectionText=="Alpha beta gamma"
        model.addHighlight();await pause(0.4)
        checks["web_highlight_paint"]=(try await web.evaluateJavaScript("document.querySelectorAll('mark[data-id]').length") as? Int ?? 0)>0
        guard let h=model.currentHighlights.first else{throw ReaderError.message("高亮没有保存")}
        model.updateHighlight(id:h.id,note:"这是持久化的中文笔记。",tags:"复习, biology");model.syncNow()
        checks["sync_from_app"]=model.syncStatus.contains("已同步")
        let reopened=try LibraryStore(root:model.store.root);checks["notes_persisted"]=reopened.state.highlights.contains{$0.id==h.id&&$0.note=="这是持久化的中文笔记。"}
        if let image=try? await web.takeSnapshot(configuration:nil),let tiff=image.tiffRepresentation,let bmp=NSBitmapImageRep(data:tiff),let png=bmp.representation(using:.png,properties:[:]){try png.write(to:model.store.root.appendingPathComponent("article-preview.png"))}
        // A synthetic PDF with a real text layer, independent of the user's documents.
        let pdfURL=model.store.root.appendingPathComponent("fixture.pdf");let data=NSMutableData();var box=CGRect(x:0,y:0,width:612,height:792);let consumer=CGDataConsumer(data:data as CFMutableData)!,context=CGContext(consumer:consumer,mediaBox:&box,nil)!
        context.beginPDFPage(nil);let gc=NSGraphicsContext(cgContext:context,flipped:false);NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=gc
        NSAttributedString(string:"Local reading should keep your notes safe.",attributes:[.font:NSFont.systemFont(ofSize:20),.foregroundColor:NSColor.black]).draw(at:CGPoint(x:50,y:650));NSGraphicsContext.restoreGraphicsState();context.endPDFPage();context.closePDF();try (data as Data).write(to:pdfURL)
        await model.importURLs([pdfURL]);await pause(0.8)
        guard let pv=descendants(window.contentView!,PDFView.self).first,let page=pv.document?.page(at:0),let selection=page.selection(for:NSRange(location:0,length:13)) else{throw ReaderError.message("PDF text selection unavailable")}
        pv.setCurrentSelection(selection,animate:false);await pause(0.3);checks["pdf_selection_bridge"] = !model.selectionText.isEmpty;model.addHighlight();await pause(0.4)
        checks["pdf_annotation_rendered"]=page.annotations.contains{$0.type=="Highlight"};checks["pdf_source_unchanged"]=(PDFDocument(url:pdfURL)?.page(at:0)?.annotations.isEmpty==true)
        let pdfID=model.selectedID!;let pdfH=model.currentHighlights.first!;model.selectDocument(d.id);await pause(0.7);model.handleDeepLink(URL(string:"shiye://document/\(pdfID)?highlight=\(pdfH.id)")!);await pause(0.6)
        checks["deep_link_selects_document_and_annotation"]=model.selectedID==pdfID&&model.selectedHighlightID==pdfH.id
        // Return to article for human visual verification.
        model.selectDocument(d.id);await pause(0.7);model.goToHighlight(h)
        checks["render_restores_saved_highlight"]=(try await descendants(window.contentView!,WKWebView.self).first?.evaluateJavaScript("document.querySelectorAll('mark[data-id]').length") as? Int ?? 0)>0
    }catch{details["error"]=error.localizedDescription}
    let report:[String:Any]=["checks":checks,"details":details,"passed":!checks.values.contains(false)&&details.isEmpty]
    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:reportURL)}
 }
}
