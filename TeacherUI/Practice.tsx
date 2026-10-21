import React, {createContext, useContext, useRef} from 'react';
import {t, LanguageContext} from './i18n';
export type PracticeQuestion = {id:string;topicID:string;turnID:string;page:number;prompt:string;options:string[];correctIndex:number;explanation:string;depth:number;origin:string;invalidated?:boolean};
export type PracticeAttempt = {id:string;selected?:number;revealed:boolean;disputed:boolean};
export type PracticeData = {questions:PracticeQuestion[];attempts:PracticeAttempt[];jobs:{id:string;topicID:string;parentID?:string;state:string}[]};
export const PracticeContext=createContext({documentID:'',answerID:'',data:{questions:[],attempts:[],jobs:[]} as PracticeData});
export const practicePost=(type:string,documentID:string,id:string,extra:Record<string,unknown>={})=>window.webkit?.messageHandlers?.teacher?.postMessage({type,documentID,id,...extra} as any);

export function PracticeQuiz({question:q}:{question:PracticeQuestion}) {
 useContext(LanguageContext);
 const context=useContext(PracticeContext);
 const a=context.data.attempts.find(a=>a.id===q.id);
 const sent=useRef(false);
 // Native state is authoritative. Reset the guard on acknowledgements; duplicate native submissions are idempotent.
 const answer=(selected?:number)=>{if(a||sent.current)return;sent.current=true;practicePost('practiceAnswer',context.documentID,q.id,{selected:selected??null,revealed:selected===undefined});queueMicrotask(()=>{sent.current=false;});};
 const correct=!!a&&!a.revealed&&a.selected===q.correctIndex;
 return <div className="quiz" data-practice-id={q.id}>
  {q.depth>0&&<small>{t("同知识点变式 · {0}/2",q.depth)}</small>}
  <strong>{q.prompt}</strong>
  <div>{q.options.map((label,i)=><button key={i} disabled={!!a} className={'quiz-option'+(a&&(i===q.correctIndex||i===a.selected)?(i===q.correctIndex?' correct':' incorrect'):'')} onClick={()=>answer(i)}>{String.fromCharCode(65+i)}. {label}</button>)}</div>
  {!a?<button className="save-button" onClick={()=>answer()}>{t("先看答案（不计为答对）")}</button>:<div className="quiz-feedback" role="status">
   <strong>{a.disputed?t("参考答案待核对"):a.revealed?t("已看答案，先复习再练习。"):correct?t("答对了。"):t("这次答错了，已加入复习笔记。")}</strong>
   <p>{q.explanation}</p>
   {!correct&&q.depth===2&&<p>{t("本轮两道变式已结束，先复习再开启新一轮。")}</p>}
   <button className="save-button" onClick={()=>practicePost('practiceReview',context.documentID,q.topicID)}>{t("查看个性化复习笔记")}</button>
   {!a.disputed&&<button className="save-button" onClick={()=>practicePost('practiceDispute',context.documentID,q.id)}>{t("参考答案有误，暂不计入")}</button>}
  </div>}
 </div>;
}
export function PracticeFollowups() {
 const c=useContext(PracticeContext);
 return <>{c.data.questions.filter(q=>q.turnID===c.answerID&&q.origin==='practice'&&!q.invalidated).map(q=><PracticeQuiz key={q.id} question={q}/>)}
  {c.data.jobs.filter(j=>['pending','error'].includes(j.state)&&c.data.questions.some(q=>q.id===j.parentID&&q.turnID===c.answerID)).map(j=><div className="quiz-feedback" key={j.id} role="status">
   {j.state==='error'?t("生成未完成，作答与笔记已保留。"):t("变式练习已排队，可继续阅读。")}
   {j.state==='error'&&<button className="save-button" onClick={()=>practicePost('practiceRetry',c.documentID,j.id)}>{t("重试生成")}</button>}
   <button className="save-button" onClick={()=>practicePost('practiceCancel',c.documentID,j.id)}>{t("先复习，暂停本轮")}</button>
  </div>)}
 </>;
}
