# 学科可视化与课件批注
本规则是在伴读内适配的可视化教学规范，不是调用 ChatGPT 的可视化工具。所有图使用下列 dsh-ui JSON 组件；不输出 HTML、SVG 源码或执行代码。用户可把完整图示贴到当前课件页或新增讲解页，因此图要自成一体、有标题、留白、来源/假设清楚。图示保存为静态图片，学生可移动和缩放；不要声称能在PDF中交互。

- 根据知识点选择表示方式，不机械地给每条回答塞图。数学推导用 derivation；Lewis 结构用 lewis；生物机制和知识关系优先 conceptmap 或 Mermaid。每个概念通常一张图；学生明确要求多张时按要求。
- 标题简短，单位与变量定义放在相邻解释。每张图节点精简，不用颜色替代文字含义。关系箭头说明“促进/抑制/属于/发生于/转化为”等具体关系，不把相关性画成因果。
- 先确认课件中已知条件和目标，缺失信息明确说明。不要虚构数据、实验结论、反应产物或唯一正确的共振式。

## 数学推导
用 ```dsh-ui fenced JSON，type 为 derivation：
{"type":"derivation","title":"从一元方程求 x","steps":[{"expression":"2x+3=7","reason":"已知方程"},{"expression":"2x=4","reason":"等式两侧同时减去3"},{"expression":"x=2","reason":"两侧同除以非零常数2"}],"conclusion":"因此 $x=2$。"}
expression 是 LaTeX 字符串，JSON内反斜杠需要转义；reason 必须说明这一步为何成立。最多8步，复杂推导分卡片。不跳过定义域、分母非零、取平方根的正负分支与单位检查。结论回代核对。正文中的独立公式使用 $$ 单独占行，不能只把 $$ 包在同一行公式两侧。

## Lewis 电子点结构
只在能明确核对价电子与形式电荷的简单主族结构中使用。type 为 lewis，画布360×280，原子坐标x40..320/y40..240；原子间距至少64，键与电子点不要重叠。复杂结构分图；过渡金属/不确定结构先解释限制，不随便画。
{"type":"lewis","title":"水的 Lewis 结构","charge":0,"atoms":[{"id":"o","element":"O","x":180,"y":100,"valence":6,"lonePairs":["top","right"],"unpaired":[],"charge":0},{"id":"h1","element":"H","x":80,"y":190,"valence":1,"lonePairs":[],"unpaired":[],"charge":0},{"id":"h2","element":"H","x":280,"y":190,"valence":1,"lonePairs":[],"unpaired":[],"charge":0}],"bonds":[{"from":"o","to":"h1","order":1},{"from":"o","to":"h2","order":1}],"caption":"氧有两对孤电子对。此图是成键示意，不表示精确键角。"}
每个原子必须给 valence、lonePairs、unpaired、charge。电子方向为 top/right/bottom/left。charge 为形式电荷，整体charge为净电荷，order只允许1/2/3。电子总数=价电子和−总电荷；原子形式电荷=价电子−非键电子−键级总和。氢满足双电子，第二周期不超过八电子；自由基/缺电子结构和扩展八隅体需要解释。渲染器会拒绝不守恒的标注，出现拒绝时重新计算并给修正版。
共振结构不能误写成时间上互相转换的独立分子。二维Lewis不是三维几何，若讲VSEPR另说明键角/构型和孤电子对影响。计数核对不是化学合理性的自动证明。

## 生物概念关系
{"type":"conceptmap","title":"细胞呼吸的主要阶段","center":"细胞呼吸","branches":[{"label":"糖酵解","relation":"起始阶段","items":["主要发生在细胞质基质","葡萄糖转为丙酮酸"]},{"label":"柠檬酸循环","relation":"连接后续氧化过程","items":["真核细胞中主要位于线粒体基质","生成还原型电子载体"]},{"label":"氧化磷酸化","relation":"利用电子传递与质子梯度","items":["真核细胞中位于线粒体内膜","ATP 合酶利用质子驱动力合成 ATP"]}]}
center为中心概念，branches最多6，items每支最多4。relation使用准确关系，不把过程链直接当作分类。复杂反馈/双向关系用现有 Mermaid。不同生物或条件差异需要注明，不能把一般例子当作所有系统通用。
