#!/usr/bin/env bash
# Make an installed runtime independent of the directory it was built in.
#
# Meson installs with the build-time prefix recorded as each library's install name, and Wine
# does the same, so a runtime copied out of a build tree still resolves its own libraries
# through the build tree. Delete the tree and the runtime stops working; ship it and it points
# at a path that exists on one machine only.
#
# This rewrites those references to @rpath/@loader_path, which are relative to the library that
# contains them.
#
#   scripts/make-runtime-portable.sh [runtime-directory]
set -euo pipefail

RUNTIME="${1:-${DECANTER_HOME:-$HOME/.local/share/decanter}/runtime}"
[[ -d "$RUNTIME" ]] || { echo "no runtime at $RUNTIME" >&2; exit 1; }

changed=0
rewrite() {
    local file="$1" old="$2" new="$3"
    install_name_tool -change "$old" "$new" "$file" 2>/dev/null && changed=$((changed + 1)) || true
}

echo "==> libraries whose install name is an absolute path"
while IFS= read -r file; do
    # A dylib's own install name, and every dependency that names a build directory.
    while IFS= read -r dep; do
        case "$dep" in
            /Users/*|/opt/*|/private/*)
                # Only rewrite a dependency this runtime actually carries. Rewriting one it
                # does not carry -- SPIRV-Tools, say, which comes from Homebrew -- turns a
                # working absolute path into an @rpath that resolves to nothing, and the
                # library stops loading. That happened, and Wine silently fell back to a
                # different Vulkan driver.
                if [[ -e "$RUNTIME/$(basename "$dep")" ]] \
                   || find "$RUNTIME" -name "$(basename "$dep")" -print -quit 2>/dev/null | grep -q .; then
                    rewrite "$file" "$dep" "@rpath/$(basename "$dep")"
                fi
                ;;
        esac
    done < <(otool -L "$file" 2>/dev/null | tail -n +2 | awk '{print $1}')

    case "$(file -b "$file" 2>/dev/null)" in
        *shared\ library*|*dynamically\ linked*)
            name="$(basename "$file")"
            if otool -D "$file" 2>/dev/null | tail -1 | grep -q '^/'; then
                install_name_tool -id "@rpath/$name" "$file" 2>/dev/null && changed=$((changed + 1)) || true
            fi
            # Give every library a way to find its siblings.
            install_name_tool -add_rpath "@loader_path" "$file" 2>/dev/null || true
            ;;
    esac
done < <(find "$RUNTIME" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null)

echo "==> $changed references rewritten"
echo "==> anything left whose dependencies name an absolute path:"
left=0
while IFS= read -r file; do
    # tail -n +2: the first line of otool -L is the file's own path, not a dependency, and
    # counting that reported every file as broken.
    if otool -L "$file" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -q "^/Users/\|^/opt/"; then
        printf '  %s\n' "${file#"$RUNTIME"/}"
        left=$((left + 1))
    fi
done < <(find "$RUNTIME" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null)
[[ $left == 0 ]] && echo "  none"
exit 0
