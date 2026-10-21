import {languageCode,localizeError} from './language.mjs';
import {studyInstructions,studyPrompt} from './study.mjs';
import {practiceInstructions,practicePrompt} from './practice.mjs';
import {teachingInstructions,buildUserContext,validateChat,runCodex,runClaude} from './tutor.mjs';
import {mkdtemp,rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import os from 'node:os';
let input='';
const controller=new AbortController();for(const s of ['SIGTERM','SIGINT'])process.on(s,()=>controller.abort());
const emit=e=>process.stdout.write(JSON.stringify(e)+'\n');
let cwd,language="zh";
try{
 for await(const chunk of process.stdin){input+=chunk;if(input.length>17000000)throw Error('请求过大');}
 const data=JSON.parse(input);language=languageCode(data?.language);const structured=['study','practice'].includes(data?.mode);if(!structured)validateChat(data);
 const instructions=data.mode==='practice'?practiceInstructions(language):data.mode==='study'?studyInstructions(language):await teachingInstructions(path.dirname(fileURLToPath(import.meta.url)),language);
 cwd=await mkdtemp(path.join(os.tmpdir(),'bandu-teacher-'));
 emit({type:'status',text:data.mode==='practice'?(language==='en'?'Preparing practice and review notes…':'正在生成变式练习与复习讲解…'):language==='en'?(data.mode==='study'?'Organizing study notes…':'Reading your selected material…'):(data.mode==='study'?'正在整理学习笔记…':'老师正在阅读你选中的内容…')});
 await (data.provider==='claude'?runClaude:runCodex)({instructions,prompt:data.mode==='practice'?practicePrompt(data):data.mode==='study'?studyPrompt(data):buildUserContext(data),images:structured?[]:data.images||[],cwd,emit,signal:controller.signal});
 emit({type:'done'});
}catch(e){emit({type:'error',error:localizeError(e.message,language)});process.exitCode=1;}
finally{if(cwd)await rm(cwd,{recursive:true,force:true});}
