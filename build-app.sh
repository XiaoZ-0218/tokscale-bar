#!/bin/sh
# Build TokscaleBar.app from the Swift package.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=TokscaleBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TokscaleBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# Ad-hoc sign so Gatekeeper and login-item registration behave.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
