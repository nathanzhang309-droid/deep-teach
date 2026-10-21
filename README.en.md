# Bandu · 伴读

**Understand your slides, annotate them in place, and review with notes that reflect your questions.**

Bandu is a native macOS reading and study app built with SwiftUI, AppKit, PDFKit, and a local WebKit teaching panel.

[Download](https://github.com/nathanzhang309-droid/bandu/releases/latest) · [中文](README.md) · [Privacy](PRIVACY.md)

![Automatic red-pen annotations beside a tutor conversation; synthetic lesson](docs/red-pen-demo.png)

- Read PDFs, presentations, unencrypted EPUBs, Markdown, text, HTML and web articles.
- Select a region and ask a tutor without leaving the page.
- Automatically add editable red circles, arrows, underlines and short labels after an answer. Undo a response's annotations or export an annotated PDF.
- See stepwise math, Lewis structures, concept maps, charts and quizzes.
- Keep personalized study notes with source pages, follow-up questions and your own additions. Review in a separate window.
- Sync Markdown to a local Obsidian vault while protecting handwritten sections.

## Requirements

Apple Silicon Mac, macOS 13+. PowerPoint import requires Keynote, or export to PDF yourself. Reading and note-taking work offline. **AI features require your own supported Codex or Claude subscription and CLI login.** They consume subscription allowances and are not a free hosted model service. Bandu excludes API-key authentication for its tutor subprocesses.

Download the Mac archive from Releases and move the app to Applications. Builds are ad-hoc signed and **not notarized by Apple**; macOS may require approval in Privacy & Security. You can also build locally:

```bash
xcode-select --install
git clone https://github.com/nathanzhang309-droid/bandu.git
cd bandu
bash build.sh
open build/伴读.app
```

The build fetches a pinned Node.js runtime from nodejs.org and verifies its SHA-256. The compiled teaching UI is included. To rebuild it, use `npm ci && npm run build` inside `TeacherUI/`. Run core and layout tests with `bash scripts/test.sh`.

Choose your Obsidian vault explicitly in Settings. New installations have no vault configured and automatic sync disabled. Notes go to `Bandu/` within the vault; existing installations retain their previous sync location.

## Privacy and limitations

Documents, notes and chat history live in `~/Library/Application Support/BanduLibrary/`. There is no Bandu cloud backend or built-in telemetry. Tutor requests send relevant lesson images/text, notes and conversation context to your selected provider; optional background note organization also uses that provider. See [PRIVACY.md](PRIVACY.md).

AI explanations and placements can be wrong. Image-based pages depend on visual recognition; there is no standalone offline OCR. Exported PDF annotations are flattened; keep the local library for editing. Inserted charts/formulas remain static images. There is no DRM support, built-in cloud sync, Intel build, or Windows/Linux version.

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), use synthetic examples, and never include private coursework, notes or credentials in an issue.

[MIT](LICENSE) for project code and teaching prompts. Dependencies retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). Not affiliated with OpenAI, Anthropic, Obsidian or Apple.
