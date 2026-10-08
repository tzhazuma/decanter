#!/usr/bin/env bash
# Build the window and wrap it in a .app bundle.
#
# Usage: scripts/build-app.sh            debug build, Decanter.app in build/
#        scripts/build-app.sh --release  optimised build
set -euo pipefail

source "$(dirname "$0")/../scripts/env.sh"

cd "$DECANTER_ROOT/app"
configuration=debug
[[ "${1:-}" == --release ]] && configuration=release

log "building the window ($configuration)"
swift build -c "$configuration"

binary="$(swift build -c "$configuration" --show-bin-path)/Decanter"
[[ -x "$binary" ]] || die "no binary at $binary"

out="$DECANTER_ROOT/build"
app="$out/Decanter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Decanter"
cp "$DECANTER_ROOT/assets/decanter.icns" "$app/Contents/Resources/" 2>/dev/null || true

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Decanter</string>
    <key>CFBundleDisplayName</key><string>Decanter</string>
    <key>CFBundleIdentifier</key><string>dev.decanter.app</string>
    <key>CFBundleExecutable</key><string>Decanter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
PLIST

log "signing ad-hoc"
codesign --force --sign - "$app" 2>/dev/null

log "done: $app"
