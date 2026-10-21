# v1.2.2 validation — 2026-10-20

- Clean public-source frontend build: passed using the committed dependency lockfile.
- Swift native build and ad-hoc signature verification: passed on Apple Silicon.
- 16 core checks: passed, including empty vault defaults, legacy preference decoding, persistence, conflict-safe Obsidian export and recovery.
- 14 layout checks: passed.
- 22 native slide checks: passed in a separate test library, including editable annotations, page bounds, undo/redo, image/formula capture, persistent selection, focus, zoom and PDF export.
- Previous v1.2.1 implementation baseline: 20 automatic-red-pen checks passed, including a real subscription answer against synthetic material and zero red pixels outside the page/viewport after scrolling and zooming. The public release preserves that implementation.
- Publication scan: no private home paths, course preferences, library files or common credential patterns found in the tracked source set. The demonstration uses a synthetic probability lesson. The downloadable application was rebuilt from the sanitized source, not copied from a personalized installation.

This is not an accuracy benchmark for arbitrary coursework. Mouse dragging has code-path and geometry coverage, but has not been certified by a complete external GUI automation run. The app is not Apple-notarized and only Apple Silicon is currently built.
