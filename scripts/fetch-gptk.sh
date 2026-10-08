#!/usr/bin/env bash
# Install Apple's D3DMetal into the runtime, from a copy the user downloads themselves.
#
#   scripts/fetch-gptk.sh [path/to/Game_Porting_Toolkit.dmg]
#
# Decanter never downloads, bundles or mirrors Apple's binaries. Apple's licence does not
# allow redistributing them, so this script does what every tool in this space does: it
# mounts the disk image the user already has, copies the libraries out of it, and stops. If
# the image is not there, it says where to get it and exits.
#
# Read the licence before you run this. You are accepting Apple's terms, not ours.
set -euo pipefail

source "$(dirname "$0")/env.sh"

RUNTIME="$DECANTER_HOME/runtime"
[[ -d "$RUNTIME" ]] || die "no runtime at $RUNTIME; run scripts/bootstrap-runtime.sh first"

# Where the libraries have to land. D3DMetal plugs in beside Wine's other unix-side
# libraries, the way CrossOver ships it in apple_gptk/external.
TARGET="$RUNTIME/lib/wine/aarch64-unix"
[[ -d "$TARGET" ]] || die "no $TARGET; is the runtime complete?"

log "Apple's Game Porting Toolkit"
cat <<'NOTICE'
  Apple publishes the toolkit at:
      https://developer.apple.com/download/all/?q=game%20porting%20toolkit
  It needs a (free) Apple ID to download, and the licence permits personal evaluation and
  testing only -- not redistribution, and not shipping a product on it. Decanter does not
  obtain it for you; this script only installs a copy you fetched yourself.

NOTICE

# Find the image: an argument, then $GPTK_DMG, then the obvious places.
dmg="${1:-${GPTK_DMG:-}}"
if [[ -z $dmg ]]; then
    while IFS= read -r candidate; do dmg="$candidate"; break; done < <(
        ls -t ~/Downloads/*.dmg ~/Desktop/*.dmg 2>/dev/null |
            grep -iE "game.?porting|gptk" || true)
fi
if [[ -z ${dmg:-} || ! -f $dmg ]]; then
    die "no toolkit disk image found. Download it, then pass it: scripts/fetch-gptk.sh ~/Downloads/Game_Porting_Toolkit.dmg"
fi
log "using $dmg"

mount_root=$(mktemp -d)
inner_mount=""
cleanup() {
    [[ -n $inner_mount ]] && hdiutil detach "$inner_mount" -quiet 2>/dev/null || true
    hdiutil detach "$mount_root" -quiet 2>/dev/null || true
    rmdir "$mount_root" 2>/dev/null || true
}
trap cleanup EXIT

log "mounting"
hdiutil attach "$dmg" -mountpoint "$mount_root" -nobrowse -quiet

# The toolkit ships a disk image inside the disk image. Find the payload either way.
source_dir="$mount_root/redist/lib/external"
if [[ ! -d $source_dir ]]; then
    inner=$(find "$mount_root" -maxdepth 2 -name "*.dmg" | head -1)
    [[ -n $inner ]] || die "no redist/lib/external in the image, and no nested image inside it"
    inner_mount=$(mktemp -d)
    log "mounting the evaluation environment inside it"
    hdiutil attach "$inner" -mountpoint "$inner_mount" -nobrowse -quiet
    source_dir="$inner_mount/redist/lib/external"
fi
[[ -d $source_dir ]] || die "no redist/lib/external at $source_dir"

log "the payload"
ls "$source_dir"

if [[ -d "$TARGET/D3DMetal.framework" ]]; then
    backup="$TARGET/D3DMetal.framework.replaced-$(date +%Y%m%d%H%M%S)"
    log "keeping the installed copy at $(basename "$backup")"
    mv "$TARGET/D3DMetal.framework" "$backup"
fi

log "installing into $TARGET"
ditto "$source_dir/." "$TARGET/"

log "done. This copy came from $dmg and is yours to keep; do not redistribute it."
cat <<'AFTER'

  One thing to know: the ARM64 runtime that Decanter builds today is a development build
  whose graphics path is DXMT. D3DMetal is loaded by winemac.drv, and an arm64 D3DMetal is
  not part of the preview releases yet -- CodeWeavers ship it in the x86_64 build only. If
  Wine reports that it could not load D3DMetal, that is why, and it is not something this
  script can fix: DXMT is the working Direct3D 11 path on arm64 today.
AFTER
