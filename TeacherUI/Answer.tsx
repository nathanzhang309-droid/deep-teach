import {safePlotExpression,parseVisual} from './visualValidation';
import { t,LanguageContext } from './i18n';
import React, { useEffect, useRef, useState, useId } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import 'katex/dist/katex.min.css';
import {DerivationCard,LewisCard,ConceptMapCard} from './ScienceCards';
import {auditLewis} from './scienceValidation';
import './science.css';
import {PracticeContext, PracticeQuiz} from './Practice';

function VisualClip({children}:{children:React.ReactNode}) {
  React.useContext(LanguageContext);
  const id='clip-'+useId().replace(/[^a-zA-Z0-9-]/g,'');
  return <span className="visual-clip"><span id={id} className="visual-clip-content">{children}</span><span className="visual-clip-actions">
    <button className="save-button" onClick={()=>window.webkit?.messageHandlers?.teacher?.postMessage({type:'placeVisual',id,newPage:false})}>{t("贴到当前页")}</button>
    <button className="save-button" onClick={()=>window.webkit?.messageHandlers?.teacher?.postMessage({type:'placeVisual',id,newPage:true})}>{t("另加讲解页")}</button>
  </span></span>;
}
// Capture a temporary local DOM copy, including canvas pixels; never send it to a service.
(window as any).prepareVisualClip=(id:string)=>{
  document.getElementById('bandu-visual-capture')?.remove();
  const source=document.getElementById(id);if(!source)throw Error(t("图示已更新，请重试"));
  const clone=source.cloneNode(true) as HTMLElement;
  source.querySelectorAll('canvas').forEach((canvas,i)=>{const target=clone.querySelectorAll('canvas')[i];target.width=canvas.width;target.height=canvas.height;target.getContext('2d')?.drawImage(canvas,0,0);});
  const host=document.createElement('div');host.id='bandu-visual-capture';host.className='message assistant';
  Object.assign(host.style,{position:'fixed',left:'0',top:'0',margin:'0',padding:'12px',zIndex:'2147483647',background:'#ffffff',borderRadius:'0',border:'0',boxShadow:'none',color:'#2b2b28',boxSizing:'border-box',width:Math.max(200,source.getBoundingClientRect().width+24)+'px'});
  clone.querySelectorAll('.bd-tabs').forEach(el=>el.remove());
  clone.removeAttribute('id');clone.style.color='#2b2b28';host.appendChild(clone);document.body.appendChild(host);
  const box=host.getBoundingClientRect();const scale=Math.min(1,(innerWidth-2)/box.width,(innerHeight-2)/box.height);
  host.style.transformOrigin='top left';host.style.transform='scale('+scale+')';
  return {x:0,y:0,width:box.width*scale,height:box.height*scale};
};
(window as any).finishVisualClip=()=>document.getElementById('bandu-visual-capture')?.remove();

type Block = Record<string, any>;
class VisualBoundary extends React.Component<{children:React.ReactNode},{error:boolean}>{
  static contextType=LanguageContext;
  state={error:false};
  static getDerivedStateFromError(){return {error:true};}
  render(){return this.state.error?<p>{t("这张图暂时无法显示，可以请老师换一种方式解释。")}</p>:this.props.children;}
}
function Quiz({block}:{block:Block}){
  React.useContext(LanguageContext);
  const context=React.useContext(PracticeContext);
  const options=Array.isArray(block.options)?block.options.slice(0,8):[];
  const question=context.data.questions.find(q=>q.origin==='teacher'&&q.turnID===context.answerID&&q.prompt===block.question&&JSON.stringify(q.options)===JSON.stringify(options.map(o=>o.label)));
  return question?<PracticeQuiz question={question}/>:<div className="quiz"><strong>{block.question}</strong><p>{t("题目尚未就绪；请等待讲解结束，或让老师重新出题。")}</p></div>;
}
function MermaidView({code}:{code:string}){
  React.useContext(LanguageContext);
  const ref=useRef<HTMLDivElement>(null);
  useEffect(()=>{let cancelled=false;
    import('mermaid').then(async({default:m})=>{
      m.initialize({startOnLoad:false,securityLevel:'strict',theme:'neutral',fontFamily:'system-ui'});
      try {const {svg}=await m.render('diagram-'+crypto.randomUUID().replaceAll('-',''),code);if(!cancelled&&ref.current)ref.current.innerHTML=svg;}
      catch{if(!cancelled&&ref.current)ref.current.textContent=t("图示未能生成，请让老师换一种方式讲。");}
    });return()=>{cancelled=true;};
  },[code]);return <div className="visual-card mermaid-visual" ref={ref}/>;
}
function Chart({block}:{block:Block}){
  React.useContext(LanguageContext);
  const ref=useRef<HTMLDivElement>(null);
  const [error,setError]=useState(false);
  useEffect(()=>{let chart:any,cancelled=false;
    setError(false);
    import('echarts').then(e=>{
      if(cancelled||!ref.current)return;chart=e.init(ref.current);
      const data=Array.isArray(block.data)?block.data:[];
      const preset=block.preset||'bar';
      let option=block.option;
      if(!option)option=preset==='pie'?{series:[{type:'pie',radius:'65%',data:data.map((d:Block)=>({name:d.label,value:d.value}))}]}:
        {grid:{left:40,right:16,top:24,bottom:40},xAxis:{type:'category',data:data.map((d:Block)=>d.label)},yAxis:{type:'value'},series:[{type:preset==='area'?'line':preset,data:data.map((d:Block)=>d.value),areaStyle:preset==='area'?{}:undefined}]};
      chart.setOption(option);
    }).catch(()=>{if(!cancelled)setError(true);});const observer=new ResizeObserver(()=>chart?.resize());if(ref.current)observer.observe(ref.current);
    return()=>{cancelled=true;observer.disconnect();chart?.dispose();};
  },[block]);return <div className="visual-card"><strong>{block.title}</strong>{error&&<p>{t("这张图暂时无法显示，请让老师换一种方式解释。")}</p>}<div ref={ref} style={{height:260,width:'100%'}}/></div>;
}
function Plot({block}:{block:Block}){
  React.useContext(LanguageContext);
  const series=Array.isArray(block.series)?block.series.slice(0,4):[];
  const params=series.flatMap((s:Block)=>s.params||[]);
  const [values,setValues]=useState<Record<string,number>>(()=>Object.fromEntries(params.map((p:Block)=>[p.name,p.value])));
  const [paths,setPaths]=useState<{d:string;color:string}[]>([]);
  const [range,setRange]=useState([-1,1]);
  const [plotError,setPlotError]=useState(false);
  const xmin=Number(block.xMin??-5),xmax=Number(block.xMax??5);
  useEffect(()=>{let cancelled=false;setPlotError(false);
    import('mathjs').then(({compile})=>{
      try{
        if(!Number.isFinite(xmin)||!Number.isFinite(xmax)||xmax<=xmin)throw Error();
        const samples=series.map((s:Block)=>{
          if(!safePlotExpression(s.expr,params.map((p:Block)=>p.name)))throw Error();
          const fn=compile(s.expr.replace(/\bln\(/g,'log('));const out=[];
          for(let i=0;i<=180;i++){const x=xmin+(xmax-xmin)*i/180;const y=Number(fn.evaluate({x,...values}));out.push([x,Number.isFinite(y)&&Math.abs(y)<1e6?y:NaN]);}return out;});
        const ys=samples.flat().map(v=>v[1]!).filter(Number.isFinite);if(!ys.length)throw Error();let lo=Math.min(...ys),hi=Math.max(...ys);if(lo===hi){lo--;hi++;}const pad=(hi-lo)*.12;lo-=pad;hi+=pad;
        const colors=['#5064c9','#24826a','#c27838','#a25a88'];
        const result=samples.map((points,i)=>({color:series[i].color||colors[i],d:points.map(([x,y],j)=>Number.isFinite(y)?`${j&&Number.isFinite(points[j-1]?.[1])?'L':'M'}${36+(x!-xmin)/(xmax-xmin)*300},${200-(y!-lo)/(hi-lo)*172}`:'').join(' ')}));
        if(!cancelled){setPaths(result);setRange([lo,hi]);}
      }catch{if(!cancelled){setPaths([]);setPlotError(true);}}
    });return()=>{cancelled=true;};
  },[JSON.stringify(block),JSON.stringify(values)]);
  return <div className="visual-card"><strong>{block.title}</strong>{plotError&&<p role="alert">{t("函数图无法显示，请让老师简化表达式。")}</p>}<svg viewBox="0 0 360 230" role="img" aria-label={block.title||t("函数图")}>
    <path d="M36 20V200H340" fill="none" stroke="#b7bdc9"/><text x="36" y="219" fontSize="11">{xmin}</text><text x="318" y="219" fontSize="11">{xmax}</text>
    <text x="2" y="28" fontSize="10">{range[1]?.toPrecision(2)}</text><text x="2" y="196" fontSize="10">{range[0]?.toPrecision(2)}</text>
    {paths.map((p,i)=><path key={i} d={p.d} fill="none" stroke={p.color} strokeWidth="2"/>)}</svg>
    {series.map((s:Block,i:number)=><small key={i} style={{display:'block'}}>{s.label||s.expr}</small>)}
    {params.map((p:Block,i:number)=><label key={i} style={{display:'flex',gap:8,alignItems:'center'}}>{p.name} = {(values[p.name]??p.value).toFixed(2)}<input aria-label={p.name} type="range" min={p.min} max={p.max} step={(p.max-p.min)/100||.01} value={values[p.name]??p.value} onChange={e=>setValues({...values,[p.name]:Number(e.target.value)})}/></label>)}</div>;
}
function BlockView({block}:{block:Block}){
  React.useContext(LanguageContext);
  if(!block||typeof block!=='object')return null;
  if(block.items&&!block.type)return <>{block.items.slice(0,8).map((b:Block,i:number)=><BlockView key={i} block={b}/>)}</>;
  switch(block.type){
    case 'derivation':return <DerivationCard block={block}/>;
    case 'conceptmap':return <ConceptMapCard block={block}/>;
    case 'lewis':try{return <LewisCard block={{...block,audit:auditLewis(block)}}/>;}catch(e){return <p role="alert">{t("这张 Lewis 结构需要老师重新核对：")}{String((e as Error).message)}{t("。请让老师修正图示。")}</p>;}

    case 'quiz':return <Quiz block={block}/>;
    case 'mermaid':return <MermaidView code={String(block.code||'')}/>;
    case 'plot':return <Plot block={block}/>;
    case 'echart':return <Chart block={block}/>;
    case 'table':return <table><thead><tr>{(block.columns||[]).map((v:string,i:number)=><th key={i}>{v}</th>)}</tr></thead><tbody>{(block.rows||[]).map((row:any[],i:number)=><tr key={i}>{row.map((v,j)=><td key={j}>{String(v)}</td>)}</tr>)}</tbody></table>;
    case 'steps':return <ol>{(block.steps||[]).map((s:Block,i:number)=><li key={i}><strong>{s.title}</strong><p>{s.desc}</p></li>)}</ol>;
    case 'callout':return <blockquote><strong>{block.title}</strong><p>{block.content}</p></blockquote>;
    case 'list':return <ul>{(block.items||[]).map((s:any,i:number)=><li key={i}>{typeof s==='string'?s:s.title||s.label||s.content}</li>)}</ul>;
    default:return <p>{block.title||t("图示")}{t("：可以请老师用流程图或表格重新说明。")}</p>;
  }
}
export function Answer({text}:{text:string}){
  return <ReactMarkdown remarkPlugins={[remarkGfm,remarkMath]} rehypePlugins={[[rehypeKatex,{strict:false,throwOnError:false}]]} components={{
    span:({node,...props})=>props.className?.includes('katex-display')?<VisualClip><span {...props}/></VisualClip>:<span {...props}/>,
    a:({children,href})=><a href={href} target="_blank" rel="noopener noreferrer">{children}</a>,
    pre:({children})=><div className="code-block">{children}</div>,
    code:({className,children})=>{
      const value=String(children).trim();
      if(className==='language-dsh-ui'){
        try{return <VisualBoundary><VisualClip><BlockView block={parseVisual(value) as Block}/></VisualClip></VisualBoundary>;}catch{return <small className="status-text">{t("图示尚未就绪；若讲解已结束，请让老师缩小或修正图示。")}</small>;}
      }
      if(className==='language-mermaid')return <VisualClip><MermaidView code={value}/></VisualClip>;
      return <code className={className}>{children}</code>;
    }
  }}>{text}</ReactMarkdown>;
}
