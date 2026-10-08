#!/usr/bin/env bash
# Sign the Wine loader with a provisioning profile, so it may carry
# com.apple.developer.cross-architecture-support and map memory below 4 GB.
#
#   scripts/sign-loader.sh <profile.provisionprofile> [identity] [--runtime] [runtime directory]
#
#   identity   defaults to the first "Apple Development" identity in the keychain
#   --runtime  enable the hardened runtime, which notarised distribution requires
#
# Only 32-bit programs need this. A runtime built by bootstrap-runtime.sh --dev cannot carry the
# entitlement at all, and one built with --release runs 64-bit programs unsigned: it is 32-bit
# programs that need the loader signed, because a 32-bit Windows process can only address memory
# below 4 GB and macOS only grants that to a process holding this entitlement.
#
# The mechanics are Hadron's (BSD-3-Clause): wrap the loader in a small .app, because a restricted
# entitlement is only valid on a bundle carrying an embedded provisioning profile, and leave the
# paths Wine expects pointing into it.
set -euo pipefail

source "$(dirname "$0")/env.sh"

profile=""; identity=""; hardened=(); runtime_dir="$DECANTER_HOME/runtime"
positional=()
for arg in "$@"; do
    case $arg in
        --runtime) hardened=(--options runtime) ;;
        *) positional+=("$arg") ;;
    esac
done
profile="${positional[0]:-}"
[[ -n ${positional[1]:-} ]] && identity="${positional[1]}"
[[ -n ${positional[2]:-} ]] && runtime_dir="${positional[2]}"

[[ -f $profile ]] || die "usage: $0 <profile.provisionprofile> [identity] [--runtime] [runtime directory]"
[[ -d "$runtime_dir/lib/wine/aarch64-unix" ]] || die "no runtime at $runtime_dir"

if [[ -z $identity ]]; then
    # By SHA-1 hash: several certificates can share a name.
    identity=$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ { print $2; exit }')
    [[ -n $identity ]] || die "no signing identity found; create one in Xcode > Settings > Accounts"
fi

unix_dir="$runtime_dir/lib/wine/aarch64-unix"
app="$unix_dir/wine.app"
work="$DECANTER_ROOT/build/sign-loader"
mkdir -p "$work"

log "reading $profile"
security cms -D -i "$profile" > "$work/profile.plist"

python3 - "$work/profile.plist" "$work/entitlements.plist" "$work/bundle-id" "${#hardened[@]}" <<'EOF'
import plistlib, sys

profile = plistlib.load(open(sys.argv[1], "rb"))
entitlements = dict(profile["Entitlements"])

# The one that matters. Without it in the profile itself there is nothing to sign with, and the
# portal is where it has to be enabled: the capability is called Cross-architecture Compatibility
# Framework, and it has to be set on the App ID before the profile is generated.
if not any(k.startswith("com.apple.developer.cross-architecture-support") for k in entitlements):
    sys.exit("this profile does not grant com.apple.developer.cross-architecture-support:\n"
             "  enable Cross-architecture Compatibility Framework on the loader's App ID,\n"
             "  then generate the profile again. docs/release-signing.md has the steps.")

app_id = entitlements["com.apple.application-identifier"]
open(sys.argv[3], "w").write(app_id.split(".", 1)[1])

# Wine needs this one and it is not restricted, so it does not have to come from the profile.
entitlements["com.apple.security.custom-x18-abi-toggle"] = True

if sys.argv[4] != "0":  # hardened runtime
    # The runtime loads its own unixlibs and bundled dylibs at run time, and compiles shaders
    # into executable memory; the hardened runtime forbids all of that unless asked not to.
    entitlements["com.apple.security.cs.allow-jit"] = True
    entitlements["com.apple.security.cs.allow-unsigned-executable-memory"] = True
    entitlements["com.apple.security.cs.allow-dyld-environment-variables"] = True
    entitlements["com.apple.security.cs.disable-library-validation"] = True

plistlib.dump(entitlements, open(sys.argv[2], "wb"))
print("entitlements:", ", ".join(sorted(entitlements)))
EOF
bundle_id=$(cat "$work/bundle-id")

# The loader, on a first run or already wrapped by a previous one.
if [[ -f $unix_dir/wine && ! -L $unix_dir/wine ]]; then
    loader="$unix_dir/wine"
elif [[ -f "$app/Contents/MacOS/wine" ]]; then
    loader="$app/Contents/MacOS/wine"
else
    die "no Wine loader in $unix_dir"
fi

log "wrapping it in $app ($bundle_id)"
mkdir -p "$app/Contents/MacOS"
if [[ $loader != "$app/Contents/MacOS/wine" ]]; then
    rm -f "$app/Contents/MacOS/wine"
    mv "$loader" "$app/Contents/MacOS/wine"
fi
cp "$profile" "$app/Contents/embedded.provisionprofile"

version=$("$app/Contents/MacOS/wine" --version 2>/dev/null | sed 's/^wine-//' || echo 0)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>wine</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleName</key><string>Decanter Loader</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>26.5</string>
    <key>NSPrincipalClass</key><string>WineApplication</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Wine execs the loader by these paths for every process it starts, so they have to lead into
# the bundle and not to a loose binary.
ln -sfn wine.app/Contents/MacOS/wine "$unix_dir/wine"
rm -f "$runtime_dir/bin/wine"
ln -s ../lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine "$runtime_dir/bin/wine"

log "signing with \"$identity\""
codesign --force --sign "$identity" --entitlements "$work/entitlements.plist" \
    ${hardened[@]+"${hardened[@]}"} "$app"
codesign --verify --strict "$app"

log "done. The signature carries:"
codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - | sed 's/^/    /'
cat <<'AFTER'

A runtime signed this way runs 32-bit programs. If the app wrapped around it was signed ad-hoc,
sign the app again too, after this: the loader inside it has just changed.

    codesign --force --deep --sign "$IDENTITY" /path/to/Decanter.app
    xcrun notarytool submit /path/to/Decanter.app --wait    # for distribution
AFTER
