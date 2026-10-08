# Guide

Everything needed to build, use and troubleshoot Decanter, in one place. The other documents
go deeper on particular subjects and are linked where they are relevant; this one is the map.

## What this is

An open-source bottle manager for running Windows programs on Apple Silicon Macs, built for
the macOS releases after Rosetta. Wine is compiled natively for arm64 and the application's
x86 code is executed by FEX inside it, so nothing runs under Rosetta and nothing stops working
when Rosetta goes.

It is early. 64-bit Windows programs run, including windowed ones and anything using OpenGL,
Direct3D 9, 11 or 12. 32-bit programs do not, for a reason that is not technical — see
[32-bit programs](#32-bit-programs).

## What you need

- An Apple Silicon Mac on macOS 27. The Wine patches are written against APIs macOS 26.5 added.
- Xcode, with the Metal toolchain. Run `xcodebuild -downloadComponent MetalToolchain` once;
  Xcode does not ship it, and without it nothing that compiles Metal shaders can build.
- Homebrew, the **arm64** one at `/opt/homebrew`. An Intel Homebrew at `/usr/local` is not
  used and will not work: the whole point is to stay off Rosetta.
- Several hours and about 25 GB, for the first build.

## Building it

```sh
git clone https://github.com/tzhazuma/decanter
cd decanter
scripts/bootstrap-runtime.sh --dev    # Wine, FEX and the graphics stack
scripts/build-app.sh                  # Decanter.app
open build/Decanter.app
```

The runtime lands in `~/.local/share/decanter/runtime`; the window reads the same bottles the
command line does, so either can be used first. `scripts/env.sh` holds the paths, and
`DECANTER_HOME` moves them.

Most of that work is not Decanter's. Making upstream Wine run natively on arm64 macOS is
[Hadron](https://github.com/Broyojo/hadron)'s (BSD-3-Clause), which the script pins and builds
from; Decanter applies its own patches on top and adds the application-management layer.

## Using it

There are two shapes of the same thing, and the window has a mode for each.

**A system** is an isolated Windows environment — its own `C:` drive, its own registry — that
several programs share. Install what you like into it and it is all still there next time.
Make one per purpose rather than one per program, so that a system is something you can keep
using.

**An application** is one program frozen out of a system into a bundle of its own, carrying the
Windows environment it runs in and the runtime that runs it. It needs nothing else afterwards:
copy it to another Mac, open it, and it works, whether or not Decanter is installed there.

To make one, open a system, add the program to its list, and choose **Export as an
Application…**. From a shell:

```sh
./cli/decanter export work 'VS Code' ~/Applications/Code.app
./cli/decanter launch ~/Applications/Code.app     # what the bundle runs
```

The space is shared rather than duplicated: the contents are clones of what is already
installed, so an export costs almost nothing until one of them changes. The accounting can
look alarming — `du` reports the whole thing — and `ls -l` on the bundle's parent shows what it
really adds.

In the window: **New Bottle**, then **Install a Windows program…**, then **Add to the list…**
to keep a shortcut for it. The output panel at the bottom shows what the tool is doing; the
panel on the left shows which runtime is installed and whether it can run 32-bit programs.

The same operations from a shell:

```sh
./cli/decanter doctor                       # what the runtime is and can do
./cli/decanter bottle create work --init    # create it and its prefix now
./cli/decanter install work ~/Downloads/setup.exe
./cli/decanter run work 'C:\Program Files\Vendor\app.exe'
./cli/decanter shortcut suggest work        # list the .exe files the bottle already has
./cli/decanter shortcut add work App 'C:\Program Files\Vendor\app.exe'
./cli/decanter recipe list                  # known configurations
```

The first run of a bottle creates its prefix and takes a minute. A bottle keeps a
`bottle.json` beside its prefix holding its Windows version, its environment variables and
its shortcuts; everything the window and the command line show comes from there.

### Environment variables

A program sometimes needs one. `./cli/decanter env <bottle> NAME=value` sets it for that
bottle, and `NAME=` removes it. Note that some names the runtime computes for every bottle —
`VK_DRIVER_FILES`, `DYLD_FALLBACK_LIBRARY_PATH`, `WINEDLLOVERRIDES` among them — and setting
one shadows what the runtime worked out rather than adding to it. `bottle info` says when you
have done that, because it is a confusing failure when you have: see
[troubleshooting](#troubleshooting).

## Graphics

There is no setting to choose: the layers are installed and each Direct3D version goes to the
one built for it.

| What the program uses | Where it goes |
|---|---|
| Direct3D 9 | DXVK, on KosmicKrisp, on Metal |
| Direct3D 10 and 11 | DXMT, straight to Metal |
| Direct3D 12 | vkd3d-proton, on KosmicKrisp |
| Vulkan | KosmicKrisp, Mesa's Vulkan on Metal |
| OpenGL | Zink on KosmicKrisp — 4.6, above the Mac's own 4.1 |
| GDI, and everything older | Wine itself |

A bottle has a **graphics backend**, chosen when it is made and changeable afterwards, in the
window or with `./cli/decanter bottle set <bottle> --graphics <name>`. Both are real
configurations, and each says where every Direct3D version goes:

| Backend | Direct3D 9 | 10 and 11 | 12 |
|---|---|---|---|
| `dxmt` (default) | DXVK on KosmicKrisp | **DXMT on Metal** | vkd3d-proton |
| `dxvk` | DXVK on KosmicKrisp | **DXVK on KosmicKrisp** | vkd3d-proton |

`dxmt` is the default because going straight to Metal is the shorter path. `dxvk` is worth
trying when a program does something DXMT gets wrong — the two are independent
implementations, and a bug in one is often not in the other. `./cli/decanter bottle info` prints
the table for a bottle, and so does the window.

Everything older than Direct3D 9 is Wine's own, and Direct3D 12 is always vkd3d-proton: Wine's
own cannot make a device here, because DXGI belongs to whichever backend is chosen.

D3DMetal — what CrossOver uses for Direct3D 12 on the Mac — cannot be used here. Apple ship it
as an x86_64-only framework, so an arm64 Wine cannot load it at all. `scripts/fetch-gptk.sh`
installs a copy of the user's own toolkit when Apple publish an arm64 build. The details, with
sources, are in [landscape.md](landscape.md).

## 32-bit programs

**They do not work, and no amount of building will change that.**

A 32-bit Windows process needs its address space below 4 GB, and granting that needs a
restricted entitlement that only an Apple-signed provisioning profile can authorise. The
`--dev` runtime sidesteps it by moving Windows' low addresses above 4 GB, which is why it
cannot run 32-bit programs.

Two ways forward, and both are decisions rather than work:

- **A paid Apple Developer Program membership** ($99/year). Then `--release` is possible, and
  the resulting runtime can be given to other people.
- **Weakening the machine's security**, which is not a release plan: it means a Recovery boot,
  Permissive Security, and re-applying an allowlist after every rebuild.

This matters for the target list, not just for old software: **NI Multisim is a 32-bit
program**, and so is PICO-8's Windows build. `docs/entitlement.md` has both routes in detail,
including what they cost and why the free one cannot be shipped.

## Known limits

Beyond 32-bit programs:

- **Kernel-level anti-cheat does not work**, so most competitive multiplayer games will not
  start. Neither will anything needing a kernel driver or a USB dongle.
- **Wireframe fill mode on Direct3D 9** renders solid. KosmicKrisp does not offer the Vulkan
  feature DXVK asks for, and Decanter patches DXVK to treat it as optional so that Direct3D 9
  works at all. `patches/dxvk/` has the patch.
- **A few extensions KosmicKrisp lacks** are listed in Hadron's `docs/d3d12-coverage.md`.
- **Software with a native Apple Silicon Mac version should use it.** LTspice, MATLAB, KiCad
  and AutoCAD all do; running them through Wine is worse in every way.
- **The first start of a program is slow** while Wine creates its environment and shaders are
  compiled.
- **Electron applications need flags.** Visual Studio Code for Windows works, and needs
  `--no-sandbox --js-flags=--jitless` to get there: without them its renderer crashes, and with
  only `--no-sandbox` the workbench does not render. Keep them with the program rather than in
  your head:

  ```sh
  ./cli/decanter shortcut add work 'VS Code' 'C:\Program Files\VSCode\Code.exe' \
      --args --no-sandbox --js-flags=--jitless
  ```

  `docs/findings.md` has the measurements, and a note on how the first, wrong answer about this
  came from measuring the window rather than asking it.

## Troubleshooting

Start with `./cli/decanter doctor` and `./cli/decanter bottle info <bottle>`, then watch the
output panel while you reproduce the problem.

**A program fails with `c000000d`.** It is a 32-bit program and the runtime cannot start it.
See [32-bit programs](#32-bit-programs). This is also what a 32-bit *installer* looks like even
when the program it installs is 64-bit — `vc_redist.x64.exe` is one.

**Direct3D 9 fails with `wined3d_adapter_gl_init` or an EGL surface error.** Wine's own
`d3d9.dll` is being used instead of DXVK's. The runtime should be setting `d3d9=n` itself;
check `bottle info` for a `WINEDLLOVERRIDES` that shadows it.

**Something about Vulkan behaves as if the runtime's driver were not there.** Look at
`doctor`'s `vulkan` line. If it says `libMoltenVK.dylib`, the Wine in the runtime was built
before `vulkan-loader` was installed and opens MoltenVK directly, ignoring `VK_DRIVER_FILES`
and offering fewer extensions than the driver has. Install `vulkan-loader` and rebuild Wine.

**A window does not appear, or appears the wrong size.** Check with the window server rather
than by looking, but do not trust the size it reports: `CGWindowListCopyWindowInfo` has been
wrong about window geometry in several cases here, once reporting a healthy 512x338 window as
95x111. Use `osascript -e 'tell application "System Events" to tell process "wine" to get size
of window 1'` for the size.

**A library turns out to be the wrong one.** `DYLD_PRINT_LIBRARIES=1` in the bottle prints what
is actually loaded, which is not always what was configured. More than one afternoon here went
to a fallback that was chosen silently and said nothing.

More, with the measurements behind each: [findings.md](findings.md).

## Legal and licensing

- **Decanter's own code is MIT.** The built runtime carries the licences of what it is made
  from: Wine LGPL-2.1-or-later, FEX MIT, DXMT LGPL-2.1-or-later, DXVK zlib, Mesa MIT,
  MoltenVK Apache-2.0, and Hadron's patches BSD-3-Clause with the licences of the projects
  they modify.
- **Apple's Game Porting Toolkit is never downloaded, bundled or mirrored.** `fetch-gptk.sh`
  installs a copy the user fetched themselves, and says so before it does anything.
- **The Windows software you run is your business**, and installing it into a bottle does not
  change its licence.

## Where things are

| | |
|---|---|
| `docs/landscape.md` | the research behind the design, with sources |
| `docs/findings.md` | what was measured, and the traps that cost the most time |
| `docs/wine-vulkan-internals.md` | how Wine finds a Vulkan driver |
| `docs/entitlement.md` | the 32-bit question in full |
| `recipes/README.md` | what a recipe is, and why one of them cannot work yet |
| `tools/README.md` | the Vulkan probe, and what it found |
| `patches/` | what Decanter changes in each component |
