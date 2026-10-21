# Third-party software

Bandu's application code and reusable teaching prompts are MIT licensed. Vendored libraries, runtime code and fonts remain under their original licenses; their copyright notices must accompany redistribution.

| Component | Purpose | License location |
| --- | --- | --- |
| Node.js 24.20.0 | Local tutor process runtime | `Resources/Licenses/Node.txt` (includes bundled dependencies) |
| Mozilla Readability | Article extraction | `Resources/Readability-LICENSE.md` (Apache-2.0) |
| DOMPurify | HTML sanitization | `Resources/DOMPurify-LICENSE` and `Resources/Licenses/dompurify-LICENSE` (Apache-2.0 or MPL-2.0) |
| marked | Article Markdown | `Resources/marked-LICENSE.md` (MIT) |
| React, react-dom | Teaching UI | `Resources/Licenses/react-LICENSE`, `react-dom-LICENSE` (MIT) |
| react-markdown / unified / remark / rehype | Teaching Markdown and math pipeline | individual files in `Resources/Licenses/` |
| KaTeX and included fonts | Formula rendering | `Resources/Licenses/katex-LICENSE` and related font notices |
| Mermaid | Diagrams | `Resources/Licenses/mermaid-LICENSE` (MIT) |
| Apache ECharts | Charts | `Resources/Licenses/echarts-LICENSE`, `echarts-NOTICE` (Apache-2.0) |
| mathjs | Expression evaluation | `Resources/Licenses/mathjs-LICENSE`, `mathjs-NOTICE` (Apache-2.0) |

`TeacherUI/package-lock.json` pins the source build dependencies. `Resources/Licenses/` also retains notices from the development dependency tree. The runtime bootstrap downloads the official Node archive, checks its pinned SHA-256, and copies its full upstream license into the bundle.

The app does not bundle Codex or Claude Code. Users install those tools separately. It does not contain proprietary reader source code or private coursework. The native interface was developed with Claude Opus 5.5 design assistance and Codex implementation assistance.
