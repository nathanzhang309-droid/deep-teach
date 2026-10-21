import AppKit
import PDFKit
@MainActor final class SlideOverlay:NSView {
    weak var model:AppModel?;weak var pdfView:PDFView?
    var start:NSPoint?;var original:SlideMark?;var resizing=false
    override var acceptsFirstResponder:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{model?.slideEditing==true && model?.boxSelection != true ? super.hitTest(point):nil}
    override func mouseDown(with event:NSEvent){
        guard let model,let view=pdfView,let pdf=view.document else{return}
        let point=convert(event.locationInWindow,from:nil),vp=convert(point,to:view)
        guard let page=view.page(for:vp,nearest:false) else{return};let index=pdf.index(for:page),pp=view.convert(vp,to:page)
        let mark=model.currentSlideProject.marks.reversed().first{$0.page==index && $0.rect.insetBy(dx:-5,dy:-5).contains(pp)}
        model.selectedSlideMarkID=mark?.id;original=mark;start=pp
        if let mark{let rect=convert(view.convert(mark.rect,from:page),from:view);resizing=CGRect(x:rect.maxX-12,y:rect.minY-6,width:18,height:18).contains(point);model.rememberSlideUndo()}
        window?.makeFirstResponder(self);needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent){guard let original,let start,let view=pdfView,let page=view.document?.page(at:original.page),let model else{return}
        let pp=view.convert(convert(convert(event.locationInWindow,from:nil),to:view),to:page);let dx=pp.x-start.x,dy=pp.y-start.y
        if resizing{model.dragSlideMark(id:original.id,x:original.x,y:original.y+dy,width:original.width+dx,height:original.height-dy)}else{model.dragSlideMark(id:original.id,x:original.x+dx,y:original.y+dy,width:original.width,height:original.height)};needsDisplay=true
    }
    override func mouseUp(with event:NSEvent){if original != nil{model?.saveSlides()};original=nil;start=nil;needsDisplay=true}
    override func scrollWheel(with event:NSEvent){pdfView?.documentView?.enclosingScrollView?.scrollWheel(with:event);needsDisplay=true}
    override func keyDown(with event:NSEvent){guard let model else{return};if event.keyCode==53{model.slideEditing=false;return};guard let id=model.selectedSlideMarkID else{super.keyDown(with:event);return}
        switch event.keyCode{case 51,117:model.deleteSlideMark(id);case 123:model.moveSlideMark(id:id,dx:-5,dy:0);case 124:model.moveSlideMark(id:id,dx:5,dy:0);case 125:model.moveSlideMark(id:id,dx:0,dy:-5);case 126:model.moveSlideMark(id:id,dx:0,dy:5);default:super.keyDown(with:event)}
    }
    override func draw(_ dirtyRect:NSRect){
        guard let model,let view=pdfView,let context=NSGraphicsContext.current?.cgContext else{return}
        context.saveGState();defer{context.restoreGState()};context.clip(to:bounds)
        if let clip=view.documentView?.enclosingScrollView?.contentView{context.clip(to:convert(clip.bounds,from:clip))}
        for mark in model.currentSlideProject.marks {
            guard let page=view.document?.page(at:mark.page) else{continue}
            let rect=convert(view.convert(mark.rect,from:page),from:view);guard rect.intersects(bounds) else{continue}
            let origin=convert(view.convert(CGPoint.zero,from:page),from:view)
            let px=convert(view.convert(CGPoint(x:1,y:0),from:page),from:view),py=convert(view.convert(CGPoint(x:0,y:1),from:page),from:view)
            context.saveGState();context.clip(to:convert(view.convert(page.bounds(for:.cropBox),from:page),from:view));context.concatenate(CGAffineTransform(a:px.x-origin.x,b:px.y-origin.y,c:py.x-origin.x,d:py.y-origin.y,tx:origin.x,ty:origin.y))
            SlideAnnotation(mark:mark,image:model.slideImage(mark.asset)).draw(with:.cropBox,in:context);context.restoreGState()
        }
        guard model.slideEditing,let m=model.selectedSlideMark,let page=view.document?.page(at:m.page) else{return}
        context.clip(to:convert(view.convert(page.bounds(for:.cropBox),from:page),from:view))
        let rect=convert(view.convert(m.rect,from:page),from:view);NSColor.systemGreen.setStroke();let path=NSBezierPath(rect:rect);path.lineWidth=1.5;path.setLineDash([4,3],count:2,phase:0);path.stroke();NSColor.systemGreen.setFill();CGRect(x:rect.maxX-5,y:rect.minY-5,width:10,height:10).fill()
    }
}
