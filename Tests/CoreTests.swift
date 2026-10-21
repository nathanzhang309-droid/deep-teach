import Foundation
@main struct CoreTests {
 static func main() throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("shiye-tests-"+newID());try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
    var count=0
    func check(_ condition:Bool,_ label:String){if !condition{fatalError("FAIL: "+label)};count+=1;print("PASS "+label)}
    check(Preferences().vaultPath.isEmpty && !Preferences().autoSync,"new installations do not connect a private vault")
    check(Preferences().syncSubfolder=="Bandu","new vaults use a generic Bandu folder")
    let legacyPreferences=try JSONDecoder().decode(Preferences.self,from:Data("{\"vaultPath\":\"/example/vault\",\"autoSync\":true,\"theme\":\"纸白\",\"fontSize\":19}".utf8))
    check(legacyPreferences.syncSubfolder==nil && legacyPreferences.autoSync,"old preferences retain their sync location and settings")
    let store=try LibraryStore(root:root.appendingPathComponent("library"))
    let d=try store.addArticle(title:"A / B: Test",html:"<p>one two three</p>",text:"one two three",kind:"html")
    let duplicate=try store.addArticle(title:"duplicate",html:"<p>one two three</p>",text:"one two three",kind:"html")
    check(duplicate.id==d.id&&store.state.documents.count==1,"duplicate imports keep a stable document identity")
    var h=Highlight(id:newID(),documentID:d.id,quote:"one two",note:"My first note",createdAt:Date(),start:0,end:7,prefix:"",suffix:" three")
    store.state.highlights=[h];try store.save()
    let reopened=try LibraryStore(root:store.root);check(reopened.state.highlights.first?.note==h.note,"highlights and notes survive reopen")
    let vault=root.appendingPathComponent("vault");try fm.createDirectory(at:vault,withIntermediateDirectories:true)
    let sync=ObsidianSync();let first=try sync.sync(state:store.state,vault:vault)
    check(first.written==1,"first sync writes one document")
    let second=try sync.sync(state:store.state,vault:vault);check(second.unchanged==1&&second.written==0,"repeated sync is idempotent")
    let file=try fm.contentsOfDirectory(at:first.folder,includingPropertiesForKeys:nil).first{$0.pathExtension=="md"}!
    var content=try String(contentsOf:file);content+="\n手写笔记应原样保留：αβ中。\n";try Data(content.utf8).write(to:file)
    h.note="Updated note";store.state.highlights=[h];let updated=try sync.sync(state:store.state,vault:vault)
    let fresh=try String(contentsOf:file);check(updated.written==1&&fresh.contains("Updated note")&&fresh.hasSuffix("手写笔记应原样保留：αβ中。\n"),"user text outside managed region survives an update")
    let altered=fresh.replacingOccurrences(of:"Updated note",with:"用户修改了同步区域");try Data(altered.utf8).write(to:file)
    h.note="Incoming new note";store.state.highlights=[h];let conflict=try sync.sync(state:store.state,vault:vault)
    check(try conflict.conflicts==1&&String(contentsOf:file)==altered,"edited managed text is never overwritten")
    let conflictDir=first.folder.appendingPathComponent("待合并");let pending=try fm.contentsOfDirectory(at:conflictDir,includingPropertiesForKeys:nil).first!;check(try String(contentsOf:pending).contains("Incoming new note"),"new version is available for manual merge")
    _=try sync.sync(state:store.state,vault:vault);check(try fm.contentsOfDirectory(at:conflictDir,includingPropertiesForKeys:nil).count==1,"repeated conflict sync does not duplicate files")
    // A user can accept latest generated content without losing freeform notes.
    let begin="<!-- shiye:\(d.id):begin -->\n",end="\n<!-- shiye:\(d.id):end -->"
    let a=altered.range(of:begin)!,b=altered.range(of:end)!
    let merged=String(altered[..<a.upperBound])+sync.render(d,marks:[h])+String(altered[b.lowerBound...]);try Data(merged.utf8).write(to:file)
    let resolved=try sync.sync(state:store.state,vault:vault);check(resolved.conflicts==0,"accepting latest content restores future automatic sync")
    store.state.highlights=[];_=try sync.sync(state:store.state,vault:vault);check(try String(contentsOf:file).contains("0 条批注"),"deleted highlights are reflected without deleting user notes")
    var tutorial=d;tutorial.id=newID();tutorial.isWelcome=true;var tutorialMark=h;tutorialMark.id=newID();tutorialMark.documentID=tutorial.id
    var tutorialState=LibraryState();tutorialState.documents=[tutorial];tutorialState.highlights=[tutorialMark]
    check(try sync.sync(state:tutorialState,vault:vault).written==1,"user highlights in welcome guide also sync")
    let index=first.folder.appendingPathComponent(".shiye-sync.json");try Data("invalid".utf8).write(to:index)
    do{_=try sync.sync(state:store.state,vault:vault);fatalError("corrupt index accepted")}catch{check(true,"corrupt sync index fails closed")}
    let corrupted=store.root.appendingPathComponent("library.json");try Data("broken".utf8).write(to:corrupted);let recovered=try LibraryStore(root:store.root);check(recovered.recoveryNotice != nil&&recovered.state.documents.count==1,"corrupt state restores valid backup and retains damaged bytes")
    print("\(count) core checks passed")
 }
}
