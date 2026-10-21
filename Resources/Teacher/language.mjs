// Only trusted, allow-listed UI language codes may affect the instruction layer.
export const languageCode = value => value === 'en' ? 'en' : 'zh';
export function languageInstructions(value, study=false) {
  return languageCode(value)==='en'
    ? '\n# Response language (overrides earlier language defaults)\nUse natural English for '+(study?'every human-readable JSON value, topic title, summary and review question.':'the explanation, quiz, diagram labels and red-pen annotation labels. Respect an explicit language request in the student’s current question.')+' Keep quoted source text, proper names, formulae and machine schema keys intact. Do not switch to Chinese merely because the course material or conversation is Chinese.'
    : '\n# 回答语言（覆盖前文默认语言）\n'+(study?'JSON 中所有面向学生的标题、摘要、要点和复习题使用自然中文。':'讲解、测验、图示标签及红笔批注使用自然中文，关键术语可附英文；学生本轮明确指定其他语言时遵从。')+'引用原文、专有名词、公式和机器字段保留原样，不要因为课件是英文就自动切换语言。';
}
const errors={
 'Claude 登录检查超时，请重试。':'Claude sign-in check timed out. Please retry.',
 '无法检查 Claude 登录。':'Could not check Claude sign-in.',
 'Claude 请求失败':'Claude request failed',
 'Claude 未完成回答，请检查订阅登录或稍后重试。':'Claude did not finish the reply. Check your subscription sign-in or retry later.',

 '当前 Codex 订阅没有可用模型，请检查登录。':'No model is available for this Codex subscription. Check your sign-in.',
 '请先用 Claude 订阅登录 Claude Code，伴读不会使用 API key。':'Sign in to Claude Code with your Claude subscription. deep-teach does not use API keys.',

 '请选择 Codex 或 Claude。':'Choose Codex or Claude.',
 '请输入 1–5000 字的问题。':'Enter a question of 1–5,000 characters.',
 '最多使用选区和整页两张图片。':'Use at most two images: the selection and the full page.',
 '图片格式或大小不支持，请缩小选区。':'Unsupported image format or size. Select a smaller area.',
 '笔记整理请求不完整':'The study-note request is incomplete.',
 '练习请求不完整':'The practice request is incomplete.',
 '请求过大':'The request is too large.',
 '已停止生成。':'Generation stopped.',
 '讲解超时，请缩小选区后重试。':'The explanation timed out. Select a smaller area and retry.',
 'Codex 连接结束。请确认 Codex 已登录，或稍后重试。':'Codex disconnected. Check that you are signed in, or retry later.',
 ' 登录已失效。':' Your sign-in has expired.',
 'Codex 请求失败':'Codex request failed',
 '模型请求失败':'Model request failed',
 '讲解失败':'Explanation failed',
 '伴读只使用已有 ChatGPT 订阅，请先在 Codex 中登录 ChatGPT 账号。':'deep-teach uses your existing ChatGPT subscription. Sign in to ChatGPT in Codex first.',
};
export function localizeError(message,language) {
 const raw=String(message ?? 'Request failed');
 const missing=raw.match(/spawn (codex|claude) ENOENT/i);
 if(missing)return languageCode(language)==='en'?`${missing[1]} CLI was not found. Install it and sign in with your subscription; see the project README.`:`未找到 ${missing[1]} CLI。请先安装并使用订阅登录，步骤见项目 README。`;
 if(languageCode(language)!=='en')return raw;
 let result=raw;for(const [zh,en] of Object.entries(errors))result=result.replaceAll(zh,en);return result;
}
