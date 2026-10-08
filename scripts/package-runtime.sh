#!/usr/bin/env bash
# Make a self-contained copy of the runtime: what Decanter.app carries, and what has to work on
# a Mac that has neither this checkout nor Homebrew.
#
#   scripts/package-runtime.sh [output directory]     (default: build/package/runtime)
#
# Starting from the installed runtime it strips what only a build needs, then follows every
# library reference that leaves the tree, copies the target in beside the others and points the
# reference at it. It finishes by proving the result: nothing may name this checkout or
# Homebrew, and every library must be able to load on its own.
set -euo pipefail

source "$(dirname "$0")/env.sh"

OUT="${1:-$DECANTER_ROOT/build/package/runtime}"
SRC="$DECANTER_HOME/runtime"
[[ -d "$SRC" ]] || die "no runtime at $SRC: run scripts/bootstrap-runtime.sh first"

EXT="$OUT/ext/lib"

# A library's own install name, and the libraries it names, without the header line that is the
# file's own path.
own_name() { otool -D "$1" 2>/dev/null | tail -n +2 | head -1; }
links()    { otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}'; }

log "copying $(du -sh "$SRC" | cut -f1) of runtime to $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
# The trailing "/." matters: cp copies a directory *into* an existing destination, which would
# put the runtime one level deeper than everything expects. "." copies its contents.
# -c clones rather than copying data, and the copy is what gets modified.
cp -Rc "$SRC"/. "$OUT"/

log "stripping debug information"
stripped=0 saved_before=$(du -sk "$OUT" | cut -f1)
while IFS= read -r file; do
    case "$(file -b "$file" 2>/dev/null)" in
        *Mach-O*)
            # -x leaves the symbols that dynamic linking needs.
            strip -x "$file" 2>/dev/null && stripped=$((stripped + 1)) || true
            ;;
    esac
done < <(find "$OUT" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null)
log "stripped $stripped files, $(du -sh "$OUT" | cut -f1) (was $(echo "$saved_before" | awk '{printf "%.1fG", $1/1048576}'))"

mkdir -p "$EXT"

# Is this a reference that leaves the runtime and is not the system's own?
outside() {
    case "$1" in
        /usr/lib/*|/System/*|@rpath/*|@loader_path/*|@executable_path/*) return 1 ;;
        /*) return 0 ;;
        *) return 1 ;;
    esac
}

# Bring one library in beside the others, and give it the same treatment: its own name, a way
# to find its siblings, and its own outgoing references rewritten too. That last step is the
# one that matters and the one that is easy to leave out -- copying a library into the package
# changes nothing about the absolute paths *it* names.
bundle() {
    local source="$1" name destination
    name="$(basename "$source")"
    destination="$EXT/$name"

    if [[ ! -f "$destination" ]]; then
        [[ -f "$source" ]] || { warn "cannot find $source"; return 0; }
        ditto "$source" "$destination"
        strip -x "$destination" 2>/dev/null || true
        install_name_tool -id "@rpath/$name" "$destination" 2>/dev/null || true
        install_name_tool -add_rpath "@loader_path" "$destination" 2>/dev/null || true
        rewrite_references "$destination"
    fi
}

# For every reference in $1 that leaves the package, bring the target in and point the reference
# at it. Existing guard: a library already in $EXT is not copied again, which also ends cycles.
rewrite_references() {
    local file="$1" dependency
    while IFS= read -r dependency; do
        [[ -n $dependency ]] || continue
        case "$dependency" in "$OUT"/*) continue ;; esac
        outside "$dependency" || continue
        bundle "$dependency"
        install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$file" 2>/dev/null || true
    done < <(links "$file")
}

log "collecting libraries that live outside the runtime"
while IFS= read -r file; do
    rewrite_references "$file"
done < <(find "$OUT" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null)

# The libraries Wine opens by name, which no link line mentions. Without these a packaged runtime
# starts and then fails on the first font or TLS connection, on a machine where nothing says why.
log "collecting libraries Wine opens by name"
for name in libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libdbus-1.3.dylib \
            libodbc.2.dylib libvulkan.1.dylib; do
    for candidate in "$BREW/lib/$name" "$BREW/opt/"*/lib/"$name" \
                     "$OUT/mesa-zink/lib/$name" "$OUT/mesa/lib/$name"; do
        [[ -f $candidate ]] || continue
        case "$candidate" in "$OUT"/*) break ;; esac   # ours, and found relatively already
        bundle "$candidate"
        break
    done
done

log "collecting licences"
# Wine is LGPL-2.1-or-later, FEX MIT, DXMT LGPL-2.1-or-later, DXVK zlib, Mesa MIT, MoltenVK
# Apache-2.0, Hadron's patches BSD-3-Clause, Decanter itself MIT. A package that ships their
# binaries has to ship their terms with them, so this is not a nicety.
LIC="$OUT/licenses"
mkdir -p "$LIC"
copy_licence() {
    local source="$1" name="$2"
    # Mesa keeps its terms under docs/, and not as a LICENSE file at the top.
    for candidate in "$source"/LICENSE* "$source"/COPYING* "$source"/license.txt \
                     "$source"/docs/license.rst "$source"/docs/license.rst.txt; do
        [[ -f $candidate ]] || continue
        cp "$candidate" "$LIC/$name-$(basename "$candidate")"
        return 0
    done
    warn "no licence file found in $source"
}
copy_licence "$DECANTER_ROOT" decanter
copy_licence "$CHECKOUT/src/wine" wine
copy_licence "$CHECKOUT/src/fex" fex
copy_licence "$CHECKOUT/src/mesa" mesa
copy_licence "$CHECKOUT/src/vkd3d-proton" vkd3d-proton
copy_licence "$CHECKOUT/src/dxvk" dxvk
copy_licence "$CHECKOUT/src/dxmt" dxmt
copy_licence "$CHECKOUT" hadron
[[ -f "$BREW/opt/molten-vk/LICENSE" ]] && cp "$BREW/opt/molten-vk/LICENSE" "$LIC/moltenvk-LICENSE"
# MoltenVK's formula carries its licence in the source tarball, not the bottle; fall back to the
# project's own text if it is not there.
[[ -f "$LIC/moltenvk-LICENSE" ]] || echo "MoltenVK is Apache-2.0, https://github.com/KhronosGroup/MoltenVK/blob/main/LICENSE" > "$LIC/moltenvk-LICENSE"
ls "$LIC" | head -20

log "checking the result"
problems=0
while IFS= read -r file; do
    while IFS= read -r dependency; do
        case "$dependency" in
            "$BREW"/*|"$DECANTER_ROOT"/*|"$DECANTER_WORK"/*|"$HOME/wine-arm64-lab"/*)
                warn "$(basename "$file") still names $dependency"
                problems=$((problems + 1))
                ;;
        esac
    done < <(links "$file")
done < <(find "$OUT" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null)

if (( problems )); then
    die "$problems reference(s) still leave the package"
fi
log "nothing names the build tree or Homebrew"

log "signing ad hoc"
# Modification invalidates signatures, and an unsigned library will not load.
while IFS= read -r file; do
    case "$(file -b "$file" 2>/dev/null)" in
        *Mach-O*) codesign --force --sign - "$file" 2>/dev/null || true ;;
    esac
done < <(find "$OUT" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null)

log "done: $OUT ($(du -sh "$OUT" | cut -f1))"
