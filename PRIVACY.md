# Privacy / 隐私说明

Bandu has no account system, hosted backend, advertising SDK, or built-in analytics.

## Stored on this Mac

The library lives at `~/Library/Application Support/BanduLibrary/`: imported documents, highlights, notes, page positions, teacher conversations, selected screenshots, personalized study notes and editable slide annotations. Previous valid JSON files are retained as recovery copies. Use the in-app library backup action to export a complete copy.

Obsidian sync writes files to the vault you explicitly select. New installs default to `Bandu/`; existing installations can retain the legacy subfolder. Sync is one-way and preserves user-written sections. Your existing iCloud/other vault sync is outside Bandu's control.

## Sent to a provider

When you ask the tutor, Bandu sends the selected crop (if any), the current full page image, nearby extracted text, a course outline, relevant notes and recent conversation context to the selected CLI's model provider. A whole document is not uploaded as a binary, but its extracted outline can include text from many pages.

With automatic study-note organization enabled, completed questions/answers, relevant source context and existing topic notes are sent to that provider in the background. Disable automatic organization in the study-notes panel to stop that background step. Reading and editing remain local.

Codex / Claude run as separately installed CLIs under your existing login. Bandu excludes API-key environment variables and instructs the tutor process not to execute tools or access additional files. CLI account handling, diagnostics, retention and provider processing are governed by those products; this project cannot promise their behavior or availability.

Web article import requests the URL and embedded resources from their hosts. PPT conversion uses local Keynote automation. PDF export, visual snapshots and rendering occur locally. Teaching UI dependencies are bundled rather than loaded from a remote CDN.

## Reporting issues safely

Do not upload your library, `.bandu` backups, course PDFs, vault, CLI account files or screenshots containing private material. Use a small synthetic document and redact any identifiers. The repository demo is generated test material.
