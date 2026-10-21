import SwiftUI
import AppKit
import WebKit
import PDFKit

func markColor(_ name:String)->NSColor {
    switch name {case "green":return NSColor(calibratedRed:0.45,green:0.77,blue:0.53,alpha:0.45);case "blue":return NSColor(calibratedRed:0.38,green:0.65,blue:0.95,alpha:0.4);case "pink":return NSColor(calibratedRed:0.95,green:0.49,blue:0.63,alpha:0.4);default:return NSColor(calibratedRed:1,green:0.82,blue:0.25,alpha:0.5)}
}
struct ReaderSurface:View {
    @ObservedObject var model:AppModel
    var body:some View{Group{if let d=model.selectedDocument {if d.kind=="pdf"{PDFSurface(model:model,document:d).id(d.id)}else{ArticleSurface(model:model,document:d).id(d.id)}}else{VStack(spacing:12){Image(systemName:"book.closed").font(.system(size:42));Text("选择一篇文档，开始阅读").font(.title3);Button("导入文档"){model.importFiles()}}.frame(maxWidth:.infinity,maxHeight:.infinity)}}}
}
struct PDFSurface:NSViewRepresentable {
    @ObservedObject var model:AppModel;let document:ReaderDocument
    func makeCoordinator()->Coordinator{Coordinator(model:model,document:document)}
    func makeNSView(context:Context)->PDFView {
        let view=PDFView();view.wantsLayer=true;view.layer?.masksToBounds=true;view.autoScales=true;view.displayMode = .singlePageContinuous;view.displayDirection = .vertical;view.displaysPageBreaks=true;view.backgroundColor = NSColor(calibratedWhite:0.92,alpha:1)
        view.document=PDFDocument(url:model.store.url(for:document));context.coordinator.view=view;model.activePDF=view;context.coordinator.basePageCount=view.document?.pageCount ?? 0
        let overlay=BoxOverlay(frame:view.bounds);overlay.wantsLayer=true;overlay.layer?.masksToBounds=true;overlay.autoresizingMask=[.width,.height];overlay.model=model;overlay.pdfView=view;view.addSubview(overlay)
        let editor=SlideOverlay(frame:view.bounds);editor.wantsLayer=true;editor.layer?.masksToBounds=true;editor.autoresizingMask=[.width,.height];editor.model=model;editor.pdfView=view;view.addSubview(editor);context.coordinator.editor=editor
        context.coordinator.observers.append(NotificationCenter.default.addObserver(forName:.PDFViewSelectionChanged,object:view,queue:.main){[weak c=context.coordinator] _ in MainActor.assumeIsolated{c?.selection()}})
        context.coordinator.observers.append(NotificationCenter.default.addObserver(forName:.PDFViewPageChanged,object:view,queue:.main){[weak c=context.coordinator] _ in MainActor.assumeIsolated{c?.pageChanged()}})
        if let clip=view.documentView?.enclosingScrollView?.contentView {clip.postsBoundsChangedNotifications=true;context.coordinator.observers.append(NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:clip,queue:.main){[weak editor,weak overlay] _ in MainActor.assumeIsolated{editor?.needsDisplay=true;overlay?.needsDisplay=true}})}
        context.coordinator.observers.append(NotificationCenter.default.addObserver(forName:.PDFViewScaleChanged,object:view,queue:.main){[weak editor,weak overlay] _ in MainActor.assumeIsolated{editor?.needsDisplay=true;overlay?.needsDisplay=true}})
        DispatchQueue.main.async{if let page=view.document?.page(at:document.page){view.go(to:page)};context.coordinator.paint();context.coordinator.pageChanged();if let id=model.jumpID{context.coordinator.jump(id)}}
        return view
    }
    func updateNSView(_ view:PDFView,context:Context){let c=context.coordinator;view.subviews.compactMap{$0 as? BoxOverlay}.first?.refresh();if c.slideRevision != model.slideRevision{c.slideRevision=model.slideRevision;c.paintSlides()};c.editor?.needsDisplay=true;if c.revision != model.readerRevision{c.revision=model.readerRevision;c.paint()};view.backgroundColor=model.theme=="夜读" ? .darkGray:NSColor(calibratedWhite:0.92,alpha:1)
        if c.commandID != model.commandID{c.commandID=model.commandID;let command=model.readerCommand
            if command=="zoomIn"{view.zoomIn(nil)}else if command=="zoomOut"{view.zoomOut(nil)}else if command=="clearSelection"{view.clearSelection()}else if command.hasPrefix("page:"),let index=Int(command.dropFirst(5)),let page=view.document?.page(at:index){view.go(to:page)}else if command=="jump",let id=model.jumpID{c.jump(id)}else if command.hasPrefix("find:"){let text=String(command.dropFirst(5));if !text.isEmpty,let match=view.document?.findString(text,fromSelection:view.currentSelection,withOptions:[.caseInsensitive]) ?? view.document?.findString(text,fromSelection:nil,withOptions:[.caseInsensitive]){view.setCurrentSelection(match,animate:true);view.go(to:match)}}}
    }
    static func dismantleNSView(_ nsView:PDFView,coordinator:Coordinator){coordinator.observers.forEach{NotificationCenter.default.removeObserver($0)}}
    @MainActor final class Coordinator:NSObject{
        let model:AppModel;let document:ReaderDocument;weak var view:PDFView?;var observers:[NSObjectProtocol]=[];var annotations:[PDFAnnotation]=[];var revision = -1;var commandID:UUID?;var slideRevision = -1;var basePageCount=0;var slideAnnotations:[PDFAnnotation]=[];weak var editor:SlideOverlay?
        init(model:AppModel,document:ReaderDocument){self.model=model;self.document=document}
        func selection(){guard let v=view,let s=v.currentSelection,let quote=s.string,!quote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let pdf=v.document else{return};var boxes:[PDFRegion]=[]
            for line in s.selectionsByLine(){for page in line.pages{let b=line.bounds(for:page);if !b.isEmpty{boxes.append(PDFRegion(page:pdf.index(for:page),x:b.minX,y:b.minY,width:b.width,height:b.height))}}}
            model.receiveSelection(SelectionAnchor(quote:quote,regions:boxes))
        }
        func paintSlides(){
            guard let pdf=view?.document else{return};let project=model.slideEdits.projects[document.id] ?? SlideProject()
            for a in slideAnnotations{a.page?.removeAnnotation(a)};slideAnnotations=[]
            while pdf.pageCount>basePageCount+project.pages.count{pdf.removePage(at:pdf.pageCount-1)}
            while pdf.pageCount<basePageCount+project.pages.count{let extra=project.pages[pdf.pageCount-basePageCount];guard let page=SlidePDF.blank(CGSize(width:extra.width,height:extra.height)) else{break};pdf.insert(page,at:pdf.pageCount)}
            for mark in project.marks{guard let page=pdf.page(at:mark.page) else{continue};let annotation=SlideAnnotation(mark:mark,image:model.slideImage(mark.asset));page.addAnnotation(annotation);slideAnnotations.append(annotation)}
            view?.needsDisplay=true;editor?.needsDisplay=true
        }
        func paint(){paintSlides();guard let pdf=view?.document else{return};for a in annotations{a.page?.removeAnnotation(a)};annotations=[]
            for h in model.highlights where h.documentID==document.id{for r in h.regions{guard let page=pdf.page(at:r.page) else{continue};let a=PDFAnnotation(bounds:CGRect(x:r.x,y:r.y,width:r.width,height:r.height),forType:.highlight,withProperties:nil);a.color=markColor(h.color);a.contents=h.note.isEmpty ? h.quote:h.note;page.addAnnotation(a);annotations.append(a)}}
        }
        func pageChanged(){guard let v=view,let pdf=v.document,let page=v.currentPage else{return};let i=pdf.index(for:page);model.pageLabel="\(i+1) / \(pdf.pageCount) 页";model.markProgress(pdf.pageCount>1 ? Double(i)/Double(pdf.pageCount-1):0,page:i);editor?.needsDisplay=true}
        func jump(_ id:String){guard let h=model.highlights.first(where:{$0.id==id}) else{return};if let r=h.regions.first,let page=view?.document?.page(at:r.page){view?.go(to:CGRect(x:r.x-20,y:r.y-80,width:r.width+40,height:r.height+160),on:page)}else if let index=h.page,let page=view?.document?.page(at:index){view?.go(to:page)}}
    }
}
struct ArticleSurface:NSViewRepresentable {
    @ObservedObject var model:AppModel;let document:ReaderDocument
    func makeCoordinator()->Coordinator{Coordinator(model:model,document:document)}
    func makeNSView(context:Context)->WKWebView{
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();config.userContentController.add(context.coordinator,name:"reader")
        let web=WKWebView(frame:.zero,configuration:config);web.setValue(false,forKey:"drawsBackground");web.navigationDelegate=context.coordinator;context.coordinator.web=web
        if let u=Bundle.main.url(forResource:"reader",withExtension:"html"){web.loadFileURL(u,allowingReadAccessTo:u.deletingLastPathComponent())}
        return web
    }
    func updateNSView(_ web:WKWebView,context:Context){let c=context.coordinator;guard c.ready else{return}
        if c.revision != model.readerRevision{c.revision=model.readerRevision;c.update()}
        if c.commandID != model.commandID{c.commandID=model.commandID;let command=model.readerCommand;if command=="jump",let id=model.jumpID{c.eval("window.reader.jump(\((try? jsonText(id)) ?? "null"))")}else if command=="clearSelection"{c.eval("window.reader.clearSelection()")}else if command.hasPrefix("find:"){c.eval("window.reader.find(\((try? jsonText(String(command.dropFirst(5)))) ?? "null"))")}}
    }
    static func dismantleNSView(_ web:WKWebView,coordinator:Coordinator){web.configuration.userContentController.removeScriptMessageHandler(forName:"reader");web.stopLoading()}
    @MainActor final class Coordinator:NSObject,WKScriptMessageHandler,WKNavigationDelegate{
        let model:AppModel;let document:ReaderDocument;weak var web:WKWebView?;var ready=false;var revision = -1;var commandID:UUID?
        init(model:AppModel,document:ReaderDocument){self.model=model;self.document=document}
        func eval(_ js:String){web?.evaluateJavaScript(js){[weak self] _,error in if let error{self?.model.status="阅读操作未完成：\(error.localizedDescription)"}}}
        func payload(includeHTML:Bool)->[String:Any]{var p:[String:Any]=["title":document.title,"kind":document.kind,"sourceURL":document.sourceURL ?? "","progress":document.progress,"theme":model.theme,"fontSize":model.fontSize,"jumpID":model.jumpID ?? ""]
            p["highlights"]=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(model.highlights.filter{$0.documentID==document.id}))) ?? []
            if includeHTML{p["html"]=(try? String(contentsOf:model.store.url(for:document),encoding:.utf8)) ?? "<p>无法读取本地正文，请从备份恢复。</p>"};return p}
        func call(_ method:String,html:Bool){guard let data=try? JSONSerialization.data(withJSONObject:payload(includeHTML:html)),let text=String(data:data,encoding:.utf8) else{return};eval("window.reader.\(method)(\(text))")}
        func update(){call("update",html:false)}
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){guard let b=message.body as? [String:Any],let type=b["type"] as? String else{return}
            switch type {
            case "ready":ready=true;revision=model.readerRevision;call("load",html:true)
            case "selection":guard let quote=b["quote"] as? String,let start=b["start"] as? Int,let end=b["end"] as? Int,start>=0,end>=start else{return};model.receiveSelection(SelectionAnchor(quote:quote,start:start,end:end,prefix:b["prefix"] as? String,suffix:b["suffix"] as? String))
            case "highlight":model.addHighlight()
            case "progress":if let p=b["value"] as? Double{model.markProgress(p)}
            case "selectedHighlight":if let id=b["id"] as? String{model.selectedHighlightID=id;model.showNotes=true}
            case "unresolved":model.status="部分批注无法自动定位，原文摘录仍保留在笔记中"
            case "external":if let s=b["url"] as? String,let u=URL(string:s),["https","http"].contains(u.scheme ?? ""){NSWorkspace.shared.open(u)}
            default:break
            }
        }
        func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){if navigationAction.navigationType == .linkActivated{if let u=navigationAction.request.url,["http","https"].contains(u.scheme ?? ""){NSWorkspace.shared.open(u)};decisionHandler(.cancel)}else{decisionHandler(.allow)}}
    }
}
