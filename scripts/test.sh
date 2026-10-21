#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests build/swift-cache
swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/Localization.swift Sources/Core.swift Tests/CoreTests.swift -o build/tests/core
DEEP_TEACH_LANGUAGE=zh build/tests/core
swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/PaneLayout.swift Tests/LayoutTests.swift -o build/tests/layout -framework SwiftUI -framework AppKit
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
build/tests/layout "$sandbox"

swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/Localization.swift Sources/Core.swift Tests/AdversarialCoreTests.swift -o build/tests/adversarial
DEEP_TEACH_LANGUAGE=zh DEEP_TEACH_TEST_RESOURCES="$PWD/Resources" build/tests/adversarial
node --test Tests/AdversarialPrompts.test.mjs
npm --prefix TeacherUI test
node Tests/check-localization.mjs
