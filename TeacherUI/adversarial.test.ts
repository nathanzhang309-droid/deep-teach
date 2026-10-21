import {t,setLanguage,canSubmit,questionLength} from './i18n';
import {safePlotExpression,parseVisual} from './visualValidation';
let count=0;function check(name:string,ok:boolean){if(!ok)throw Error(name);count++;console.log('PASS',name);}
for(const language of ['zh','en']){
 setLanguage(language);
 check(language+' interface text',t('设置')===(language==='en'?'Settings':'设置'));
 check(language+' input limit',canSubmit('🧪'.repeat(5000),false,false)&&!canSubmit('🧪'.repeat(5001),false,false));
 check(language+' IME never submits',!canSubmit('拼音输入法',false,true));
 check(language+' busy/empty never submits',!canSubmit('hello',true,false)&&!canSubmit(' \n ',false,false));
 check(language+' placeholder payload is not reinterpreted',t('第 {0} 页','{1}')=== (language==='en'?'Page {1}':'第 {1} 页'));
}
check('emoji length matches native scalar count',questionLength('🧪汉字')===3);
check('valid science formulae',safePlotExpression('sin(x)+exp(-x^2)')&&safePlotExpression('1e-3*x + a',['a']));
for(const expr of ['zeros(1000000000)','range(1,1000000000)','factorial(999999999)','evaluate(x)','import(x)','x.constructor','x=3','[1,2]'])check('reject '+expr,!safePlotExpression(expr));
for(const source of ['null','{"type":"callout","content":"中文 English 🧪"}'])check('safe JSON parses',parseVisual(source)!==undefined);
for(const source of ['[',JSON.stringify(Array(101).fill(1)),'['.repeat(14)+'0'+']'.repeat(14),'a'.repeat(50001)]){let rejected=false;try{parseVisual(source)}catch{rejected=true}check('malformed/oversized visual rejected',rejected);}
console.log(count+' frontend adversarial checks passed');
