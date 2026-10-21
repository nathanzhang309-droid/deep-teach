import Foundation

struct StudyTurn: Codable, Identifiable {
    var id: String; var question: String; var answer: String; var page: Int
    var state: String = "pending"; var topicID: String
}
struct StudyTopic: Codable, Identifiable {
    var id: String; var title: String
    var summary = ""; var points: [String] = []; var confusions: [String] = []; var reviewQuestion = ""
    var turnIDs: [String] = []; var mastered = false; var personalNote = ""; var refined = false
}
struct StudyNotebook: Codable {
    var topics: [StudyTopic] = []; var turns: [StudyTurn] = []; var visitedPages: [Int] = []
    var completed = false
    var practice: PracticeNotebook? // Optional for existing v1 notebooks.
}
struct StudyArchive: Codable { var version = 1; var autoEnabled = true; var notebooks: [String: StudyNotebook] = [:]; var autoPractice: Bool? }
struct StudyRefinement: Codable {
    var topicID: String?; var title: String; var summary: String
    var points: [String]; var confusions: [String]; var reviewQuestion: String
}
enum StudyEngine {
    @discardableResult static func record(_ book: inout StudyNotebook, question: TeacherMessage, answer: TeacherMessage) -> Bool {
        guard question.role == "user", answer.role == "assistant", !answer.failed,
              answer.completed != false, !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !book.turns.contains(where: { $0.id == answer.id }) else { return false }
        let topicID = "topic-" + answer.id
        let anchor = question.context?.anchor?.quote ?? ""
        let title = String((anchor.isEmpty ? question.text : anchor).replacingOccurrences(of: "\n", with: " ").prefix(52))
        book.topics.append(StudyTopic(id: topicID, title: title, turnIDs: [answer.id]))
        book.turns.append(StudyTurn(id: answer.id, question: question.text, answer: answer.text, page: max(1, question.page), topicID: topicID))
        if !book.visitedPages.contains(question.page) { book.visitedPages.append(max(1, question.page)); book.visitedPages.sort() }
        book.completed = false
        return true
    }
    static func apply(_ refined: StudyRefinement, turnID: String, to book: inout StudyNotebook) throws {
        guard let t = book.turns.firstIndex(where: { $0.id == turnID }) else { throw ReaderError.message(L("原始问答已不存在")) }
        if book.turns[t].state == "done" { return }
        guard !refined.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !refined.summary.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              refined.title.count <= 160, refined.summary.count <= 10000,
              refined.points.count <= 20, refined.confusions.count <= 20,
              (refined.points + refined.confusions + [refined.reviewQuestion]).allSatisfy({ $0.count <= 5000 }) else { throw ReaderError.message(L("整理结果格式不完整，原问答已保留")) }
        let oldID = book.turns[t].topicID
        let targetID = (refined.topicID?.isEmpty == false) ? refined.topicID! : oldID
        guard let index = book.topics.firstIndex(where: { $0.id == targetID }) else { throw ReaderError.message(L("整理结果引用了不存在的知识点")) }
        var target = book.topics[index]
        if targetID != oldID, let source = book.topics.first(where: { $0.id == oldID }) {
            for id in source.turnIDs where !target.turnIDs.contains(id) { target.turnIDs.append(id) }
            if !source.personalNote.isEmpty { target.personalNote += (target.personalNote.isEmpty ? "" : "\n\n") + source.personalNote }
            for i in book.turns.indices where book.turns[i].topicID == oldID { book.turns[i].topicID = targetID }
            PracticeEngine.mergeTopic(oldID, into: targetID, in: &book)
        }
        target.title = refined.title; target.summary = refined.summary; target.points = refined.points
        target.confusions = refined.confusions; target.reviewQuestion = refined.reviewQuestion; target.refined = true
        book.topics[index] = target
        if targetID != oldID { book.topics.removeAll { $0.id == oldID } }
        book.turns[t].state = "done"
    }
    static func markdown(_ book: StudyNotebook, document: ReaderDocument) -> String {
        func clean(_ s: String) -> String { s.replacingOccurrences(of:"<!-- shiye:",with:"&lt;!-- shiye:") }
        var text = L("## 个性化学习笔记\n\n") + (book.completed ? L("已标记本轮学习完成") : L("学习中")) + L(" · {0} 个知识点 · {1} 次提问\n\n提问次数表示关注程度；掌握状态由你自行标记。\n", String(describing: book.topics.count), String(describing: book.turns.count))
        for topic in book.topics.sorted(by: { $0.turnIDs.count > $1.turnIDs.count }) {
            text += L("\n### {0}\n\n{1}{2} 次提问 · {3}\n\n", String(describing: clean(topic.title)), String(describing: topic.turnIDs.count >= 2 ? L("重点追问 · ") : ""), String(describing: topic.turnIDs.count), String(describing: topic.mastered ? L("自评已掌握") : L("待复习")))
            if topic.refined {
                text += clean(topic.summary) + "\n\n"
                if !topic.points.isEmpty { text += L("**核心要点**\n\n") + topic.points.map { "- " + clean($0) }.joined(separator:"\n") + "\n\n" }
                if !topic.confusions.isEmpty { text += L("**曾经追问的地方**\n\n") + topic.confusions.map { "- " + clean($0) }.joined(separator:"\n") + "\n\n" }
                if !topic.reviewQuestion.isEmpty { text += L("**复习自测**\n\n") + clean(topic.reviewQuestion) + "\n\n" }
            } else { text += L("原始问答 · 待整理\n\n") }
            for turn in book.turns where topic.turnIDs.contains(turn.id) {
                let location = document.kind == "pdf" ? L("第 {0} 页", String(describing: turn.page)) : L("原文")
                text += "<details>\n<summary>\(clean(turn.question).replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;"))</summary>\n\n" + clean(turn.answer) + "\n\n</details>\n\n[\(location)](shiye://document/\(document.id)?page=\(turn.page))\n\n"
            }
            if !topic.personalNote.isEmpty { text += L("**我的补充**\n\n") + clean(topic.personalNote) + "\n\n" }
            text += PracticeEngine.markdown(topicID: topic.id, book: book)
        }
        return text
    }
}
