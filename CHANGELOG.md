# Changelog

## 1.3.0 — 2026-10-21

- Add system/Chinese/English interface language, localized native menus, teacher and science UI, first-run guide, dates and export headings. Preserve user content, drafts, quiz selections and stored IDs.
- Send an allow-listed response language to both tutor and study-note requests. Reinforce it when question/source language differs.
- Preserve overlong drafts, protect IME composition, and cancel requests stopped before context preparation completes. Mark interrupted responses as incomplete; limit streaming output.
- Bound visual JSON complexity and restrict plot functions to prevent expensive allocation/evaluation expressions.
- Fix long Unicode/emoji export filenames, validate sync ancestors before creating directories, and reject redirected sync indexes/targets.
- Reject ambiguous legacy text encodings instead of silently interpreting them as UTF-16.
- Add bilingual adversarial tests and English layout verification. See docs/VALIDATION.md for results and limits.

## 1.2.2 — 2026-10-20

First public release. Based on the locally tested 1.2.1 application.

- Publish native reader, automatic red-pen annotations, editable slide overlays, personalized study notes and Obsidian export.
- Remove personal vault paths, course preferences and private validation records.
- Default to no connected vault and no automatic vault sync; new exports use `Bandu/`, while existing preferences retain their legacy location.
- Add a checksum-verified Node runtime bootstrap, exact frontend dependencies, lockfile, build/test scripts and GitHub Actions.
- Include Chinese/English documentation, privacy and contribution guides, third-party notices and a synthetic lesson demo.

## 1.2.1 — local baseline

- Automatically annotate the question's captured page after successful tutor replies.
- Add transparent red labels, circles, underlines and arrows with per-answer undo.
- Clip annotations and selection overlays to the page and reading viewport while scrolling or zooming.
