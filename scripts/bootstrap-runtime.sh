#!/usr/bin/env bash
# Build the arm64 Wine + FEX runtime that Decanter runs applications with, and the graphics
# stack it presents through.
#
#   scripts/bootstrap-runtime.sh [--dev|--release]
#
# The macOS arm64 enablement work — the Wine patches, the FEX Darwin patches, the build order,
# the graphics stack — is Hadron's (BSD-3-Clause, https://github.com/Broyojo/hadron). This
# script pins a Hadron revision, builds the parts Decanter needs, applies Decanter's own
# patches on top, and installs the result as a runtime.
#
#   --dev      (default) no Apple Developer account needed; 64-bit programs only
#   --release  needs a provisioning profile carrying
#              com.apple.developer.cross-architecture-support; 32-bit programs too
set -euo pipefail

DECANTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$DECANTER_ROOT/scripts/env.sh"

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

# The two variants differ in one Wine build flag. --dev moves Windows' low addresses above 4 GB
# so that no restricted entitlement is needed, at the cost of 32-bit programs. --release leaves
# them where Windows expects, and then the loader must be signed with
# com.apple.developer.cross-architecture-support or the kernel kills it at startup.
#
# --release builds and packages without any signing identity. It runs 64-bit programs as it is;
# 32-bit programs need the loader signed, which scripts/sign-loader.sh does with a provisioning
# profile, and which can be done by anyone holding one. See docs/release-signing.md.
WINE_VARIANT_FLAG="--dev"
INSTALL_TREE="dist-dev"
if [[ $VARIANT == release ]]; then
    WINE_VARIANT_FLAG=""
    INSTALL_TREE="dist"
fi

log "installing build dependencies (arm64 Homebrew)"
# vulkan-loader must be here *before* Wine is configured. Wine's configure prefers the Khronos
# loader and falls back to MoltenVK; a Wine built with the fallback opens MoltenVK directly, so
# VK_DRIVER_FILES does nothing, the runtime's own Vulkan driver never loads, and a program sees
# fewer device extensions than the driver really has. That is invisible until something needs
# one of the missing ones.
brew install llvm lld bison flex meson ninja cmake pkg-config freetype gnutls \
    molten-vk vulkan-loader vulkan-headers libclc spirv-llvm-translator spirv-tools \
    glslang 2>&1 | tail -3

if [[ ! -d "$CHECKOUT/.git" ]]; then
    log "cloning Hadron at $HADRON_REF"
    mkdir -p "$DECANTER_WORK"
    git clone --filter=blob:none "$HADRON_REPO" "$CHECKOUT"
fi
log "checking out Hadron $HADRON_REF"
git -C "$CHECKOUT" fetch --quiet origin "$HADRON_REF" 2>/dev/null || true
git -C "$CHECKOUT" checkout --quiet --detach "$HADRON_REF" || die "cannot check out $HADRON_REF"

log "toolchain"
"$CHECKOUT/scripts/setup-toolchain.sh"

# --- sources ------------------------------------------------------------------------------
# Hadron's fetch.sh clones each component at its pinned revision and applies Hadron's patches.
# Ours go on top, from this repository, so that what Decanter changes is in one place and can
# be read without diffing two trees.
fetch_and_patch() {
    local name="$1"
    # Hadron's fetch.sh checks the component out at its pinned revision, and git refuses to do
    # that over a modified tree -- which is exactly the state a previous run leaves behind, since
    # our patches are applied to the working tree rather than committed. So start clean.
    if [[ -d "$CHECKOUT/src/$name/.git" ]]; then
        git -C "$CHECKOUT/src/$name" reset --hard -q 2>/dev/null || true
    fi
    "$CHECKOUT/scripts/fetch.sh" "$name"
    # A fetch that loses its connection leaves submodules half-checked-out, and the build then
    # fails much later with a missing CMakeLists.txt. Hadron's script does this too; a network
    # that drops once in a while makes doing it twice worthwhile.
    if [[ -d "$CHECKOUT/src/$name/.git" ]]; then
        # --force, not just --init: a submodule whose path was moved in .gitmodules keeps a stale
        # gitdir, git decides it is already at the right commit and checks nothing out, and the
        # build then fails much later with a directory that exists and is empty. FEX's
        # cpp-optparse is exactly that case.
        for attempt in 1 2 3; do
            git -C "$CHECKOUT/src/$name" submodule update --init --recursive --filter=blob:none \
                --force --checkout -q 2>/dev/null && break
            sleep 5
        done
    fi
    local patches=("$DECANTER_ROOT/patches/$name"/*.patch)
    if [[ -e ${patches[0]} ]]; then
        log "applying ${#patches[@]} Decanter patch(es) to $name"
        # git apply, not git am: these are plain diffs from git diff rather than mailbox files,
        # and am refuses them with "Patch format detection failed".
        git -C "$CHECKOUT/src/$name" apply --3way "${patches[@]}"
    fi
}

log "fetching sources at Hadron's pinned revisions"
for component in wine fex mesa mesa-zink vkd3d-proton dxvk; do
    case $component in
        mesa-zink) ;; # built from the mesa checkout
        *) fetch_and_patch "$component" ;;
    esac
done
# Mesa's own submodules are needed before its patches will compile.
git -C "$CHECKOUT/src/mesa" submodule update --init --recursive --depth 1

# --- builds ---------------------------------------------------------------------------------
# PATH order is the whole trick for anything Meson-configured here:
#   /usr/bin first        -> clang, cc and c++ are Apple's, which can find Xcode's SDK
#   Homebrew after        -> llvm-ar and friends, which Mesa asks for by bare name
# Homebrew's llvm/bin must never win, or clang looks for its sysroot under CommandLineTools,
# where a machine whose only SDK is Xcode's has nothing, and the failure names no compiler.
APPLE_FIRST_PATH="/usr/bin:/bin:/usr/sbin:/sbin:$BREW/bin:$BREW/opt/llvm/bin:$BREW/opt/bison/bin"

mesa_venv="$CHECKOUT/build/venv-mesa"
if [[ ! -x "$mesa_venv/bin/python" ]]; then
    log "creating Mesa's Python environment"
    python3 -m venv "$mesa_venv"
    "$mesa_venv/bin/pip" install -q mako packaging pyyaml
fi

log "building Wine natively for arm64 macOS ($VARIANT, $JOBS jobs)"
PATH="$BREW/bin:$PATH" "$CHECKOUT/scripts/build-wine.sh" $WINE_VARIANT_FLAG

log "building FEX's emulator DLLs"
# The same FEX build serves both variants; only where it is installed differs, and it has to land
# in the same tree Wine did or the runtime comes out without an emulator. "${VAR:-default}" would
# read as "use --dev when the flag is empty", which is exactly backwards for a release build.
if [[ $VARIANT == dev ]]; then
    "$CHECKOUT/scripts/build-fex.sh" --dev
else
    "$CHECKOUT/scripts/build-fex.sh"
fi

log "building KosmicKrisp (Vulkan on Metal)"
rm -rf "$CHECKOUT/build/mesa"
PATH="$mesa_venv/bin:$APPLE_FIRST_PATH" \
    CC=/usr/bin/clang CXX=/usr/bin/clang++ OBJC=/usr/bin/clang \
    PKG_CONFIG_PATH="$BREW/opt/llvm/lib/pkgconfig:$BREW/lib/pkgconfig" \
    meson setup "$CHECKOUT/build/mesa" "$CHECKOUT/src/mesa" \
        --buildtype=debugoptimized --prefix="$CHECKOUT/dist/mesa" \
        -Dplatforms=macos -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= \
        -Dopengl=false -Dzstd=disabled --prefer-static >/dev/null
PATH="$mesa_venv/bin:$APPLE_FIRST_PATH" ninja -C "$CHECKOUT/build/mesa" install >/dev/null

log "building Zink (OpenGL on Vulkan)"
rm -rf "$CHECKOUT/build/mesa-zink"
PATH="$mesa_venv/bin:$APPLE_FIRST_PATH" \
    CC=/usr/bin/clang CXX=/usr/bin/clang++ OBJC=/usr/bin/clang \
    PKG_CONFIG_PATH="$BREW/opt/llvm/lib/pkgconfig:$BREW/lib/pkgconfig" \
    meson setup "$CHECKOUT/build/mesa-zink" "$CHECKOUT/src/mesa" \
        --buildtype=debugoptimized --prefix="$CHECKOUT/dist/mesa-zink" \
        -Dplatforms=macos -Dvulkan-drivers=kosmickrisp -Dgallium-drivers=zink \
        -Dopengl=true -Degl=enabled -Dgles2=enabled -Dglx=disabled -Dzstd=disabled \
        -Ddraw-use-llvm=false -Dmoltenvk-dir="$BREW/opt/molten-vk" \
        -Dvulkan-loader-rpath="$BREW/lib" >/dev/null
PATH="$mesa_venv/bin:$APPLE_FIRST_PATH" ninja -C "$CHECKOUT/build/mesa-zink" install >/dev/null

log "building vkd3d-proton (Direct3D 12) and DXVK"
# Hadron's script builds DXVK's DXGI only, for vkd3d-proton to present through. Decanter also
# wants DXVK's Direct3D 9, so that build is its own call with d3d9 on.
"$CHECKOUT/scripts/build-vulkan.sh" vkd3d-proton dxvk
rm -rf "$CHECKOUT/build/dxvk-d3d9"
PATH="$CHECKOUT/toolchains/llvm-mingw/bin:$PATH" meson setup "$CHECKOUT/build/dxvk-d3d9" "$CHECKOUT/src/dxvk" \
    --cross-file "$CHECKOUT/build/x86_64-mingw.cross" --buildtype=release \
    --prefix="$CHECKOUT/dist/dxvk-d3d9" --bindir=x64 --libdir=x64 \
    -Denable_d3d8=false -Denable_d3d9=true -Denable_d3d10=false -Denable_d3d11=false >/dev/null
PATH="$CHECKOUT/toolchains/llvm-mingw/bin:$PATH" ninja -C "$CHECKOUT/build/dxvk-d3d9" install >/dev/null

# --- install ---------------------------------------------------------------------------------
log "installing runtime into $RUNTIME"
rm -rf "$RUNTIME"
mkdir -p "$RUNTIME"
ditto "$CHECKOUT/$INSTALL_TREE" "$RUNTIME"
echo "$VARIANT" > "$RUNTIME/variant"
echo "$HADRON_REF" > "$RUNTIME/hadron-pin"

for part in mesa mesa-zink vkd3d-proton dxvk; do
    [[ -d "$CHECKOUT/dist/$part" ]] || continue
    rm -rf "$RUNTIME/$part"
    ditto "$CHECKOUT/dist/$part" "$RUNTIME/$part"
done
mkdir -p "$RUNTIME/dxvk/x64"
ditto "$CHECKOUT/dist/dxvk-d3d9/x64/d3d9.dll" "$RUNTIME/dxvk/x64/d3d9.dll"

log "pointing the Vulkan manifest at this runtime"
# The manifest Meson installed names the build directory it was configured with.
python3 - "$RUNTIME" <<'PY'
import json, pathlib, sys
runtime = pathlib.Path(sys.argv[1])
for manifest in (runtime / "mesa/share/vulkan/icd.d").glob("*.json"):
    data = json.loads(manifest.read_text())
    stem = pathlib.Path(data["ICD"]["library_path"]).name
    data["ICD"]["library_path"] = str(runtime / "mesa/lib" / stem)
    manifest.write_text(json.dumps(data, indent=4) + "\n")
    print(f"  {manifest.name} -> {data['ICD']['library_path']}")
PY

log "making the runtime independent of the build directory"
"$DECANTER_ROOT/scripts/make-runtime-portable.sh" "$RUNTIME"

if [[ $VARIANT == release ]]; then
    log "checking the loader's entitlement"
    loader="$RUNTIME/lib/wine/aarch64-unix/wine"
    carried=$(codesign -d --entitlements - "$loader" 2>/dev/null | grep -c "cross-architecture-support" || true)
    if (( carried )); then
        log "the loader carries the cross-architecture entitlement"
    else
        warn "the loader does NOT carry com.apple.developer.cross-architecture-support."
        warn "This runtime runs 64-bit programs. 32-bit programs need the loader signed with it:"
        warn "    scripts/sign-loader.sh <profile.provisionprofile> <identity>"
        warn "docs/release-signing.md explains where a profile comes from."
    fi
fi

log "done"
if grep -qa "libMoltenVK.dylib" "$RUNTIME/lib/wine/aarch64-unix/win32u.so" 2>/dev/null; then
    warn "this Wine opens MoltenVK instead of the Khronos loader, so it will ignore"
    warn "VK_DRIVER_FILES and use fewer extensions than the driver offers."
    warn "Install vulkan-loader and build Wine again."
fi
"$DECANTER_ROOT/cli/decanter" doctor
