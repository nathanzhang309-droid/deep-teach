import Foundation

/// Language affects interface text and new model requests, never stored user content or stable IDs.
enum AppLanguage {
    static var preference = normalized(ProcessInfo.processInfo.environment["DEEP_TEACH_LANGUAGE"] ?? UserDefaults.standard.string(forKey:"DeepTeachLanguage") ?? "system")
    static func normalized(_ value:String)->String { ["system","zh","en"].contains(value) ? value : "system" }
    static func resolve(_ value:String,preferred:[String]=Locale.preferredLanguages)->String {
        let choice=normalized(value)
        return choice=="system" ? ((preferred.first ?? "en").lowercased().hasPrefix("zh") ? "zh":"en") : choice
    }
    static var code:String { resolve(preference) }
    static var locale:Locale { preference=="system" ? .autoupdatingCurrent : Locale(identifier:code=="zh" ? "zh_Hans":"en_"+(Locale.current.region?.identifier ?? "US")) }
    static let english:[String:String] = {
        let test=ProcessInfo.processInfo.environment["DEEP_TEACH_TEST_RESOURCES"].map{URL(fileURLWithPath:$0)}
        guard let url=(test ?? Bundle.main.resourceURL)?.appendingPathComponent("en.json"),
              let data=try? Data(contentsOf:url),let entries=try? JSONDecoder().decode([String:String].self,from:data) else { return [:] }
        return entries
    }()
    static func text(_ key:String,_ values:[String]=[],language:String?=nil)->String {
        let template=(language ?? code)=="en" ? (english[key] ?? key):key
        let pattern=try! NSRegularExpression(pattern:#"\{(\d+)\}"#)
        let result=NSMutableString(string:template)
        for match in pattern.matches(in:template,range:NSRange(template.startIndex...,in:template)).reversed() {
            if let range=Range(match.range(at:1),in:template),let index=Int(template[range]),values.indices.contains(index) { result.replaceCharacters(in:match.range,with:values[index]) }
        }
        return result as String
    }
}
func L(_ key:String,_ values:String...)->String { AppLanguage.text(key,values) }
