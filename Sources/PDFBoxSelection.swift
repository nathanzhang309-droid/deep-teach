import AppKit
import PDFKit
@MainActor final class BoxOverlay:NSView {
    weak var model:AppModel?;weak var pdfView:PDFView?;var dragging:NSPoint?;var box:NSRect = .zero
    var pulseTimer:Timer?;var capturing=false
    override var acceptsFirstResponder:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView? {model?.boxSelection==true ? super.hitTest(point):nil}
    override func resetCursorRects(){if model?.boxSelection==true{addCursorRect(bounds,cursor:.crosshair)}}
    override func keyDown(with event:NSEvent){if event.keyCode==53{model?.clearImageSelection();dragging=nil;box = .zero;needsDisplay=true}else{super.keyDown(with:event)}}
    override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self);dragging=convert(event.locationInWindow,from:nil);box = .zero}
    override func mouseDragged(with event:NSEvent){guard let a=dragging else{return};let b=convert(event.locationInWindow,from:nil);box=NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(b.x-a.x),height:abs(b.y-a.y));needsDisplay=true}
    var persistentBox:NSRect?{
        guard let r=model?.selectedImageRegion,let view=pdfView,let page=view.document?.page(at:r.page) else{return nil}
        return convert(view.convert(CGRect(x:r.x,y:r.y,width:r.width,height:r.height),from:page),from:view)
    }
    func refresh(){needsDisplay=true;window?.invalidateCursorRects(for:self)
        if model?.selectedImageRegion != nil,pulseTimer==nil {pulseTimer=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true){[weak self] _ in MainActor.assumeIsolated{guard let self else{return};if self.model?.selectedImageRegion==nil{self.pulseTimer?.invalidate();self.pulseTimer=nil};self.needsDisplay=true}}}
    }
    override func viewWillMove(toWindow newWindow:NSWindow?){if newWindow==nil{pulseTimer?.invalidate();pulseTimer=nil};super.viewWillMove(toWindow:newWindow)}
    override func draw(_ dirtyRect:NSRect){guard !capturing else{return};let rect=box.isEmpty ? persistentBox ?? .zero:box;guard !rect.isEmpty else{return}
        guard let context=NSGraphicsContext.current?.cgContext else{return};context.saveGState();defer{context.restoreGState()};context.clip(to:bounds)
        if let view=pdfView,let clip=view.documentView?.enclosingScrollView?.contentView{context.clip(to:convert(clip.bounds,from:clip))}
        if let region=model?.selectedImageRegion,let view=pdfView,let page=view.document?.page(at:region.page){context.clip(to:convert(view.convert(page.bounds(for:.cropBox),from:page),from:view))}
        let alpha=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1:0.72+0.25*sin(Date.timeIntervalSinceReferenceDate*2.5)
        NSColor.systemGreen.withAlphaComponent(0.10).setFill();rect.fill()
        let path=NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3);NSColor.white.withAlphaComponent(0.9).setStroke();path.lineWidth=4;path.stroke();NSColor.systemGreen.withAlphaComponent(alpha).setStroke();path.lineWidth=2;path.stroke()
        NSColor.systemGreen.setFill();for p in [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)]{CGRect(x:p.x-3,y:p.y-3,width:6,height:6).fill()}
    }
    override func mouseUp(with event:NSEvent){capture(box)}
    func capture(_ requested:NSRect){box=requested;defer{dragging=nil;box = .zero;capturing=false;needsDisplay=true;model?.boxSelection=false;refresh()}
        guard let model,let view=pdfView,let pdf=view.document,box.width>8,box.height>8 else{return}
        let selected=convert(box,to:view).intersection(view.bounds);guard let page=view.page(for:CGPoint(x:selected.midX,y:selected.midY),nearest:true) else{return}
        let rect=view.convert(selected,to:page).intersection(page.bounds(for:.cropBox));guard !rect.isEmpty else{return}
        let screen=view.convert(rect,from:page).intersection(view.bounds);capturing=true;needsDisplay=true;displayIfNeeded()
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:screen) else{return};view.cacheDisplay(in:screen,to:bitmap);guard let bytes=bitmap.representation(using:.png,properties:[:]) else{return}
        let i=pdf.index(for:page),quote=page.selection(for:rect)?.string ?? "图表选区"
        let region=PDFRegion(page:i,x:rect.minX,y:rect.minY,width:rect.width,height:rect.height)
        model.receiveSelection(SelectionAnchor(quote:quote.isEmpty ? "图表选区":quote,regions:[region]))
        model.selectedImage="data:image/png;base64,"+bytes.base64EncodedString();model.selectedImagePage=i;model.selectedImageRegion=region
        model.slideEditing=false;model.showTutor=true;model.showNotes=true;model.selectionRequest=UUID();model.tutorStatus="已框选第 \(i+1) 页的区域，想问这部分什么？"
    }
}
