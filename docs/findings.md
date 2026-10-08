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

## Windows applications show real windows

Checked against the window server rather than by eye, so the result is evidence and not an
impression (`CGWindowListCopyWindowInfo`, looking for windows whose owner is `wine`):

| Test | Program | Result |
|---|---|---|
| E | `gui-x64.exe`, Win32 GUI, x86-64, emulated | `owner=wine title="decanter x86-64 GUI test" layer=0` |
| F | `gui-ec.exe`, same, ARM64EC | `owner=wine title="decanter x86-64 GUI test" layer=0` |
| — | Wine's own `notepad` (native arm64 PE) | `owner=wine title="Untitled - Notepad"` |

The geometry is right in Windows' own terms: a window created at 520x340 reports a window
rect of 520x340, a client rect of 512x306, and 96 dpi — measured from inside the application
by writing `GetWindowRect` to a file.

**Do not read `kCGWindowBounds` at all; use the accessibility API.** That call lists a window
and its title correctly, but its geometry is wrong here: a 940x640 window was reported as
105x124, and a 520x340 one as 97x111, and neither ever settles to the real value. The
accessibility API tells the truth:

```
$ osascript -e 'tell application "System Events" to tell process "Decanter" to get size of window 1'
940, 640
```

This first looked like a window that had not finished opening, which was wrong. Use
CoreGraphics to answer *does a window exist*, and System Events to answer *how big is it*.

## The graphics stack works: Direct3D 11 reaches Metal

With DXMT installed, from a program running as **emulated x86-64 code**:

```
info:  Maximum supported feature level: D3D_FEATURE_LEVEL_11_1
info:  Using feature level D3D_FEATURE_LEVEL_11_1
adapter 0: Apple M3 Pro
D3D11 device created, feature level 0xb100
CreateBuffer (vertex): ok
CreateTexture2D 512x512: ok
CreateVertexShader: ok
```

The adapter is the Mac's own GPU. The path is x86-64 Windows code → FEX → DXMT's ARM64X
`d3d11.dll` → `winemetal` → Metal.

Three things had to be got right, and each failed in a way that did not name its cause:

1. **Xcode does not ship the Metal compiler.** `xcrun -f metal` fails until
   `xcodebuild -downloadComponent MetalToolchain` (839 MB, no admin rights needed) has run.
   DXMT's shaders cannot be compiled without it.
2. **Homebrew's `llvm@15` is usable, and DXMT knows it** — `src/airconv/darwin/meson.build`
   special-cases a `native_llvm_path` under `/opt/homebrew/opt` and links in `libzstd.a` and
   `libunwind.a`. But it tests the **path string**, so a symlink
   (`toolchains/llvm15 -> /opt/homebrew/opt/llvm@15`) silently skips that branch and the link
   fails on `_ZSTD_compress` and friends. Configure with the real path:
   `-Dnative_llvm_path=/opt/homebrew/opt/llvm@15`. This avoids building LLVM 15 from source
   entirely — which is just as well, because Apple clang 21 crashes (a compiler ICE in
   TableGen) trying to build it.
3. **A Wine prefix made before DXMT was installed cannot see it.** DXMT's DLLs depend on
   `winemetal.dll`, which Wine links into the prefix when the prefix is created. Rebuild the
   prefix after installing DXMT, or the failure is
   `import_dll Library winemetal.dll ... not found` naming the wrong culprit.

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

## Vulkan and Direct3D 12: built, and two requirements short

The whole open-source Vulkan path builds and installs:

| Component | Artefact | State |
|---|---|---|
| KosmicKrisp, Mesa's Vulkan on Metal | `runtime/mesa/lib/libvulkan_kosmickrisp.dylib` | works: `vulkaninfo` reports `deviceName = Apple M3 Pro` |
| Zink, Mesa's OpenGL on Vulkan | `runtime/mesa-zink/lib/libEGL.1.dylib` | built, wired through `WINE_MAC_OPENGL=egl` |
| vkd3d-proton, D3D12 on Vulkan | `runtime/vkd3d-proton/x64/{d3d12,d3d12core}.dll` | loads, enumerates the adapter, **no device yet** |
| DXVK's DXGI | `runtime/dxvk/x64/dxgi.dll`, staged as `dxgi_dxvk.dll` | installed |

`patches/vkd3d-proton/` carries one fix, applied after Hadron's queue. vkd3d-proton 3.0.1
declares `vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR` as a **required** instance
function, and gives up on an instance whose loader cannot resolve it — which is the case on
KosmicKrisp, whose cooperative matrix support is absent. The patch makes the pointer optional
and returns "no cooperative matrix" if it is missing, which is safe because the only call site
is already guarded by the feature bit. That removed the first wall:

```
before:  Could not get instance proc addr for
         'vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR'.
         D3D12CreateDevice: 0x80004005

after:   fixme:d3d12_find_physical_device: Could not find Vulkan physical device
             for DXGI adapter.
         err:vkd3d_init_device_caps: Lacking support for transform feedback.
         D3D12CreateDevice: 0x80070057
```

Two requirements are still unmet, and the evidence narrows the first one a long way:

- **vkd3d-proton cannot match a Vulkan device to the DXGI adapter — and that is not fatal.**
  It matches by LUID/UUID, then by PCI vendor and device ID. DXMT's adapter is built on Metal
  and carries no Vulkan identity, so neither test succeeds; the code then logs a FIXME and
  **falls back to the first physical device** (`libs/d3d12core/main.c`). So this explains the
  FIXME line and nothing else. The error that stops D3D12 is the next one.
- **KosmicKrisp reports no transform feedback inside the Wine process, but does outside it.**
  Measured five ways now, and three suspects have been eliminated:

  | Check | Result |
  |---|---|
  | Which ICD the loader opens inside Wine (`VK_LOADER_DEBUG`) | exactly the runtime's KosmicKrisp |
  | `vulkaninfo` natively, **the exact environment the bottle manager passes** | 152 extensions, transform feedback present |
  | A Windows program asking its own driver (`tools/vkprobe.c`) | device `Apple M3 Pro`, 126 extensions, no transform feedback |
  | Wine's own log of what the host reports (`WINEDEBUG=+vulkan`) | **127** host extensions, no transform feedback |
  | Same, with `MESA_KK_EXPERIMENTAL=all` | unchanged |

  **Eliminated:** the ICD is not mis-selected (the loader names ours, and the host's
  `VK_EXT_external_memory_metal` is KosmicKrisp's own extension); MoltenVK is not involved
  (disabling it with `VK_LOADER_DRIVERS_DISABLE` changes nothing); and Wine is not filtering the
  list away (it passes 127 host extensions through to 126 client ones, and the mechanism,
  `is_device_extension_supported`, only drops extensions Wine has no thunks for).

  That leaves one statement, measured three separate ways: **the driver reports its
  flag-gated extensions outside Wine and not inside it.** What the flags add is exactly what is
  missing — `VK_EXT_device_generated_commands`, `VK_EXT_transform_feedback` and the rest of
  the `MESA_KK_EXPERIMENTAL` set. The loader in that same process demonstrably reads the
  environment, so this is not simply "the variable never arrives"; the next thing to find out
  is what is different about how the ICD is reached from inside Wine.

  `WINEDEBUG=+vulkan` (the channel is named `vulkan`, not `winevulkan`) prints Wine's own view
  of the host: `init_physical_device Host physical device extensions:` followed by the list.
  That is the best instrument here, better than the probe.

Direct3D 11 on DXMT is unaffected, is what the productivity targets need, and was re-checked
after these changes.



### Two traps in wiring this up

1. **Copying a DLL into the prefix is not enough when Wine already has one.** Wine installs
   its own `d3d12.dll` when the prefix is made, so a staging step that only fills gaps leaves
   Wine's version in place and every D3D12 program fails to find a device. Compare and
   replace.
2. **The ICD's JSON names an absolute path.** `kosmickrisp_mesa_icd.aarch64.json` points at
   the build directory it was configured with, so installing the driver elsewhere means
   rewriting `library_path`, or nothing loads.
3. **An installed runtime is not self-contained by default.** Meson and Wine both record
   their build-time prefix as each library's install name, so a runtime copied out of a tree
   still resolves its own libraries *through that tree* — `runtime/mesa-zink/lib/libEGL.1.dylib`
   asked for `~/wine-arm64-lab/hadron/dist/mesa-zink/lib/libgallium-…dylib`. Delete the tree
   and the runtime breaks; ship it and it names a path that exists on one machine. Confirmed
   with `DYLD_PRINT_LIBRARIES=1`, fixed with `scripts/make-runtime-portable.sh` (rewrites those
   to `@rpath`/`@loader_path`, now part of the bootstrap), and re-checked the same way: nothing
   from the build directory is loaded any more.

   A note on checking it: the first line of `otool -L` output is the file's **own path**, not a
   dependency. Counting that line reported 40 healthy files as broken.

## The lessons that cost time

1. `brew --prefix` decides which Homebrew the build uses. With `/usr/local/bin` ahead of
   `/opt/homebrew/bin` in `PATH` it resolves to the Intel Homebrew, and the build fails with
   `FreeType development files not found` — long after the real cause. Every script here
   exports `PATH=/opt/homebrew/bin:$PATH` first, and `scripts/env.sh` asserts the result.
2. **Homebrew's clang cannot build Mesa here.** `env.sh` puts `$BREW/opt/llvm/bin` first on
   `PATH` so `llvm-config` resolves, but that also makes `clang` mean LLVM 23, which looks for
   its sysroot under `/Library/Developer/CommandLineTools/SDKs/` — where this machine has
   nothing newer than `MacOSX26.2.sdk`. The failure reads
   `no such sysroot directory: '/Library/Developer/CommandLineTools/SDKs/MacOSX27.sdk'`, and
   only shows up in the Objective-C sanity check, so the build dies with
   `Compiler ... cannot compile programs` and no mention of which compiler. Configure Mesa
   with `CC=/usr/bin/clang CXX=/usr/bin/clang++ OBJC=/usr/bin/clang`: `llvm-config` stays on
   `PATH` for Mesa to find LLVM, and the SDK is Xcode's.
3. **A partial clone cannot take `git am --3way`.** `scripts/fetch.sh` clones Mesa with
   `--filter=blob:none`; when a patch needs the three-way fallback, git tries to fetch the
   blobs and dies with `remote error: upload-pack: not our ref`, leaving the repository
   mid-`am`. Clone Mesa without the filter, or apply the queue with plain `git am`: the
   patches were made against the pinned commit and 83 of 83 applied cleanly that way.
4. `git -C <dir> am <relative-path>` resolves the path **relative to `<dir>`**, not to the
   current directory. A patch script that looks right applies nothing, and the build then
   succeeds without the patches. This cost a full rebuild.
5. FEX needs its submodules. A `--depth 1 --filter=blob:none` clone followed by a checkout
   silently leaves `External/range-v3` and `Source/Common/cpp-optparse` empty, and CMake
   fails much later. Hadron's own `scripts/fetch.sh` does the submodule update; a hand-rolled
   fetch has to as well.
6. A stale `.git/modules/*/index.lock` from an interrupted submodule update blocks the retry.

## Not yet done

- No graphics stack is built yet (DXMT, MoltenVK, Mesa). The tests above are console
  programs; a windowed application will need DXMT at least.
- The bottle manager has not been exercised against the runtime end to end.
- Nothing has been run on the release variant, because it needs the entitlement.
