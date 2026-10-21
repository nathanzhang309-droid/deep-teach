#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon macOS is required.' >&2; exit 1; }
if [[ ! -x Resources/Teacher/runtime/node ]]; then bash scripts/bootstrap-runtime.sh; fi
BUILD_DIR="${SHIYE_BUILD_DIR:-build}"
mkdir -p "$BUILD_DIR/swift-cache"
APP="$BUILD_DIR/伴读.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -Onone -module-cache-path "$BUILD_DIR/swift-cache" -target arm64-apple-macosx13.0 Sources/*.swift -o "$APP/Contents/MacOS/Bandu" -framework SwiftUI -framework AppKit -framework PDFKit -framework WebKit -framework CryptoKit
cp -R Resources/. "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
