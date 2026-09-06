#!/bin/sh
# Build TokscaleBar.app from the Swift package.
# Usage: ./build-app.sh [--universal]
# Env:   VERSION=1.2.3 overrides CFBundleShortVersionString (used by CI releases).
set -e
cd "$(dirname "$0")"

if [ "$1" = "--universal" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TokscaleBar"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/TokscaleBar"
fi

APP=TokscaleBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# Ad-hoc sign so Gatekeeper and login-item registration behave. A failed
# signing must fail the build, not ship an unsigned bundle.
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "Built $APP"
