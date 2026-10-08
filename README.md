# Decanter

An open-source bottle manager for running Windows applications — especially **productivity
and engineering software** — on Apple Silicon Macs, **natively**. No Rosetta, no Intel
translation of the Mac side: Wine is built for arm64, and x86 Windows code is executed by
FEX inside Wine.

This is the CrossOver-shaped hole in the Mac Wine ecosystem: the existing open-source tools
either target Steam games (Hadron), or are frozen and Rosetta-bound (Whisky, Wineskin).
Nobody has built a bottle manager aimed at "I need to run one Windows program for work".

## Status

**Early, but the core works.** Verified on an M3 Pro / macOS 27.2 with **no code-signing
identity and no Apple Developer account**:

- arm64-native Wine builds and runs; it is a Mach-O arm64 binary and nothing in the process
  tree carries Rosetta's translated flag.
- **64-bit Windows programs run**, console and windowed, through FEX's emulation.
- **Direct3D 9, 10, 11 and 12**, each through the layer chosen for it — DXVK on KosmicKrisp,
  DXMT straight to Metal, or vkd3d-proton — and **OpenGL 4.6**, through Zink on KosmicKrisp,
  which is higher than the Mac's own OpenGL reaches.
- **Two graphics backends** per system, listed per Direct3D version in the window.
- **A real application runs**: the portable Windows x64 build of Visual Studio Code renders its
  whole workbench. See `docs/findings.md`.
- **Two shapes of environment**: a *system* holds several programs and needs Decanter; an
  *application* is one program frozen into a bundle that carries its own runtime.
- **A disk image is published**, so none of the above has to be built to be used.

Not there yet: **32-bit Windows programs**, which need a restricted entitlement and therefore a
paid Apple Developer account. NI Multisim is one of them. The scripts to build and sign such a
runtime are here; `docs/release-signing.md` is the procedure, and anyone with a profile can
follow it.

## Why this exists

Apple has announced that Rosetta's support for applications ends after macOS 27; from
macOS 28 it is kept only for certain older games. Every Mac Wine wrapper built before 2026
runs as an **x86_64 process under Rosetta** and therefore has a known expiry date. The only
sustainable path is a native arm64 Wine plus an emulator for the Windows x86 code, which is
what Wine's ARM64EC support and FEX provide.

## How it works

```
  Windows application (x86-64 / x86)
        │
        ├── Wine            native arm64 macOS program, provides the Windows API
        │     └── FEX       emulator DLLs loaded inside Wine
        │           ├── xtajit64.dll   ARM64EC backend  — emulates x86-64
        │           └── xtajit.dll     WoW64 backend    — emulates 32-bit x86
        │
        └── graphics        DXVK (D3D9, or 9–11), DXMT (D3D10/11), vkd3d-proton (D3D12),
                            KosmicKrisp (Vulkan), Zink (OpenGL) — all landing on Metal
```

Wine is built with `--enable-archs=arm64ec,aarch64,i386`, so its own PE side is native ARM64
and only the application's x86 code is emulated. MoltenVK is not used: KosmicKrisp, Mesa's
Vulkan driver, drives Metal directly, and MoltenVK cannot create an instance under Wine.

## The entitlement, and why it matters

Windows requires certain structures at fixed addresses below 4 GB. Granting a process a
low address space needs the restricted entitlement
`com.apple.developer.cross-architecture-support`, which can only be carried by a bundle with
an embedded provisioning profile, which in turn needs an Apple Developer account.

Decanter therefore builds in two variants:

| Variant | Entitlement | 64-bit apps | 32-bit apps | Who can build it |
|---|---|---|---|---|
| `--dev` | not needed | yes | **no** | anyone |
| `release` | required | yes | yes | Apple Developer Program member |

The `--dev` variant moves the low-address requirement above 4 GB, which is why it cannot run
32-bit programs. **This matters for the productivity use case**: NI Multisim is a 32-bit
program, so it needs the release variant.

## Install

The easy way is the disk image: [latest release](https://github.com/tzhazuma/decanter/releases/latest),
drag Decanter to Applications. It carries its own runtime, so nothing else is needed.

To build it yourself you need an Apple Silicon Mac with macOS 27, Xcode, and Homebrew:

```sh
git clone https://github.com/tzhazuma/decanter
cd decanter
scripts/bootstrap-runtime.sh --dev     # build the arm64 Wine, FEX and graphics runtime
scripts/build-app.sh --no-runtime      # a small app that uses the runtime just built
open build/package/Decanter.app
```

Leave `--no-runtime` off to build the app that carries a runtime of its own, which is what a
release is and takes a few minutes longer to assemble.

The window and the command line are two front ends to the same thing: the window runs
`cli/decanter` and reads the same `bottle.json` files, so what you create in one shows up in
the other.

From the command line:

```sh
./cli/decanter doctor                  # check the runtime
./cli/decanter bottle create work      # a system: one Windows environment, several programs
./cli/decanter install work ~/Downloads/setup.exe
./cli/decanter run work 'C:\Program Files\Vendor\app.exe'
./cli/decanter shortcut add work App 'C:\Program Files\Vendor\app.exe'
./cli/decanter export work App ~/Applications/App.app   # an application: one program, on its own
```

**New here? [docs/guide.md](docs/guide.md)** is everything — building, using, the two shapes,
the limits, and how to find out what went wrong.

## Layout

```
app/         Decanter.app: the window (SwiftUI), built by scripts/build-app.sh
cli/         the manager both front ends agree on, and what an exported app runs
scripts/     runtime bootstrap, packaging, app build, Apple toolkit import, loader signing
recipes/     known configurations (Visual C++ runtime, .NET)
tools/       a Vulkan probe, an icon drawn rather than shipped, a screenshot tool
docs/        guide.md first, then the research and the measurements behind it
patches/     what Decanter changes in each component it builds
```

## Credits and licences

Decanter's own code is MIT (`LICENSE`).

The hard part — making upstream Wine run natively on arm64 macOS — is the work of
[Hadron](https://github.com/Broyojo/hadron) (BSD-3-Clause), whose patch queue
`scripts/bootstrap-runtime.sh` pins and applies. Hadron is built for Steam games; Decanter
takes the same runtime and puts an application-and-bottle layer on top. If Hadron upstream
ever ships a general-purpose manager, this project should fold into it rather than compete.

The built runtime carries the licences of what it is made from — Wine (LGPL-2.1-or-later), FEX
(MIT), DXMT (LGPL-2.1-or-later), DXVK (zlib), Mesa (MIT), MoltenVK (Apache-2.0) — and they
travel with it: a packaged app has them under
`Contents/SharedSupport/runtime/licenses`.
