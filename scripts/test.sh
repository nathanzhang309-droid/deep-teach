#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests build/swift-cache
swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/Core.swift Tests/CoreTests.swift -o build/tests/core
build/tests/core
swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/PaneLayout.swift Tests/LayoutTests.swift -o build/tests/layout -framework SwiftUI -framework AppKit
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
build/tests/layout "$sandbox"
