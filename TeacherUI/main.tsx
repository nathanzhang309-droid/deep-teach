import './compat';
import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Answer } from './Answer';
import './style.css';
const StableAnswer = React.memo(Answer);

type Theme = '纸白' | '暖纸' | '夜读';
type Provider = 'codex' | 'claude';
type Level = '零基础' | '学过但模糊' | '比较熟悉';

type Message = {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  saved: boolean;
  inkCount?: number;
  page: number;
};

type Payload = {
  hasImageSelection: boolean;
  selectionRequest: string;
  theme: Theme;
  title: string;
  selectionLabel: string;
  provider: Provider;
  level: Level;
  busy: boolean;
  status: string;
  messages: Message[];
};

type Outgoing =
  | { type: 'placeVisual'; id: string; newPage: boolean }
  | { type: 'focusSelection'; request: string }
  | { type: 'reselect' | 'clearSelection' }
  | { type: 'ready' }
  | { type: 'send'; question: string }
  | { type: 'stop' }
  | { type: 'save' | 'undoInk'; id: string }
  | { type: 'explain' }
  | { type: 'provider'; value: Provider }
  | { type: 'level'; value: Level }
  | { type: 'notes' };

declare global {
  interface Window {
    teacher: { receive(payload: Payload): void };
    webkit?: { messageHandlers?: { teacher?: { postMessage(message: Outgoing): void } } };
  }
}

const post = (message: Outgoing) => window.webkit?.messageHandlers?.teacher?.postMessage(message);

const initialState: Payload = {
  hasImageSelection: false, selectionRequest: "",
  theme: '纸白',
  title: '',
  selectionLabel: '',
  provider: 'codex',
  level: '学过但模糊',
  busy: false,
  status: '',
  messages: [],
};

const themeClass: Record<Theme, string> = { 纸白: 'theme-paper', 暖纸: 'theme-warm', 夜读: 'theme-night' };
const providers: { value: Provider; label: string }[] = [
  { value: 'codex', label: 'Codex' },
  { value: 'claude', label: 'Claude' },
];
const levels: Level[] = ['零基础', '学过但模糊', '比较熟悉'];

// Native 可能早于 React 挂载就推送状态，先暂存，挂载后再交给组件
let pending: Payload | null = null;
let listener: ((payload: Payload) => void) | null = null;
window.teacher = {
  receive(payload) {
    if (listener) listener(payload);
    else pending = payload;
  },
};

const isErrorStatus = (status: string) => /错误|失败|超时|error|fail/i.test(status);

function EmptyState({ busy, hasDocument }: { busy: boolean; hasDocument: boolean }) {
  return (
    <div className="empty">
      <h2>有不懂的地方，就问老师</h2>
      <ol>
        <li>在正文里<strong>选中文字</strong>，老师会围绕这段讲。</li>
        <li>PDF 可点工具栏「<strong>框图</strong>」，框出公式、图表或扫描段落。</li>
        <li>什么都不选，老师会讲当前页或整篇文章。</li>
      </ol>
      <button className="primary" disabled={busy || !hasDocument} onClick={() => post({ type: 'explain' })}>
        讲讲当前页/文章
      </button>
      {!hasDocument && <p className="hint">先在书房里打开一篇文档。</p>}
    </div>
  );
}

function MessageView({ message, streaming }: { message: Message; streaming: boolean }) {
  const page = message.page > 0 ? <span className="meta">第 {message.page} 页</span> : null;

  if (message.role === 'user') {
    return (
      <div className="message user">
        <div className="bubble">{message.text}</div>
        {page}
      </div>
    );
  }

  return (
    <article className={`message assistant${streaming ? ' streaming' : ''}`}>
      <StableAnswer text={message.text} />
      <div className="message-actions">
        {page}
        {!!message.inkCount && <><span className="meta" style={{color:'#C23B2E'}}>已在课件上标注，可编辑或撤销</span><button className="save-button" onClick={()=>post({type:'undoInk',id:message.id})}>撤销批注</button></>}
        {message.saved ? (
          <span className="saved">已收进笔记</span>
        ) : (
          <button className="save-button" disabled={streaming || !message.text.trim()} onClick={() => post({ type: 'save', id: message.id })}>
            收进笔记
          </button>
        )}
      </div>
    </article>
  );
}

function App() {
  const [state, setState] = useState<Payload>(() => pending ?? initialState);
  const [draft, setDraft] = useState('');
  const [settingsOpen, setSettingsOpen] = useState(false);
  const composing = useRef(false);
  const pinned = useRef(true);
  const scroller = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    listener = setState;
    if (pending) {
      setState(pending);
      pending = null;
    }
    post({ type: 'ready' });
    return () => {
      listener = null;
    };
  }, []);

  useEffect(() => {
    document.documentElement.className = themeClass[state.theme] ?? 'theme-paper';
  }, [state.theme]);

  useEffect(() => {
    if(state.hasImageSelection){input.current?.focus();post({type:'focusSelection',request:state.selectionRequest});}
  },[state.hasImageSelection,state.selectionRequest]);

  // 只有用户停在底部时才跟随新输出，往上翻阅时不打扰
  const onScroll = () => {
    const el = scroller.current;
    if (!el) return;
    pinned.current = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
  };

  useLayoutEffect(() => {
    const el = scroller.current;
    if (el && pinned.current) el.scrollTop = el.scrollHeight;
  }, [state.messages, state.busy]);

  useLayoutEffect(() => {
    const el = input.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }, [draft]);

  const submit = () => {
    const question = draft.trim();
    if (!question || state.busy || composing.current) return;
    post({ type: 'send', question });
    setDraft('');
    pinned.current = true;
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if(event.key==='Escape' && state.hasImageSelection && !draft){event.preventDefault();post({type:'clearSelection'});return;}
    if (event.nativeEvent.isComposing || composing.current || event.keyCode === 229) return;
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      submit();
    }
  };

  const { messages, busy, status } = state;
  const last = messages[messages.length - 1];
  const waiting = busy && (!last || last.role === 'user');
  const error = isErrorStatus(status);

  return (
    <div className="panel">
      <header className="panel-header">
        <button className="back" onClick={() => post({ type: 'notes' })} title="返回批注">
          ‹ 批注
        </button>
        <h1>老师</h1>
        <button
          className={`settings-toggle${settingsOpen ? ' active' : ''}`}
          aria-expanded={settingsOpen}
          onClick={() => setSettingsOpen((open) => !open)}
        >
          设置
        </button>
      </header>

      {settingsOpen && (
        <section className="settings">
          <div className="field">
            <span className="field-label">模型</span>
            <div className="segmented" role="group" aria-label="模型">
              {providers.map((p) => (
                <button
                  key={p.value}
                  className={p.value === state.provider ? 'selected' : ''}
                  aria-pressed={p.value === state.provider}
                  onClick={() => post({ type: 'provider', value: p.value })}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>
          <div className="field">
            <span className="field-label">讲解程度</span>
            <div className="segmented" role="group" aria-label="讲解程度">
              {levels.map((level) => (
                <button
                  key={level}
                  className={level === state.level ? 'selected' : ''}
                  aria-pressed={level === state.level}
                  onClick={() => post({ type: 'level', value: level })}
                >
                  {level}
                </button>
              ))}
            </div>
          </div>
          <p className="hint">通过本机已登录的 Codex / Claude 作答，消耗你现有的订阅额度，不会新增 API 费用。</p>
        </section>
      )}

      <div className="context">
        <span className="context-label">当前上下文</span>
        <span className="context-title" title={state.title}>{state.title || '未打开文档'}</span>
        {state.selectionLabel && (
          <span className="context-selection" title={state.selectionLabel}>{state.selectionLabel}</span>
        )}
      </div>

      <main className="messages" ref={scroller} onScroll={onScroll}>
        {messages.length === 0 && !busy ? (
          <EmptyState busy={busy} hasDocument={Boolean(state.title)} />
        ) : (
          messages.map((m, index) => (
            <MessageView key={m.id} message={m} streaming={busy && m.role === 'assistant' && index === messages.length - 1} />
          ))
        )}
        {waiting && (
          <div className="thinking" aria-live="polite">
            老师正在思考<span className="dots"><i /><i /><i /></span>
          </div>
        )}
      </main>

      {status && (
        <div className={`status${error ? ' error' : ''}`} role={error ? 'alert' : 'status'}>
          {status}
        </div>
      )}

      <footer className="composer" data-selection={state.hasImageSelection || undefined}>
        {state.hasImageSelection && <div className="selection-bar" role="group" aria-label="已框选区域">
          <span className="selection-chip" aria-live="polite">已框选区域</span>
          <button className="selection-explain" disabled={busy} onClick={()=>post({type:'explain'})}>讲解所选区域</button>
          <button className="selection-ghost" onClick={()=>post({type:'reselect'})}>重新框选</button>
          <button className="selection-ghost" onClick={()=>post({type:'clearSelection'})}>取消选区</button>
        </div>}
        <textarea
          ref={input}
          rows={2}
          value={draft}
          aria-label={state.hasImageSelection ? "针对所选区域提问" : "输入问题"}
          placeholder={state.hasImageSelection ? "想问这部分什么？" : state.selectionLabel ? `就「${state.selectionLabel}」提问…` : '问老师任何问题…'}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={onKeyDown}
          onCompositionStart={() => (composing.current = true)}
          onCompositionEnd={() => (composing.current = false)}
        />
        <div className="composer-bar">
          <span className="shortcut">⌘↩ 发送</span>
          {busy ? (
            <button className="stop" onClick={() => post({ type: 'stop' })}>停止</button>
          ) : (
            <button className="send" disabled={!draft.trim()} onClick={submit}>发送</button>
          )}
        </div>
      </footer>
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
