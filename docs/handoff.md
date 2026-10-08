# Handoff — the context export

The session that built Decanter ended on 2026-10-09; this document is its context export, so
that the next session — human or agent — can continue without re-deriving anything. It says
what exists, what was decided and why, what is broken, and where the raw evidence lives.
Everything below was verified on the build machine on 2026-10-09 unless marked **UNVERIFIED**.

**Reading order for an agent:** `docs/guide.md` (how it works) → `docs/findings.md` (what was
measured, and the traps that cost the most time) → this file. Read §7 before trusting the
release anywhere but the build machine.

## 0. Where things stand

- **Repo** — `github.com/tzhazuma/decanter`, public, MIT. Branch `main`; as of commit `169699f`
  ("Bring the README back in line with what the project does"): 30 commits, 33 tracked files,
  clean tree. This export adds `docs/handoff.md`, `AGENTS.md` and `CLAUDE.md`.
- **Release** — `v0.1.0`, published 2026-10-08. One asset: `Decanter-0.1.0.dmg`,
  459,187,141 bytes, sha256 `25dfee9c7790aed3ba56578a5a28d69f9e60c00c4ebf392c82d9a82dd6646244`.
  Byte-identical mirrors: `~/Downloads/Decanter-0.1.0.dmg` and `build/package/Decanter-0.1.0.dmg`.
  The release tag points at `e303891` — 7 commits behind `main`; the DMG was built from the
  newer tree. The local clone has no tags (the tag exists only on GitHub).
- **Installed runtime** — `~/.local/share/decanter/runtime` (2.4 GB), `variant` = `dev`
  (no entitlement; 64-bit only). Wine `wine-11.18-271-gee44e5d65c`, with FEX, DXMT, DXVK,
  vkd3d-proton and Mesa (KosmicKrisp + Zink). Built from `~/wine-arm64-lab/hadron`, not from
  the bootstrap checkout — see §7.5.
- **Bottles** — `smoke` (win11/dxmt; Notepad, and VS Code with `--no-sandbox --js-flags=--jitless`)
  and `demo` (win11/dxmt; Notepad), under `~/.local/share/decanter/bottles/<name>/`.
- **Works** — 64-bit Windows programs, console and windowed; Direct3D 9/10/11/12 through both
  graphics backends; OpenGL 4.6 (Zink on KosmicKrisp); the window (two modes: systems and
  applications) and the CLI; export-as-application; a published DMG that carries its own
  runtime. VS Code for Windows x64 renders its whole workbench.
- **Does not work** — 32-bit Windows programs (restricted entitlement — §8); kernel anti-cheat,
  kernel drivers, USB dongles (out of scope). The app is ad-hoc signed, not notarised, so other
  machines need the usual right-click → Open.
- **Known defects in the shipped artifact** — §7, read it before trusting the DMG (or an
  exported app) on another machine.

## 1. What Decanter is, and the constraints it was built under

A free, open-source, GUI alternative to CrossOver for Apple Silicon Macs, aimed at the macOS
releases after Rosetta's x86 support ends. The goal: **run basic Windows programs, productivity
software first (Multisim-class), without Rosetta and without paying CrossOver**.

Constraints set over the build, all still in force:

1. **Fully open-source/free.** No paid components. Apple's D3DMetal (via the Game Porting
   Toolkit) is **never bundled, downloaded or mirrored**: `scripts/fetch-gptk.sh` only imports
   a copy the user fetched themselves. The GPTK licence restricts *use*, not just
   redistribution, so "not selling it" is not a loophole.
2. **No Rosetta.** The runtime is arm64-native Wine; the application's x86 code runs through
   FEX inside Wine (ARM64EC).
3. **Aimed at the next macOS**, where Rosetta is going away.
4. **A window, not just a command line.** Two shapes: a *system* (a bottle that holds several
   programs) and an *application* (one program exported into a self-contained bundle).

Architecture: Decanter is a bottle manager + packaging layer on top of a natively built arm64
Wine runtime. The runtime comes from [Hadron](https://github.com/Broyojo/hadron) (BSD-3), a
build system that assembles Wine + FEX + DXMT + DXVK + vkd3d-proton + Mesa with a patch queue.
Decanter adds the runtime build/packaging scripts, the Python CLI (`cli/decanter`), the SwiftUI
window (`app/`), recipes, and the docs.

**Why not port FEX ourselves:** researched early; the FEX macOS port that was circulating
(`willfaust/FEX`, branch `ios-port-2607`) turned out to be an iOS-host port, not macOS-native.
Hadron already assembles the whole stack — Wine, FEX and the graphics layers — with the macOS
patches and pins in place; its docs note that CrossOver's ARM64 preview source is not published
and that Hadron's approach is "almost certainly" how it works. Reuse won.

## 2. The machine

- Apple M3 Pro, macOS 27.2 (build 26B5101f), Xcode SDK 27.0. **No signing identity and no
  Apple Developer account** — everything is ad-hoc signed.
- arm64 Homebrew at `/opt/homebrew`. An Intel Homebrew also exists at `/usr/local` — never use
  it (`scripts/env.sh` asserts the arm64 prefix). Every fresh shell wants
  `export PATH=/opt/homebrew/bin:$PATH`.
- `gh` is at `/opt/homebrew/bin/gh` (not in the default PATH), authenticated as `tzhazuma`
  (repo scope). `git` had a stale proxy `127.0.0.1:7890` in config; the proxy that actually
  worked was `127.0.0.1:7897`.
- Pre-existing software, *not ours*, do not confuse: Gcenx Wine Devel 10.5 (x86_64, under
  Rosetta) at `/usr/local/bin/wine`; CrossOver 24.0.5; Whisky 2.3.5.
- Disk was the recurring constraint: ~21 GB free at the low point, cleanup freed ~14 GB.
- **No sudo is needed for any documented workflow; the build avoided it entirely. Keep it
  that way.**
- Test programs: `~/wine-arm64-lab/test/` (`d3d9/10/11/12-x64.exe`, `glprobe.exe`,
  `vkprobe.exe`, `windowinfo.exe`, `gui-x64.exe`, `hello-x64/x86/ec.exe`, `metrics.exe`).
  End-to-end installer case: `~/Downloads/omapX64V1030Setup.exe` (x86-64, 86 MB). The user's
  PICO-8 (`~/pico8/pico8.exe`) is a 32-bit PE and cannot run on the dev runtime (§8);
  `~/Applications/PICO-8.app` is a custom launcher that runs it through CrossOver.

## 3. Layout

Repo `~/decanter` (the window also finds the CLI at `~/decanter/cli/decanter` when run from
source):

| Path | What |
|---|---|
| `app/` | SwiftUI window (Systems / Applications modes); shells out to the CLI, never reimplements it |
| `cli/decanter` | Python 3, 769 lines — bottles, run, install, shortcuts, env, recipes, export, launch, doctor |
| `scripts/` | `env.sh`, `bootstrap-runtime.sh`, `make-runtime-portable.sh`, `package-runtime.sh`, `build-app.sh`, `make-dmg.sh`, `sign-loader.sh`, `fetch-gptk.sh` |
| `patches/` | three: vkd3d-proton (cooperative-matrix query optional), dxvk (fillModeNonSolid optional), mesa (KosmicKrisp flags trace) |
| `recipes/` | `vcrun2015` (fails on dev — 32-bit bootstrapper), `dotnet48` (untested) |
| `tools/` | `vkprobe.c`, `make-icon.swift`, `devtools-shot.py` |
| `docs/` | guide / findings / landscape / entitlement / release-signing / wine-vulkan-internals + this file |

Build trees on disk:

- `~/.cache/decanter/hadron` — what `bootstrap-runtime.sh` uses (shallow clone of pin
  `3e7043aa…`, v0.1.1). Its `src/wine` is at `9a2fd5a6c6`.
- `~/wine-arm64-lab/hadron` — **the tree the installed runtime was actually built from**:
  `src/wine` `ee44e5d65c` (`wine-11.18-271-gee44e5d65c`), `src/fex` `242695a7c`,
  `src/mesa` `373ca1d1b54`, `src/vkd3d-proton` `3f4b638b`, `src/dxvk` `4bef032e`,
  `src/dxmt` `2909010`. Build logs in `~/wine-arm64-lab/*.log`. The lab directory itself is
  not a git repo; each `src/` component is.

Component pins (Hadron's `sources.conf`, applied by `fetch.sh`): wine `6880117619af…`,
fex `0df84d38…`, dxmt `e86484e5…`, mesa `30da3918…`, vkd3d-proton `v3.0.1`, dxvk `v3.1.1`;
toolchain llvm-mingw `20260922`; DXMT builds against LLVM 15 (`/opt/homebrew/opt/llvm@15`).

Runtime layout (installed): `bin/` (wine + tools + `FEXOfflineCompiler{32,64}.exe`),
`lib/wine/{aarch64-unix,aarch64-windows,i386-windows,…}`, `dxvk/x64`, `vkd3d-proton/x64`,
`mesa/` (KosmicKrisp), `mesa-zink/`, `include/`, `share/`, `variant`.

Bottle data: `~/.local/share/decanter/bottles/<name>/{bottle.json,prefix}`; exported apps are
recorded in `~/.local/share/decanter/exported.json` (not yet created on this machine).

## 4. Graphics routing as built

| Windows API | Route | Notes |
|---|---|---|
| Direct3D 9 | DXVK, always | Wine's own needs a GL context — a longer path to the same Metal device |
| Direct3D 10 / 11 | `dxmt` (default) or `dxvk`, per bottle | DXMT → Metal directly; DXVK → Vulkan → KosmicKrisp → Metal |
| Direct3D 12 | vkd3d-proton, always | Wine's own cannot make a device here, because DXGI is DXMT's or DXVK's |
| OpenGL | Zink on KosmicKrisp | reports 4.6 compatibility |
| Vulkan | KosmicKrisp, through the Khronos loader | *not* MoltenVK — see the trap in §6 |

All eight backend × D3D-version combinations were tested and pass; the matrix and the raw
measurements are in `docs/findings.md`.

**UNVERIFIED claim to retest before repeating:** the README says MoltenVK "cannot create an
instance under Wine". The session's own evidence shows a stale build *did* load MoltenVK as the
driver (a probe saw `VK_MVK_moltenvk`). The strong claim was never directly measured — test it
before republishing it.

## 5. Exact command chains

Build (dev runtime, from source):

```sh
scripts/bootstrap-runtime.sh --dev      # the full runtime → ~/.local/share/decanter/runtime
scripts/package-runtime.sh              # self-contained copy → build/package/runtime
scripts/build-app.sh                    # → build/package/Decanter.app  (--no-runtime for a small dev shell)
scripts/make-dmg.sh                     # → build/package/Decanter-<version>.dmg  (~9 minutes)
```

- `bootstrap-runtime.sh` installs the brew dependencies first (including `vulkan-loader`
  **before** Wine — see §6.1), clones Hadron at the pin, fetches and patches
  wine/fex/mesa/vkd3d-proton/dxvk, builds everything into `$CHECKOUT/dist-dev`, copies it into
  the runtime, then runs `make-runtime-portable.sh` and `cli/decanter doctor`. It **overrides
  `CHECKOUT` itself** (`$DECANTER_WORK/hadron`); an exported `CHECKOUT` has no effect on it.
- `package-runtime.sh` honours `$CHECKOUT` for licence collection. The shipped v0.1.0 runtime
  was packaged with `CHECKOUT="$HOME/wine-arm64-lab/hadron" ./scripts/package-runtime.sh`.
- Release/32-bit runtime: `scripts/bootstrap-runtime.sh --release` →
  `scripts/sign-loader.sh <profile> [identity] [--runtime]` → re-sign the app
  (`codesign --force --deep --sign "$IDENTITY" /Applications/Decanter.app`). Full procedure:
  `docs/release-signing.md`.
- Publish: `gh release delete-asset v0.1.0 Decanter-0.1.0.dmg -y` then
  `gh release upload v0.1.0 build/package/Decanter-0.1.0.dmg --clobber`.
- Verify the shipped image: mount it, run the app from the volume, and drive Direct3D 12 from
  inside (that is how the published DMG was tested).

Use:

```sh
./cli/decanter doctor
./cli/decanter bottle create work --windows win11 --graphics dxmt --init
./cli/decanter install work ~/Downloads/setup.exe
./cli/decanter run work 'C:\Program Files\Vendor\app.exe'
./cli/decanter shortcut add work App '<path>' --args …
./cli/decanter export work 'VS Code' ~/Applications/Code.app     # APFS-cloned, self-contained
./cli/decanter launch ~/Applications/Code.app
./cli/decanter env work NAME=value        # NAME= removes; shadows runtime-computed vars — §6.4
```

Version strings live in `cli/decanter:21` (`VERSION`), `scripts/build-app.sh:65`
(`CFBundleShortVersionString`); `make-dmg.sh` reads the plist to name the DMG. Exported apps
get `1.0`.

## 6. Traps that already cost time (do not re-learn)

1. **Install `vulkan-loader` before building Wine.** Wine's configure picks the Khronos loader
   if present, else silently falls back to MoltenVK; `win32u` then dlopens MoltenVK directly,
   `VK_DRIVER_FILES` is ignored, device extensions drop 149→126, and vkd3d-proton refuses to
   make a device. This was the real cause of the long Direct3D 12 hunt. `doctor` now reports
   which library Wine opens.
2. **`CGWindowListCopyWindowInfo` lies about window size** (a healthy 940×640 reported as
   105×124; `screencapture -l` follows the same bad geometry). Ask Windows
   (`windowinfo.exe` / `GetWindowRect`) or use the DevTools protocol
   (`tools/devtools-shot.py`) instead. A wrong "VS Code does not render" conclusion came from
   this.
3. **Wine windows are invisible to macOS accessibility APIs** (`System Events` reports zero
   windows) — use accessibility only for native app windows.
4. **Bottle env shadows runtime-computed values** (`DYLD_FALLBACK_LIBRARY_PATH`,
   `VK_DRIVER_FILES`, `WINEDLLOVERRIDES`…). An empty-string leftover cost whole rounds twice;
   `bottle info` lists these overrides.
5. **Wine does not fall back to built-in DLLs**: deleting a staged `d3d11.dll` from the prefix
   breaks imports — copy the builtin back instead.
6. **`cp -Rc src dst` nests** when `dst` exists — use `cp -Rc "$SRC"/. "$DST"/`.
7. **`${VAR:-default}` treats empty as unset** — this once sent a release build's FEX into the
   dev tree.
8. **`git -C <dir> am <relative-path>` resolves the path against `<dir>`**, not the cwd — it
   silently applies nothing.
9. **Submodules need `--force`** when `.gitmodules` moved paths (FEX's `cpp-optparse`): plain
   `submodule update` considers itself done and leaves the directory empty.
10. **`otool -L`'s first line is the file's own path**, not a dependency.
11. **Patches are plain diffs — apply with `git apply`, not `git am`.**
12. **Meson: put `/usr/bin` ahead of Homebrew** so clang uses Apple's clang and the SDK;
    `llvm-ar` still resolves.
13. **Running the runtime's `wine` directly creates a default `~/.wine` prefix** — go through
    `./cli/decanter run` or set `WINEPREFIX`.
14. Debug channels: `WINEDEBUG=+vulkan` (not `+winevulkan`); `DYLD_PRINT_LIBRARIES=1` shows
    what actually loaded, which is not always what was configured.

Fuller versions with evidence: `docs/findings.md`; loader mechanics in
`docs/wine-vulkan-internals.md`.

## 7. Known defects and gaps — fix these first

1. **The packaged runtime's Vulkan ICD carries absolute, machine-specific paths.** Verified
   inside the shipped DMG itself: both manifests under
   `Decanter.app/Contents/SharedSupport/runtime/{mesa,mesa-zink}/share/vulkan/icd.d/` have an
   absolute `library_path` — the `mesa` one points at
   `/Users/azuma/.local/share/decanter/runtime/mesa/lib/libvulkan_kosmickrisp.dylib` (the
   builder's installed runtime; it exists only on this machine), the `mesa-zink` one points
   into a build tree that no longer exists anywhere. The CLI points `VK_DRIVER_FILES` at the
   `mesa` manifest, so on any other machine Direct3D 9, Direct3D 12, DXVK and OpenGL would
   lose their Vulkan driver (DXMT's D3D10/11 would still work — it goes straight to Metal).
   The local "run from the mounted image" test passed *because* the absolute path happens to
   resolve here. `package-runtime.sh` never rewrites ICD JSONs, and its forbidden-reference
   check does not include `$DECANTER_HOME`, so nothing catches this. Suggested fix: have the
   CLI generate the ICD into a writable location (e.g. `$DECANTER_HOME/cache/icd.d/`) at run
   time with the runtime's real path, and point `VK_DRIVER_FILES` at that — it works for
   exported apps too, without mutating a signed bundle. Also add `$DECANTER_HOME` to the
   check. Then rebuild, retest from the image, and re-upload.
2. **`bootstrap-runtime.sh` does not build DXMT**, yet `dxmt` is the CLI/GUI default backend.
   The only mention of dxmt in `scripts/` is the licence copy in `package-runtime.sh:131`. A
   fresh bootstrap therefore silently serves Wine's built-in Direct3D for the "DXMT" backend.
   The installed runtime has DXMT because it came from the `~/wine-arm64-lab` build. Fix: add
   DXMT to the bootstrap build list (Hadron has `build-dxmt.sh`), or make the default backend
   honest about what is staged.
3. **The window's New Bottle sheet still offers the old backend list.** `Views.swift:427`
   defaults to `wined3d` and the picker (lines 439–441) offers only "WineD3D (built in)" and
   "DXMT"; `bottle create --graphics` accepts only `dxmt|dxvk` (`cli/decanter:685`), so
   creating a bottle with the default selection fails with an argparse error, and DXVK cannot
   be chosen at creation at all. (The bottle *detail* picker is fine — it uses the `Backend`
   enum, and legacy `wined3d` values map to `dxmt` for existing bottles.) Fix the sheet to
   offer `dxmt`/`dxvk` like the detail picker.
4. **Doc drift.** `docs/findings.md`'s "Not yet done" section still says no graphics stack is
   built and the bottle manager was never exercised end to end — both false. The tail of
   `docs/wine-vulkan-internals.md` still presents the MoltenVK fallback as an open lead.
   `docs/guide.md` says "There is no setting to choose" about the graphics backend (it exists,
   lines 113–125 of the same file) and gives a stale `open build/Decanter.app` path (the script
   writes `build/package/Decanter.app`). Extension counts are quoted as 126→149 (findings) and
   126 vs 152 (tools/README).
5. **Runtime provenance drift.** The installed runtime has `variant` = `dev` but no
   `hadron-pin` file, and its Wine (`ee44e5d65c`) is from the lab tree while the bootstrap
   checkout is at `9a2fd5a6c6`. Rebuilding via bootstrap will not reproduce the shipped
   runtime byte-for-byte.
6. **The `v0.1.0` tag points at `e303891`, 7 commits behind `main`**; the shipped DMG was
   built from the newer tree. Tag the next release at its build commit.
7. **The shipped app is a debug Swift build** (no release build in `app/.build`); rebuild with
   `build-app.sh --release` for a release.
8. **`build/Decanter.app` is stale** (truncated `Info.plist`, no `SharedSupport`) — the live
   artifact is `build/package/Decanter.app`.
9. **UNVERIFIED**: `scripts/bootstrap-runtime.sh` has never completed end-to-end in one run
   (it was assembled in pieces; three full attempts stopped at network, submodule and
   interrupt problems); `make-runtime-portable.sh`'s conservative rewrite rule was validated
   only on the current runtime; the MoltenVK claim in §4.

## 8. The 32-bit situation (summary; details in `docs/entitlement.md` and `docs/release-signing.md`)

Running 32-bit Windows code needs the restricted entitlement
`com.apple.developer.cross-architecture-support` on the Wine loader. It cannot be self-signed:
ad-hoc signing plus the entitlement is `Killed: 9`. It needs an Apple-issued provisioning
profile (paid Developer Program) or a SIP downgrade (`csrutil enable --without debug`,
re-applied after every reboot) — neither is shippable. The decision, final: **do not build
32-bit**; keep the scripts so anyone with a certificate can. `bootstrap-runtime.sh --release`
builds and reports whether the loader carries the entitlement; `sign-loader.sh` signs it;
`docs/release-signing.md` is the full procedure. Affected targets: NI Multisim, PICO-8 (use
its native Mac build), `vc_redist.x64.exe` (a 32-bit bootstrapper despite the name).

## 9. Raw evidence, and how to mine it

- **Session log** — the whole build, turn by turn:
  `~/.kimi-code/sessions/wd_azuma_b1b4c0909e80/session_50b6e9d1-0d2d-4cb7-be42-adcd0c509ef2/agents/main/wire.jsonl`.
  One JSON record per line; the conversation is in `context.append_message` (user prompts) and
  `context.append_loop_event` (text, tool calls, tool results); everything else is
  bookkeeping. Lines are very long — grep for a keyword, then read that single line, or:

  ```sh
  SES=~/.kimi-code/sessions/wd_azuma_b1b4c0909e80/session_50b6e9d1-0d2d-4cb7-be42-adcd0c509ef2
  grep -n 'VK_DRIVER_FILES' "$SES/agents/main/wire.jsonl" | head
  sed -n '1234p' "$SES/agents/main/wire.jsonl" | jq -r 'keys'   # discover the record shape
  ```

  Window 1 is lines 1–9040 (the original session); window 2 (lines 9041+) holds the compaction
  and this export. `context.apply_compaction` marks compaction boundaries; `context.undo`
  would mark retractions — there are none.
- **Docs index** — `guide.md` (the map), `findings.md` (measurements + traps), `landscape.md`
  (the research, with sources), `entitlement.md`, `release-signing.md`,
  `wine-vulkan-internals.md`.
- **Bottle state** — `~/.local/share/decanter/bottles/<name>/bottle.json`.

## 10. If you pick this up next

1. Fix §7.1 (the ICD paths) and §7.3 (the New Bottle sheet) — both are user-visible; then
   rebuild the image and cut `v0.1.1` (§5).
2. Add DXMT to the bootstrap build (§7.2) so the tree builds what it ships.
3. Sweep the stale doc sections (§7.4).
4. More real-world testing: x86-64 productivity installers (the `omapX64V1030Setup.exe` case),
   the `.NET` recipe, more Electron apps (VS Code already works with its flags).
5. 32-bit only when a certificate appears (§8).
