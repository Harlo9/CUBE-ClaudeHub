#!/bin/bash
# Builds "Cube Hub.app" into build/ and launches it.
# Usage: ./build.sh            build + (re)launch
#        ./build.sh --no-run   build only
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Cube Hub.app"   # the folder name is the name shown by the Dock and Finder
STAMP="Resources/Frames/.stamp"

# 1. Reduced cube frames: regenerated only when an original (or the script) changed.
if [ ! -f "$STAMP" ] || [ -n "$(find Assets Scripts/make_frames.swift -newer "$STAMP" -print -quit)" ]; then
    echo "→ Generating reduced frames…"
    swift Scripts/make_frames.swift
    touch "$STAMP"
fi

# Signing identity: the "Apple Development" certificate if there is one, so the app keeps
# the same identity from one build to the next (macOS then remembers the permission to
# drive Terminal). Otherwise an ad-hoc signature ("-"), and macOS may ask again after a build.
# (`|| true`: finding none is not an error, e.g. on GitHub's Macs.)
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}' || true)"
SIGN_ID="${SIGN_ID:--}"

# 2. Compile the app and cube-hook (the program run by the Claude Code hooks).
echo "→ Compiling…"
swift build -c release --product CubeWidget
swift build -c release --product cube-hook
BIN_DIR="$(swift build -c release --show-bin-path)"

# cube-hook is installed in ~/.cube-widget/bin, where the hooks of ~/.claude/settings.json
# find it. Copied then renamed, so a hook running right now never sees a half-copied file.
HOOK_DIR="$HOME/.cube-widget/bin"
mkdir -p "$HOOK_DIR"
cp "$BIN_DIR/cube-hook" "$HOOK_DIR/cube-hook.new"
codesign --force --sign "$SIGN_ID" "$HOOK_DIR/cube-hook.new" >/dev/null 2>&1
mv -f "$HOOK_DIR/cube-hook.new" "$HOOK_DIR/cube-hook"

# 3. Assemble the .app bundle (a .app is just a folder with a fixed layout).
pkill -x CubeWidget 2>/dev/null || true
rm -rf "$APP" build/CubeWidget.app   # also the app's former name
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CubeWidget" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Frames "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"   # made by Scripts/make_icon.sh
rm -f "$APP/Contents/Resources/Frames/.stamp"
# Sounds are optional: the app plays nothing for a missing file. Those of Sons/ (not in
# the repository) come first; otherwise three of them are macOS's own sounds, taken from
# this Mac (they belong to Apple, so they are not shipped with the code).
SOUNDS="$APP/Contents/Resources/Sons"
mkdir -p "$SOUNDS"
if [ -d Sons ]; then cp -R Sons/. "$SOUNDS/"; fi
for pair in fini:Glass attente:Purr dodo:Bottle; do
    name="${pair%%:*}"; system="/System/Library/Sounds/${pair##*:}.aiff"
    if ! ls "$SOUNDS/$name".* >/dev/null 2>&1 && [ -f "$system" ]; then cp "$system" "$SOUNDS/$name.aiff"; fi
done

# 4. Signature (required by macOS to run the app on Apple Silicon). Errors are shown:
#    the first time, macOS may ask to let codesign use the certificate ("Always Allow").
codesign --force --sign "$SIGN_ID" "$APP"

echo "✓ Built $APP"
if [ "${1:-}" != "--no-run" ]; then
    open "$APP"
    echo "✓ Launched"
fi
