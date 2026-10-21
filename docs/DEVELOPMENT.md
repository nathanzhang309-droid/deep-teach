# Development and validation

## Structure

- `Sources/`: native reader, library, selection, annotation overlay, note organization and Obsidian sync.
- `TeacherUI/`: React source for the local WKWebView teaching panel.
- `Resources/TeacherUI/`: committed compiled UI, CSS and fonts.
- `Resources/Teacher/`: Node tutor process, provider adapters and reusable teaching instructions.
- `Tests/`: portable core/layout tests and synthetic import fixtures.

`build.sh` targets Apple Silicon/macOS 13. It downloads Node 24.20.0 from the official release site only if the runtime is absent. The bootstrap verifies the archive SHA-256. `SHIYE_BUILD_DIR` can override the default `build/` directory; the legacy prefix is retained for development compatibility.

## Checks without an AI account

```bash
(cd TeacherUI && npm ci && npm run build)
bash scripts/test.sh
bash build.sh
codesign --verify --deep --strict build/伴读.app
```

Core tests cover local persistence, deduplication, sync idempotency, manual-note protection, conflict handling, recovery and public defaults. Layout tests cover proportions, minimum widths and persistence. These are the CI checks.

## Native integration checks

Always use an empty temporary directory for `SHIYE_DATA_DIR`. Never point a test at your real library.

```bash
TEST_DATA=$(mktemp -d)
open -n --env SHIYE_DATA_DIR="$TEST_DATA" --env BANDU_SLIDE_TEST=1 build/伴读.app
```

This writes a JSON result and synthetic PDF/screenshots inside the test directory. Inspect results and close the test app before testing another mode. Supported modes:

- `BANDU_SLIDE_TEST=1`: 22 native selection/editing/visual-capture/export checks. No provider call required.
- `BANDU_LAYOUT_TEST=1`: native layout and restoration checks.
- `BANDU_STUDY_TEST=1`: local study-note checks. Add `BANDU_STUDY_LIVE_TEST=1` only to opt into subscription-backed semantic organization.
- `BANDU_INTEGRATION_TEST=1`: reading/import/selection; `BANDU_LIVE_TEST=1` opts into its live provider test.
- `BANDU_INK_TEST=1`: 20 automatic-annotation checks, including viewport/page clipping pixel counts and a **real Codex request using synthetic material**. This mode consumes your subscription allowance.

The local 1.2.1 baseline passed 20 ink checks and 22 slide checks, including a real Codex answer and rendered PDF inspection. Test results are not claims of model accuracy across arbitrary coursework or an automated end-to-end mouse-drag certification. New public-default tests cover empty vault configuration and legacy compatibility.

## Releases

Build from the exact tagged source. Do not upload an old personalized app bundle. Check the bundle for private paths, teaching preferences, data, account files and logs. Keep Node and third-party licenses.

```bash
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/伴读.app dist/deep-teach-1.3.0-macOS-arm64.zip
(cd dist && shasum -a 256 deep-teach-1.3.0-macOS-arm64.zip > SHA256SUMS.txt)
```

The initial release is ad-hoc signed and not notarized. No signing certificates, provider sessions or private credentials belong in CI. Repository maintainers must document tested versions and limitations honestly.

## Bilingual adversarial checks

`bash scripts/test.sh` now also runs `Tests/AdversarialCoreTests.swift`, the Node request-contract tests, the bundled TypeScript adversarial tests, and translation/placeholder coverage. Run `npm ci` in `TeacherUI/` first. These tests do not call a subscribed model.

For native WebKit/AppKit checks, use a separately signed test copy with a unique bundle identifier, remove its URL handlers, and provide a **new synthetic library** through `SHIYE_DATA_DIR`. Launch with `BANDU_ADVERSARIAL_TEST=1 DEEP_TEACH_LANGUAGE=en`; `adversarial-native.json` is written under that library. The harness tests native menus, selection preservation, a mock teacher bridge (no model calls), IME events, draft limits, narrow panes, quiz state and Obsidian exports. `BANDU_INK_TEST=1` additionally calls a real logged-in Codex subscription; do not enable it in CI. See `Sources/AdversarialNativeTests.swift` and the existing test harnesses for fixtures.

Translations live in `Resources/en.json`; native `L()` and web `t()` substitute indexed placeholders without reinterpreting user strings. Keep theme, filter, provider and persisted folder identifiers unchanged. Add new interface keys to the catalog and run `Tests/check-localization.mjs`.
