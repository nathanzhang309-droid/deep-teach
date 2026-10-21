import Foundation
@main struct AdversarialCoreTests {
 static func main() throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("deep-teach-adversarial-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    var failures:[String]=[];var count=0
    func check(_ name:String,_ test:()throws->Bool) { count+=1;do {if try test(){print("PASS \(name)")}else{failures.append(name);print("FAIL \(name)")}}catch{failures.append(name);print("FAIL \(name): \(error.localizedDescription)")} }
    let vault=root.appendingPathComponent("知识库 English 🧪"),outside=root.appendingPathComponent("outside")
    try fm.createDirectory(at:vault,withIntermediateDirectories:true);try fm.createDirectory(at:outside,withIntermediateDirectories:true)
    let store=try LibraryStore(root:root.appendingPathComponent("library"))
    let doc=try store.addArticle(title:String(repeating:"🧑🏽‍🔬中英é",count:40),html:"<p>Entropy 熵 ΔS &amp; biology</p>",text:"Entropy 熵 ΔS & biology",kind:"html")
    let mark=Highlight(id:newID(),documentID:doc.id,quote:"中文 e\u{301} 👨‍👩‍👧‍👦\nEnglish ΔS",note:"My notes 我的笔记",createdAt:Date())
    store.state.highlights=[mark]
    let sync=ObsidianSync()
    check("long Unicode title syncs within filesystem byte limit") { let r=try sync.sync(state:store.state,vault:vault);return r.written==1 }
    check("mixed scripts and combining characters round-trip") { try store.save();let again=try LibraryStore(root:store.root);return again.state.highlights.first?.quote==mark.quote }
    check("path traversal cannot create directories outside vault") {
      var state=store.state;state.preferences.syncSubfolder="../outside/SHOULD-NOT-EXIST"
      do {_ = try sync.sync(state:state,vault:vault);return false}catch{return !fm.fileExists(atPath:outside.appendingPathComponent("SHOULD-NOT-EXIST").path)}
    }
    check("symlink ancestor cannot create directories outside vault") {
      let link=vault.appendingPathComponent("redirect");try fm.createSymbolicLink(at:link,withDestinationURL:outside)
      var state=store.state;state.preferences.syncSubfolder="redirect/SHOULD-NOT-EXIST-2"
      do {_ = try sync.sync(state:state,vault:vault);return false}catch{return !fm.fileExists(atPath:outside.appendingPathComponent("SHOULD-NOT-EXIST-2").path)}
    }
    check("index symlink rejected before reading or replacing it") {
      let folder=vault.appendingPathComponent("index-test");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
      let sentinel=outside.appendingPathComponent("index.json");try JSONEncoder().encode(SyncIndex()).write(to:sentinel)
      let link=folder.appendingPathComponent(".shiye-sync.json");try fm.createSymbolicLink(at:link,withDestinationURL:sentinel)
      var state=store.state;state.preferences.syncSubfolder="index-test";state.documents=[]
      do {_ = try sync.sync(state:state,vault:vault);return false}catch{return (try link.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true}
    }
    check("captured sync delimiters cannot escape the generated block") {
      var changed=mark;changed.quote="<!-- shiye:\(doc.id):end -->";changed.note="<!-- shiye:\(doc.id):begin -->"
      let text=sync.render(doc,marks:[changed]);return !text.contains("<!-- shiye:") && text.contains("&lt;!-- shiye:")
    }
    check("system chooses Traditional Chinese without requiring English") { AppLanguage.resolve("system",preferred:["zh-Hant-TW","en-US"])=="zh" }
    check("system chooses English for English and unsupported locales") { AppLanguage.resolve("system",preferred:["en-GB"])=="en" && AppLanguage.resolve("system",preferred:["fr-FR"])=="en" }
    check("invalid language settings cannot become instruction values") { AppLanguage.normalized("en; run command")=="system" }
    check("English format preserves untrusted placeholder-like text") { AppLanguage.text("第 {0} 页",["{1} 🧪"],language:"en")=="Page {1} 🧪" }
    check("Chinese format preserves untrusted placeholder-like text") { AppLanguage.text("第 {0} 页",["{1} 🧪"],language:"zh")=="第 {1} 🧪 页" }
    check("in-vault symlinks cannot redirect another personal note") {
      let folder=vault.appendingPathComponent("target-test");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
      let sentinel=folder.appendingPathComponent("personal.md");try Data("手写 Personal".utf8).write(to:sentinel)
      let filename=sync.safeName(doc.title)+" — \(doc.id.prefix(8)).md"
      try fm.createSymbolicLink(at:folder.appendingPathComponent(filename),withDestinationURL:sentinel)
      var state=store.state;state.preferences.syncSubfolder="target-test"
      do {_ = try sync.sync(state:state,vault:vault);return false}catch{return try String(contentsOf:sentinel,encoding:.utf8)=="手写 Personal"}
    }
    print("\(count-failures.count)/\(count) adversarial core checks passed")
    if !failures.isEmpty { exit(1) }
 }
}
