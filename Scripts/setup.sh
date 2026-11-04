#!/bin/bash
set -euo pipefail

if ! xcodebuild -version; then
    echo 'A usable full Xcode installation is required. Select it with xcode-select.' >&2
    exit 1
fi
xcrun swift --version
if [[ "$(uname -m)" != arm64 ]]; then
    echo 'Run setup natively on Apple Silicon (arm64).' >&2
    exit 1
fi
install_tool() {
    if ! command -v brew >/dev/null; then
        echo "Homebrew is required to install $1. Install it from https://brew.sh and rerun make setup." >&2
        exit 1
    fi
    brew install "$1"
}
if ! command -v swiftlint >/dev/null; then
    install_tool swiftlint
fi
if ! xcrun --find swift-format >/dev/null 2>&1 && ! command -v swift-format >/dev/null; then
    install_tool swift-format
fi
swiftlint version
