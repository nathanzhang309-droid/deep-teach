import SwiftUI

@MainActor struct StudyPracticeView: View {
    @ObservedObject var model: AppModel
    let topicID: String
    private var questions: [PracticeQuestion] { model.currentPractice.questions.filter { $0.topicID == topicID && $0.invalidated != true } }
    private var jobs: [PracticeJob] { model.currentPractice.jobs.filter { $0.topicID == topicID && ["pending", "error"].contains($0.state) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("知识点练习")).font(.headline)
                Spacer()
                Button(L("出一道自测题")) { model.requestPractice(topicID: topicID) }
                    .disabled(!jobs.isEmpty || questions.contains { q in !model.currentPractice.attempts.contains { $0.id == q.id } })
            }
            Text(L("首次作答会保存；答错或看答案后最多追加两道变式。"))
                .font(.caption).foregroundColor(.secondary)
            Toggle(L("自动追加练习与复习讲解"), isOn: Binding(get: { model.autoPracticeEnabled }, set: { model.setAutoPractice($0) }))
                .toggleStyle(.switch)
            ForEach(Array(questions.suffix(3))) { question in questionCard(question) }
            ForEach(jobs) { job in
                HStack {
                    Text(job.state == "error" ? L("生成未完成，作答与笔记已保留。") : L("变式练习已排队，可继续阅读。"))
                        .font(.caption)
                    if job.state == "error" { Button(L("重试生成")) { model.retryPractice(jobID: job.id) } }
                    Button(L("先复习，暂停本轮")) { model.cancelPractice(jobID: job.id) }
                }
            }
            if !model.practiceStatus.isEmpty { Text(model.practiceStatus).font(.caption).foregroundColor(.secondary) }
            if !PracticeEngine.attempts(topicID: topicID, book: model.currentNotebook).isEmpty {
                Divider()
                Text(L("个性化复习笔记")).font(.headline)
                Text(LocalizedStringKey(PracticeEngine.markdown(topicID: topicID, book: model.currentNotebook))).textSelection(.enabled)
                    .font(.body).fixedSize(horizontal: false, vertical: true)
                Text(L("参考讲解由 AI 生成；答案有误时可标记待核对，不计入薄弱点。"))
                    .font(.caption).foregroundColor(.secondary)
            }
        }.padding(14).background(Color.secondary.opacity(0.06)).cornerRadius(10)
    }
    private func questionCard(_ q: PracticeQuestion) -> some View {
        let attempt = model.currentPractice.attempts.first { $0.id == q.id }
        return VStack(alignment: .leading, spacing: 8) {
            if q.depth > 0 { Text(L("同知识点变式 · {0}/2", String(q.depth))).font(.caption).foregroundColor(.secondary) }
            Text(q.prompt).font(.body.weight(.medium))
            ForEach(q.options.indices, id: \.self) { i in
                Button {
                    if let doc = model.selectedID { model.submitPractice(documentID: doc, questionID: q.id, selected: i, revealed: false) }
                } label: {
                    HStack {
                        Text("\(i + 1). \(q.options[i])").multilineTextAlignment(.leading)
                        Spacer()
                        if attempt != nil, i == q.correctIndex { Image(systemName: "checkmark.circle").foregroundColor(.green) }
                        else if let a = attempt, a.selected == i { Image(systemName: "xmark.circle").foregroundColor(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(attempt != nil).buttonStyle(.bordered)
            }
            if let a = attempt {
                Text(a.disputed ? L("参考答案待核对") : a.revealed ? L("已看答案，先复习再练习。") : PracticeEngine.isCorrect(a, question: q) ? L("答对了。") : L("这次答错了，已加入复习笔记。"))
                    .font(.callout.weight(.medium))
                Text(q.explanation).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("回到第 {0} 页", String(q.page))) { model.jumpToStudySource(page: q.page) }
                    if !a.disputed { Button(L("参考答案有误，暂不计入")) { model.disputePractice(questionID: q.id) } }
                }
                if q.depth == 2 && !PracticeEngine.isCorrect(a, question: q) {
                    Text(L("本轮两道变式已结束，先复习再开启新一轮。")).font(.caption).foregroundColor(.secondary)
                }
            } else {
                Button(L("先看答案（不计为答对）")) {
                    if let doc = model.selectedID { model.submitPractice(documentID: doc, questionID: q.id, selected: nil, revealed: true) }
                }
            }
        }.padding(10).background(Color.primary.opacity(0.03)).cornerRadius(8)
    }
}
