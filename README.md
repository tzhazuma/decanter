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
- **64-bit Windows x86-64 programs run through FEX's emulation and print correctly.**
- **Windows applications show real windows** — checked against the window server, not by eye.
- **Direct3D 11 reaches the Mac's GPU**: from an emulated x86-64 process, DXMT reports
  `adapter 0: Apple M3 Pro`, creates a device at feature level 11_1, and creates buffers,
  textures and shaders.
- The bottle manager creates, lists and runs programs (`cli/decanter run smoke app.exe`).

- 32-bit Windows programs fail with `c000000d`. The emulator is built and installed; the
  block is the address space, not a missing component. See `docs/findings.md`.

Not built yet: MoltenVK and the Vulkan path for Direct3D 12, and a GUI. The interface is a
command line for now.

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
        └── graphics        DXMT (D3D10/11 → Metal), MoltenVK (Vulkan → Metal)
```

Wine is built with `--enable-archs=arm64ec,aarch64,i386`, so its own PE side is native ARM64
and only the application's x86 code is emulated.

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

Requires an Apple Silicon Mac with macOS 27, Xcode, and Homebrew.

```sh
git clone https://github.com/tzhazuma/decanter
cd decanter
scripts/bootstrap-runtime.sh --dev     # fetch and build the arm64 Wine + FEX runtime
scripts/build-app.sh                   # build Decanter.app
open build/Decanter.app
```

The window and the command line are two front ends to the same bottles: the window runs
`cli/decanter`, and reads the same `bottle.json` files, so whatever you create in one shows
up in the other.

From the command line:

```sh
./cli/decanter doctor                  # check the runtime
./cli/decanter bottle create work
./cli/decanter install work ~/Downloads/setup.exe
./cli/decanter run work "C:\\Program Files\\Vendor\\app.exe"
```

## Layout

```
app/         Decanter.app: the window (SwiftUI), built by scripts/build-app.sh
scripts/     runtime bootstrap, app build
cli/         the bottle manager both front ends agree on
recipes/     known configurations (Visual C++ runtime, .NET)
docs/        the research behind the design, and what was measured
patches/     our own patches, if any
```

## Credits and licences

Decanter's own code is MIT (`LICENSE`).

The hard part — making upstream Wine run natively on arm64 macOS — is the work of
[Hadron](https://github.com/Broyojo/hadron) (BSD-3-Clause), whose patch queue
`scripts/bootstrap-runtime.sh` pins and applies. Hadron is built for Steam games; Decanter
takes the same runtime and puts an application-and-bottle layer on top. If Hadron upstream
ever ships a general-purpose manager, this project should fold into it rather than compete.

The built runtime carries the licences of what it is made from: Wine is LGPL-2.1-or-later,
FEX is MIT, DXMT is LGPL-2.1-or-later, MoltenVK is Apache-2.0.
