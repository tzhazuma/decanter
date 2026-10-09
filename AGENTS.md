# AGENTS.md

Working notes for AI agents in this repo. If you are a human, `README.md` and
`docs/guide.md` are the better door.

Decanter is a free, open-source CrossOver alternative for Apple Silicon: a bottle manager, a
SwiftUI window and a CLI, on top of a natively built arm64 Wine + FEX runtime, with Direct3D
through DXMT / DXVK / vkd3d-proton and OpenGL through Zink, all landing on Metal.

**Read `docs/handoff.md` first** — it is the context export from the session that built this:
current state, decisions, traps, and the defects to fix first. Then `docs/guide.md` (how it
works) and `docs/findings.md` (what was measured).

## Environment

- Apple Silicon only. Use the arm64 Homebrew at `/opt/homebrew`; the Intel one at `/usr/local`
  is never used. Every fresh shell wants `export PATH=/opt/homebrew/bin:$PATH` (`gh` lives
  there too, authenticated as `tzhazuma`).
- No sudo is needed for any documented workflow. Avoid it.

## Conventions

- Builds land in `build/` and `app/.build/`; both are gitignored. Never commit build output.
- Commits use the project's identity and carry no AI attribution:
  `git -c user.name="唐志昊" -c user.email="116373901+tzhazuma@users.noreply.github.com" commit -m "…"`
  (no `Co-Authored-By` trailers, no "generated with" lines). Messages are plain sentences
  about what changed.
- Releases: replace assets with `gh release delete-asset v0.1.0 <name> -y` then
  `gh release upload v0.1.0 <file> --clobber`.

## Build and verify

```sh
scripts/bootstrap-runtime.sh --dev          # the full runtime (hours; needs the Metal toolchain)
CHECKOUT="$HOME/wine-arm64-lab/hadron" ./scripts/package-runtime.sh
scripts/build-app.sh && scripts/make-dmg.sh # → build/package/Decanter-<version>.dmg
./cli/decanter doctor                       # first thing to run after any change
```

The CLI is the single source of behaviour; the window only shells out to it.

## Traps that already cost time (full list in `docs/findings.md`)

- Install brew `vulkan-loader` **before** building Wine, or Wine silently bakes in MoltenVK and
  Direct3D 12 breaks. `doctor` says which library Wine opens.
- `CGWindowListCopyWindowInfo` (and `screencapture -l`) lie about Wine window geometry — ask
  Windows (`windowinfo.exe`) or use `tools/devtools-shot.py`.
- **Never hand Wine's stdio a pipe**: Electron's Node reads stderr lazily and dies with
  `open EBADF` on one — that was the "VS Code hangs when launched from the window" bug. The
  CLI runs Wine with its output on a file (`run_wine_streaming`) and forwards the bytes.
- Bottle env vars shadow the runtime's computed ones (`DYLD_FALLBACK_LIBRARY_PATH`,
  `VK_DRIVER_FILES`); an empty value is not "unset".
- `cp -Rc src dst` nests when `dst` exists; use `cp -Rc "$SRC"/. "$DST"/`.
- Patches are plain diffs: `git apply`, not `git am`.

## Status (2026-10-09)

v0.1.0 is out (dev runtime, 64-bit only; 32-bit needs a paid entitlement and was deliberately
not built). Known defects and their state: `docs/handoff.md` §7 — the packaged runtime's
Vulkan ICD carrying absolute paths was fixed in the CLI on 2026-10-09 (the manifest is
regenerated at run time), and the window gained a Stop button for hung runs the same day.
