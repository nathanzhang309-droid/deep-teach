import Foundation

struct PracticeQuestion: Codable, Identifiable {
    var id: String; var topicID: String; var turnID: String; var page: Int
    var prompt: String; var options: [String]; var correctIndex: Int; var explanation: String
    var rootID: String; var depth: Int = 0; var parentID: String?
    var origin: String = "teacher"
    var invalidated: Bool?
}
struct PracticeAttempt: Codable, Identifiable {
    var id: String; var selected: Int?; var revealed: Bool; var disputed = false; var createdAt = Date()
}
struct PracticeJob: Codable, Identifiable {
    var id: String; var topicID: String; var parentID: String?; var state = "pending"; var automatic = false
}
struct PracticeReview: Codable, Identifiable {
    var id: String; var explanation: String; var steps: [String]; var generated = false
}
struct PracticeNotebook: Codable {
    var questions: [PracticeQuestion] = []; var attempts: [PracticeAttempt] = []
    var jobs: [PracticeJob] = []; var reviews: [PracticeReview] = []
}
struct PracticeResponse: Codable {
    struct Question: Codable { var prompt: String; var options: [String]; var correctIndex: Int; var explanation: String }
    struct Review: Codable { var explanation: String; var steps: [String] }
    var question: Question; var review: Review
}

enum PracticeEngine {
    static func valid(_ q: PracticeResponse.Question) -> Bool {
        !q.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && q.prompt.count <= 3000 &&
        (2...6).contains(q.options.count) && q.options.indices.contains(q.correctIndex) &&
        q.options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1000 } &&
        Set(q.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == q.options.count &&
        !q.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && q.explanation.count <= 6000
    }
    static func isCorrect(_ attempt: PracticeAttempt, question: PracticeQuestion) -> Bool {
        !attempt.revealed && attempt.selected == question.correctIndex
    }
    static func attempts(topicID: String, book: StudyNotebook) -> [(PracticeQuestion, PracticeAttempt)] {
        let p = book.practice ?? PracticeNotebook()
        return p.attempts.compactMap { a in
            guard !a.disputed, let q = p.questions.first(where: { $0.id == a.id && $0.topicID == topicID }) else { return nil }
            return (q, a)
        }
    }
    /// An incorrect/revealed answer needs review until two subsequent independent first answers are correct.
    /// This is a transparent review rule, not a mastery score or a change to the student's self-assessment.
    static func needsReview(topicID: String, book: StudyNotebook) -> Bool {
        let rows = attempts(topicID: topicID, book: book)
        guard let failure = rows.lastIndex(where: { !isCorrect($0.1, question: $0.0) }) else { return false }
        return rows.count - failure - 1 < 2
    }
    @discardableResult static func register(answer: TeacherMessage, in book: inout StudyNotebook) -> Int {
        // Older archived messages omit completed; only already-recorded study turns are eligible.
        guard answer.completed != false, !answer.failed, answer.text.utf8.count <= 240_000,
              let turn = book.turns.first(where: { $0.id == answer.id }) else { return 0 }
        let regex = try! NSRegularExpression(pattern: "```dsh-ui\\s*\\n([\\s\\S]*?)```")
        let ns = answer.text as NSString
        var blocks: [[String: Any]] = []
        func visit(_ object: Any, depth: Int = 0) {
            guard depth < 4, blocks.count < 12, let node = object as? [String: Any] else { return }
            if node["type"] as? String == "quiz" { blocks.append(node) }
            else if node["type"] == nil, let items = node["items"] as? [Any] { for item in items.prefix(8) { visit(item, depth: depth + 1) } }
        }
        for match in regex.matches(in: answer.text, range: NSRange(location: 0, length: ns.length)) {
            if let object = try? JSONSerialization.jsonObject(with: Data(ns.substring(with: match.range(at: 1)).utf8)) { visit(object) }
        }
        var p = book.practice ?? PracticeNotebook(); var count = 0
        for (index, b) in blocks.enumerated() {
            guard let prompt = b["question"] as? String, let opts = b["options"] as? [[String: Any]],
                  opts.allSatisfy({ $0["label"] is String }), let correct = opts.firstIndex(where: { ($0["correct"] as? Bool) == true }),
                  opts.filter({ ($0["correct"] as? Bool) == true }).count == 1 else { continue }
            let explanation = (b["explanation"] as? String) ?? (opts[correct]["feedback"] as? String) ?? L("请回到原讲解核对这道题。")
            let parsed = PracticeResponse.Question(prompt: prompt, options: opts.compactMap { $0["label"] as? String }, correctIndex: correct, explanation: explanation)
            guard valid(parsed) else { continue }
            let id = "quiz-\(answer.id)-\(index)"
            guard !p.questions.contains(where: { $0.id == id }) else { continue }
            p.questions.append(PracticeQuestion(id: id, topicID: turn.topicID, turnID: turn.id, page: turn.page,
                prompt: prompt, options: parsed.options, correctIndex: correct, explanation: explanation, rootID: id))
            count += 1
        }
        book.practice = p; return count
    }
    @discardableResult static func submit(questionID: String, selected: Int?, revealed: Bool, in book: inout StudyNotebook) -> Bool {
        guard var p = book.practice, let q = p.questions.first(where: { $0.id == questionID }),
              q.invalidated != true, !p.attempts.contains(where: { $0.id == questionID }),
              revealed ? selected == nil : (selected.map { q.options.indices.contains($0) } ?? false) else { return false }
        let a = PracticeAttempt(id: questionID, selected: selected, revealed: revealed)
        p.attempts.append(a)
        if !isCorrect(a, question: q) {
            p.reviews.append(PracticeReview(id: questionID, explanation: q.explanation, steps: []))
            if q.depth < 2 { p.jobs.append(PracticeJob(id: "followup-" + q.id, topicID: q.topicID, parentID: q.id, automatic: true)) }
        }
        book.practice = p; return true
    }
    @discardableResult static func request(topicID: String, in book: inout StudyNotebook) -> Bool {
        guard book.topics.contains(where: { $0.id == topicID }) else { return false }
        var p = book.practice ?? PracticeNotebook()
        guard !p.jobs.contains(where: { $0.topicID == topicID && $0.state == "pending" }),
              !p.questions.contains(where: { q in q.topicID == topicID && q.invalidated != true && !p.attempts.contains(where: { $0.id == q.id }) }) else { return false }
        p.jobs.append(PracticeJob(id: UUID().uuidString, topicID: topicID)); book.practice = p; return true
    }
    static func apply(_ response: PracticeResponse, jobID: String, to book: inout StudyNotebook) throws {
        guard var p = book.practice, let j = p.jobs.firstIndex(where: { $0.id == jobID && $0.state == "pending" }),
              let topic = book.topics.first(where: { $0.id == p.jobs[j].topicID }),
              let turn = book.turns.first(where: { $0.topicID == topic.id }) else { throw ReaderError.message(L("练习上下文已变化，请重试。")) }
        guard valid(response.question), response.review.explanation.count <= 6000, response.review.steps.count <= 8,
              response.review.steps.allSatisfy({ $0.count <= 2000 }) else { throw ReaderError.message(L("练习格式不完整，请重试。")) }
        let parent = p.jobs[j].parentID.flatMap { id in p.questions.first(where: { $0.id == id }) }
        if let parentID = p.jobs[j].parentID {
            guard let parent, parent.id == parentID, parent.depth < 2,
                  let a = p.attempts.first(where: { $0.id == parentID }), !a.disputed, !isCorrect(a, question: parent) else { throw ReaderError.message(L("练习上下文已变化，请重试。")) }
        }
        guard !p.questions.contains(where: { $0.topicID == topic.id && $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == response.question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) else { throw ReaderError.message(L("老师重复了原题，请重试生成变式题。")) }
        let q = response.question
        p.questions.append(PracticeQuestion(id: jobID, topicID: topic.id, turnID: parent?.turnID ?? turn.id, page: parent?.page ?? turn.page,
            prompt: q.prompt, options: q.options, correctIndex: q.correctIndex, explanation: q.explanation,
            rootID: parent?.rootID ?? jobID, depth: (parent?.depth ?? -1) + 1, parentID: parent?.id, origin: "practice"))
        if let parent, let i = p.reviews.firstIndex(where: { $0.id == parent.id }), !response.review.explanation.isEmpty {
            p.reviews[i] = PracticeReview(id: parent.id, explanation: response.review.explanation, steps: response.review.steps, generated: true)
        }
        p.jobs[j].state = "done"; book.practice = p
    }
    static func dispute(questionID: String, in book: inout StudyNotebook) {
        guard var p = book.practice, let i = p.attempts.firstIndex(where: { $0.id == questionID }) else { return }
        p.attempts[i].disputed = true
        var excluded: Set<String> = [questionID]
        for _ in 0..<3 { for q in p.questions where q.parentID.map({ excluded.contains($0) }) == true { excluded.insert(q.id) } }
        for i in p.questions.indices where excluded.contains(p.questions[i].id) { p.questions[i].invalidated = true }
        for i in p.attempts.indices where excluded.contains(p.attempts[i].id) { p.attempts[i].disputed = true }
        for j in p.jobs.indices where p.jobs[j].parentID.map({ excluded.contains($0) }) == true && p.jobs[j].state != "done" { p.jobs[j].state = "cancelled" }
        book.practice = p
    }
    static func mergeTopic(_ old: String, into target: String, in book: inout StudyNotebook) {
        guard var p = book.practice else { return }
        for i in p.questions.indices where p.questions[i].topicID == old { p.questions[i].topicID = target }
        for i in p.jobs.indices where p.jobs[i].topicID == old { p.jobs[i].topicID = target }
        book.practice = p
    }
    static func markdown(topicID: String, book: StudyNotebook) -> String {
        let rows = attempts(topicID: topicID, book: book)
        guard !rows.isEmpty else { return "" }
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "<!-- shiye:", with: "&lt;!-- shiye:") }
        let failures = rows.filter { !isCorrect($0.1, question: $0.0) }
        var text = L("**练习与个性化复习**\n\n")
        text += (needsReview(topicID: topicID, book: book) ? L("需要复习：近期有答错或看答案的记录。") : L("最近练习已完成；不等同于完全掌握。")) + "\n\n"
        for (q, a) in failures {
            text += "- " + L("题目：{0}", clean(q.prompt)) + "\n"
            text += "  " + (a.revealed ? L("本次查看了答案，未计为独立答对。") : L("你的选择：{0}", a.selected.flatMap { q.options.indices.contains($0) ? clean(q.options[$0]) : nil } ?? "—")) + "\n"
            text += "  " + L("参考答案：{0}", q.options.indices.contains(q.correctIndex) ? clean(q.options[q.correctIndex]) : "—") + "\n"
            let review = book.practice?.reviews.first(where: { $0.id == q.id })
            text += "  " + clean(review?.explanation ?? q.explanation) + "\n"
            for step in review?.steps ?? [] { text += "  - " + clean(step) + "\n" }
            text += "  " + L("来源：第 {0} 页", String(q.page)) + "\n\n"
        }
        text += L("记录 {0} 次首次作答，其中 {1} 次独立答对。", String(rows.count), String(rows.filter { isCorrect($0.1, question: $0.0) }.count)) + "\n\n"
        return text
    }
}
