import AppKit
import WebKit

@MainActor enum PracticeNativeTests {
 static func run(model: AppModel, window: NSWindow) async {
    guard ProcessInfo.processInfo.environment["SHIYE_DATA_DIR"] != nil else { return }
    var checks: [String: Bool] = [:]; var error = ""
    func pause(_ seconds: Double = 0.2) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    do {
        model.autoSync = false; model.study.autoEnabled = false; model.study.autoPractice = false
        let doc = try model.store.addArticle(title: "Synthetic probability practice", html: "<h1>Conditional probability</h1><p>P(A|B)=P(A∩B)/P(B). B is the condition.</p>", text: "Conditional probability", kind: "html")
        let other = try model.store.addArticle(title: "Other synthetic course", html: "<h1>Other</h1>", text: "Other", kind: "html")
        model.library = model.store.state.documents; model.selectDocument(doc.id)
        let user = TeacherMessage(id: "user-practice", role: "user", text: "Which denominator?", page: 3)
        let answer = TeacherMessage(id: "answer-practice", role: "assistant", text: """
        P(A|B)=P(A∩B)/P(B). We restrict the sample space to B.
        ```dsh-ui
        {"type":"quiz","question":"Which denominator belongs to P(A|B)?","options":[{"label":"P(A)","correct":false},{"label":"P(B)","correct":true}],"explanation":"B is the given condition. Divide by P(B)."}
        ```
        """, page: 3, completed: true)
        model.teaching.conversations[doc.id] = [user, answer]; model.saveTeaching()
        model.recordStudyTurn(documentID: doc.id, answerID: answer.id)
        let q = model.currentPractice.questions[0]
        checks["completed_teacher_quiz_registered"] = q.turnID == answer.id && q.page == 3
        model.selectDocument(other.id)
        model.submitPractice(documentID: doc.id, questionID: q.id, selected: 0, revealed: false)
        checks["stale_web_submission_cannot_cross_documents"] = model.study.notebooks[doc.id]!.practice!.attempts.isEmpty
        model.selectDocument(doc.id)
        let backup = model.store.root.appendingPathComponent("practice-save-test.json")
        try FileManager.default.moveItem(at: model.studyURL, to: backup)
        try FileManager.default.createDirectory(at: model.studyURL, withIntermediateDirectories: false)
        model.submitPractice(documentID: doc.id, questionID: q.id, selected: 0, revealed: false)
        checks["failed_disk_write_rolls_back_and_blocks_generation"] = model.currentPractice.attempts.isEmpty && model.practicePersistenceBlocked && !model.practiceBusy
        try FileManager.default.removeItem(at: model.studyURL); try FileManager.default.moveItem(at: backup, to: model.studyURL)

        // Exercise the shipped React page and the real WKScriptMessageHandler, not a copied grading function.
        let coordinator = TeacherPanel.Coordinator(model)
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.userContentController.add(coordinator, name: "teacher")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 650, height: 800), configuration: config)
        coordinator.web = web; web.navigationDelegate = coordinator
        let resources = Bundle.main.resourceURL!.appendingPathComponent("TeacherUI")
        web.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        for _ in 0..<100 { if coordinator.ready { break }; await pause(0.1) }
        coordinator.update(); await pause(0.6)
        let clicked = try await web.evaluateJavaScript("(() => { const b=document.querySelector('[data-practice-id] .quiz-option'); if (!b) return false; b.click(); return true; })()") as? Bool
        await pause(0.3); coordinator.update(); await pause(0.3)
        checks["real_web_quiz_click_persists_wrong_answer"] = clicked == true && model.currentPractice.attempts.first?.selected == 0
        checks["auto_off_queues_without_request"] = model.currentPractice.jobs.count == 1 && !model.practiceBusy && model.practiceProcess == nil
        let state = try await web.evaluateJavaScript("({disabled:[...document.querySelectorAll('[data-practice-id] .quiz-option')].every(b=>b.disabled),review:document.querySelector('[data-practice-id] .quiz-feedback')?.textContent||''})") as? [String: Any]
        checks["web_feedback_acknowledges_native_state"] = state?["disabled"] as? Bool == true && !(state?["review"] as? String ?? "").isEmpty
        model.submitPractice(documentID: doc.id, questionID: q.id, selected: 1, revealed: false)
        checks["duplicate_answer_does_not_overwrite_or_enqueue_twice"] = model.currentPractice.attempts.count == 1 && model.currentPractice.attempts[0].selected == 0 && model.currentPractice.jobs.count == 1
        let topic = q.topicID
        model.setStudyPersonalNote(topicID: topic, text: "Keep my handwritten supplement.")
        model.setStudyMastered(topicID: topic, value: true)
        let saved = try JSONDecoder().decode(StudyArchive.self, from: Data(contentsOf: model.studyURL))
        checks["durable_attempt_and_immediate_personal_review"] = saved.notebooks[doc.id]!.practice!.reviews.count == 1 && saved.notebooks[doc.id]!.topics[0].mastered
        let vault = model.store.root.appendingPathComponent("test-vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        model.vaultPath = vault.path; model.syncNow()
        let files = try FileManager.default.contentsOfDirectory(at: vault.appendingPathComponent(ObsidianSync.subfolder), includingPropertiesForKeys: nil)
        let note = try files.first { (try? String(contentsOf: $0).contains(q.prompt)) == true }.unwrap()
        var md = try String(contentsOf: note); checks["review_sync_includes_actual_choice_and_source"] = md.contains("P(A)") && md.contains("B is the given condition") && md.contains("?page=3")
        md += "\nFreeform Obsidian supplement.\n"; try md.write(to: note, atomically: true, encoding: .utf8)
        let job = model.currentPractice.jobs[0]
        if ProcessInfo.processInfo.environment["BANDU_PRACTICE_LIVE_TEST"] == "1" {
            model.tutorProvider = ProcessInfo.processInfo.environment["BANDU_TEST_PROVIDER"] ?? "codex"
            model.setAutoPractice(true)
            for _ in 0..<240 { if !model.practiceBusy { break }; await pause(1) }
            checks["live_followup_and_personalized_review"] = model.currentPractice.jobs[0].state == "done" && model.currentPractice.questions.count == 2 && model.currentPractice.reviews[0].generated
            if checks["live_followup_and_personalized_review"] != true { error = model.practiceStatus }
        } else {
            let response = PracticeResponse(question: .init(prompt: "Given the condition C, which denominator?", options: ["P(C)", "P(A)"], correctIndex: 0, explanation: "The denominator is P(C)."), review: .init(explanation: "Your choice P(A) uses the target instead of the condition.", steps: ["Identify the condition B.", "Use P(B) as the denominator."]))
            var latest = model.currentNotebook; try PracticeEngine.apply(response, jobID: job.id, to: &latest)
            model.editPractice(documentID: doc.id) { $0 = latest }
        }
        model.setAutoPractice(false); model.syncNow()
        checks["obsidian_manual_supplement_survives_updated_review"] = try String(contentsOf: note).contains("Freeform Obsidian supplement.")
        checks["learning_update_preserves_self_assessment_and_manual_note"] = model.currentNotebook.topics[0].mastered && model.currentNotebook.topics[0].personalNote.contains("handwritten")
        coordinator.update(); await pause(0.3)
        let count = try await web.evaluateJavaScript("document.querySelectorAll('[data-practice-id]').length") as? Int
        checks["generated_followup_appears_in_teacher_chat"] = count == 2
        model.openStudyReview(topicID: topic); await pause(0.5)
        checks["review_window_opens_and_resizes"] = model.studyWindow?.isVisible == true && model.studyWindow?.styleMask.contains(.resizable) == true
        let reloaded = AppModel(store: try LibraryStore(root: model.store.root))
        checks["reload_restores_practice_without_duplicate_questions"] = reloaded.study.notebooks[doc.id]!.practice!.questions.count == model.currentPractice.questions.count
        checks["reload_retains_wrong_attempt"] = reloaded.study.notebooks[doc.id]!.practice!.attempts.first?.selected == 0
        config.userContentController.removeScriptMessageHandler(forName: "teacher"); web.stopLoading()
    } catch let e { error = e.localizedDescription }
    model.pausePracticeProcess(); model.pauseStudyProcess()
    let result: [String: Any] = ["checks": checks, "error": error, "passed": error.isEmpty && !checks.values.contains(false), "language": AppLanguage.code]
    if let bytes = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? bytes.write(to: model.store.root.appendingPathComponent("practice-validation.json")) }
    if ProcessInfo.processInfo.environment["BANDU_TEST_QUIT"] == "1" { NSApp.terminate(nil) }
 }
}
private extension Optional {
 func unwrap() throws -> Wrapped { guard let value = self else { throw ReaderError.message("Practice test: missing synced note") }; return value }
}
