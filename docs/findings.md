# What was measured

On an M3 Pro, macOS 27.2, Xcode 27.0 SDK, arm64 Homebrew, **no code-signing identity of any
kind** — which is the point: this is the no-Apple-account path.

Runtime: Wine 11.18 (`wine-11.18-271-gee44e5d65c`) built from Hadron's pinned revision with
Hadron's patch queue applied; FEX built from the same pin, installed as `xtajit.dll` and
`xtajit64.dll`.

## The stack runs 64-bit Windows x86-64 programs, natively

Three test programs, cross-compiled with llvm-mingw, run under the dev runtime:

| Test | Binary | Path exercised | Result |
|---|---|---|---|
| A | `hello-x64.exe`, PE32+ x86-64 | FEX ARM64EC emulation | **prints correctly** |
| B | `hello-ec.exe`, ARM64EC | mixed native/emulated module | **prints correctly** |
| C | `hello-x86.exe`, PE32 i386 | WoW64 + FEX, needs entitlement | fails, `c000000d` |

```
===== TEST A: x86-64 (needs FEX ARM64EC emulation) =====
hello from emulated x86-64 Windows code
pointer size: 64 bits

===== TEST B: ARM64EC (mixed native/emulated) =====
hello from emulated x86-64 Windows code
pointer size: 64 bits
```

Wine itself is a Mach-O arm64 executable, and no process in the tree carries Rosetta's
translated flag (`ps -eo pid,translated` shows none). Nothing about this path is Rosetta.

A native PE (`cmd.exe /c echo`) also works, which is the no-emulation case.

## The 32-bit path fails, and that is the entitlement

```
===== TEST C: 32-bit i386 (needs WoW64 + entitlement) =====
wine: failed to start L"\\??\\Z:\\...\\hello-x86.exe": c000000d
Application could not be started, or no application associated with the specified file.
```

`c000000d` is `STATUS_INVALID_PARAMETER`: a 32-bit Windows process needs its address space
below 4 GB, and the dev runtime moved Windows' low addresses above 4 GB precisely to avoid
needing the restricted entitlement. The emulator DLLs are built and present
(`xtajit.dll`, 4.9 MB) — this is not a missing component, it is the address-space
restriction.

## The same thing happens to the programs we actually care about

```
$ scripts/wine-dev ~/pico8/pico8.exe          # PICO-8, PE32 i386
wine: failed to start ... c000000d
```

PICO-8's Windows build is 32-bit. So is **NI Multisim** — NI's own compatibility table lists
it under "Using 32-bit Software", with the 64-bit column "Not supported".

**Conclusion: the productivity targets need a paid Apple Developer Program membership.**

## The lessons that cost time

1. `brew --prefix` decides which Homebrew the build uses. With `/usr/local/bin` ahead of
   `/opt/homebrew/bin` in `PATH` it resolves to the Intel Homebrew, and the build fails with
   `FreeType development files not found` — long after the real cause. Every script here
   exports `PATH=/opt/homebrew/bin:$PATH` first, and `scripts/env.sh` asserts the result.
2. `git -C <dir> am <relative-path>` resolves the path **relative to `<dir>`**, not to the
   current directory. A patch script that looks right applies nothing, and the build then
   succeeds without the patches. This cost a full rebuild.
3. FEX needs its submodules. A `--depth 1 --filter=blob:none` clone followed by a checkout
   silently leaves `External/range-v3` and `Source/Common/cpp-optparse` empty, and CMake
   fails much later. Hadron's own `scripts/fetch.sh` does the submodule update; a hand-rolled
   fetch has to as well.
4. A stale `.git/modules/*/index.lock` from an interrupted submodule update blocks the retry.

## Not yet done

- No graphics stack is built yet (DXMT, MoltenVK, Mesa). The tests above are console
  programs; a windowed application will need DXMT at least.
- The bottle manager has not been exercised against the runtime end to end.
- Nothing has been run on the release variant, because it needs the entitlement.
