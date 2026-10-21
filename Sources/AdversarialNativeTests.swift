import AppKit
import WebKit
import PDFKit

@MainActor private final class AuditBridge:NSObject,WKScriptMessageHandler {
    var messages:[[String:Any]]=[]
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){if let data=message.body as? [String:Any]{messages.append(data)}}
}
@MainActor enum AdversarialNativeTests {
    static func run(model:AppModel,window:NSWindow)async {
        guard ProcessInfo.processInfo.environment["SHIYE_DATA_DIR"] != nil else{return}
        var checks:[String:Bool]=[:];var failure=""
        func pause(_ seconds:Double=0.35)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
        let bridge=AuditBridge(),config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();config.userContentController.add(bridge,name:"teacher")
        let web=WKWebView(frame:CGRect(x:0,y:0,width:320,height:720),configuration:config)
        let panel=NSWindow(contentRect:web.frame,styleMask:[.titled,.resizable],backing:.buffered,defer:false);panel.contentView=web;panel.title="deep-teach · synthetic bilingual audit";panel.isReleasedWhenClosed=false
        defer{panel.close();web.configuration.userContentController.removeScriptMessageHandler(forName:"teacher")}
        do{
            model.autoSync=false;model.study.autoEnabled=false
            checks["english_first_run_guide"]=AppLanguage.code=="en" && AppModel.welcome.contains("Welcome to deep-teach")
            checks["english_native_menu"]=NSApp.mainMenu?.items.contains{$0.submenu?.title=="File"}==true
            let originalIDs=model.library.map{$0.id},theme=model.theme
            model.search="English 中文 🧪";model.importURLText="https://example.com/未提交";model.setLanguage("zh");model.setLanguage("en")
            checks["language_switch_keeps_native_drafts_and_ids"]=model.search=="English 中文 🧪" && model.importURLText=="https://example.com/未提交" && model.theme==theme && model.library.map{$0.id}==originalIDs
            model.search=""
            checks["utf8_and_utf16_bilingual_decode"] = try decodeText(Data("中文 English 🧪".utf8))=="中文 English 🧪" && decodeText("中文 English 🧪".data(using:.utf16)!)=="中文 English 🧪"
            do{_ = try decodeText(Data([0xD6,0xD0,0xCE,0xC4]));checks["ambiguous_legacy_encoding_rejected"]=false}catch{checks["ambiguous_legacy_encoding_rejected"]=error.localizedDescription.contains("UTF-8")}
            let untrusted="<html><title>中文 English 🧪</title><body><p>双语 DNA entropy 🧪 é</p><script>window.ATTACK=true</script><img src='file:///etc/passwd' onerror='alert(1)'><a href='javascript:alert(1)'>恶意链接</a><iframe src='https://example.com'></iframe></body></html>"
            let article=try await model.processor.extract(untrusted)
            checks["bilingual_import_sanitizes_active_content"]=article.text.contains("双语 DNA entropy 🧪") && !article.html.contains("<script") && !article.html.contains("onerror") && !article.html.contains("file://") && !article.html.contains("javascript:") && !article.html.contains("<iframe")
            let d=try model.store.addArticle(title:article.title,html:article.html,text:article.text,kind:"html");model.library=model.store.state.documents;model.selectDocument(d.id)
            let before=model.tutorMessages.count;model.sendTeacher("Synthetic cancellation test");model.stopTeacher();await pause()
            checks["stop_during_preparation_cannot_launch_request"]=model.teacherProcess==nil && !model.tutorBusy && model.tutorMessages.count==before
            model.showTutor=false;model.showNotes=false;await pause(0.7)
            func allWebs(_ view:NSView)->[WKWebView]{(view as? WKWebView).map{[$0]} ?? view.subviews.flatMap{allWebs($0)}}
            if let reader=allWebs(window.contentView!).first {
                _ = try await reader.evaluateJavaScript("(()=>{let r=document.createRange();r.selectNodeContents(document.querySelector('#article-body p'));getSelection().removeAllRanges();getSelection().addRange(r);return true})()")
                await pause();let quote=model.selectionText
                model.setLanguage("zh");await pause()
                let retained=try await reader.evaluateJavaScript("getSelection().toString()") as? String
                checks["language_switch_preserves_article_selection"]=retained==quote
                model.setLanguage("en");await pause()
                checks["reader_language_switches_without_reload"]=(try await reader.evaluateJavaScript("document.documentElement.lang") as? String)=="en"
                model.addHighlight();await pause()
                let painted=try await reader.evaluateJavaScript("document.querySelector('mark')?.textContent") as? String
                checks["mixed_unicode_selection_and_highlight_roundtrip"]=quote=="双语 DNA entropy 🧪 é" && model.currentHighlights.last?.quote==quote && painted==quote
                if let mark=model.currentHighlights.last {
                    model.updateHighlight(id:mark.id,note:"Personal note 我的补充 🧪",tags:"biology 生物")
                    let vault=model.store.root.appendingPathComponent("合成 Vault 🧪");try FileManager.default.createDirectory(at:vault,withIntermediateDirectories:true);model.vaultPath=vault.path;model.syncNow()
                    let syncFolder=vault.appendingPathComponent("Bandu"),file=try FileManager.default.contentsOfDirectory(at:syncFolder,includingPropertiesForKeys:nil).first{$0.pathExtension=="md"}!
                    var contents=try String(contentsOf:file,encoding:.utf8);checks["english_obsidian_headings"]=contents.contains("## My notes") && contents.contains("Read in deep-teach")
                    contents+="\nUser-owned 手写 notes — never translate.\n";try contents.write(to:file,atomically:true,encoding:.utf8)
                    model.setLanguage("zh");model.syncNow();let updated=try String(contentsOf:file,encoding:.utf8)
                    checks["language_switch_sync_preserves_personal_notes"]=updated.contains("User-owned 手写 notes — never translate.") && updated.contains("Personal note 我的补充 🧪")
                    model.setLanguage("en")
                }
            }
            let resources=Bundle.main.resourceURL!.appendingPathComponent("TeacherUI");web.loadFileURL(resources.appendingPathComponent("index.html"),allowingReadAccessTo:resources);panel.makeKeyAndOrderFront(nil)
            for _ in 0..<80 {if bridge.messages.contains(where:{$0["type"] as? String=="ready"}){break};await pause(0.1)}
            checks["teacher_bridge_ready"]=bridge.messages.contains{$0["type"] as? String=="ready"}
            let quiz="```dsh-ui\n{\"type\":\"quiz\",\"question\":\"DNA / RNA 核酸\",\"options\":[{\"label\":\"Uracil 尿嘧啶\",\"correct\":true}]}\n```"
            func payload(_ language:String,_ messages:[[String:Any]]=[])->[String:Any]{["language":language,"hasImageSelection":true,"selectionRequest":"synthetic","theme":"纸白","title":"Synthetic lesson 合成课件","selectionLabel":"","provider":"codex","level":"学过但模糊","busy":false,"status":"","messages":messages]}
            func receive(_ data:[String:Any])async throws {let json=String(data:try JSONSerialization.data(withJSONObject:data),encoding:.utf8)!;_ = try await web.evaluateJavaScript("window.teacher.receive(\(json))");await pause()}
            func bool(_ js:String)async throws->Bool {(try await web.evaluateJavaScript(js) as? Bool)==true}
            func type(_ text:String)async throws {let json=try jsonText(text);_ = try await web.evaluateJavaScript("(()=>{const e=document.querySelector('textarea');Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(e,\(json));e.dispatchEvent(new Event('input',{bubbles:true}));return true})()");await pause(0.1)}
            for language in ["en","zh"] {
                try await receive(payload(language))
                checks[language+"_html_lang"] = try await bool("document.documentElement.lang===\(try jsonText(language=="en" ? "en":"zh-Hans"))")
                checks[language+"_selection_focus"] = try await bool("document.activeElement===document.querySelector('textarea')")
                checks[language+"_teacher_labels"] = try await bool(language=="en" ? "document.querySelector('h1').textContent==='Tutor' && document.querySelector('.selection-explain').textContent==='Explain selected area'":"document.querySelector('h1').textContent==='老师' && document.querySelector('.selection-explain').textContent==='讲解所选区域'")
                for width in [320,360,480] {
                    panel.setContentSize(CGSize(width:width,height:720));await pause()
                    checks[language+"_no_horizontal_overflow_\(width)"] = try await bool("document.documentElement.scrollWidth<=innerWidth+1 && [...document.querySelectorAll('.selection-bar button,.send')].every(e=>e.getBoundingClientRect().right<=innerWidth+1)")
                }
                try await type("尚未发送 Unsent 🧪");let sentBefore=bridge.messages.filter{$0["type"] as? String=="send"}.count
                _ = try await web.evaluateJavaScript("(()=>{let e=document.querySelector('textarea');e.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,data:'拼'}));e.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Enter',metaKey:true,isComposing:true}));return true})()")
                await pause();checks[language+"_ime_enter_not_sent"]=bridge.messages.filter{$0["type"] as? String=="send"}.count==sentBefore
                _ = try await web.evaluateJavaScript("document.querySelector('textarea').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'拼'}))")
                try await type(String(repeating:"🧪",count:5001));_ = try await web.evaluateJavaScript("document.querySelector('.send').click()")
                checks[language+"_overlong_draft_preserved"] = try await bool("Array.from(document.querySelector('textarea').value).length===5001 && document.querySelector('.send').disabled")
                checks[language+"_overlong_not_sent"]=bridge.messages.filter{$0["type"] as? String=="send"}.count==sentBefore
                try await type("正常问题 Valid question 🧪");_ = try await web.evaluateJavaScript("document.querySelector('textarea').dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Enter',metaKey:true}))")
                await pause();checks[language+"_shortcut_sends_once"]=bridge.messages.filter{$0["type"] as? String=="send"}.count==sentBefore+1 && bridge.messages.last(where:{$0["type"] as? String=="send"})?["question"] as? String=="正常问题 Valid question 🧪"
            }
            let messages:[[String:Any]]=[["id":"answer","role":"assistant","text":quiz,"saved":false,"page":1]]
            try await receive(payload("zh",messages));_ = try await web.evaluateJavaScript("document.querySelector('.quiz-option').click()")
            try await type("我的草稿 Unsent draft {1} 🧪");try await receive(payload("en",messages))
            checks["language_switch_preserves_teacher_draft"] = try await bool("document.querySelector('textarea').value==='我的草稿 Unsent draft {1} 🧪'")
            checks["language_switch_preserves_quiz_state_and_source"] = try await bool("document.querySelector('.quiz-option').classList.contains('correct') && document.querySelector('.quiz-feedback').textContent.includes('Correct') && document.querySelector('.quiz').textContent.includes('Uracil 尿嘧啶')")
            checks["english_page_label"] = try await bool("document.querySelector('.meta').textContent==='Page 1'")
            if let image=try? await web.takeSnapshot(configuration:nil),let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data){try bitmap.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent("english-teacher.png"))}
            model.setLanguage("en");model.showTutor=false;model.showStudyNotes=true;model.showSettings=true;await pause(0.6)
            if let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent("english-native.png"))}
            checks["language_settings_sheet_available"]=window.attachedSheet != nil
            if let sheet=window.attachedSheet,let view=sheet.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:model.store.root.appendingPathComponent("english-settings.png"))}
            model.showSettings=false
        }catch{failure=String(describing:error)}
        let result:[String:Any]=["checks":checks,"error":failure,"passed":!checks.values.contains(false)&&failure.isEmpty]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:model.store.root.appendingPathComponent("adversarial-native.json"))}
    }
}
