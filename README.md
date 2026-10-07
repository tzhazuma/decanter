# Decanter

An open-source bottle manager for running Windows applications — especially **productivity
and engineering software** — on Apple Silicon Macs, **natively**. No Rosetta, no Intel
translation of the Mac side: Wine is built for arm64, and x86 Windows code is executed by
FEX inside Wine.

This is the CrossOver-shaped hole in the Mac Wine ecosystem: the existing open-source tools
either target Steam games (Hadron), or are frozen and Rosetta-bound (Whisky, Wineskin).
Nobody has built a bottle manager aimed at "I need to run one Windows program for work".

## Status

**Early.** The runtime builds and runs 64-bit Windows programs on macOS 27 / Apple Silicon.
32-bit Windows programs need the entitlement path (see below). Nothing here is a finished
product.

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
```

Then:

```sh
./cli/decanter doctor                  # check the runtime
./cli/decanter bottle create work
./cli/decanter install work ~/Downloads/setup.exe
./cli/decanter run work "C:\\Program Files\\Vendor\\app.exe"
```

## Layout

```
scripts/     runtime bootstrap and build
cli/         the bottle manager
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
