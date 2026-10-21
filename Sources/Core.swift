import Foundation
import CryptoKit

struct PDFRegion: Codable, Equatable { var page:Int; var x:Double; var y:Double; var width:Double; var height:Double }
struct ReaderDocument: Codable, Equatable, Identifiable {
    var id:String; var title:String; var kind:String; var sourceURL:String?; var createdAt:Date; var lastOpenedAt:Date
    var progress:Double = 0; var archived:Bool = false; var isWelcome:Bool = false
    var relativePath:String; var digest:String; var page:Int = 0
}
struct Highlight: Codable, Equatable, Identifiable {
    var id:String; var documentID:String; var quote:String; var note:String = ""; var tags:String = ""; var color:String = "yellow"; var createdAt:Date
    var page:Int?; var regions:[PDFRegion] = []; var start:Int?; var end:Int?; var prefix:String?; var suffix:String?
}
struct Preferences: Codable {
    var vaultPath:String = ""
    var syncSubfolder:String? = "Bandu"
    var autoSync:Bool = false; var theme:String = "纸白"; var fontSize:Double = 19
}
struct LibraryState: Codable { var version=1; var documents:[ReaderDocument]=[]; var highlights:[Highlight]=[]; var preferences=Preferences() }
enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription:String? { if case .message(let s)=self { return s }; return nil }
}
func sha256(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
func htmlEscape(_ s:String)->String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
func newID()->String { UUID().uuidString.lowercased() }
func jsonText<T:Encodable>(_ value:T) throws -> String { String(data:try JSONEncoder().encode(value),encoding:.utf8)! }

final class LibraryStore {
    let root:URL; var state:LibraryState; var recoveryNotice:String?
    let fm=FileManager.default
    var stateURL:URL { root.appendingPathComponent("library.json") }
    init(root:URL) throws {
        self.root=root
        try fm.createDirectory(at:root.appendingPathComponent("documents"),withIntermediateDirectories:true)
        let file=root.appendingPathComponent("library.json"), backup=root.appendingPathComponent("library.previous.json")
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        if fm.fileExists(atPath:file.path) {
            do { state=try decoder.decode(LibraryState.self,from:Data(contentsOf:file)) }
            catch {
                if let data=try? Data(contentsOf:backup),let old=try? decoder.decode(LibraryState.self,from:data) {
                    state=old; recoveryNotice="资料库已从上一次保存恢复。损坏文件已保留。"
                    try fm.copyItem(at:file,to:root.appendingPathComponent("library-damaged-\(newID()).json"))
                } else { throw ReaderError.message("资料库无法读取，已保留原文件。请从备份恢复：\(file.path)") }
            }
        } else { state=LibraryState() }
        guard state.version == 1 else { throw ReaderError.message("资料库版本较新，请使用匹配版本的伴读。") }
    }
    func save() throws {
        let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];e.dateEncodingStrategy = .iso8601
        let bytes=try e.encode(state)
        if let old=try? Data(contentsOf:stateURL) {
            let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            if (try? decoder.decode(LibraryState.self,from:old)) != nil { try old.write(to:root.appendingPathComponent("library.previous.json"),options:.atomic) }
        }
        try bytes.write(to:stateURL,options:.atomic)
    }
    func url(for document:ReaderDocument)->URL { root.appendingPathComponent(document.relativePath) }
    func folder(_ id:String)throws->URL { let u=root.appendingPathComponent("documents").appendingPathComponent(id);try fm.createDirectory(at:u,withIntermediateDirectories:true);return u }
    func addArticle(title:String,html:String,text:String,kind:String,sourceURL:String?=nil,isWelcome:Bool=false) throws -> ReaderDocument {
        // Include content in identity; same URL may legitimately have a later captured version.
        let identity=sha256(Data(((sourceURL ?? "")+"\n"+html).utf8))
        if let d=state.documents.first(where:{$0.digest==identity}) { return d }
        let id=newID(),dir=try folder(id)
        try Data(html.utf8).write(to:dir.appendingPathComponent("article.html"),options:.atomic)
        try Data(text.utf8).write(to:dir.appendingPathComponent("search.txt"),options:.atomic)
        let d=ReaderDocument(id:id,title:title.isEmpty ? "未命名文档":title,kind:kind,sourceURL:sourceURL,createdAt:Date(),lastOpenedAt:Date(),isWelcome:isWelcome,relativePath:"documents/\(id)/article.html",digest:identity)
        state.documents.insert(d,at:0);try save();return d
    }
}

struct SyncResult { var written:Int=0;var unchanged:Int=0;var conflicts:Int=0;var folder:URL }
struct SyncEntry:Codable { var documentID:String;var filename:String;var blockHash:String }
struct SyncIndex:Codable { var version=1;var entries:[String:SyncEntry]=[:] }

final class ObsidianSync {
    static let subfolder="Bandu"
    static let legacySubfolder="Myknowledge/2-Areas/阅读笔记/拾页"
    let fm=FileManager.default
    func sync(state:LibraryState,vault:URL,studyBlocks:[String:String]=[:])throws->SyncResult {
        var dir:ObjCBool=false
        guard fm.fileExists(atPath:vault.path,isDirectory:&dir),dir.boolValue else { throw ReaderError.message("Obsidian 库文件夹不可用，请在设置中重新选择。") }
        let output=vault.appendingPathComponent(state.preferences.syncSubfolder ?? Self.legacySubfolder)
        try fm.createDirectory(at:output,withIntermediateDirectories:true)
        // Refuse redirecting the dedicated sync subtree through a symbolic link.
        guard output.resolvingSymlinksInPath().path.hasPrefix(vault.resolvingSymlinksInPath().path+"/") else { throw ReaderError.message("同步目录指向库以外的位置，已停止写入。") }
        let indexURL=output.appendingPathComponent(".shiye-sync.json")
        var index:SyncIndex
        if fm.fileExists(atPath:indexURL.path) {
            do { index=try JSONDecoder().decode(SyncIndex.self,from:Data(contentsOf:indexURL)) }
            catch { throw ReaderError.message("同步索引损坏，已停止写入以保护笔记。请保留 .shiye-sync.json 并从备份恢复。") }
        } else { index=SyncIndex() }
        var result=SyncResult(folder:output)
        for d in state.documents {
            let marks=state.highlights.filter{$0.documentID==d.id}.sorted{$0.createdAt<$1.createdAt}
            guard !marks.isEmpty || studyBlocks[d.id] != nil || index.entries[d.id] != nil else {continue}
            let filename=index.entries[d.id]?.filename ?? "\(safeName(d.title)) — \(d.id.prefix(8)).md"
            guard filename == (filename as NSString).lastPathComponent else {throw ReaderError.message("同步索引包含无效路径。")}
            let target=output.appendingPathComponent(filename)
            guard target.resolvingSymlinksInPath().deletingLastPathComponent()==output.resolvingSymlinksInPath() else {throw ReaderError.message("同步目标不是普通笔记路径。")}
            let begin="<!-- shiye:\(d.id):begin -->",end="<!-- shiye:\(d.id):end -->"
            let block=render(d,marks:marks)+(studyBlocks[d.id].map{"\n\n"+$0} ?? "")
            let hash=sha256(Data(block.utf8))
            let managed="\(begin)\n\(block)\n\(end)"
            if fm.fileExists(atPath:target.path) {
                let old=try String(contentsOf:target,encoding:.utf8)
                if let a=old.range(of:begin+"\n"),let b=old.range(of:"\n"+end,range:a.upperBound..<old.endIndex),old.components(separatedBy:begin).count==2,old.components(separatedBy:end).count==2 {
                    let current=String(old[a.upperBound..<b.lowerBound])
                    if current == block {
                        index.entries[d.id]=SyncEntry(documentID:d.id,filename:filename,blockHash:hash);result.unchanged+=1;continue
                    }
                    if let expected=index.entries[d.id]?.blockHash,sha256(Data(current.utf8))==expected {
                        let changed=String(old[..<a.upperBound])+block+String(old[b.lowerBound...])
                        try saveBackup(target,output:output)
                        try Data(changed.utf8).write(to:target,options:.atomic)
                    } else {
                        try writeConflict(d,block:managed,output:output);result.conflicts+=1;continue
                    }
                } else {try writeConflict(d,block:managed,output:output);result.conflicts+=1;continue}
            } else {
                let fresh="---\nshiye_document: \(d.id)\nsource: 伴读\n---\n\n# \(d.title.replacingOccurrences(of:"\n",with:" "))\n\n\(managed)\n\n## 我的笔记\n\n在这里自由写笔记。此区域会在同步时保留。\n"
                try Data(fresh.utf8).write(to:target,options:.atomic)
            }
            index.entries[d.id]=SyncEntry(documentID:d.id,filename:filename,blockHash:hash);result.written+=1
            // Persist each completed file so a subsequent partial failure does not invalidate prior writes.
            try JSONEncoder().encode(index).write(to:indexURL,options:.atomic)
        }
        try JSONEncoder().encode(index).write(to:indexURL,options:.atomic)
        return result
    }
    func safeName(_ text:String)->String {
        let bad=CharacterSet(charactersIn:"/\\:*?\"<>|\n\r#[]^")
        let n=text.components(separatedBy:bad).joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines)
        return String((n.isEmpty ? "阅读笔记":n).prefix(90))
    }
    func render(_ d:ReaderDocument,marks:[Highlight])->String {
        var s="[在伴读中阅读](shiye://document/\(d.id))"
        if let source=d.sourceURL,let u=URL(string:source),["http","https"].contains(u.scheme?.lowercased() ?? "") {s+=" · [原文](\(source.replacingOccurrences(of:")",with:"%29")))"}
        s+="\n\n\(marks.count) 条批注\n"
        for h in marks {
            let location=h.page.map{"第 \($0+1) 页"} ?? "回到原文"
            s+="\n### \(location)\n\n"
            // Escape sync delimiters and Markdown headings inside captured content.
            let quote=h.quote.replacingOccurrences(of:"<!-- shiye:",with:"&lt;!-- shiye:")
            s+=quote.components(separatedBy:"\n").map{"> "+$0}.joined(separator:"\n")+"\n\n"
            if !h.note.isEmpty {s+="**笔记**\n\n"+h.note.replacingOccurrences(of:"<!-- shiye:",with:"&lt;!-- shiye:")+"\n\n"}
            if !h.tags.isEmpty {s+="标签："+h.tags.replacingOccurrences(of:"<!-- shiye:",with:"&lt;!-- shiye:")+"\n\n"}
            s+="[定位到这条批注](shiye://document/\(d.id)?highlight=\(h.id))\n^shiye-\(h.id)\n"
        }
        return s
    }
    func writeConflict(_ d:ReaderDocument,block:String,output:URL)throws {
        let dir=output.appendingPathComponent("待合并");try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        guard dir.resolvingSymlinksInPath().path.hasPrefix(output.resolvingSymlinksInPath().path+"/") else {throw ReaderError.message("待合并目录路径异常。")}
        let file=dir.appendingPathComponent("\(safeName(d.title)) — \(d.id.prefix(8)).md")
        let content="# \(d.title) 的新批注\n\n原笔记中的自动同步区域已被修改，伴读保留了它。以下是最新版本，可手动合并。若希望恢复自动更新，将原笔记两个 shiye 标记之间的内容替换为这里的对应内容，再同步一次。\n\n\(block)\n"
        if fm.fileExists(atPath:file.path), (try? String(contentsOf:file)) != content { try saveBackup(file,output:output) }
        guard !fm.fileExists(atPath:file.path) || (try? file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true else {throw ReaderError.message("待合并文件路径异常。")}
        try Data(content.utf8).write(to:file,options:.atomic)
    }
    func saveBackup(_ target:URL,output:URL)throws {
        let dir=output.appendingPathComponent(".shiye-backups");try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        guard dir.resolvingSymlinksInPath().path.hasPrefix(output.resolvingSymlinksInPath().path+"/") else {throw ReaderError.message("同步备份目录路径异常。")}
        let stamp=Int(Date().timeIntervalSince1970*1000)
        try fm.copyItem(at:target,to:dir.appendingPathComponent("\(stamp)-\(newID().prefix(8))-\(target.lastPathComponent)"))
    }
}
