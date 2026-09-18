#!/bin/sh
# Build TokscaleBar.app from the Swift package.
# Usage: ./build-app.sh [--universal]
# Env:   VERSION=1.2.3 overrides CFBundleShortVersionString (used by CI releases).
set -eu
cd "$(dirname "$0")"

# One swift build call both compiles and reports the output dir; invoking it
# twice would wait on the build lock a second time for nothing.
if [ "${1:-}" = "--universal" ]; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi
BIN="$BIN_DIR/TokscaleBar"

APP=TokscaleBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    # CFBundleVersion must increase monotonically; UTC unix time is
    # timezone-proof and stays in uint32 range until 2106.
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date -u +%s)" "$APP/Contents/Info.plist"
fi

# Ad-hoc sign so Gatekeeper and login-item registration behave. A failed
# signing must fail the build, with its message visible. Strip xattrs first:
# checkouts on iCloud Drive carry extra attributes that intermittently break
# codesign.
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
