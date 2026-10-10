# The cross-architecture entitlement

Windows applications expect certain structures at fixed addresses below 4 GB, and
`KUSER_SHARED_DATA` at `0x7ffe0000`. macOS gives every process a PAGEZERO of at least 4 GB and
does not normally hand out a low address space, so a Wine loader that needs one must be
granted `com.apple.developer.cross-architecture-support`.

## Why the low pages are kept unmapped

`__PAGEZERO` — the segment every arm64 binary starts with — is 4 GB of *nothing*: address zero
to 0x100000000, no access, `filesize 0` (`otool -l /bin/bash` shows it). Its purpose is the
oldest defence in the book: a null or small pointer dereference lands there and faults
immediately, instead of reaching memory an attacker arranged. Whole exploit classes — null-page
mapping, low-address spraying — live in the low pages, and keeping them unmapped closes them.
The region above it, up to 0x7000000000, is the system's own layout — the main binary at
0x100000000, the dyld shared cache at 0x180000000 — and is not handed out either; an `mmap` at
0x7FFE0000 on this machine fails with "Cannot allocate memory".

Programs from other architectures need exactly what is forbidden here: x86 keeps fixed
structures below 4 GB (KUSER_SHARED_DATA at 0x7ffe0000, the TEB and PEB, image bases), and a
32-bit program's every pointer lives there. The entitlement unlocks an address space laid out
the way the foreign architecture expects — which is, in effect, permission to lower a security
boundary, so Apple issues it only per team, through provisioning profiles, and that is what a
Developer Program membership buys.

## Why it cannot be worked around

| Approach | Why it fails |
|---|---|
| Ad-hoc sign with the entitlement | AMFI kills the process; a restricted entitlement is only valid when authorised by an embedded provisioning profile |
| Disable SIP / boot-arg `amfi_get_out_of_my_way=1` | Works, but asking users to weaken their system security is not a shipping option, and CodeWeavers say the same |
| Move the structures above 4 GB | This is what the `--dev` build does. It works for 64-bit programs, which compute addresses themselves. It fails for 32-bit programs, whose pointers can only reach 4 GB |

## Getting it

Written from Hadron's `docs/apple-developer-setup.md`, which is the most complete public
description:

1. Register two explicit App IDs, one for the app and one for the loader — for example
   `com.example.decanter` and `com.example.decanter.loader`.
2. On the **loader** App ID only, enable the capability. In the portal it appears as
   *Cross-architecture Compatibility Framework*. As of 2026-09-29 it is self-serve.
3. Create certificates: *Apple Development* for local testing, *Developer ID Application*
   for distribution.
4. Register each development Mac using the Provisioning UDID from
   `system_profiler SPHardwareDataType`.
5. Create a profile for the loader App ID. Use a *macOS App Development* profile locally, and
   a *Developer ID* profile for builds other people will run.

Verify that a profile actually carries it:

```sh
security cms -D -i Decanter_Loader_Dev.provisionprofile | plutil -p - | grep -A12 Entitlements
```

The entitlement goes **only** on the loader bundle, never on the app or on general-purpose
tools. The loader ships as a small `.app` inside the main app, which is how CrossOver wraps
its loader in `wine.app`.

## Is there a free way around it?

Short answer: **yes, for one machine, at the cost of weakening that machine's security; and
no, not for anything you distribute.**

Measured on the target Mac (macOS 27.2, SIP enabled, `vm.cs_system_enforcement` = 1): a binary
signed ad-hoc **carrying** the entitlement is killed at exec, while the identical binary
without it runs. The entitlement is in the signature; AMFI refuses it because no provisioning
profile authorises it.

```
$ codesign -f -s - --entitlements cross-arch.plist ./enttest && ./enttest hi
Killed: 9                      # exit 137
$ codesign -f -s - ./enttest-clean && ./enttest-clean hi
control runs fine          # exit 0
```

### The three routes, cheapest first

**0. Free Apple ID, `-unmanaged` variant — free, expected to fail.** The `-unmanaged`
entitlement is documented by CodeWeavers as the free-account form of the same thing, and
Hadron's notes say the capability became self-serve on 2026-09-29. But App IDs and profiles
in the developer portal are a paid-program feature, and a user on wine-devel reported the
capability being neither visible nor addable on a free account. Worth five minutes to check;
do not plan around it.

**1. `amfi-allow` + `csrutil enable --without debug` — the least severe real option.**
[amfi-allow](https://github.com/Lakr233/amfi-allow) (MIT, tested on macOS 26 and 27) does not
patch `amfid`. It uses Apple's own mechanism: `AMFIRequirementsManager` reads
`/Library/Preferences/com.apple.security.coderequirements.plist` and takes its `Entitlements`
key as the requirement a binary must satisfy to be allowed restricted entitlements. Put a
binary's `cdhash` in there and AMFI itself permits that one binary. Then the loader can be
ad-hoc signed with the entitlement and it will run.

It still needs **`csrutil enable --without debug`**, which on Apple Silicon means booting into
Recovery, accepting Permissive Security, and changing SIP there. That cannot be done from a
running system — not by a script, and not by an agent.

Two details worth knowing: the allowlist lives in `amfid`'s memory as well as the plist, so it
must be re-applied after every reboot and every rebuild (a new signature means a new cdhash);
and the tool deliberately keeps `AllowUnsafeDynamicLinking = false`, because setting
`Entitlements` alone flips it on and unrestricts every process on the machine.

**2. `csrutil disable` + `amfi_get_out_of_my_way=1` — the blunt one.** Turns off code-signing
enforcement system-wide. Reported consequences go beyond the intended one: AMFI-off breaks
DriverKit's own exec path (`ENOEXEC`), and the enforcing alternative kills dexts with
`CODESIGNING`. This is the option to skip.

### What any of them costs

- Recovery boot and Permissive Security: a physical step at startup, and a reduced-security
  boot policy that persists.
- Code-signing enforcement is weakened machine-wide, not just for Wine. `DYLD_INSERT_LIBRARIES`
  comes closer to being usable against arbitrary processes.
- It is per-machine. **It does not solve distribution**: asking every user of a tool to weaken
  their Mac's security is not a release plan.
- macOS updates may reset or break it.

### Recommendation

For PICO-8 specifically: use the native Mac build, which needs no Wine at all.

For 32-bit Windows software that has no alternative, the honest order is: try route 0, then
decide between route 1 (free, one machine, weakened) and paying for the Developer Program
($99/year, no security change, and the only path that can ship to other people).

## The same wall, one floor up: arm64 programs that hardcode KUSER_SHARED_DATA

The entitlement is not only about 32-bit address space. Windows keeps a shared read-only page,
KUSER_SHARED_DATA, at a fixed address — 0x7FFE0000 — in every process, and plenty of native
programs read it directly. Without the entitlement macOS refuses that mapping:
`mmap(0x7FFE0000)` fails with "Cannot allocate memory". So the dev runtime moves the page to
0x1007FFE0000 and patches Wine's own code and the ARM64EC thunks to use it; x86-64 programs
under FEX work, but a native arm64 program that reads the hardcoded address does not — the
win32-arm64 build of VS Code page-faults on exactly that read. The release runtime maps the
page where Windows puts it, so with the entitlement both the 32-bit programs and those arm64
programs work. (Hadron's patch says it plainly: "Only 64-bit programs that don't hardcode the
address work in this mode.")

