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
## OpenGL 4.6, higher than the Mac's own

```
GL_VENDOR:   Mesa
GL_RENDERER: zink Vulkan 1.4(Apple M3 Pro (MESA_KOSMICKRISP))
GL_VERSION:  4.6 (Compatibility Profile) Mesa 26.3.0-devel
glClear: ok   SwapBuffers: ok
```

Wine's Mac driver hands Mesa's EGL a `CAMetalLayer` and Zink drives KosmicKrisp on top of
it, so a Windows program gets OpenGL 4.6 where Apple's own OpenGL stops at 4.1. Wine asks for
this with `WINE_MAC_OPENGL=egl`; without it, it looks for the system OpenGL and fails.

The first attempt failed with `EGL_BAD_NATIVE_WINDOW` (0x300b), and the cause was a leftover:
a debugging session had written `DYLD_FALLBACK_LIBRARY_PATH=runtime/mesa/lib:...` into that
bottle's environment — the wrong directory, `mesa-zink` is the one that carries EGL — and it
shadowed the value the runtime computes. Wine then found Homebrew's Mesa 26.2.4 EGL instead,
which does not take a `CAMetalLayer` from Wine.

That is the second time a stale bottle variable of mine produced a convincing-looking technical
failure, so `cli/decanter bottle info` now lists any bottle variable that shadows one the
runtime computes.

## Direct3D 9 works too, through DXVK

```
CreateDevice (HAL): 0x00000000
Clear: ok
Present: ok
CreateVertexBuffer: ok
```

DXVK's Direct3D 9 on KosmicKrisp, presenting into a real swapchain. Building it takes one
thing beyond `scripts/build-vulkan.sh`'s default, which disables 9: set `-Denable_d3d9=true`.
Wiring it takes another: the builtin `d3d9.dll` wins unless the environment says otherwise, so
`WINEDLLOVERRIDES` needs `d3d9=n` the same way Direct3D 12 needs `d3d12,d3d12core=n`. Without
it the program gets Wine's wined3d, which here fails earlier and less clearly:

```
err:wgl:macdrv_egl_surface_create Failed to create an EGL surface
err:d3d:wined3d_adapter_gl_init Failed to get a GL context for adapter
Direct3DCreate9: FAILED
```

DXVK then refused the device for a different reason — `fillModeNonSolid` is marked required in
`dxvk_device_info.cpp`, and KosmicKrisp does not offer it. `patches/dxvk/` makes it optional.
The cost is wireframe fill mode on Direct3D 9, which renders solid instead; the alternative
was no Direct3D 9 at all.

## Direct3D 12 works

```
CreateDXGIFactory2: 0x00000000
adapter 0: Apple M3 Pro
D3D12CreateDevice: 0x00000000
feature level: 0xc000            (D3D_FEATURE_LEVEL_12_0)
CreateCommandQueue: ok
CreateCommittedResource 256x256: ok
```

A D3D12 device, a command queue and a resource, from a program running as emulated x86-64
code, on vkd3d-proton over KosmicKrisp. Direct3D 11 still goes through DXMT.

### The cause was a stale Wine, and one line explains it

Wine's `configure` prefers the Khronos loader and **falls back to MoltenVK**:

```
WINE_CHECK_SONAME(MoltenVK, vkGetInstanceProcAddr,
                  [AC_DEFINE_UNQUOTED(SONAME_LIBVULKAN, ["$ac_cv_lib_soname_MoltenVK"])])
```

and `dlls/win32u/vulkan.c` then does `dlopen(SONAME_LIBVULKAN)`.

The first Wine build here ran **before `vulkan-loader` was installed** (it arrived with the
Vulkan stack, later), so `configure` took the fallback and baked `libMoltenVK.dylib` into
`win32u.so`. Wine then opened MoltenVK directly — bypassing the Khronos loader altogether, so
`VK_DRIVER_FILES` did nothing and the runtime's own driver never loaded. The two builds say it
plainly:

| `strings win32u.so` | `libvulkan.1.dylib` | `libMoltenVK.dylib` |
|---|---|---|
| the runtime's copy | 0 | **1** |
| the current build tree | **1** | 0 |

Refreshing the runtime from the current build fixed it in one step: the probe went from 126
device extensions to **149**, `VK_EXT_transform_feedback` and `VK_EXT_device_generated_commands`
appeared, and vkd3d-proton accepted the device.

Every earlier symptom follows from that one line. MoltenVK has no transform feedback and no
device-generated commands, which is exactly what vkd3d-proton requires before it will make a
device; it reports 126 device extensions where KosmicKrisp reports 149; and
`MESA_KK_EXPERIMENTAL` had no effect because it is a KosmicKrisp variable and KosmicKrisp was
never loaded.

`scripts/bootstrap-runtime.sh` now installs `vulkan-loader` **before** building Wine and
warns if `win32u.so` still names MoltenVK, and `cli/decanter doctor` reports which library
Wine was built to open.

### What this cost, and what would have caught it

The lesson is not about Direct3D. It is that **a fallback chosen silently by a configure
script is invisible at run time**. Wine logged nothing about opening MoltenVK; from outside,
MoltenVK and KosmicKrisp both report a device called "Apple M3 Pro" with a plausible extension
list. What found it was `DYLD_PRINT_LIBRARIES=1`, which prints what is actually loaded rather
than what was configured — worth reaching for far earlier than it was.

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

## Visual Studio Code runs

As an experiment with a large, real 64-bit Windows application, the portable Windows x64 build of
VS Code, extracted into a bottle and started through `decanter run`.

| Flags | Result |
|---|---|
| none | `GPU process isn't usable. Goodbye.`, then an unhandled exception |
| `--no-sandbox` | no crash, but the window shows only its background — the workbench never renders |
| `--no-sandbox --js-flags=--jitless` | **the whole workbench renders**, 1200x800: menu bar, activity bar, the Welcome tab, Walkthroughs, the status bar |
| `--disable-gpu` added to the above | no difference, so it is not needed |

So it works, with `--no-sandbox --js-flags=--jitless`. A shortcut can carry those flags
(`decanter shortcut add <bottle> Name <path> --args --no-sandbox --js-flags=--jitless`), which
is what the window does when the arguments field is filled in.

### How the first answer was wrong

This section first said VS Code "launches, loads and does not paint", with a screenshot showing a
blank window. **That was a measurement error, not a finding**, and it is worth leaving the
correction here rather than quietly deleting the mistake.

`CGWindowListCopyWindowInfo` reported the VS Code window as 131x156, and `screencapture -l` —
which uses the same window-server geometry — then captured exactly that region, which is the
window's title bar and a strip of empty space. Both were wrong. Asked directly, Windows said the
window was 1208x804 at 152,91, exactly what `--window-size=1200,800` had requested, and Chromium's
own DevTools answered `Page.captureScreenshot` with the complete, correctly laid out workbench.

The instrument that settled it is `tools/devtools-shot.py`: it asks the page to photograph
itself over the DevTools protocol, so neither the window server nor the screen is involved.
Anything about whether an application *renders* should be asked that way.

Two lessons, and this document has now recorded both more than once. `CGWindowListCopyWindowInfo`
is not evidence of a window's size — it has been wrong for a native SwiftUI window, for a
hand-written Win32 window and for this one. And a screenshot is only as good as the geometry it
was taken with.

## The second VS Code report: an EBADF in Node, found and fixed

**Found, later the same day — see "The cause" at the end of this section.** The account below is
how the hunt went before the reproduction was built.

On 2026-10-09 the report came back: VS Code "still" fails — an error appears and no window.
The run behind it was found still hanging from the night before. Started through the window at
23:39, its process tree was a main process, a GPU process and a network service — **no renderer,
no crashpad handler, no log directory, no crash report** — every thread idle. The main process
had loaded Chromium's resources but had not run the application's JavaScript (no log directory
was ever created).

Killing that session and running the same command again — same app bundle, same arguments, same
environment — works, twice in a row: the whole process tree comes up, the window appears and the
workbench renders. What was checked, so a later attempt need not repeat it:

- **Not Gatekeeper.** The installed app carries quarantine (4,139 attributes) and `spctl`
  rejects it, but `syspolicyd` scanned the runtime binaries on first launch and allowed them
  (`GK evaluateScanResult`) — no dialog and no denial, on the night's run or on the retries.
- **Not a crash.** No `.ips` report and no crashpad dump. The `ReportCrashService` seen at
  23:39:04 was iStat Menus Menubar, which this machine crashes "6869 times in a row" — its own
  noise, not ours.
- **Not the environment.** The window's environment (minimal `PATH`, XQuartz's `DISPLAY`, no
  `LANG`, `__PYVENV_LAUNCHER__`) was reproduced exactly; it works.
- **Not `code.lock`, the FEX disk cache, or `start.exe /exec`** — all are shared with the
  working runs. `start.exe /exec` is Wine's normal fallback when a program needs a different
  loader, which is every x86-64 launch on this setup (`dlls/ntdll/unix/env.c`).
- One difference remains unexplained: the hung run had **no crashpad handler**, and its main
  process briefly became frontmost 35 seconds in with no window to show for it.

If it recurs: the window's **Stop** button (added the same day) kills the bottle's session, and
a second launch is the workaround. The evidence is in the unified log at 2026-10-08 23:39
(syspolicyd, launchd, runningboardd, and wine processes 51244–51282).

### The cause: Node reads stderr lazily, and Wine gave it a pipe

Reproduced, finally, by rebuilding the window's own way of launching things: a small Swift
program using `Foundation.Process`, one `Pipe` for stdout and stderr, a `readabilityHandler`
draining it, and the window's exact environment. The same command that works from a shell hung
from that program — and its main process had put up a window titled **Error**. Asked directly
(a probe compiled for the bottle enumerated the dialog's controls), it said:

    A JavaScript error occurred in the main process
    Uncaught Exception:
    Error: open EBADF
        at new Socket (node:net:651:13)
        at createWritableStdioStream (node:internal/bootstrap/switches/is_main_thread:83:18)
        at process.getStderr [as stderr] (node:internal/bootstrap/switches/is_main_thread:175:12)

Node builds its stdio streams lazily. When the descriptor is a file it wraps it as a file; when
it is a pipe it wraps it as a pipe socket — and under Wine the pipe handle it gets is not one it
can use, so the first write to stderr throws **EBADF**, the main process dies before it draws
anything, and what remains is the error dialog and a process that never shows a window. That is
the whole difference between `decanter run …` from a shell (output redirected to a file: works)
and the same command from the window (output collected through NSPipe: dies at once).

The fix is in the command line tool, not the window: `run_wine_streaming()` gives Wine a file
for its output and forwards the bytes to its own stdout — a pipe only Python ever writes, and
Python does not have this problem. Applied to `run`, `install`, `launch` and recipe steps.
Verified by rerunning the same Foundation.Process reproduction: the process tree comes up
complete, the Welcome window renders, and the workbench answers the DevTools protocol with a
full-page screenshot.

## The transparent window: DXMT cannot present a cross-process swapchain

With the EBADF fixed, VS Code started from the window — and its window came up **transparent**:
title bar, no content, the desktop showing through. The log said why:

    err:   CreateSwapChain: cross-process swapchain not supported yet
    ERROR:ui\gl\angle_platform_impl.cc:47] SwapChain11.cpp:640 ... HRESULT: 0x80004005
    ERROR:ui\gl\gl_surface_egl.cc:434] eglCreateWindowSurface failed with error EGL_BAD_ALLOC

Chromium's GPU process renders for windows owned by the browser process, so the swapchain has
to cross a process boundary; DXMT refuses that, ANGLE's Direct3D 11 backend then cannot make a
surface, and nothing is ever painted. Every earlier "VS Code renders" check went through
DevTools, which photographs the *page*, not the presented window — so this had been wrong all
along without being seen. The instrument that shows the difference is the window-server capture,
`screencapture -l <window id>`.

Switching the bottle to the `dxvk` backend fixes it outright: DXVK presents through Vulkan and
has no such limit, the window-server capture then shows the whole workbench, and the errors are
gone. **DXVK is now the default backend for that reason**, and DXMT remains for anything that
would rather go straight to Metal.

## Can the JIT run? No — and the ARM64 build does not either

VS Code without `--js-flags=--jitless` crashes its renderer under FEX:
`renderer process gone (reason: crashed, code: -1073741819)` — an access violation, and the same
with `--no-opt`, so it is not TurboFan-specific. FEX's own SMC configuration is the lever:

- `FEX_SMCCHECKS=mtrack` (the default): crashes — the tracking misses something V8 does to its
  own code pages.
- `FEX_SMCCHECKS=full`: **no crash** — the workbench does come up — but the checking costs so
  much that startup takes two to three minutes instead of thirty seconds, and the renderer burns
  five minutes of CPU getting there. Set per bottle with `decanter env <bottle> FEX_SMCCHECKS=full`
  and drop `--js-flags=--jitless` from the shortcut, if the trade is ever wanted.
- The **win32-arm64 build of VS Code** (native, no FEX) starts and then page-faults inside Wine
  (`Unhandled page fault on read access to 000000007FFE0296`) — and this one has a definite
  cause rather than "not supported yet". Hadron's patch
  `patches/wine/0003-ntdll-Allow-building-with-KUSER_SHARED_DATA-above-4G.patch` moves
  KUSER_SHARED_DATA from its fixed Windows address 0x7FFE0000 to 0x1007FFE0000, because arm64
  macOS refuses to map memory below 4 GB (and between 4 GB and 0x7000000000) without the
  cross-architecture entitlement — `mmap(0x7FFE0000)` here fails with "Cannot allocate memory".
  Wine's own code and the ARM64EC thunks were patched to use the moved page, and x86-64 programs
  under FEX work; but a native arm64 program that reads the hardcoded 0x7FFE0000 address — as
  this build does — hits an unmapped page. The patch says it plainly: "Only 64-bit programs that
  don't hardcode the address work in this mode." The arm64 route therefore cannot be fixed on
  the dev runtime; it needs the same entitlement the 32-bit programs need.

`--js-flags=--jitless` stays the usable configuration: the interpreter is slow, but its code is
hot and cached, while a JIT keeps writing new code and pays FEX's self-modification price.
