import Foundation
// Minimal chat types keep the learning engine tests independent of AppKit/WebKit.
struct TeacherAnchor { var quote: String }
struct TeacherContext { var anchor: TeacherAnchor? }
struct TeacherMessage {
    var id: String; var role: String; var text: String; var page: Int
    var context: TeacherContext?; var failed = false; var completed: Bool? = true
}
@main struct PracticeTests {
    static func main() throws {
        var count = 0
        func check(_ name: String, _ value: Bool) { precondition(value, name); count += 1; print("PASS", name) }
        func response(_ text: String) -> PracticeResponse { PracticeResponse(question: .init(prompt: text, options: ["B", "A"], correctIndex: 0, explanation: "Use the condition B as the denominator."), review: .init(explanation: "You selected A; the denominator is B, the given condition.", steps: ["Identify the condition.", "Divide the intersection by its probability."])) }
        var book = StudyNotebook()
        let quiz = """
        ```dsh-ui
        {"items":[{"type":"quiz","question":"P(A|B) 的分母？","options":[{"label":"P(A)","correct":false},{"label":"P(B)","correct":true}],"explanation":"已知 B，分母为 P(B)。"}]}
        ```
        """
        let user = TeacherMessage(id: "u", role: "user", text: "条件概率？", page: 3)
        let answer = TeacherMessage(id: "a", role: "assistant", text: quiz, page: 3)
        check("record source", StudyEngine.record(&book, question: user, answer: answer))
        let topic = book.topics[0].id
        check("asking is not evidence of weakness", !PracticeEngine.needsReview(topicID: topic, book: book))
        check("register valid nested bilingual quiz", PracticeEngine.register(answer: answer, in: &book) == 1)
        check("register is idempotent", PracticeEngine.register(answer: answer, in: &book) == 0)
        let root = book.practice!.questions[0].id
        check("reject out of range", !PracticeEngine.submit(questionID: root, selected: 99, revealed: false, in: &book))
        check("reject contradictory reveal", !PracticeEngine.submit(questionID: root, selected: 1, revealed: true, in: &book))
        check("first wrong answer saved", PracticeEngine.submit(questionID: root, selected: 0, revealed: false, in: &book))
        check("wrong answer adds one job and immediate review", book.practice!.jobs.count == 1 && book.practice!.reviews.count == 1 && PracticeEngine.needsReview(topicID: topic, book: book))
        check("cannot rewrite first attempt", !PracticeEngine.submit(questionID: root, selected: 1, revealed: false, in: &book) && book.practice!.attempts.count == 1)
        let job1 = book.practice!.jobs[0].id
        do { try PracticeEngine.apply(response("P(A|B) 的分母？"), jobID: job1, to: &book); check("duplicate rejected", false) } catch { check("duplicate leaves pending job intact", book.practice!.jobs[0].state == "pending" && book.practice!.questions.count == 1) }
        try PracticeEngine.apply(response("Given P(A∩B)=0.1 and P(B)=0.5, which probability is the denominator?"), jobID: job1, to: &book)
        check("followup keeps source and bounded depth", book.practice!.questions[1].depth == 1 && book.practice!.questions[1].page == 3 && book.practice!.questions[1].turnID == "a")
        check("personalized review saved", book.practice!.reviews[0].generated && book.practice!.reviews[0].steps.count == 2)
        var recovery = book
        _ = PracticeEngine.submit(questionID: job1, selected: 0, revealed: false, in: &recovery)
        check("one correct answer does not prematurely clear weakness", PracticeEngine.needsReview(topicID: topic, book: recovery))
        check("manual new round available after correct", PracticeEngine.request(topicID: topic, in: &recovery))
        let recoveryJob = recovery.practice!.jobs.last!.id
        try PracticeEngine.apply(response("New independent check"), jobID: recoveryJob, to: &recovery)
        _ = PracticeEngine.submit(questionID: recoveryJob, selected: 0, revealed: false, in: &recovery)
        check("two subsequent first answers resolve review flag, not mastery", !PracticeEngine.needsReview(topicID: topic, book: recovery) && !recovery.topics[0].mastered)
        check("revealing an answer counts as review", PracticeEngine.submit(questionID: job1, selected: nil, revealed: true, in: &book))
        let job2 = book.practice!.jobs.last!.id
        try PracticeEngine.apply(response("Second variation"), jobID: job2, to: &book)
        _ = PracticeEngine.submit(questionID: job2, selected: 1, revealed: false, in: &book)
        check("at most two automatic followups per root", book.practice!.questions.last!.depth == 2 && book.practice!.jobs.count == 2)
        let before = book
        PracticeEngine.dispute(questionID: root, in: &book)
        check("disputed question and descendants excluded", PracticeEngine.attempts(topicID: topic, book: book).isEmpty && book.practice!.questions.allSatisfy { $0.invalidated == true })
        check("disputed history retained", book.practice!.attempts.count == 3 && book.practice!.questions.count == 3)
        var pending = before; pending.practice!.jobs.append(.init(id: "pending", topicID: topic, parentID: job2))
        PracticeEngine.dispute(questionID: root, in: &pending)
        check("dispute cancels pending descendant", pending.practice!.jobs.last!.state == "cancelled")
        book = before
        book.topics[0].personalNote = "My handwritten supplement"; book.topics[0].mastered = true
        let other = TeacherMessage(id: "b", role: "assistant", text: "B is the condition.", page: 7)
        _ = StudyEngine.record(&book, question: user, answer: other)
        let target = book.topics.last!.id
        try StudyEngine.apply(.init(topicID: target, title: "Conditional probability", summary: "Restrict the sample space to B.", points: [], confusions: [], reviewQuestion: "Which denominator?"), turnID: "a", to: &book)
        check("topic merge retargets questions and jobs", book.practice!.questions.allSatisfy { $0.topicID == target } && book.practice!.jobs.allSatisfy { $0.topicID == target })
        check("topic merge preserves personal supplement", book.topics[0].personalNote.contains("handwritten"))
        let doc = ReaderDocument(id: "doc", title: "Probability", kind: "pdf", createdAt: Date(), lastOpenedAt: Date(), relativePath: "test.pdf", digest: "test")
        let markdown = StudyEngine.markdown(book, document: doc)
        check("export includes error, selected option, reasoning, source and manual notes", markdown.contains("P(A)") && markdown.contains("Identify the condition") && markdown.contains("?page=3") && markdown.contains("handwritten"))
        let roundtrip = try JSONDecoder().decode(StudyNotebook.self, from: JSONEncoder().encode(book))
        check("roundtrip retains first attempts", roundtrip.practice!.attempts.count == 3 && roundtrip.practice!.attempts[1].revealed)
        let legacy = try JSONDecoder().decode(StudyArchive.self, from: Data(#"{"version":1,"autoEnabled":false,"notebooks":{"doc":{"topics":[],"turns":[],"visitedPages":[],"completed":false}}}"#.utf8))
        check("legacy archive decodes without migration loss", legacy.notebooks["doc"]!.practice == nil && legacy.autoPractice == nil)
        for malformed in [response("").question, .init(prompt: "test", options: [" A ", "a"], correctIndex: 0, explanation: "x"), .init(prompt: "test", options: ["A","B"], correctIndex: -1, explanation: "x")] { check("reject malformed question", !PracticeEngine.valid(malformed)) }
        var invalid = StudyNotebook(); var malformed = answer
        malformed.text = quiz.replacingOccurrences(of: "false", with: "true")
        _ = StudyEngine.record(&invalid, question: user, answer: malformed)
        check("multiple correct options rejected", PracticeEngine.register(answer: malformed, in: &invalid) == 0)
        malformed = answer; malformed.completed = false
        check("partial streamed quiz cannot be answered", PracticeEngine.register(answer: malformed, in: &invalid) == 0)
        malformed.completed = nil
        check("legacy recorded complete quiz remains usable", PracticeEngine.register(answer: malformed, in: &invalid) == 1)
        print("\(count) practice engine checks passed")
    }
}
