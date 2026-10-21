import AppKit
import PDFKit
import WebKit
@MainActor enum LayoutIntegrationTests {
 static func run(model: AppModel, window: NSWindow) async {
    guard ProcessInfo.processInfo.environment["SHIYE_DATA_DIR"] != nil else { return }
    var checks: [String: Bool] = [:]
    var error = ""
    func pause() async { try? await Task.sleep(nanoseconds: 600_000_000) }
    func webs(_ v: NSView) -> [WKWebView] { (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(webs) }
    do {
        model.autoSync = false
        model.layout.resetAll()
        let pdfURL = model.store.root.appendingPathComponent("layout-fixture.pdf")
        let pdf = PDFDocument()
        for i in 0..<3 {
            let image = NSImage(size: NSSize(width: 612, height: 792))
            image.lockFocus(); NSColor.white.setFill(); NSRect(x:0,y:0,width:612,height:792).fill()
            NSAttributedString(string: "Layout test page \(i + 1)", attributes: [.font:NSFont.systemFont(ofSize:30)]).draw(at:NSPoint(x:50,y:650))
            image.unlockFocus(); pdf.insert(PDFPage(image:image)!,at:i)
        }
        pdf.write(to: pdfURL)
        await model.importURLs([pdfURL]); model.showTutor=true; model.showNotes=true
        await pause(); await pause()
        guard let view=model.activePDF, let web=webs(window.contentView!).first else { throw ReaderError.message("Missing reading views") }
        view.go(to: view.document!.page(at:1)!); await pause()
        _ = try await web.evaluateJavaScript("window.layoutProbe='kept';let t=document.querySelector('textarea');if(t)t.value='未发送的布局测试草稿';true")
        let before = web.frame.width
        let total = window.contentView!.bounds.width
        model.layout.adjust(.tutor,by:120,total:total,libraryVisible:true,right:.tutor)
        await pause()
        checks["teacher_width_changes"] = web.frame.width > before + 60
        checks["pdf_view_identity_kept"] = model.activePDF === view
        checks["pdf_page_kept"] = view.currentPage === view.document?.page(at:1)
        checks["teacher_webview_identity_kept"] = webs(window.contentView!).contains { $0 === web }
        checks["teacher_draft_kept"] = (try await web.evaluateJavaScript("window.layoutProbe==='kept' && document.querySelector('textarea')?.value==='未发送的布局测试草稿'") as? Bool) == true
        model.layout.save()
        checks["saved_ratio_reloads"] = PaneLayout(root:model.store.root).ratio(.tutor) == model.layout.ratio(.tutor)
        window.setContentSize(NSSize(width:1160,height:720)); await pause()
        checks["minimum_reader_in_actual_view"] = view.frame.width >= 519
        checks["minimum_teacher_in_actual_view"] = web.frame.width >= 319
        window.setContentSize(NSSize(width:1380,height:820)); await pause()
        model.layout.resetAll(); await pause()
        checks["default_right_restored"] = abs(web.frame.width - 400) < 2
        checks["window_menu_has_reset"] = NSApp.mainMenu?.items.first(where:{$0.submenu?.title=="窗口"})?.submenu?.items.contains(where:{$0.title=="恢复默认布局"}) == true
    } catch let e { error=e.localizedDescription }
    let report:[String:Any] = ["checks":checks,"error":error,"passed":error.isEmpty && !checks.values.contains(false)]
    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:model.store.root.appendingPathComponent("layout-integration.json")) }
 }
}
