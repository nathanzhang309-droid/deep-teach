import React from 'react';
import katex from 'katex';

/* ───────── 通用工具 ───────── */

type Dir = 'top' | 'right' | 'bottom' | 'left';
const DIRS: Dir[] = ['top', 'right', 'bottom', 'left'];
const VEC: Record<Dir, [number, number]> = { top: [0, -1], right: [1, 0], bottom: [0, 1], left: [-1, 0] };
const BOND_NAME: Record<1 | 2 | 3, string> = { 1: '单键', 2: '双键', 3: '三键' };

const str = (v: unknown): string => (typeof v === 'string' ? v : typeof v === 'number' && Number.isFinite(v) ? String(v) : '');
const arr = (v: unknown): any[] => (Array.isArray(v) ? v : []);
const num = (v: unknown, d: number): number => {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
  return Number.isFinite(n) ? n : d;
};
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));
const r2 = (n: number) => Math.round(n * 100) / 100;
const uniqDirs = (v: unknown): Dir[] => {
  const set = new Set(arr(v).map((d) => String(d)));
  return DIRS.filter((d) => set.has(d));
};
const fmtCharge = (n: number): string => {
  if (!n) return '';
  const m = Math.abs(n);
  return `${m === 1 ? '' : m}${n > 0 ? '+' : '−'}`;
};

function renderTex(expr: string, displayMode: boolean): string {
  try {
    return katex.renderToString(expr, {
      displayMode,
      throwOnError: false,
      trust: false,
      strict: 'ignore',
      maxSize: 30,
      maxExpand: 500,
    });
  } catch {
    return '';
  }
}

function Tex({ expr, display = false }: { expr: string; display?: boolean }) {
  const html = React.useMemo(() => renderTex(expr, display), [expr, display]);
  if (!html) return <span className="bd-tex-fallback">{expr}</span>;
  return <span className={display ? 'bd-tex bd-tex-block' : 'bd-tex'} dangerouslySetInnerHTML={{ __html: html }} />;
}

/** 普通文字中允许 $…$ 行内公式 */
function RichText({ text }: { text: string }) {
  const parts = React.useMemo(() => text.split(/(\$[^$\n]+\$)/g).filter(Boolean), [text]);
  return (
    <>
      {parts.map((p, i) =>
        p.length > 2 && p.startsWith('$') && p.endsWith('$') ? (
          <Tex key={i} expr={p.slice(1, -1)} />
        ) : (
          <React.Fragment key={i}>{p}</React.Fragment>
        ),
      )}
    </>
  );
}

/** 结论可能是纯文字、带 $ 的文字，或整段 LaTeX */
function SmartText({ text }: { text: string }) {
  if (text.includes('$')) return <RichText text={text} />;
  if (/\\[a-zA-Z]+|[\^_{}]/.test(text)) return <Tex expr={text} display />;
  return <>{text}</>;
}

function CardHead({ kicker, title, id }: { kicker: string; title: string; id: string }) {
  return (
    <header className="bd-head">
      <span className="bd-kicker">{kicker}</span>
      <h3 id={id} className="bd-title">
        {title}
      </h3>
    </header>
  );
}

/* ───────── 1. 推导卡片 ───────── */

export function DerivationCard({ block }: { block: any }) {
  const titleId = React.useId();
  const title = str(block?.title).trim() || '推导过程';
  const steps = arr(block?.steps)
    .map((s) => ({ expression: str(s?.expression).trim(), reason: str(s?.reason).trim() }))
    .filter((s) => s.expression || s.reason);
  const conclusion = str(block?.conclusion).trim();

  return (
    <section className="bd-card bd-dv" aria-labelledby={titleId}>
      <CardHead kicker="推导" title={title} id={titleId} />

      {steps.length > 0 && (
        <ol className="bd-dv-steps">
          {steps.map((s, i) => (
            <li className="bd-dv-step" key={i}>
              <span className="bd-dv-no" aria-hidden="true">
                {i + 1}
              </span>
              <div className="bd-dv-body">
                <span className="bd-sr">第 {i + 1} 步</span>
                {s.expression && (
                  <div className="bd-dv-math" tabIndex={0} role="group" aria-label={`第 ${i + 1} 步算式`}>
                    <Tex expr={s.expression} display />
                  </div>
                )}
                {s.reason && (
                  <p className="bd-dv-reason">
                    <span className="bd-dv-because">依据</span>
                    <span className="bd-dv-reason-text">
                      <RichText text={s.reason} />
                    </span>
                  </p>
                )}
              </div>
            </li>
          ))}
        </ol>
      )}

      {conclusion && (
        <div className="bd-dv-conc">
          <span className="bd-dv-conc-label">结论</span>
          <div className="bd-dv-conc-body">
            <SmartText text={conclusion} />
          </div>
        </div>
      )}
    </section>
  );
}

/* ───────── 2. 路易斯结构卡片 ───────── */

interface LAtom {
  key: string;
  el: string;
  x: number;
  y: number;
  pairs: Dir[];
  singles: Dir[];
  charge: number;
  hw: number; // 标签半宽，用于左右电子点避让
}
interface LBond {
  a: LAtom;
  b: LAtom;
  order: 1 | 2 | 3;
}

const SVG_FONT = '"Helvetica Neue", "PingFang SC", Arial, sans-serif';
const C_INK = 'var(--bd-ink, #2c332e)';
const C_PAPER = 'var(--bd-well, #f6f2e9)';
const C_ACCENT = 'var(--bd-accent, #56705f)';
const C_BOND = 'var(--bd-bond, #4a554d)';

function normLewis(block: any) {
  const atoms: LAtom[] = [];
  const byId = new Map<string, LAtom>();
  arr(block?.atoms).forEach((a, i) => {
    const raw = str(a?.element).replace(/[^A-Za-z]/g, '').slice(0, 3);
    const el = raw ? raw[0].toUpperCase() + raw.slice(1).toLowerCase() : '?';
    const atom: LAtom = {
      key: String(i),
      el,
      x: clamp(num(a?.x, 180), 24, 336),
      y: clamp(num(a?.y, 140), 24, 256),
      pairs: uniqDirs(a?.lonePairs),
      singles: uniqDirs(a?.unpaired),
      charge: Math.round(num(a?.charge, 0)),
      hw: el.length === 1 ? 8 : el.length === 2 ? 13 : 18,
    };
    atoms.push(atom);
    const id = a?.id;
    if (id !== undefined && id !== null && !byId.has(String(id))) byId.set(String(id), atom);
  });

  const seen = new Set<string>();
  const bonds: LBond[] = [];
  arr(block?.bonds).forEach((b) => {
    const a = byId.get(String(b?.from));
    const c = byId.get(String(b?.to));
    if (!a || !c || a === c) return;
    const k = [a.key, c.key].sort().join('-');
    if (seen.has(k)) return;
    seen.add(k);
    const o = Math.round(num(b?.order, 1));
    bonds.push({ a, b: c, order: o >= 3 ? 3 : o === 2 ? 2 : 1 });
  });

  let minD = Infinity;
  for (let i = 0; i < atoms.length; i++)
    for (let j = i + 1; j < atoms.length; j++)
      minD = Math.min(minD, Math.hypot(atoms[i].x - atoms[j].x, atoms[i].y - atoms[j].y));
  const dense = atoms.length > 12 || minD < 46;

  return { atoms, bonds, dense, total: Math.round(num(block?.charge, 0)) };
}

function bondLines(bd: LBond) {
  const dx = bd.b.x - bd.a.x;
  const dy = bd.b.y - bd.a.y;
  const len = Math.hypot(dx, dy);
  if (len <= 41) return [];
  const ux = dx / len;
  const uy = dy / len;
  const px = -uy;
  const py = ux;
  const offs = bd.order === 3 ? [-5.5, 0, 5.5] : bd.order === 2 ? [-3.5, 3.5] : [0];
  const x1 = bd.a.x + ux * 20;
  const y1 = bd.a.y + uy * 20;
  const x2 = bd.b.x - ux * 20;
  const y2 = bd.b.y - uy * 20;
  return offs.map((o) => ({
    x1: r2(x1 + px * o),
    y1: r2(y1 + py * o),
    x2: r2(x2 + px * o),
    y2: r2(y2 + py * o),
  }));
}

function Electrons({ a }: { a: LAtom }) {
  const dot = { fill: C_INK };
  const dist = (d: Dir) => (d === 'left' || d === 'right' ? a.hw + 7 : 17);
  const out: React.ReactNode[] = [];
  a.pairs.forEach((d) => {
    const [vx, vy] = VEC[d];
    const r = dist(d);
    const cx = a.x + vx * r;
    const cy = a.y + vy * r;
    const px = -vy * 3.6;
    const py = vx * 3.6;
    out.push(
      <circle key={`p-${d}-1`} cx={r2(cx + px)} cy={r2(cy + py)} r={2.2} style={dot} />,
      <circle key={`p-${d}-2`} cx={r2(cx - px)} cy={r2(cy - py)} r={2.2} style={dot} />,
    );
  });
  a.singles.forEach((d) => {
    const [vx, vy] = VEC[d];
    const r = dist(d) + (a.pairs.includes(d) ? 7 : 0);
    out.push(<circle key={`u-${d}`} cx={r2(a.x + vx * r)} cy={r2(a.y + vy * r)} r={2.2} style={{ fill: C_ACCENT }} />);
  });
  return <>{out}</>;
}

function LewisSvg({ atoms, bonds, total, label }: { atoms: LAtom[]; bonds: LBond[]; total: number; label: string }) {
  let bracket: React.ReactNode = null;
  if (total !== 0 && atoms.length > 0) {
    const minX = clamp(Math.min(...atoms.map((a) => a.x)) - 32, 6, 330);
    const maxX = clamp(Math.max(...atoms.map((a) => a.x)) + 32, 30, 336);
    const minY = clamp(Math.min(...atoms.map((a) => a.y)) - 32, 8, 250);
    const maxY = clamp(Math.max(...atoms.map((a) => a.y)) + 32, 30, 272);
    const bs = { fill: 'none', stroke: C_BOND, strokeWidth: 1.6, strokeLinejoin: 'round' as const };
    bracket = (
      <g>
        <path d={`M${minX + 7},${minY} H${minX} V${maxY} H${minX + 7}`} style={bs} />
        <path d={`M${maxX - 7},${minY} H${maxX} V${maxY} H${maxX - 7}`} style={bs} />
        <text x={maxX + 3} y={minY + 8} style={{ fill: C_ACCENT, fontSize: 15, fontWeight: 600, fontFamily: SVG_FONT }}>
          {fmtCharge(total)}
        </text>
      </g>
    );
  }

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 360 280"
      className="bd-lw-svg"
      role="img"
      aria-label={label}
      style={{ fontFamily: SVG_FONT }}
    >
      <title>{label}</title>
      <g>
        {bonds.map((bd, i) =>
          bondLines(bd).map((l, j) => (
            <line
              key={`${i}-${j}`}
              {...l}
              style={{ stroke: C_BOND, strokeWidth: 2, strokeLinecap: 'round' }}
            />
          )),
        )}
      </g>
      {bracket}
      {atoms.map((a) => (
        <g key={a.key}>
          <text
            x={a.x}
            y={a.y}
            dy="0.35em"
            textAnchor="middle"
            style={{
              fill: C_INK,
              fontSize: 22,
              fontWeight: 500,
              stroke: C_PAPER,
              strokeWidth: 5,
              strokeLinejoin: 'round',
              paintOrder: 'stroke',
            }}
          >
            {a.el}
          </text>
          <Electrons a={a} />
          {a.charge !== 0 && (
            <text
              x={r2(a.x + a.hw + 3)}
              y={r2(a.y - 11)}
              style={{
                fill: C_ACCENT,
                fontSize: 13,
                fontWeight: 600,
                stroke: C_PAPER,
                strokeWidth: 3,
                paintOrder: 'stroke',
              }}
            >
              {fmtCharge(a.charge)}
            </text>
          )}
        </g>
      ))}
    </svg>
  );
}

export function LewisCard({ block }: { block: any }) {
  const titleId = React.useId();
  const title = str(block?.title).trim() || '路易斯结构';
  const caption = str(block?.caption).trim();
  const audit = str(block?.audit).trim();
  const { atoms, bonds, dense, total } = React.useMemo(() => normLewis(block), [block]);
  const [page, setPage] = React.useState<'diagram' | 'detail'>(dense ? 'detail' : 'diagram');

  const names = React.useMemo(() => {
    const count: Record<string, number> = {};
    atoms.forEach((a) => (count[a.el] = (count[a.el] || 0) + 1));
    const seen: Record<string, number> = {};
    const m = new Map<LAtom, string>();
    atoms.forEach((a) => {
      seen[a.el] = (seen[a.el] || 0) + 1;
      m.set(a, count[a.el] > 1 ? `${a.el}（${seen[a.el]}）` : a.el);
    });
    return m;
  }, [atoms]);

  const details = atoms.map((a) => {
    const links = bonds
      .filter((b) => b.a === a || b.b === a)
      .map((b) => `与 ${names.get(b.a === a ? b.b : b.a)} 形成${BOND_NAME[b.order]}`);
    const facts: string[] = [];
    if (links.length) facts.push(links.join('，'));
    facts.push(a.pairs.length ? `${a.pairs.length} 对孤电子对` : '无孤电子对');
    if (a.singles.length) facts.push(`${a.singles.length} 个未成对电子`);
    if (a.charge) facts.push(`形式电荷 ${a.charge > 0 ? '+' : '−'}${Math.abs(a.charge)}`);
    return { a, name: names.get(a) || a.el, text: facts.join('；') + '。' };
  });

  const svgLabel = `${title}的路易斯结构图`;
  const hasAtoms = atoms.length > 0;

  return (
    <section className="bd-card bd-lw" aria-labelledby={titleId}>
      <CardHead kicker="结构" title={title} id={titleId} />

      {hasAtoms && (
        <div className="bd-tabs" role="tablist" aria-label="查看方式">
          <button
            type="button"
            role="tab"
            aria-selected={page === 'diagram'}
            className={page === 'diagram' ? 'is-on' : ''}
            onClick={() => setPage('diagram')}
          >
            结构图
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={page === 'detail'}
            className={page === 'detail' ? 'is-on' : ''}
            onClick={() => setPage('detail')}
          >
            逐个原子看
          </button>
        </div>
      )}

      {hasAtoms && (
        <div className="bd-lw-panel" role="tabpanel" hidden={page !== 'diagram'}>
          {dense && <p className="bd-hint">这张结构比较密，可以左右滑动查看，或切到「逐个原子看」。</p>}
          <figure className="bd-lw-figure">
            <div className={dense ? 'bd-lw-stage is-dense' : 'bd-lw-stage'} tabIndex={dense ? 0 : undefined}>
              <LewisSvg atoms={atoms} bonds={bonds} total={total} label={svgLabel} />
            </div>
            {caption && <figcaption className="bd-lw-caption">{caption}</figcaption>}
          </figure>
          <p className="bd-lw-legend" aria-hidden="true">
            <span className="bd-lw-key bd-lw-key-pair" />
            孤电子对
            <span className="bd-lw-key bd-lw-key-single" />
            未成对电子
          </p>
        </div>
      )}

      {hasAtoms && (
        <div className="bd-lw-panel" role="tabpanel" hidden={page !== 'detail'}>
          <ul className="bd-lw-list">
            {details.map((d) => (
              <li key={d.a.key}>
                <span className="bd-lw-el">
                  {d.a.el}
                  {d.a.charge !== 0 && <sup>{fmtCharge(d.a.charge)}</sup>}
                </span>
                <span className="bd-lw-desc">
                  {d.name !== d.a.el && <strong>{d.name}：</strong>}
                  {d.text}
                </span>
              </li>
            ))}
          </ul>
          {total !== 0 && (
            <p className="bd-lw-total">
              整体带电荷 <strong>{fmtCharge(total)}</strong>
            </p>
          )}
          {caption && <p className="bd-lw-caption">{caption}</p>}
        </div>
      )}

      {!hasAtoms && caption && <p className="bd-lw-caption">{caption}</p>}

      {audit && (
        <p className="bd-foot">
          {!/^电子/.test(audit) && <span className="bd-foot-label">电子计数</span>}
          {audit}
        </p>
      )}
    </section>
  );
}

/* ───────── 3. 概念图卡片 ───────── */

export function ConceptMapCard({ block }: { block: any }) {
  const titleId = React.useId();
  const title = str(block?.title).trim() || '概念图';
  const center = str(block?.center).trim() || title;
  const branches = arr(block?.branches)
    .map((b) => ({
      label: str(b?.label).trim(),
      relation: str(b?.relation).trim(),
      items: arr(b?.items)
        .map((s) => str(s).trim())
        .filter(Boolean),
    }))
    .filter((b) => b.label || b.items.length);

  return (
    <section className="bd-card bd-cm" aria-labelledby={titleId}>
      <CardHead kicker="概念" title={title} id={titleId} />

      <div className="bd-cm-center">
        <span className="bd-cm-center-tag">核心</span>
        <strong className="bd-cm-center-text">
          <RichText text={center} />
        </strong>
      </div>

      {branches.length > 0 && (
        <>
          <span className="bd-cm-trunk" aria-hidden="true" />
          <ul className="bd-cm-grid">
            {branches.map((b, i) => (
              <li className="bd-cm-branch" key={i}>
                <div className="bd-cm-link" aria-hidden="true">
                  <span className="bd-cm-stem" />
                  {b.relation && <span className="bd-cm-rel">{b.relation}</span>}
                  <span className="bd-cm-arrow" />
                </div>
                <article className="bd-cm-node">
                  {b.relation && (
                    <span className="bd-sr">
                      {center} {b.relation} {b.label}
                    </span>
                  )}
                  {b.label && (
                    <h4 className="bd-cm-label">
                      <RichText text={b.label} />
                    </h4>
                  )}
                  {b.items.length > 0 && (
                    <ul className="bd-cm-items">
                      {b.items.map((it, j) => (
                        <li key={j}>
                          <RichText text={it} />
                        </li>
                      ))}
                    </ul>
                  )}
                </article>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}
