# deep-teach · 伴读

**[简体中文](README.md) | [English](README.en.md)**

**Understand your slides, annotate them in place, and review with notes shaped by your questions.**

deep-teach is a native macOS reading and study app. Open a PDF or presentation, select what you don’t understand, and ask an AI tutor that explains alongside the page and adds editable red-pen annotations. Turn your questions into personalized study notes, review them in a separate window, sync them to Obsidian, or export an annotated PDF.

[Download](https://github.com/nathanzhang309-droid/deep-teach/releases/latest) · [中文](README.md) · [Privacy](PRIVACY.md)

## Meet deep-teach in 45 seconds

https://github.com/user-attachments/assets/accb2c11-6abc-42bf-ab44-21cfe720c1e7

**[Download the English video](https://github.com/nathanzhang309-droid/deep-teach/raw/refs/heads/main/docs/media/deep-teach-en-bgm.mp4)** · 45 seconds · English captions · Instrumental BGM, no voiceover. Shown with synthetic course material and demo data.

![English tutor interface with a synthetic lesson](docs/english-teacher.png)

- Switch between English and Chinese in Settings without losing drafts or quiz selections.
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
git clone https://github.com/nathanzhang309-droid/deep-teach.git
cd deep-teach
bash build.sh
open build/伴读.app
```

The build fetches a pinned Node.js runtime from nodejs.org and verifies its SHA-256. The compiled teaching UI is included. To rebuild it, use `npm ci && npm run build` inside `TeacherUI/`. After `npm ci` in `TeacherUI/`, run the storage, layout, bilingual request, input and localization tests with `bash scripts/test.sh` (Node.js 24 required).

Choose your Obsidian vault explicitly in Settings. New installations have no vault configured and automatic sync disabled. Notes go to `Bandu/` within the vault; existing installations retain their previous sync location.

## Language and input

Open **Settings → Language** and choose **System / 中文 / English**. The interface, native menus and new explanations follow your choice immediately. Existing course material, notes and conversations keep their original text; unsent drafts and quiz selections survive switching. You can ask in either language. To override the selected reply language, explicitly ask the tutor to answer in your preferred language.

Mixed-script and emoji titles are supported. Text imports accept UTF-8 or UTF-16 with a BOM; convert other encodings first. Questions over 5,000 Unicode code points are not sent, and the draft remains available to edit. Obsidian keeps its existing folder names; `待合并` is the pending-merge folder, where conflicts are saved for manual review.

See the [bilingual adversarial test report](docs/VALIDATION.md) for measured coverage and limits.

## Privacy and limitations

Documents, notes and chat history live in `~/Library/Application Support/BanduLibrary/`. There is no Bandu cloud backend or built-in telemetry. Tutor requests send relevant lesson images/text, notes and conversation context to your selected provider; optional background note organization also uses that provider. See [PRIVACY.md](PRIVACY.md).

AI explanations and placements can be wrong. Image-based pages depend on visual recognition; there is no standalone offline OCR. Exported PDF annotations are flattened; keep the local library for editing. Inserted charts/formulas remain static images. There is no DRM support, built-in cloud sync, Intel build, or Windows/Linux version.

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), use synthetic examples, and never include private coursework, notes or credentials in an issue.

[MIT](LICENSE) for project code and teaching prompts. Dependencies retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). Not affiliated with OpenAI, Anthropic, Obsidian or Apple.
