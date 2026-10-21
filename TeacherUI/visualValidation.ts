const functions=new Set(['sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','sqrt','abs','exp','log','ln','pow','min','max','floor','ceil','round']);
export function safePlotExpression(value:unknown,parameters:string[]=[]):value is string {
  if(typeof value!=='string'||value.length>200||!/^[\w\s.+\-*/^(),]+$/.test(value))return false;
  if(parameters.length>8 || parameters.some(p=>!/^[a-zA-Z][a-zA-Z0-9_]{0,20}$/.test(p)||['constructor','prototype','__proto__'].includes(p)))return false;
  const allowed=new Set(['x','pi','e',...parameters]);
  const tokens=value.replace(/\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/gi,'0').match(/[a-zA-Z_]\w*/g)||[];
  // No allocation, imports, arbitrary evaluation, assignments, accessors, or factorials.
  return tokens.every(token=>allowed.has(token)||functions.has(token));
}
export function parseVisual(source:string):unknown {
  if(source.length>50_000)throw Error('Visual too large');
  const block=JSON.parse(source);let count=0;
  function visit(value:any,depth:number){
    if(++count>2500||depth>12)throw Error('Visual too complex');
    if(Array.isArray(value)&&value.length>100)throw Error('Too many items');
    if(value && typeof value==='object')for(const child of Object.values(value))visit(child,depth+1);
  }
  visit(block,0);return block;
}
