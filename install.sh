#!/bin/bash
#
# Build FreeFlow, put it in /Applications, and launch it.
#
# This exists because `open FreeFlow.xcodeproj` is a bad last step. With Xcode
# installed it opens Xcode and waits for someone to press Run. Without Xcode
# nothing has registered .xcodeproj as a document type, so Finder shows it for
# what it is on disk: a folder. Either way no app appears.

set -euo pipefail
cd "$(dirname "$0")"

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DEST="$INSTALL_DIR/FreeFlow.app"

say() { printf '\n==> %s\n' "$1"; }
die() { printf '\nerror: %s\n' "$1" >&2; exit 1; }

# The Command Line Tools ship a stub xcodebuild that only reports that it isn't
# the real one. If Xcode is installed but xcode-select still points at the
# tools, aim at it for this run rather than asking for sudo.
if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
  xcodebuild -version >/dev/null 2>&1 || die "Xcode is not installed, and FreeFlow can't be built without it.
The Command Line Tools on their own are not enough.

  1. Install Xcode from the App Store (free, about 12 GB).
  2. Open it once and accept the licence.
  3. Run ./install.sh again."
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || die "XcodeGen is missing and so is Homebrew.
Install Homebrew from https://brew.sh, then run ./install.sh again."
  say "Installing XcodeGen"
  brew install xcodegen
fi

say "Generating the Xcode project"
xcodegen generate

say "Building (the first build downloads WhisperKit and takes a few minutes)"
xcodebuild -project FreeFlow.xcodeproj -scheme FreeFlow -configuration Release \
  -derivedDataPath build -quiet build

BUILT="build/Build/Products/Release/FreeFlow.app"
[ -d "$BUILT" ] || die "The build finished but $BUILT isn't there."

say "Installing to $DEST"
if [ -d "$DEST" ]; then
  # Replacing a running app leaves the old process alive on deleted files.
  pkill -x FreeFlow 2>/dev/null || true
  rm -rf "$DEST"
fi
mkdir -p "$INSTALL_DIR"
cp -R "$BUILT" "$DEST"

say "Opening FreeFlow"
open "$DEST"

cat <<'EOF'

FreeFlow is running. It lives in the menu bar, and the first launch walks
through permissions and the model download.
EOF
