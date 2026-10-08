# Recipes

A recipe is a known configuration for an application: something to fetch, something to run,
settings to apply. `cli/decanter recipe list` shows them, `recipe apply <bottle> <name>`
uses one.

Steps are `download` (fetched into the bottle), `run` (a Windows path, with optional `args`),
`set` (an environment variable) and `windows` (the Windows version to report).

## vcrun2015 does not work on a development runtime

`vc_redist.x64.exe` is a **32-bit bootstrapper** — `machine: i386` in its PE header — even
though the name says x64 and the payload it installs is 64-bit. A development runtime cannot
start 32-bit programs, so the recipe fails with:

```
wine: failed to start L"\\??\\C:\\decanter\\vc_redist.x64.exe": c000000d
```

It needs the release runtime and the entitlement, like any other 32-bit program. Worth
knowing before hunting for a problem in the recipe itself.

Wine also ships its own `msvcp140`, `vcruntime140` and friends as builtins, and many programs
are satisfied by those. Check whether the application actually complains before adding a
recipe for it.

## Adding one

Look up what the application needs, keep the recipe to what is required, and say in `status`
whether it has been run — `tested` means someone ran it on a runtime and watched it work.
