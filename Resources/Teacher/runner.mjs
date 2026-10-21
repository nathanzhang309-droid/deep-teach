import {studyInstructions,studyPrompt} from './study.mjs';
import {teachingInstructions,buildUserContext,validateChat,runCodex,runClaude} from './tutor.mjs';
import {mkdtemp,rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import os from 'node:os';
let input='';for await(const chunk of process.stdin){input+=chunk;if(input.length>17000000)throw Error('请求过大');}
const controller=new AbortController();for(const s of ['SIGTERM','SIGINT'])process.on(s,()=>controller.abort());
const emit=e=>process.stdout.write(JSON.stringify(e)+'\n');
let cwd;
try{
 const data=JSON.parse(input);if(data.mode!=='study')validateChat(data);
 const instructions=data.mode==='study'?studyInstructions:await teachingInstructions(path.dirname(fileURLToPath(import.meta.url)));
 cwd=await mkdtemp(path.join(os.tmpdir(),'bandu-teacher-'));
 emit({type:'status',text:data.mode==='study'?'正在整理学习笔记…':'老师正在阅读你选中的内容…'});
 await (data.provider==='claude'?runClaude:runCodex)({instructions,prompt:data.mode==='study'?studyPrompt(data):buildUserContext(data),images:data.mode==='study'?[]:data.images||[],cwd,emit,signal:controller.signal});
 emit({type:'done'});
}catch(e){emit({type:'error',error:e.message});process.exitCode=1;}
finally{if(cwd)await rm(cwd,{recursive:true,force:true});}
