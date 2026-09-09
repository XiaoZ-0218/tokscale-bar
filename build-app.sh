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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    # CFBundleVersion must increase monotonically; UTC unix time is
    # timezone-proof and stays in uint32 range until 2106.
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date -u +%s)" "$APP/Contents/Info.plist"
fi

# Ad-hoc sign so Gatekeeper and login-item registration behave. A failed
# signing must fail the build, with its message visible.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
