import {createContext} from 'react';
export const LanguageContext=createContext('zh');
import translations from '../Resources/en.json';
const english: Record<string,string> = translations;
let language: 'zh' | 'en' = 'zh';
export function setLanguage(value:unknown) { language=value==='en'?'en':'zh'; }
export function t(key:string,...values:unknown[]):string {
  const template=language==='en'?(english[key]??key):key;
  return template.replace(/\{(\d+)\}/g,(match,index)=>Number(index)<values.length?String(values[Number(index)]):match);
}
export const questionLength = (value:string) => Array.from(value.trim()).length;
export const canSubmit = (value:string,busy:boolean,composing:boolean) => !busy && !composing && questionLength(value)>0 && questionLength(value)<=5000;
