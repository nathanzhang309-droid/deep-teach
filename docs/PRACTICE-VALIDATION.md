# 1.4.0 · Adaptive practice and review / 错题复练与个性化复习

Validation for the [1.4.0 release](https://github.com/nathanzhang309-droid/deep-teach/releases/tag/v1.4.0), 2026-10-21.

The updated source connects single-choice quiz attempts to study topics. A wrong first attempt or revealing an answer saves a review immediately and queues a same-topic variation plus a targeted explanation. Each initial question permits at most two automatic follow-ups. Two independent correct first attempts after the latest failure clear the “Needs review” flag; self-assessed mastery is separate. Disputed reference answers and their descendants are excluded from the flag while retaining their history.

新增流程：首次作答 → 答错／看答案 → 先保存复习要点 → 生成变式与针对性讲解 → 大屏筛选与 Obsidian 同步。关闭自动追加不丢记录；订阅失败可重试或暂停。旧资料兼容，手写补充继续受保护。

## Validation

- **117 portable checks**: 16 storage/sync, 14 layout, 12 adversarial storage/localization, 31 practice-engine, 18 prompt/runner, 26 frontend. `bash scripts/test.sh` passes.
- **47 native checks** across Chinese offline (15), English/Codex live (16), and Chinese/Claude live (16). Uses the bundled React UI, real WKWebView option clicks and the native bridge, not a substitute grading implementation.
- Native coverage includes stale document messages, repeated clicks, disk-write rollback, automatic generation disabled, first-attempt persistence, immediate review, model-generated variation appearing in chat, Obsidian freeform preservation, self-assessment/manual-note preservation, independent resizable review window, and reopening saved data.
- Live requests use synthetic conditional-probability material only. Codex produced an English conditional-probability variation and review of the chosen denominator. Claude produced a Chinese numerical variation and a review explicitly qualifying inferred confusion as possible. Both mathematical examples were checked against their source formula.
- 619 localized call sites and 574 English entries checked. Both live outputs used the selected UI language despite English source text in the Chinese test.
- Native app compiles and its ad-hoc code signature verifies. The final 1.4.0 bundle repeated all 15 offline native checks successfully after the last source changes.

Machine-readable results: [practice-validation-evidence.json](practice-validation-evidence.json). Previous version's broader annotation/slide evidence remains in [VALIDATION.md](VALIDATION.md); those old results are not represented as new tests.

## Reproduce native checks

Build the app, then use a **fresh temporary data directory**:

```bash
SHIYE_DATA_DIR="$(mktemp -d)" DEEP_TEACH_LANGUAGE=zh \
BANDU_PRACTICE_TEST=1 BANDU_TEST_QUIT=1 \
'build/伴读.app/Contents/MacOS/Bandu'
```

The result is `practice-validation.json` under that directory. Set `BANDU_PRACTICE_LIVE_TEST=1` and `BANDU_TEST_PROVIDER=codex` or `claude` to exercise an existing subscription login; this consumes subscription allowance. Never point tests at a daily-use library. The test exits after saving its result.

## Limits

This implements first-attempt **single-choice** practice, not grading of arbitrary free-text or handwritten solutions. Generated questions and explanations can be wrong; students can mark a reference answer as disputed. The review rule is transparent bookkeeping, not a validated mastery model or a diagnostic claim. Semantic equivalence of questions is encouraged by the prompt; only exact repeated question text is rejected locally. No automatic spaced-repetition schedule is implemented. Tests do not establish broad subject accuracy or service availability in every region.
