import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const catalog=JSON.parse(await readFile('Resources/en.json','utf8'));
let count=0;
for(const folder of ['Sources','TeacherUI'])for(const name of await readdir(folder)){
 if(!/\.(swift|tsx|ts)$/.test(name)||/Tests|\.test\./.test(name))continue;
 const text=await readFile(folder+'/'+name,'utf8');
 for(const match of text.matchAll(/\b(?:L|t)\("((?:[^"\\]|\\.)*)"/g)){
  const key=JSON.parse('"'+match[1]+'"');if(!/[\u3400-\u9fff]/.test(key))continue;
  assert.equal(typeof catalog[key],'string',`${name}: missing English: ${key}`);count++;
 }
}
for(const [key,value]of Object.entries(catalog))assert.deepEqual(key.match(/\{\d+\}/g)?.sort()??[],value.match(/\{\d+\}/g)?.sort()??[],`Placeholder mismatch: ${key}`);
console.log(`${count} localized call sites covered; ${Object.keys(catalog).length} English entries checked`);
