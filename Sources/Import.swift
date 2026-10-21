import Foundation
import WebKit
import PDFKit

struct ArticleResult { var title:String;var html:String;var text:String;var images:[String] }
@MainActor final class ArticleProcessor:NSObject,WKNavigationDelegate {
    var web:WKWebView!;var ready=false;var waiting:[CheckedContinuation<Void,Never>]=[]
    override init(){super.init();let c=WKWebViewConfiguration();c.websiteDataStore = .nonPersistent();web=WKWebView(frame:.zero,configuration:c);web.navigationDelegate=self
        if let u=Bundle.main.url(forResource:"processor",withExtension:"html"){web.loadFileURL(u,allowingReadAccessTo:u.deletingLastPathComponent())}
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){ready=true;waiting.forEach{$0.resume()};waiting=[]}
    func call(_ script:String,arguments:[String:Any])async throws->Any {
        try await withCheckedThrowingContinuation { (c:CheckedContinuation<Any,Error>) in
            web.callAsyncJavaScript(script,arguments:arguments,in:nil,in:.page){result in c.resume(with:result)}
        }
    }
    func renderMarkdown(_ text:String)async throws->String {
        if !ready {await withCheckedContinuation{waiting.append($0)}}
        return try await call("return marked.parse(text,{async:false})",arguments:["text":text]) as? String ?? ""
    }
    func extract(_ html:String,base:String="",readable:Bool=false)async throws->ArticleResult{
        if !ready {await withCheckedContinuation{waiting.append($0)}}
        let result=try await call("return window.extractArticle(html,base,readable)",arguments:["html":html,"base":base,"readable":readable])
        guard let d=result as? [String:Any],let content=d["html"] as? String else {throw ReaderError.message("正文解析失败。")}
        return ArticleResult(title:d["title"] as? String ?? "",html:content,text:d["text"] as? String ?? "",images:d["images"] as? [String] ?? [])
    }
}
final class XMLTree:NSObject,XMLParserDelegate {
    var elements:[(String,[String:String])]=[]
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes attributeDict:[String:String]){elements.append((elementName,attributeDict))}
    static func parse(_ bytes:Data)throws->[(String,[String:String])]{let d=XMLTree(),p=XMLParser(data:bytes);p.shouldResolveExternalEntities=false;p.delegate=d;guard p.parse() else{throw ReaderError.message("EPUB 目录无法解析。")};return d.elements}
}
func runProcess(_ executable:String,_ arguments:[String],maxBytes:Int=32_000_000)throws->Data{
    let p=Process();p.executableURL=URL(fileURLWithPath:executable);p.arguments=arguments
    let pipe=Pipe();p.standardOutput=pipe;p.standardError=FileHandle.nullDevice;try p.run()
    var result=Data()
    while true {let chunk=pipe.fileHandleForReading.readData(ofLength:65536);if chunk.isEmpty{break};result.append(chunk);if result.count>maxBytes{p.terminate();throw ReaderError.message("文件过大，已停止导入。")}}
    p.waitUntilExit();guard p.terminationStatus==0 else{throw ReaderError.message("无法读取文件或压缩包。")};return result
}
func decodeText(_ data:Data)throws->String{if let s=String(data:data,encoding:.utf8){return s};if let s=String(data:data,encoding:.utf16){return s};throw ReaderError.message("请将文本保存为 UTF-8 后再导入。")}
func simpleMarkdown(_ text:String)->String {
    // Minimal offline Markdown: headings, paragraphs, quotes and fenced code; no embedded scripts.
    var result="",code=false,paragraph:[String]=[]
    func flush(){if !paragraph.isEmpty{result+="<p>"+paragraph.map(htmlEscape).joined(separator:"<br>")+"</p>";paragraph=[]}}
    for line in text.components(separatedBy:.newlines){
        if line.hasPrefix("```"){flush();result+=code ? "</code></pre>":"<pre><code>";code.toggle();continue}
        if code{result+=htmlEscape(line)+"\n";continue}
        if line.isEmpty{flush();continue}
        let hashes=line.prefix(while:{$0=="#"}).count
        if hashes>0&&hashes<=6&&line.dropFirst(hashes).hasPrefix(" "){flush();result+="<h\(hashes)>\(htmlEscape(String(line.dropFirst(hashes+1))))</h\(hashes)>"}
        else if line.hasPrefix("> "){flush();result+="<blockquote>\(htmlEscape(String(line.dropFirst(2))))</blockquote>"}
        else{paragraph.append(line)}
    }
    flush();if code{result+="</code></pre>"};return result
}
struct EPUBReader {
    let file:URL
    func entry(_ name:String)throws->Data {
        guard !name.hasPrefix("/"),!name.split(separator:"/").contains(".."),!name.contains("\\"),!name.contains("*"),!name.contains("?"),!name.contains("[") else{throw ReaderError.message("EPUB 包含不支持的资源路径。")}
        return try runProcess("/usr/bin/unzip",["-p",file.path,name])
    }
    func load()throws->(String,String){
        let listing=try decodeText(runProcess("/usr/bin/unzip",["-Z1",file.path],maxBytes:2_000_000))
        let names=Set(listing.components(separatedBy:.newlines))
        guard names.count<4000,!names.contains("META-INF/encryption.xml") else {throw ReaderError.message("该 EPUB 带有加密资源或内容过多，暂不能导入。")}
        let container=try XMLTree.parse(entry("META-INF/container.xml"))
        guard let opf=container.first(where:{$0.0=="rootfile"})?.1["full-path"] else{throw ReaderError.message("EPUB 缺少内容目录。")}
        let package=try XMLTree.parse(entry(opf));let base=(opf as NSString).deletingLastPathComponent
        let manifest=Dictionary(package.filter{$0.0=="item"}.compactMap{x->(String,[String:String])? in guard let id=x.1["id"] else{return nil};return(id,x.1)},uniquingKeysWith:{first,_ in first})
        let spine=package.filter{$0.0=="itemref"}.compactMap{$0.1["idref"]}
        guard !spine.isEmpty,spine.count<700 else{throw ReaderError.message("EPUB 没有可读取的章节。")}
        var combined="",total=0
        for (i,id) in spine.enumerated(){
            guard let href=manifest[id]?["href"] else{continue}
            let path=normalized(base:base,href:href);let bytes=try entry(path);total+=bytes.count
            guard total<30_000_000 else{throw ReaderError.message("电子书正文超过 30 MB，暂不能导入。")}
            var html=try decodeText(bytes)
            let regex=try NSRegularExpression(pattern:"(?i)(?:src|href)=[\"']([^\"']+\\.(?:png|jpg|jpeg|gif|webp))[\"']")
            let matches=regex.matches(in:html,range:NSRange(html.startIndex...,in:html))
            for m in matches.reversed(){guard let range=Range(m.range(at:1),in:html) else{continue};let original=String(html[range]);let asset=normalized(base:(path as NSString).deletingLastPathComponent,href:original)
                if names.contains(asset),let data=try? entry(asset),data.count<5_000_000{total+=data.count;guard total<60_000_000 else{throw ReaderError.message("电子书图片总量过大。")};let ext=(asset as NSString).pathExtension.lowercased();let mime=(ext=="jpg" ? "jpeg":ext);html.replaceSubrange(range,with:"data:image/\(mime);base64,\(data.base64EncodedString())")}
            }
            // Each chapter is sanitized later by DOMPurify; retain headings but not head styles/scripts.
            if let a=html.range(of:"<body[^>]*>",options:[.regularExpression,.caseInsensitive]),let b=html.range(of:"</body>",options:[.backwards,.caseInsensitive]){html=String(html[a.upperBound..<b.lowerBound])}
            combined+="<section><h2>第 \(i+1) 节</h2>\(html)</section>"
        }
        guard !combined.isEmpty else{throw ReaderError.message("没有读取到电子书正文。")}
        return(file.deletingPathExtension().lastPathComponent,combined)
    }
    func normalized(base:String,href:String)->String {
        let raw=href.removingPercentEncoding ?? href
        return ((base.isEmpty ? raw:base+"/"+raw) as NSString).standardizingPath
    }
}
