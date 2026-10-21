import Foundation

@MainActor extension AppModel {
    var currentPractice: PracticeNotebook { currentNotebook.practice ?? PracticeNotebook() }
    var autoPracticeEnabled: Bool { study.autoPractice ?? true }
    var weakStudyTopics: [StudyTopic] { currentStudyTopics.filter { PracticeEngine.needsReview(topicID: $0.id, book: currentNotebook) } }
    func registerExistingPractice() {
        guard studyWritable else { return }; var count = 0; let old = study
        for id in study.notebooks.keys.sorted() {
            guard var book = study.notebooks[id] else { continue }
            for answer in teaching.conversations[id] ?? [] where answer.role == "assistant" { count += PracticeEngine.register(answer: answer, in: &book) }
            study.notebooks[id] = book
        }
        if count > 0 && !saveStudy(sync: false) { study = old; practicePersistenceBlocked = true }
    }

    /// Persist before acknowledging an answer or starting a subscription request. Roll back on disk errors.
    @discardableResult func editPractice(documentID: String, _ edit: (inout StudyNotebook) -> Void) -> Bool {
        guard studyWritable, let previous = study.notebooks[documentID] else { return false }
        var next = previous; edit(&next); study.notebooks[documentID] = next
        guard saveStudy() else { study.notebooks[documentID] = previous; practicePersistenceBlocked = true; practiceStatus = L("练习记录保存失败，请重试。"); return false }
        practicePersistenceBlocked = false; tutorRevision += 1; return true
    }
    func submitPractice(documentID: String, questionID: String, selected: Int?, revealed: Bool) {
        guard documentID == selectedID else { return }
        var accepted = false
        guard editPractice(documentID: documentID, { accepted = PracticeEngine.submit(questionID: questionID, selected: selected, revealed: revealed, in: &$0) }), accepted else { return }
        practiceStatus = L("首次作答已保存，复习笔记已更新。")
        processStudyQueue()
    }
    func requestPractice(topicID: String) {
        guard let id = selectedID else { return }
        var accepted = false
        guard editPractice(documentID: id, { accepted = PracticeEngine.request(topicID: topicID, in: &$0) }), accepted else { return }
        practiceStatus = L("正在准备知识点自测…"); processStudyQueue()
    }
    func disputePractice(questionID: String) {
        guard let id = selectedID else { return }
        if editPractice(documentID: id, { PracticeEngine.dispute(questionID: questionID, in: &$0) }) {
            if activePracticeJob?.0 == id, let jobID = activePracticeJob?.1,
               currentPractice.jobs.first(where: { $0.id == jobID })?.state == "cancelled" { pausePracticeProcess() }
            practiceStatus = L("已标记待核对，不再用这次作答判断薄弱点。"); processStudyQueue()
        }
    }
    func retryPractice(jobID: String) {
        guard let id = selectedID else { return }
        if editPractice(documentID: id, { book in
            guard let i = book.practice?.jobs.firstIndex(where: { $0.id == jobID && $0.state == "error" }) else { return }
            book.practice!.jobs[i].state = "pending"; book.practice!.jobs[i].automatic = false
        }) { processStudyQueue() }
    }
    func cancelPractice(jobID: String) {
        guard let id = selectedID else { return }
        if activePracticeJob?.0 == id && activePracticeJob?.1 == jobID { pausePracticeProcess() }
        if editPractice(documentID: id, { book in
            guard let i = book.practice?.jobs.firstIndex(where: { $0.id == jobID && ["pending", "error"].contains($0.state) }) else { return }
            book.practice!.jobs[i].state = "cancelled"
        }) { practiceStatus = L("本轮已暂停，作答和笔记仍保留。"); processStudyQueue() }
    }
    func setAutoPractice(_ enabled: Bool) {
        let old = study.autoPractice; study.autoPractice = enabled
        guard saveStudy(sync: false) else { study.autoPractice = old; return }
        if !enabled, let (docID, jobID) = activePracticeJob,
           study.notebooks[docID]?.practice?.jobs.first(where: { $0.id == jobID })?.automatic == true { pausePracticeProcess() }
        processStudyQueue()
    }
    func pausePracticeProcess() {
        let runner = practiceProcess; practiceProcess = nil; activePracticeJob = nil; practiceBusy = false; runner?.stop()
    }
    @discardableResult func processPracticeQueue() -> Bool {
        guard studyWritable, !practicePersistenceBlocked, !tutorBusy, !studyBusy, !practiceBusy else { return false }
        var candidate: (String, PracticeJob)?
        for id in study.notebooks.keys.sorted() where library.contains(where: { $0.id == id }) {
            if let job = study.notebooks[id]?.practice?.jobs.first(where: { $0.state == "pending" && (!$0.automatic || autoPracticeEnabled) }) { candidate = (id, job); break }
        }
        guard let (docID, job) = candidate, let book = study.notebooks[docID], let topic = book.topics.first(where: { $0.id == job.topicID }) else { return false }
        let parent = job.parentID.flatMap { id in book.practice?.questions.first(where: { $0.id == id }) }
        let attempt = parent.flatMap { q in book.practice?.attempts.first(where: { $0.id == q.id }) }
        let sources = book.turns.filter { $0.topicID == topic.id }.suffix(4).map { ["page": $0.page, "question": String($0.question.prefix(2000)), "answer": String($0.answer.prefix(7000))] as [String: Any] }
        var request: [String: Any] = ["mode": "practice", "language": AppLanguage.code, "provider": tutorProvider,
            "topic": ["title": topic.title, "summary": topic.summary, "points": topic.points], "sources": sources,
            "previousQuestions": (book.practice?.questions.filter { $0.topicID == topic.id }.suffix(8).map(\.prompt) ?? [])]
        if let parent, let attempt {
            request["attempt"] = ["question": parent.prompt, "options": parent.options, "correctIndex": parent.correctIndex,
                "selectedIndex": attempt.selected as Any? ?? NSNull(), "revealed": attempt.revealed, "explanation": parent.explanation]
        }
        let runner = TeacherProcess(); practiceProcess = runner; activePracticeJob = (docID, job.id); practiceBusy = true
        practiceStatus = L("正在生成变式练习与复习讲解…")
        var output = ""; var finalized = false
        func fail(_ message: String) {
            _ = self.editPractice(documentID: docID) { b in
                if let i = b.practice?.jobs.firstIndex(where: { $0.id == job.id && $0.state == "pending" }) { b.practice!.jobs[i].state = "error" }
            }
            self.practiceStatus = L("生成未完成，作答与复习笔记已保留。{0}", message)
        }
        do { try runner.start(request) { [weak self, weak runner] event in
            guard let self, let runner, self.practiceProcess === runner else { return }
            switch event["type"] as? String {
            case "delta":
                if !finalized { output += event["text"] as? String ?? ""; if output.utf8.count > 60000 { finalized = true; fail(L("输出过长，请重试")); runner.stop() } }
            case "error": if !finalized { finalized = true; fail(event["error"] as? String ?? L("请重试")) }
            case "done":
                guard !finalized else { return }; finalized = true
                do {
                    guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end else { throw ReaderError.message(L("练习格式不完整，请重试。")) }
                    let response = try JSONDecoder().decode(PracticeResponse.self, from: Data(output[start...end].utf8))
                    guard var latest = self.study.notebooks[docID] else { return }
                    try PracticeEngine.apply(response, jobID: job.id, to: &latest)
                    if self.editPractice(documentID: docID, { $0 = latest }) { self.practiceStatus = L("变式练习已就绪，复习笔记已更新。") }
                    else { fail(L("练习记录保存失败，请重试。")) }
                } catch { fail(error.localizedDescription) }
            case "exit":
                if !finalized { fail(L("生成意外中断，请重试。")) }
                self.practiceProcess = nil; self.activePracticeJob = nil; self.practiceBusy = false; self.processStudyQueue()
            default: break
            }
        }} catch { fail(error.localizedDescription); practiceProcess = nil; activePracticeJob = nil; practiceBusy = false }
        return true
    }
}
