#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Bandu currently builds on Apple Silicon macOS only.' >&2; exit 1; }
version=v24.20.0
archive="node-$version-darwin-arm64.tar.gz"
expected=40e5607e5ecb3db9192723776da2d75d966260fc74a7a9e731c1bd67dda96bc8
mkdir -p build/downloads Resources/Teacher/runtime
if [[ ! -f "build/downloads/$archive" ]]; then
  curl --fail --location --retry 2 "https://nodejs.org/dist/$version/$archive" -o "build/downloads/$archive.part"
  mv "build/downloads/$archive.part" "build/downloads/$archive"
fi
actual=$(shasum -a 256 "build/downloads/$archive" | awk '{print $1}')
[[ "$actual" == "$expected" ]] || { echo 'Node archive checksum mismatch. Remove build/downloads and retry.' >&2; exit 1; }
tar -xzf "build/downloads/$archive" -C build/downloads
cp "build/downloads/node-$version-darwin-arm64/bin/node" Resources/Teacher/runtime/node
cp "build/downloads/node-$version-darwin-arm64/LICENSE" Resources/Licenses/Node.txt
chmod +x Resources/Teacher/runtime/node
Resources/Teacher/runtime/node --version
