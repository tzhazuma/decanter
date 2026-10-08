#!/usr/bin/env bash
# Build Decanter.app — the window, the command line tool, and the runtime all three use.
#
#   scripts/build-app.sh [--release] [--no-runtime]
#
# With --no-runtime the app carries no runtime and uses the one installed for the user, which is
# what a development build wants: the window starts in seconds instead of carrying 2.4 GB. A
# release carries its own, and then works on a Mac with no checkout, no Homebrew and no build.
set -euo pipefail

source "$(dirname "$0")/env.sh"

configuration=debug
with_runtime=1
for arg in "$@"; do
    case $arg in
        --release) configuration=release ;;
        --no-runtime) with_runtime=0 ;;
        *) die "unknown option $arg" ;;
    esac
done

out="$DECANTER_ROOT/build/package"
app="$out/Decanter.app"

log "building the window ($configuration)"
cd "$DECANTER_ROOT/app"
swift build -c "$configuration"
binary="$(swift build -c "$configuration" --show-bin-path)/Decanter"
[[ -x $binary ]] || die "no binary at $binary"

log "assembling $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/SharedSupport/cli"
cp "$binary" "$app/Contents/MacOS/Decanter"
cp "$DECANTER_ROOT/assets/decanter.icns" "$app/Contents/Resources/"

# The same tool the checkout runs, so the two front ends cannot drift apart.
cp "$DECANTER_ROOT/cli/decanter" "$app/Contents/SharedSupport/cli/decanter"
chmod +x "$app/Contents/SharedSupport/cli/decanter"

if (( with_runtime )); then
    runtime="$out/runtime"
    if [[ ! -x "$runtime/bin/wine" ]]; then
        log "no packaged runtime yet, making one"
        "$DECANTER_ROOT/scripts/package-runtime.sh" "$runtime"
    fi
    log "carrying $(du -sh "$runtime" | cut -f1) of runtime"
    cp -Rc "$runtime" "$app/Contents/SharedSupport/runtime"
else
    warn "no runtime inside the app: it will use the one installed for the user"
fi

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Decanter</string>
    <key>CFBundleDisplayName</key><string>Decanter</string>
    <key>CFBundleIdentifier</key><string>dev.decanter.app</string>
    <key>CFBundleExecutable</key><string>Decanter</string>
    <key>CFBundleIconFile</key><string>decanter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

log "signing ad-hoc, deepest first"
# The runtime carries its own libraries and helpers; they are signed by package-runtime.sh, and
# the bundle around them has to be signed after, not before.
codesign --force --sign - "$app" 2>/dev/null || true

log "done: $app ($(du -sh "$app" | cut -f1))"
