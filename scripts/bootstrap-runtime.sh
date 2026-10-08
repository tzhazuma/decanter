#!/usr/bin/env bash
# Build the arm64 Wine + FEX runtime that Decanter runs applications with.
#
#   scripts/bootstrap-runtime.sh [--dev|--release]
#
# The macOS arm64 enablement work — the Wine patches, the FEX Darwin patches, the build
# order — is Hadron's (BSD-3-Clause, https://github.com/Broyojo/hadron). This script pins
# a Hadron revision, builds the two components Decanter needs (Wine and FEX, not the
# Steam bridge or the game graphics stack), and installs the result as a runtime.
#
#   --dev      (default) no Apple Developer account needed; 64-bit programs only
#   --release  needs a provisioning profile carrying
#              com.apple.developer.cross-architecture-support; 32-bit programs too

source "$(dirname "$0")/env.sh"

VARIANT=dev
for arg in "$@"; do
    case $arg in
        --dev) VARIANT=dev ;;
        --release) VARIANT=release ;;
        *) die "unknown option $arg" ;;
    esac
done

# Pinned: the Hadron revision whose patches and build scripts this project was tested with.
HADRON_REPO="${HADRON_REPO:-https://github.com/Broyojo/hadron.git}"
HADRON_REF="${HADRON_REF:-3e7043aa4264aab9d598ff6d52d49ac53d0fca00}"

CHECKOUT="$DECANTER_WORK/hadron"
RUNTIME="$DECANTER_HOME/runtime"

if [[ $VARIANT == release ]]; then
    die "--release needs a provisioning profile; see docs/entitlement.md and use Hadron's scripts directly for now"
fi

log "installing build dependencies (arm64 Homebrew)"
brew install llvm lld bison meson ninja cmake pkg-config freetype gnutls 2>&1 | tail -3

if [[ ! -d "$CHECKOUT/.git" ]]; then
    log "cloning Hadron at $HADRON_REF"
    mkdir -p "$DECANTER_WORK"
    git clone --filter=blob:none "$HADRON_REPO" "$CHECKOUT"
fi
log "checking out Hadron $HADRON_REF"
git -C "$CHECKOUT" fetch --quiet origin "$HADRON_REF" 2>/dev/null || true
git -C "$CHECKOUT" checkout --quiet --detach "$HADRON_REF" || die "cannot check out $HADRON_REF"
echo "$HADRON_REF" > "$CHECKOUT/.decanter-pin"

log "toolchain"
"$CHECKOUT/scripts/setup-toolchain.sh"

log "fetching Wine and FEX sources at Hadron's pinned revisions"
"$CHECKOUT/scripts/fetch.sh" wine fex

log "building Wine natively for arm64 macOS ($VARIANT variant, $JOBS jobs)"
"$CHECKOUT/scripts/build-wine.sh" --dev

log "building FEX's emulator DLLs"
"$CHECKOUT/scripts/build-fex.sh" --dev

log "installing runtime into $RUNTIME"
rm -rf "$RUNTIME"
mkdir -p "$RUNTIME"
# dist-dev is a self-contained tree: bin/, lib/wine/<arch>-windows/, lib/wine/<arch>-unix/
ditto "$CHECKOUT/dist-dev" "$RUNTIME"
echo "$VARIANT" > "$RUNTIME/variant"

log "making the runtime independent of the build directory"
# Meson and Wine record their build-time prefix as each library's install name, so a runtime
# copied out of a tree still resolves its own libraries through that tree.
"$DECANTER_ROOT/scripts/make-runtime-portable.sh" "$RUNTIME"
echo "$HADRON_REF" > "$RUNTIME/hadron-pin"

log "done"
"$DECANTER_ROOT/cli/decanter" doctor
