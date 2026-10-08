#!/usr/bin/env bash
# Put Decanter.app into a disk image: the app beside a link to Applications, compressed. What a
# release publishes and what a Homebrew cask would download.
#
#   scripts/make-dmg.sh [Decanter.app]      (default: build/package/Decanter.app)
#
# Build the app first, and with its runtime: scripts/build-app.sh --release
set -euo pipefail

source "$(dirname "$0")/env.sh"

APP="${1:-$DECANTER_ROOT/build/package/Decanter.app}"
[[ -d "$APP" ]] || die "no $APP: run scripts/build-app.sh first"

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.1.0)
out="$DECANTER_ROOT/build/package/Decanter-$version.dmg"

if [[ ! -d "$APP/Contents/SharedSupport/runtime/bin" ]]; then
    warn "this app carries no runtime: it will only work on a Mac that has one installed"
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
# A clone, so staging costs neither time nor space; the image is made from the copy.
cp -Rc "$APP" "$stage/Decanter.app"
ln -s /Applications "$stage/Applications"

rm -f "$out"
log "compressing $(du -sh "$APP" | cut -f1) into $out"
# ULMO is the most compressed read-only format hdiutil offers for an image that only has to be
# opened and dragged from.
hdiutil create -quiet -volname "Decanter $version" -srcfolder "$stage" -fs APFS -format ULMO "$out"

log "built $out ($(du -h "$out" | cut -f1))"
log "sha256 $(shasum -a 256 "$out" | cut -d' ' -f1)"
