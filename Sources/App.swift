import SwiftUI
import AppKit
import Darwin

@main struct ShiyeMain {
    static func main(){let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);withExtendedLifetime(delegate){app.run()}}
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var window:NSWindow!;var model:AppModel!;var initialURLs:[URL]=[];var libraryLock:Int32 = -1
    func applicationDidFinishLaunching(_ notification:Notification){
        do{let env=ProcessInfo.processInfo.environment
            let root=env["SHIYE_DATA_DIR"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("BanduLibrary")
            if env["SHIYE_DATA_DIR"]==nil && !FileManager.default.fileExists(atPath:root.path) {
                let old=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Shiye")
                if FileManager.default.fileExists(atPath:old.appendingPathComponent("library.json").path){try FileManager.default.copyItem(at:old,to:root)}
            }
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            libraryLock=Darwin.open(root.appendingPathComponent(".library.lock").path,O_CREAT|O_RDWR,0o600)
            guard libraryLock>=0,flock(libraryLock,LOCK_EX|LOCK_NB)==0 else {
                if let running=NSRunningApplication.runningApplications(withBundleIdentifier:"local.nathan.bandu.unified").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}){running.activate(options:[.activateAllWindows,.activateIgnoringOtherApps])}
                throw ReaderError.message("这个资料库已在另一个伴读窗口中打开。请使用已打开的应用。")
            }
            let store=try LibraryStore(root:root);model=AppModel(store:store)
            window=NSWindow(contentRect:NSRect(x:0,y:0,width:1380,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="伴读";window.minSize=NSSize(width:1160,height:650);if !window.setFrameUsingName("ShiyeMain"){window.center()};window.setFrameAutosaveName("ShiyeMain");window.delegate=self;window.isReleasedWhenClosed=false
            window.contentView=NSHostingView(rootView:ContentView(model:model));menu();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            if !initialURLs.isEmpty{application(NSApp,open:initialURLs)}
            if env["SHIYE_DATA_DIR"] == nil {model.processStudyQueue()}
            if env["BANDU_INK_TEST"]=="1"{Task{await InkTests.run(model:model,window:window)}}
            if env["BANDU_SLIDE_TEST"]=="1"{Task{await SlideTests.run(model:model,window:window)}}
            if env["BANDU_STUDY_TEST"]=="1"{Task{await StudyTests.run(model:model,window:window)}}
            if env["BANDU_LAYOUT_TEST"]=="1"{Task{await LayoutIntegrationTests.run(model:model,window:window)}}
            if env["BANDU_INTEGRATION_TEST"]=="1"{Task{await IntegrationTests.run(model:model,window:window)}}
            if env["SHIYE_UI_TEST"]=="1"{Task{await NativeTests.run(model:model,window:window)}}
        }catch{let a=NSAlert();a.messageText="伴读无法打开资料库";a.informativeText=error.localizedDescription;a.runModal();NSApp.terminate(nil)}
    }
    func menu(){let root=NSMenu()
        func sub(_ title:String)->NSMenu{let item=NSMenuItem();item.submenu=NSMenu(title:title);root.addItem(item);return item.submenu!}
        func item(_ m:NSMenu,_ title:String,_ action:Selector,_ key:String=""){let i=NSMenuItem(title:title,action:action,keyEquivalent:key);i.target=self;m.addItem(i)}
        let a=sub("伴读");item(a,"关于伴读",#selector(about));item(a,"设置…",#selector(settings),",");a.addItem(.separator());item(a,"隐藏伴读",#selector(hide),"h");a.addItem(.separator());item(a,"退出伴读",#selector(quit),"q")
        let f=sub("文件");item(f,"导入文档…",#selector(importFile),"o");item(f,"保存网页文章…",#selector(importURL),"l");item(f,"同步到 Obsidian",#selector(sync),"s");item(f,"导出资料库备份…",#selector(backup))
        let e=sub("编辑");for(title,selector,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")]{e.addItem(NSMenuItem(title:title,action:Selector(selector),keyEquivalent:key))}
        let w=sub("窗口");let minimize=NSMenuItem(title:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m");w.addItem(minimize);w.addItem(.separator());item(w,"学习笔记 · 大屏复习",#selector(studyReview));item(w,"恢复默认布局",#selector(resetLayout));NSApp.windowsMenu=w;NSApp.mainMenu=root
    }
    @objc func studyReview(){model.openStudyReview()}
    @objc func resetLayout(){model.layout.resetAll()}
    @objc func about(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"伴读",.applicationVersion:(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")+" 学习与课件批注版",.credits:NSAttributedString(string:"本地阅读 · 划线批注 · Obsidian 同步\n界面设计：Claude Opus 5.5\n阅读本地免费；老师使用已有订阅额度，无新增 API 账单。")])}
    @objc func settings(){model.showSettings=true};@objc func hide(){NSApp.hide(nil)};@objc func quit(){NSApp.terminate(nil)};@objc func importFile(){model.importFiles()};@objc func importURL(){model.showURLImport=true};@objc func sync(){model.syncNow()};@objc func backup(){model.exportBackup()}
    func application(_ application:NSApplication,open urls:[URL]){guard model != nil else{initialURLs.append(contentsOf:urls);return};for url in urls{if url.scheme=="shiye"{model.handleDeepLink(url)}else if url.isFileURL{Task{await model.importURLs([url])}}};window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{window?.makeKeyAndOrderFront(nil);return true}
    func applicationWillTerminate(_ notification:Notification){model?.saveSlides();model?.pauseStudyProcess();model?.saveStudy(sync:false);model?.studyWindow?.saveFrame(usingName:"BanduStudyReview");model?.layout.save();window?.saveFrame(usingName:"ShiyeMain");model?.saveTeaching();model?.teacherProcess?.stop();model?.persist(sync:false);if model?.autoSync==true{model?.syncNow()}}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
}
