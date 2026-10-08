# Signing a runtime so it can run 32-bit programs

A released Decanter runtime runs 64-bit Windows programs as it comes. 32-bit ones need one extra
step, and this is how to do it. It needs an Apple Developer Program membership and about twenty
minutes.

## Why it is needed at all

Windows requires `KUSER_SHARED_DATA` at `0x7ffe0000` and other structures at fixed addresses, and
a 32-bit Windows process can only address memory below 4 GB. Granting a process an address space
that starts below 4 GB is what `com.apple.developer.cross-architecture-support` allows.

It is a **restricted** entitlement, which means AMFI will kill any process that carries it unless
an Apple-signed provisioning profile embedded in the bundle authorises it. Signing ad-hoc with the
entitlement does not work — the process dies at exec. That is not a detail of this project; it is
how the platform works.

There are two ways round it and one of them is not a way out:

| | |
|---|---|
| **This document** | a provisioning profile, which needs a paid Apple Developer Program membership |
| **`bootstrap-runtime.sh --dev`** | moves Windows' low addresses above 4 GB, so nothing is needed — and 32-bit programs cannot follow it there |
| Weakening SIP | works, is per-machine, and cannot be shipped to anyone. `docs/entitlement.md` |

## What is in the release, and what is not

The published disk image is a **development** runtime: 64-bit programs, no account needed. A
**release** runtime — the one that can run 32-bit programs once signed — is not published,
because building it takes about forty minutes and it cannot run anything until somebody signs
it. The scripts to build one are in the repository and are all that is needed:

```sh
scripts/bootstrap-runtime.sh --release      # builds it, and says what the loader still needs
scripts/sign-loader.sh <profile> --runtime  # signs the loader; anyone with a profile can
```

The bootstrap builds the release variant of Wine, FEX and the graphics stack, installs them as
a runtime in `~/.local/share/decanter/runtime`, and finishes by reading the loader's signature
and telling you whether it carries the entitlement — `codesign -d --entitlements` under the
hood. It runs 64-bit programs meanwhile, so a runtime built this way is not wasted while you
wait for an account.

## What you need

- An Apple Developer Program membership ($99/year). A free Apple ID cannot be used: the
  Certificates, Identifiers & Profiles section of the developer portal requires membership.
- A Mac with a signing identity in its keychain.

## One-time setup

1. **Two App IDs.** In <https://developer.apple.com/account/resources/identifiers>, add an App ID
   for the loader — `com.example.decanter.loader` is fine — and one for the app if you are also
   distributing a signed app. Restricted entitlements only belong on the loader.

2. **The capability.** Open the loader's App ID, enable **Cross-architecture Compatibility
   Framework**, and save. As of late 2026 this is self-serve; no request form.

3. **Certificates.** In Xcode, Settings → Accounts → Manage Certificates, add *Developer ID
   Application* for builds you give to other people, and *Apple Development* for your own machine.

4. **The profile.** Back in the portal, under Profiles, add a *Developer ID* profile for the
   loader's App ID and the Developer ID certificate, then download it. You get a
   `.provisionprofile` file.

## Signing

```sh
scripts/sign-loader.sh ~/Downloads/Decanter_Loader.provisionprofile
```

It finds your identity automatically, or takes one: `sign-loader.sh <profile> <identity>`.
Add `--runtime` when the result has to be notarised, which enables the hardened runtime and the
entitlements it needs — Wine loads its own libraries at run time and compiles shaders into
executable memory, which the hardened runtime forbids by default.

If the runtime you are signing sits inside a packaged app, sign the app again afterwards: the
loader inside it has just changed.

```sh
codesign --force --deep --sign "$IDENTITY" /Applications/Decanter.app
```

If you built the runtime yourself, sign it where it is
(`~/.local/share/decanter/runtime`) — or pass a directory as the last argument to sign a copy
somewhere else.

## Verifying

```sh
# The profile you were given must grant the entitlement.
security cms -D -i ~/Downloads/Decanter_Loader.provisionprofile | plutil -p - | grep -A12 Entitlements

# The loader must carry it, and be signed with your identity rather than ad-hoc.
codesign -d --entitlements - --xml ~/.local/share/decanter/runtime/lib/wine/aarch64-unix/wine.app | plutil -p -

# And it must actually start.
~/.local/share/decanter/runtime/bin/wine --version
```

Then a 32-bit program:

```sh
./cli/decanter run <bottle> ~/Downloads/some-32bit-program.exe
```

Wine's own built-in 32-bit programs are the quickest test: `./cli/decanter run <bottle> 'C:\windows\syswow64\cmd.exe' /c ver`.

## If something goes wrong

- **`this profile does not grant com.apple.developer.cross-architecture-support`** — the
  capability was not enabled on the App ID before the profile was generated, or the profile was
  made for a different App ID. Enable it and download a new one.
- **The process is killed the moment it starts, with no message** — the loader is signed but the
  profile did not authorise it. Check with the `codesign` command above; ad-hoc is not enough.
- **32-bit programs still fail with `c000000d`** — the runtime is the `--dev` variant. It cannot
  carry the entitlement by construction; build with `--release`.
- **Everything fails after signing** — the hardened runtime without `--runtime`'s entitlements
  will refuse to load Wine's libraries. Re-sign with `--runtime`, or without it if you are not
  notarising.

## What not to do

Do not ask users to disable SIP. It works on one machine, it lowers that machine's security
permanently, and it cannot be part of a release — which is the whole reason the entitlement exists
as a signing problem rather than a workaround.
