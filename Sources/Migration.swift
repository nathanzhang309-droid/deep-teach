import Foundation
import AppKit
import PDFKit

@MainActor extension AppModel {
    func importLegacy(_ file:URL)throws {
        let bytes=try Data(contentsOf:file)
        guard bytes.count<250_000_000,let backup=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],backup["format"] as? String=="bandu-backup",backup["version"] as? Int==1,let lectures=backup["lectures"] as? [[String:Any]],lectures.count<=100 else{throw ReaderError.message(L("这不是有效的伴读备份"))}
        var validated:[([String:Any],Data)]=[]
        for l in lectures {
            guard let id=l["id"] as? String,let base64=l["bytes"] as? String,let data=Data(base64Encoded:base64),sha256(data)==id,PDFDocument(data:data) != nil,l["name"] is String,l["messages"] is [[String:Any]],l["notes"] is [[String:Any]] else{throw ReaderError.message(L("备份包含不完整的课件，未导入"))}
            validated.append((l,data))
        }
        let backups=store.root.appendingPathComponent("迁移备份");try FileManager.default.createDirectory(at:backups,withIntermediateDirectories:true)
        let preserved=backups.appendingPathComponent(L("伴读旧版-")+sha256(bytes).prefix(12)+".bandu");if !FileManager.default.fileExists(atPath:preserved.path){try bytes.write(to:preserved,options:.atomic)}
        for (lecture,pdfBytes) in validated.sorted(by:{($0.0["updated"] as? Double ?? 0)<($1.0["updated"] as? Double ?? 0)}) {
            let digest=sha256(pdfBytes);let d:ReaderDocument
            if let existing=library.first(where:{$0.digest==digest}){d=existing}else{
                let id=newID(),folder=try store.folder(id);try pdfBytes.write(to:folder.appendingPathComponent("original.pdf"),options:.atomic)
                let page=max(0,(lecture["page"] as? Int ?? 1)-1),count=PDFDocument(data:pdfBytes)?.pageCount ?? 1
                d=ReaderDocument(id:id,title:lecture["name"] as! String,kind:"pdf",createdAt:Date(),lastOpenedAt:Date(),progress:count>1 ? Double(page)/Double(count-1):0,relativePath:"documents/\(id)/original.pdf",digest:digest,page:page);library.append(d)
            }
            for n in lecture["notes"] as! [[String:Any]] {
                guard let oldID=n["id"] as? String,let text=n["text"] as? String else{throw ReaderError.message(L("笔记格式不完整，原备份已保留"))}
                let id="legacy-"+String(sha256(Data((digest+oldID).utf8)).prefix(32));if highlights.contains(where:{$0.id==id}){continue}
                highlights.append(Highlight(id:id,documentID:d.id,quote:n["quote"] as? String ?? L("旧版学习笔记"),note:text,tags:"伴读 迁入",createdAt:Date(timeIntervalSince1970:(n["created"] as? Double ?? Date().timeIntervalSince1970*1000)/1000),page:max(0,(n["page"] as? Int ?? 1)-1)))
            }
            for m in lecture["messages"] as! [[String:Any]] {
                guard let id=m["id"] as? String,let text=m["text"] as? String,let role=m["role"] as? String,["user","assistant"].contains(role) else{throw ReaderError.message(L("对话格式不完整，原备份已保留"))}
                let stable="legacy-"+id;if teaching.conversations[d.id,default:[]].contains(where:{$0.id==stable}){continue}
                teaching.conversations[d.id,default:[]].append(TeacherMessage(id:stable,role:role,text:text,page:m["page"] as? Int ?? 1,failed:m["failed"] as? Bool ?? false))
            }
            selectedID=d.id;persist(sync:false);saveTeaching()
        }
        status=L("已迁入 {0} 份旧版课件及对话，原备份已保留", String(describing: validated.count));showTutor=true;showNotes=true
    }
    func importPowerPoint(_ source:URL)async throws->ReaderDocument {
        let data=try Data(contentsOf:source);guard data.count<50*1024*1024 else{throw ReaderError.message(L("PowerPoint 超过 50 MB，请先导出 PDF"))}
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("bandu-ppt-"+newID());try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let input=dir.appendingPathComponent("source."+source.pathExtension.lowercased()),pdf=dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent+".pdf"),script=dir.appendingPathComponent("convert.applescript")
        try data.write(to:input)
        let text="""
        on run argv
          set inputFile to POSIX file (item 1 of argv)
          set outputFile to POSIX file (item 2 of argv)
          tell application "Keynote"
            set lectureDoc to open inputFile
            try
              export lectureDoc to outputFile as PDF
            on error errMsg number errNum
              close lectureDoc saving no
              error errMsg number errNum
            end try
            close lectureDoc saving no
          end tell
        end run
        """
        try text.write(to:script,atomically:true,encoding:.utf8);status=L("正在通过 Keynote 转换课件…")
        do{_ = try await Task.detached{try runProcess("/usr/bin/osascript",[script.path,input.path,pdf.path])}.value}catch{throw ReaderError.message(L("Keynote 转换失败。请允许自动化权限，或先在 PowerPoint 中导出 PDF。"))}
        return try await importFile(pdf)
    }
}
