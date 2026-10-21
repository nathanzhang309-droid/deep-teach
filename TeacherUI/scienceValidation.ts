import { t } from './i18n';
// Arithmetic and geometry checks for a learning diagram; not a chemical plausibility solver.
export function auditLewis(block:any):string {
  const fail=(message:string):never=>{throw Error(message)};
  const atoms=block.atoms,bonds=block.bonds;
  if(!Array.isArray(atoms)||atoms.length<1||atoms.length>12||!Array.isArray(bonds)||bonds.length>18)fail(t("请把结构拆成较小的图示"));
  const valences:Record<string,number>={H:1,He:2,Li:1,Be:2,B:3,C:4,N:5,O:6,F:7,Ne:8,Na:1,Mg:2,Al:3,Si:4,P:5,S:6,Cl:7,Ar:8,K:1,Ca:2,Br:7,I:7};
  const directions=['top','right','bottom','left'];const map=new Map<string,any>();
  for(const a of atoms){
    if(typeof a.id!=='string'||map.has(a.id)||!Number.isFinite(a.x)||!Number.isFinite(a.y)||a.x<40||a.x>320||a.y<40||a.y>240)fail(t("原子位置或标识不完整"));
    if(valences[a.element]===undefined||a.valence!==valences[a.element])fail(t("该元素的价电子数需要重新核对"));
    if(!Number.isInteger(a.charge)||Math.abs(a.charge)>4)fail(t("形式电荷需要重新核对"));
    for(const list of [a.lonePairs,a.unpaired])if(!Array.isArray(list)||list.length>4||list.some((x:any)=>!directions.includes(x))||new Set(list).size!==list.length)fail(t("孤电子标注需要重新核对"));
    if(a.lonePairs.some((x:string)=>a.unpaired.includes(x)))fail(t("电子标记重叠"));
    map.set(a.id,a);
  }
  const edges=new Set();const orders=new Map<string,number>();
  for(const b of bonds){
    if(!map.has(b.from)||!map.has(b.to)||b.from===b.to||![1,2,3].includes(b.order))fail(t("化学键连接需要重新核对"));
    const key=[b.from,b.to].sort().join('|');if(edges.has(key))fail(t("化学键重复"));edges.add(key);
    const a=map.get(b.from),z=map.get(b.to);if(Math.hypot(z.x-a.x,z.y-a.y)<64)fail(t("原子间距太近，请展开图示"));
    orders.set(b.from,(orders.get(b.from)||0)+b.order);orders.set(b.to,(orders.get(b.to)||0)+b.order);
  }
  if(!Number.isInteger(block.charge)||Math.abs(block.charge)>8)fail(t("总电荷需要重新核对"));
  let nonbond=0,sumCharge=0;
  for(const a of atoms){
    const n=a.lonePairs.length*2+a.unpaired.length,order=orders.get(a.id)||0;
    const formal=a.valence-n-order;
    if(formal!==a.charge)fail(t("{0} 的形式电荷与电子标记不符", a.element));
    const shell=n+2*order;if(a.element==='H'&&shell>2||['B','C','N','O','F'].includes(a.element)&&shell>8)fail(t("{0} 周围电子数超出本图适用范围", a.element));
    nonbond+=n;sumCharge+=a.charge;
  }
  const actual=nonbond+bonds.reduce((n:number,b:any)=>n+b.order*2,0);
  const expected=atoms.reduce((n:number,a:any)=>n+a.valence,0)-block.charge;
  if(sumCharge!==block.charge||actual!==expected)fail(t("电子总数或总电荷不守恒"));
  return t("价电子 {0} 个 · 图中 {1} 个 · 总电荷 {2}{3} · 形式电荷计数一致（不代表已验证分子稳定性）", expected, actual, block.charge>0?'+':'', block.charge);
}
