import AppKit
import PDFKit

struct SlideMark:Codable,Identifiable {
    var id=newID();var kind:String;var text="";var color="#55735B";var fontSize:Double=18
    var x:Double;var y:Double;var width:Double;var height:Double;var page:Int
    var asset:String?;var rotation:Int=0;var answerID:String?
    var rect:CGRect {CGRect(x:x,y:y,width:width,height:height)}
}
struct SlidePage:Codable,Identifiable {var id=newID();var width:Double;var height:Double}
struct SlideProject:Codable {var marks:[SlideMark]=[];var pages:[SlidePage]=[]}
struct SlideArchive:Codable {var version=1;var projects:[String:SlideProject]=[:]}

func slideColor(_ hex:String)->NSColor {
    let raw=hex.replacingOccurrences(of:"#",with:"");let n=UInt32(raw,radix:16) ?? 0x55735B
    return NSColor(srgbRed:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
}
final class SlideAnnotation:PDFAnnotation {
    let mark:SlideMark;let image:NSImage?
    init(mark:SlideMark,image:NSImage?=nil){self.mark=mark;self.image=image;super.init(bounds:mark.rect,forType:.stamp,withProperties:nil);contents=mark.text;shouldDisplay=true;shouldPrint=true}
    required init?(coder:NSCoder){return nil}
    override func copy(with zone:NSZone?=nil)->Any{SlideAnnotation(mark:mark,image:image)}
    override func draw(with box:PDFDisplayBox,in context:CGContext){
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        context.saveGState();defer{context.restoreGState();NSGraphicsContext.restoreGraphicsState()}
        let r=bounds.insetBy(dx:2,dy:2),color=slideColor(mark.color)
        context.clip(to:bounds)
        switch mark.kind {
        case "image":image?.draw(in:r,from:.zero,operation:.sourceOver,fraction:1)
        case "underline":
            color.setStroke();let path=NSBezierPath();path.move(to:CGPoint(x:r.minX,y:r.midY));path.line(to:CGPoint(x:r.maxX,y:r.midY));path.lineWidth=2.5;path.stroke()
        case "rectangle","ellipse":
            color.setStroke();let path=mark.kind=="ellipse" ? NSBezierPath(ovalIn:r):NSBezierPath(roundedRect:r,xRadius:5,yRadius:5);path.lineWidth=3;path.stroke()
        case "arrow":
            let points:[(CGPoint,CGPoint)]=[(CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.maxX,y:r.minY)),(CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.minY)),(CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.minX,y:r.maxY)),(CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY))]
            let (a,b)=points[abs(mark.rotation)%4];color.setStroke();let path=NSBezierPath();path.move(to:a);path.line(to:b);path.lineWidth=3;path.stroke()
            let angle=atan2(b.y-a.y,b.x-a.x),size=min(15,max(7,min(r.width,r.height)/2));let head=NSBezierPath();head.move(to:b)
            head.line(to:CGPoint(x:b.x-size*cos(angle-0.45),y:b.y-size*sin(angle-0.45)));head.move(to:b);head.line(to:CGPoint(x:b.x-size*cos(angle+0.45),y:b.y-size*sin(angle+0.45)));head.lineWidth=3;head.stroke()
        default:
            if mark.kind != "label" {NSColor(calibratedRed:0.985,green:0.98,blue:0.955,alpha:0.97).setFill();NSBezierPath(roundedRect:r,xRadius:6,yRadius:6).fill()}
            let area=r.insetBy(dx:mark.kind=="label" ? 3:10,dy:mark.kind=="label" ? 3:8);let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping;paragraph.lineSpacing=3
            var size=CGFloat(mark.fontSize);var text=NSAttributedString()
            repeat {text=NSAttributedString(string:mark.text,attributes:[.font:NSFont.systemFont(ofSize:size,weight:mark.kind=="label" ? .medium:.regular),.foregroundColor:color,.paragraphStyle:paragraph]);if text.boundingRect(with:CGSize(width:area.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height<=area.height || size<=9 {break};size-=1} while true
            text.draw(with:area,options:[.usesLineFragmentOrigin,.usesFontLeading])
        }
    }
}
enum SlidePDF {
    static func blank(_ size:CGSize)->PDFPage? {
        let data=NSMutableData();var box=CGRect(origin:.zero,size:size)
        guard let consumer=CGDataConsumer(data:data as CFMutableData),let context=CGContext(consumer:consumer,mediaBox:&box,nil) else{return nil}
        context.beginPDFPage(nil);context.setFillColor(NSColor.white.cgColor);context.fill(box);context.endPDFPage();context.closePDF()
        return PDFDocument(data:data as Data)?.page(at:0)
    }
    static func renderedImage(_ page:PDFPage,maxSide:CGFloat=1800)->NSImage? {
        guard let ref=page.pageRef else{return nil};let crop=page.bounds(for:.cropBox),rotated=abs(page.rotation)%180==90
        let size=rotated ? CGSize(width:crop.height,height:crop.width):crop.size
        let scale=min(1,maxSide/max(size.width,size.height)),target=CGSize(width:size.width*scale,height:size.height*scale)
        let image=NSImage(size:target);image.lockFocus();defer{image.unlockFocus()}
        guard let c=NSGraphicsContext.current?.cgContext else{return nil}
        c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(origin:.zero,size:target))
        c.concatenate(ref.getDrawingTransform(.cropBox,rect:CGRect(origin:.zero,size:target),rotate:0,preserveAspectRatio:true));c.drawPDFPage(ref);c.clip(to:crop)
        for a in page.annotations where a.shouldDisplay {a.draw(with:.cropBox,in:c)}
        return image
    }
    static func export(_ pdf:PDFDocument,to url:URL)throws {
        let data=NSMutableData()
        guard let consumer=CGDataConsumer(data:data as CFMutableData),let context=CGContext(consumer:consumer,mediaBox:nil,nil) else{throw ReaderError.message("无法创建PDF")}
        for index in 0..<pdf.pageCount {
            guard let page=pdf.page(at:index),let ref=page.pageRef else{throw ReaderError.message("无法读取第 \(index+1) 页")}
            let crop=page.bounds(for:.cropBox),rotated=abs(page.rotation)%180==90
            var box=CGRect(origin:.zero,size:rotated ? CGSize(width:crop.height,height:crop.width):crop.size)
            let info=[kCGPDFContextMediaBox as String:Data(bytes:&box,count:MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(info);context.saveGState()
            context.concatenate(ref.getDrawingTransform(.cropBox,rect:box,rotate:0,preserveAspectRatio:true))
            context.drawPDFPage(ref);context.clip(to:crop)
            // Draw live annotation graphics explicitly: PDFKit serialization loses custom stamp subclasses.
            for annotation in page.annotations where annotation.shouldDisplay && annotation.shouldPrint { annotation.draw(with:.cropBox,in:context) }
            context.restoreGState();context.endPDFPage()
        }
        context.closePDF();let bytes=data as Data
        guard let reopened=PDFDocument(data:bytes),reopened.pageCount==pdf.pageCount else{throw ReaderError.message("PDF导出失败，原文未改变")}
        try bytes.write(to:url,options:.atomic)
    }
}
