# visual-teacher

「能画就画」的教学可视化技能。目标：把抽象概念变成看得见的东西，并且**每张图配一句大白话解读**——图是辅助，讲明白才是目的。

## 两个渲染通道

### 通道一：dsh-ui 围栏（默认，内联渲染在回答里）

在回答正文中输出一个代码围栏，语言标签写 `dsh-ui`，内容是一个 JSON 对象。它会在聊天界面里直接渲染成交互组件，用户不用打开任何文件：

```dsh-ui
{"title":"可选标题","gap":14,"items":[...]}
```

规则：
- 围栏放哪，组件就出现在哪，前后文字自然流动；围栏一闭合立即渲染
- 一条回答 3–8 个组件为宜；一句话能说清的事不画图
- 若当前界面不支持 dsh-ui（比如纯终端 CLI），直接改用通道二

### 通道二：独立 HTML 文件（复杂交互 / 动画 / 保存分享）

当需求超出 dsh-ui 能力（多图联动、自定义动画、交互式模拟、物理演示），或用户要保存、分享、打印时：

1. 用 tool-fs 把自包含 HTML 写到工作目录的 `visual/` 文件夹，文件名用短英文，如 `visual/sin-wave.html`
2. 写完后用 bash 执行 `open visual/sin-wave.html`（macOS）在浏览器里打开
3. 告诉用户文件路径，方便他以后重开或分享
4. 库全部走 CDN：function-plot（函数图）、KaTeX（公式）、ECharts（图表）、Mermaid（流程图），模板见文末

## 内容 → 组件选择表

| 要讲的内容 | 用什么 |
|---|---|
| 数学函数、曲线、图像（sin、抛物线、导数、极限） | `plot`（可带参数滑块、动画按钮） |
| 数据对比、趋势、占比（柱状/折线/饼图/散点） | `echart`（优先）或 `chart` |
| 流程、因果链、状态机、时间轴 | `mermaid` 或 `steps` / `timeline` |
| 架构、层级、概念结构 | `diagram` 或 `table` / `list` |
| 几何体、空间关系（体积、三视图、立体几何） | `scene3d` |
| 强调 / 注意 / 警告 | `callout` |
| 关键数字、进度 | `stat` / `progress` |
| 讲完后的自测 | `quiz`（点选即判题） |

## 关键组件字段速查

### plot — 数学函数图（数学课首选）

```dsh-ui
{"type":"plot","title":"正弦函数的图像","xMin":-6.28,"xMax":6.28,"series":[
  {"expr":"a*sin(b*x)","label":"a·sin(b·x)","color":"#4f8cff",
   "params":[
     {"name":"a","value":1,"min":0.2,"max":3},
     {"name":"b","value":1,"min":0.5,"max":4}
   ]}
]}
```

- `series[].expr`：表达式字符串，支持 `sin/cos/tan/asin/acos/atan/sqrt/cbrt/exp/log/ln/abs/floor/ceil/round/min/max/pow`，常量 `pi/e/tau`；**变量只有 `x`，其他字母一律当作参数**
- `params`：渲染成实时滑块，拖动即时重绘（y 轴锁定）；某参数加 `"animateTo":3,"durationMs":4000,"loop":true` 会出现播放按钮，自动动画演示
- `series[].kind`：可选 `line|area|scatter`（默认 line；area 填色到基线；scatter 散点）
- `color`：十六进制色；`xMin/xMax` 给合理范围（三角函数常用 -6.28~6.28 或 -3.14~3.14）
- 同一张图多条曲线就在 `series` 里放多个对象；图可拖拽平移、滚轮缩放

### echart — 数据图表（视觉效果最好）

```dsh-ui
{"type":"echart","title":"各月销量","height":300,"preset":"bar",
 "data":[{"label":"一月","value":120},{"label":"二月","value":200},{"label":"三月","value":150}]}
```

- `preset`：`bar|line|area|pie|scatter`，用和上面一样的 `data` 格式
- 复杂图表用 full option 模式：`"option":{...}` 直接写 ECharts 原生配置（dataZoom/radar/gauge/heatmap 等全支持），但 option 里不要放函数

### chart — 轻量图表（echart 的备选）

`{"type":"chart","kind":"bars|line|donut","data":[{"label":"...","value":n,"color":"#hex?"}],"series":[...]?}`

### mermaid — 流程图/状态图/时间线

```dsh-ui
{"type":"mermaid","code":"graph TD\n  A[输入] --> B{判断}\n  B -->|是| C[输出]\n  B -->|否| D[返回]"}
```

**注意：JSON 字符串里的换行必须写成转义 `\n`（反斜杠+n，两个字符）**，不能写真实换行。支持 flowchart/sequence/class/gantt/pie/er/state/journey。自动布局用 mermaid；需要精确定位、编辑级排版时用 diagram。

### diagram — 架构/层级/示意图（27 种 kind）

```dsh-ui
{"type":"diagram","kind":"flowchart","nodes":[{"id":"a","label":"概念A","type":"focal"},{"id":"b","label":"概念B"}],"edges":[{"from":"a","to":"b","label":"导致"}]}
```

kind 常用：`architecture / flowchart / timeline / tree / layers / venn / quadrant / cycle`。规则类 kind 只给 nodes/edges 自动排版；坐标类 kind（architecture 等）给 `x/y/w/h` 精确定位。节点 type：`focal|backend|store|external|input|optional|security`。

### scene3d — 立体几何/空间

```dsh-ui
{"type":"scene3d","title":"立方体","meshes":[
  {"shape":"box","size":[1,1,1],"color":"#4f8cff","rotation":[0.6,0.8,0]}
]}
```

shape 支持 `box|sphere|cone|cylinder|torus`；可拖拽旋转、滚轮缩放；mesh 数量 1–5 个。

### quiz — 讲完出小测验（当场判卷）

```dsh-ui
{"type":"quiz","question":"导数 f'(x) 的几何意义是什么？","options":[
  {"label":"曲线在 x 处的切线斜率","correct":true,"feedback":"对，这就是导数的几何意义"},
  {"label":"曲线与 x 轴围成的面积"},
  {"label":"曲线在 x 处的函数值"}
],"explanation":"导数 = 切线的斜率；面积是积分的几何意义。"}
```

用户点选即判题、可重试。讲完一个概念用它让用户确认自己真懂了。

### 其他常用

- `table`：`{"type":"table","columns":["方案","优点","缺点"],"rows":[["A","快","贵"],["B","慢","便宜"]]}`（表头可点击排序）
- `steps`：`{"type":"steps","current":0,"steps":[{"title":"第一步","desc":"..."}]}`
- `timeline`：`{"type":"timeline","items":[{"title":"...","desc":"...","time":"..."}]}`
- `callout`：`{"type":"callout","tone":"info|success|warning|error","title":"...","content":"..."}`
- `stat`：`{"type":"stat","label":"...","value":"..."}`；`list`：`{"type":"list","items":["..."]}`
- `keyvalue`：`{"type":"keyvalue","pairs":[{"key":"...","value":"..."}]}`

## JSON 围栏自检（发出前必查）

1. 括号配对：`{` 与 `}`、`[` 与 `]` 数量相等；收尾序列逐个核对（长表格最易把 `]]}]}` 写成 `]}]}]}`）
2. 无尾随逗号
3. 字符串值里的引号用中文引号「」或“”，不要用半角 `"`
4. 最后一个字符必须是 `}`；mermaid 的 code 里换行写成 `\n` 转义
5. 组件树 ≤200 节点、嵌套 ≤8 层；超长表格拆成多个组件分开发

## 画图原则

1. **每张图必须配一句大白话解读**——这句解读就是教学本体，图不能单独出现
2. 标题、坐标轴、图例全部用中文；标签写「是什么」而不是只写符号
3. plot 给合理 xMin/xMax，让图形特征完整露出来
4. 颜色克制：2–4 种，深色主题用亮色（如 #4f8cff、#f5a524、#67c23a、#f56c6c）
5. 同一批数据不要用两种图重复表达（又画 bars 又画 donut = 冗余）
6. 一句话能说清的事不画图；图服务于理解，不为炫技

## 通道二：独立 HTML 模板（自包含，全 CDN）

按需增删，骨架如下：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>函数图像</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css">
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/contrib/auto-render.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/function-plot@1/dist/function-plot.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<style>
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         max-width: 860px; margin: 0 auto; padding: 24px; line-height: 1.8; }
  h1 { font-size: 1.5rem; }
  .card { background: #fafafa; border: 1px solid #e5e5e5; border-radius: 10px;
          padding: 16px; margin: 16px 0; }
  .plot { width: 100%; height: 420px; }
  .chart { width: 100%; height: 360px; }
  @media (prefers-color-scheme: dark) {
    body { background: #16181d; color: #e6e6e6; }
    .card { background: #1f2228; border-color: #33373f; }
  }
</style>
</head>
<body>
<h1>标题（用大白话写）</h1>
<p>一句话白话解读：……</p>

<div class="card">
  <div id="plot" class="plot"></div>
</div>
<p>公式：\(y = a\sin(bx)\)</p>

<div class="card">
  <div id="chart" class="chart"></div>
</div>

<div class="mermaid">
graph TD
  A[输入] --> B[处理] --> C[输出]
</div>

<script>
  // 1. 函数图（function-plot）：fn 写表达式，自动无限缩放
  functionPlot({
    target: '#plot',
    grid: true,
    xAxis: { domain: [-6.28, 6.28] },
    yAxis: { domain: [-3, 3] },
    data: [
      { fn: 'sin(x)', color: '#4f8cff' },
      { fn: '2*sin(x)', color: '#f56c6c' }
    ]
  });

  // 2. 图表（ECharts）
  var chart = echarts.init(document.getElementById('chart'));
  chart.setOption({
    tooltip: { trigger: 'axis' },
    xAxis: { type: 'category', data: ['一月', '二月', '三月'] },
    yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [120, 200, 150], itemStyle: { color: '#67c23a' } }]
  });

  // 3. 公式渲染（KaTeX，页面加载后自动把 \(...\) 和 $$...$$ 变成公式）
  document.addEventListener('DOMContentLoaded', function () {
    renderMathInElement(document.body, {
      delimiters: [
        { left: '\\(', right: '\\)', display: false },
        { left: '$$', right: '$$', display: true }
      ]
    });
  });
</script>
</body>
</html>
```

要点：
- 一个文件讲一个主题；多主题拆多个文件，别塞进一页
- function-plot 的 `fn` 支持与 dsh-ui plot 相同的表达式（x 为变量），区间在 `xAxis/yAxis.domain` 里定
- 交互式模拟（弹簧、抛体、电路）就写原生 JS + Canvas/SVG 动画，不要引额外框架
- 写完后用 bash `open` 打开验证一次再交付；交付时把文件路径告诉用户
