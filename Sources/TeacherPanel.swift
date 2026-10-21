import SwiftUI
import WebKit
import AppKit
struct TeacherPanel:NSViewRepresentable {
    @ObservedObject var model:AppModel
    func makeCoordinator()->Coordinator{Coordinator(model)}
    func makeNSView(context:Context)->WKWebView {
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();config.userContentController.add(context.coordinator,name:"teacher")
        let web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=context.coordinator;context.coordinator.web=web
        if let dir=Bundle.main.resourceURL?.appendingPathComponent("TeacherUI"){web.loadFileURL(dir.appendingPathComponent("index.html"),allowingReadAccessTo:dir)}
        return web
    }
    func updateNSView(_ web:WKWebView,context:Context){context.coordinator.update()}
    static func dismantleNSView(_ web:WKWebView,coordinator:Coordinator){web.configuration.userContentController.removeScriptMessageHandler(forName:"teacher");web.stopLoading()}
    @MainActor final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        var model:AppModel;weak var web:WKWebView?;var ready=false;var capturing=false;var lastSelectionRequest:UUID?
        init(_ model:AppModel){self.model=model}
        func update(){guard ready else{return};let data:[String:Any]=["hasImageSelection":model.selectedImageRegion != nil,"selectionRequest":model.selectionRequest.uuidString,"theme":model.theme,"title":model.selectedDocument?.title ?? "先打开一份资料","selectionLabel":model.selectedImage != nil ? "已框选图表":model.pending?.quote.isEmpty==false ? String(model.selectionText.prefix(90)):model.pageLabel.isEmpty ? "当前文章":"当前第 "+model.pageLabel,"provider":model.tutorProvider,"level":model.tutorLevel,"busy":model.tutorBusy,"status":model.tutorStatus,"messages":model.tutorMessages.map{message in ["id":message.id,"role":message.role,"text":InkPlan.visibleText(message.text),"inkCount":model.currentSlideProject.marks.filter{mark in mark.answerID==message.id}.count,"saved":message.saved,"page":message.page] as [String:Any]}]
            if let bytes=try? JSONSerialization.data(withJSONObject:data),let json=String(data:bytes,encoding:.utf8){web?.evaluateJavaScript("window.teacher?.receive(\(json))",completionHandler:nil)}
        }
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){guard let data=message.body as? [String:Any],let type=data["type"] as? String else{return}
            switch type {
            case "ready":ready=true;update()
            case "placeVisual":if let id=data["id"] as? String{captureVisual(id:id,newPage:data["newPage"] as? Bool ?? false)}
            case "send":if let text=data["question"] as? String{model.sendTeacher(text)}
            case "stop":model.stopTeacher()
            case "undoInk":if let id=data["id"] as? String{model.removeTeacherInk(id)}
            case "focusSelection":
                if data["request"] as? String==model.selectionRequest.uuidString,model.selectedImageRegion != nil,model.showTutor,!model.slideEditing,let web {web.window?.makeFirstResponder(web);web.evaluateJavaScript("document.querySelector('textarea')?.focus()",completionHandler:nil)}
            case "reselect":model.startBoxSelection()
            case "clearSelection":model.clearImageSelection()
            case "save":if let id=data["id"] as? String{model.saveTeacherAnswer(id)}
            case "explain":model.askTeacher()
            case "notes":model.showTutor=false;model.showNotes=true;model.showStudyNotes=false
            case "provider":if let value=data["value"] as? String,["codex","claude"].contains(value){model.tutorProvider=value;model.saveTeaching()}
            case "level":if let value=data["value"] as? String,["零基础","学过但模糊","比较熟悉"].contains(value){model.tutorLevel=value;model.saveTeaching()}
            default:break
            }
        }
        func captureVisual(id:String,newPage:Bool){
            guard !capturing,let web,model.selectedDocument?.kind=="pdf",let docID=model.selectedID else{model.status="先打开PDF或PPT课件，再放入图示";return}
            guard id.hasPrefix("clip-"),id.count<160 else{return};capturing=true
            Task { @MainActor in
                defer{capturing=false;web.evaluateJavaScript("window.finishVisualClip?.()",completionHandler:nil)}
                do{
                    let result=try await web.evaluateJavaScript("window.prepareVisualClip(\((try? jsonText(id)) ?? "null"))")
                    guard let r=result as? [String:Double],let width=r["width"],let height=r["height"],width>0,height>0 else{throw ReaderError.message("没有找到可用图示")}
                    try await Task.sleep(nanoseconds:120_000_000)
                    let config=WKSnapshotConfiguration();config.rect=CGRect(x:0,y:0,width:width,height:height);config.snapshotWidth=NSNumber(value:min(2400,max(1200,width*2)))
                    let image=try await web.takeSnapshot(configuration:config)
                    guard model.selectedID==docID else{throw ReaderError.message("课件已切换，请重新选择图示")}
                    _=try await web.evaluateJavaScript("window.finishVisualClip()")
                    try model.placeSlideImage(image,newPage:newPage)
                }catch{model.errorMessage="图示放入课件失败："+error.localizedDescription}
            }
        }
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){if action.navigationType == .linkActivated{if let url=action.request.url,["https","http"].contains(url.scheme ?? ""){NSWorkspace.shared.open(url)};decisionHandler(.cancel)}else{decisionHandler(.allow)}}
    }
}
