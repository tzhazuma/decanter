# The Mac Wine landscape, and why Decanter is built the way it is

Research done 2026-10-08. Every claim here links to its source; anything unverified says so.

## 1. Everything built before 2026 has an expiry date

Rosetta 2 translates x86-64 Mac code to arm64. Every Mac Wine wrapper until 2026 ran Wine
itself as an x86-64 process under Rosetta, which is why Whisky, Wineskin, Porting Kit and
the Gcenx Wine builds all worked on Apple Silicon without being ported.

Apple has now ended that path. From the developer announcement: *"macOS 27: Final release to
support Rosetta — Intel-only apps will no longer run on Mac computers with Apple silicon
after this update."* The support document adds: *"Starting with macOS 28, the next major
macOS release, Rosetta functionality will be available only for certain older, unmaintained
games that rely on Intel-based frameworks."*

- <https://developer.apple.com/news/?id=w5ngl9k2>
- <https://support.apple.com/en-us/102527>

So the industry has roughly one macOS release to move Wine from "x86-64 under Rosetta" to
"arm64 with an x86 emulator for the Windows code". That is the entire reason this project
exists in the shape it does.

## 2. The architecture that replaces it

Wine's own answer is **ARM64EC**: Wine's PE side is built for ARM64 (or ARM64EC, a hybrid
where a module can be partly native and partly emulated), and the application's x86 code is
run by an emulator that plugs into a documented slot.

The slot is real and upstream. Wine's `dlls/ntdll/loader.c` looks up
`HKLM\Software\Microsoft\Wow64\amd64` and loads `C:\windows\system32\xtajit64.dll`; upstream
ships only a stub that prints "x64 emulation not implemented". The emulator replaces that
DLL.

- <https://gitlab.winehq.org/wine/wine/-/blob/master/dlls/xtajit64/cpu.c>
- <https://wiki.fex-emu.com/index.php/Development:ARM64EC>

Two emulator DLLs are needed:

| Module | Emulates | Installed as |
|---|---|---|
| `libarm64ecfex.dll` (arm64ec PE) | x86-64 | `xtajit64.dll` |
| `libwow64fex.dll` (aarch64 PE) | 32-bit x86 under new WoW64 | `xtajit.dll` |

Timeline of the upstream work, from CodeWeavers: Wine 8.0 (2023-01) PE conversion and WoW64
thunks; Wine 9.0 (2024-01) native ARM binaries and emulated i386; Wine 10.0 (2025-01) full
ARM64EC; 2025-11 first Linux ARM64 preview with FEX; 2026-07 first macOS ARM64 preview.

- <https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac>

## 3. The macOS blockers, and who has solved them

Four macOS-specific problems, all described by Brendan Shanks (CodeWeavers) on wine-devel,
plus one entitlement:

| Problem | Why it exists | macOS answer |
|---|---|---|
| x18 register | Windows ARM64 ABI keeps the TEB in x18; Apple's ABI reserves it | `os_set_custom_x18_abi_enabled()` (macOS 26.4+) |
| Page size | Windows assumes 4 KB pages; arm64 macOS uses 16 KB | `posix_spawnattr_set_4k_page_size_np()` |
| Low addresses | Windows wants structures below 4 GB and at `0x7ffe0000`; macOS requires PAGEZERO ≥ 4 GB | `-Wl,-x86_64_layout_emulation`, PAGEZERO ≈ 0x170000000 |
| Memory model | x86 has TSO; arm64 is weakly ordered | `thread_set_x86_64_compat()`, **per thread, not inherited** |

- <https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/>

Brendan's macOS patches were still "planned, not submitted" as of 2026-09-08
(<https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/message/EYMEAE4QQE2CR4OBITUENL3LB67ECDLU/>),
which is why an out-of-tree patch set is needed today.

**The one project that has this working in public is Hadron** (BSD-3-Clause,
<https://github.com/Broyojo/hadron>): native arm64 Wine, FEX as `xtajit*.dll`, DXMT / mtld3d
/ vkd3d-proton / Mesa for graphics, integrated as a Steam Play tool. Decanter pins a Hadron
revision and reuses its patch queue rather than duplicating years of work.

## 4. The entitlement is the real gate

Windows needs the low address space. Granting it needs
`com.apple.developer.cross-architecture-support`, a **restricted** entitlement, so it can
only be carried by a bundle with an embedded provisioning profile, which needs an Apple
Developer account. Ad-hoc signing does not work: AMFI kills the process.

As of 2026-09-29 the capability is self-serve in the developer portal — no approval step —
but it still requires a paid Apple Developer Program membership for a Developer ID profile
that others can use. See `entitlement.md`.

What this means in practice:

- **Anyone** can build and run the `--dev` variant, which moves the low-address structures
  above 4 GB. 64-bit Windows programs only.
- **32-bit Windows programs need the release variant**, which needs the account.

## 5. Graphics: what to use for what

| Direct3D | Open-source answer | Notes |
|---|---|---|
| 9 | wined3d, or mtld3d (Rust, direct to Metal) | |
| 10 / 11 | **DXMT** (LGPL-2.1-or-later) | direct to Metal, no Vulkan in between |
| 12 | vkd3d-proton on Mesa's KosmicKrisp | requires a full Vulkan driver |
| Vulkan | MoltenVK (Apache-2.0) | |
| OpenGL | wined3d, or Zink on KosmicKrisp | |

D3DMetal, which is what CrossOver uses for Direct3D 12 on the Mac, is Apple's proprietary
technology shipped in the Game Porting Toolkit. It cannot be redistributed; tools that use
it require the user to download it from Apple themselves. Decanter does not use it.

- <https://github.com/3Shain/dxmt>
- <https://github.com/KhronosGroup/MoltenVK>

## 6. What the alternatives are, and why they are not this

| Project | Licence | Why it is not the answer here |
|---|---|---|
| Whisky | GPL-3.0 | Archived 2025-05; x86-64 under Rosetta; frozen at Wine 7.7 |
| Wineskin / Sikarugir | mixed, partly closed | Rosetta-bound; documents itself as not a CrossOver replacement |
| Porting Kit | closed (free) | Game-focused; warns that macOS 27 removes Rosetta 2 and breaks its ports |
| Hadron | BSD-3 | Steam-only: it is a Steam Play compatibility tool, not a program manager |
| CrossOver | commercial | The thing this is an alternative to; uses non-redistributable D3DMetal |
| Bottles (Linux) | GPL-3.0 | Linux only; macOS runner is Rosetta-based |

No open-source project was found that manages **arbitrary Windows applications** for
productivity use on arm64 macOS. That is the gap Decanter fills.

## 7. Running real software: what to expect

Verified from public compatibility data, not from our own testing yet:

- **NI Multisim** is a **32-bit** Windows program (NI's own compatibility table lists it
  under "Using 32-bit Software" with 64-bit "Not supported"
  <https://www.ni.com/en/shop/software-portfolio/ni-product-compatibility-for-microsoft-windows-11.html>),
  so it needs the release variant, and a well-prepared bottle: the Wine AppDB entry for 14.3
  rates it Gold and lists `corefonts` and `dotnet462` as required
  <https://appdb.winehq.org/objectManager.php?sClass=version&iId=42750>.
- NI has no Windows-on-ARM build and does not support ARM64 Windows
  <https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000001DsFACA0&l=en-US>.
- Software that already has a native Apple Silicon Mac version (LTspice, MATLAB, AutoCAD,
  KiCad) should not be run through Wine at all.
- Kernel-level anti-cheat, kernel drivers, and USB dongles do not work under Wine, arm64 or
  otherwise.
