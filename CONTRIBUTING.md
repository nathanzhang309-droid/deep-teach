# Contributing

1. Open an issue describing a reproducible problem or a focused improvement. Use synthetic course material.
2. Fork the repository and work on a branch. Requirements and build steps are in README.md.
3. Run `bash scripts/test.sh` and `bash build.sh`. If changing the teaching UI, run `npm ci && npm run build` in TeacherUI first.
4. For UI, selection, annotation or export changes, exercise the native integration checks in docs/DEVELOPMENT.md and include a redacted screenshot when useful.
5. Open a pull request explaining the visible behavior and checks performed. Keep original documents unchanged, preserve existing data and avoid paid API dependencies.

Never commit a real library, model credentials, `.env`, logs with personal content, or private teaching material. Contributions are under the repository MIT license. Keep upstream copyright notices and dependency licenses.
