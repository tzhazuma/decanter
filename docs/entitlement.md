# The cross-architecture entitlement

Windows applications expect certain structures at fixed addresses below 4 GB, and
`KUSER_SHARED_DATA` at `0x7ffe0000`. macOS gives every process a PAGEZERO of at least 4 GB and
does not normally hand out a low address space, so a Wine loader that needs one must be
granted `com.apple.developer.cross-architecture-support`.

## Why it cannot be worked around

| Approach | Why it fails |
|---|---|
| Ad-hoc sign with the entitlement | AMFI kills the process; a restricted entitlement is only valid when authorised by an embedded provisioning profile |
| Disable SIP / boot-arg `amfi_get_out_of_my_way=1` | Works, but asking users to weaken their system security is not a shipping option, and CodeWeavers say the same |
| Move the structures above 4 GB | This is what the `--dev` build does. It works for 64-bit programs, which compute addresses themselves. It fails for 32-bit programs, whose pointers can only reach 4 GB |

## Getting it

Written from Hadron's `docs/apple-developer-setup.md`, which is the most complete public
description:

1. Register two explicit App IDs, one for the app and one for the loader — for example
   `com.example.decanter` and `com.example.decanter.loader`.
2. On the **loader** App ID only, enable the capability. In the portal it appears as
   *Cross-architecture Compatibility Framework*. As of 2026-09-29 it is self-serve.
3. Create certificates: *Apple Development* for local testing, *Developer ID Application*
   for distribution.
4. Register each development Mac using the Provisioning UDID from
   `system_profiler SPHardwareDataType`.
5. Create a profile for the loader App ID. Use a *macOS App Development* profile locally, and
   a *Developer ID* profile for builds other people will run.

Verify that a profile actually carries it:

```sh
security cms -D -i Decanter_Loader_Dev.provisionprofile | plutil -p - | grep -A12 Entitlements
```

The entitlement goes **only** on the loader bundle, never on the app or on general-purpose
tools. The loader ships as a small `.app` inside the main app, which is how CrossOver wraps
its loader in `wine.app`.

## The cost, stated plainly

An open-source project that wants to ship 32-bit support has to publish builds signed by a
Developer ID profile carrying this entitlement. That requires a paid Apple Developer Program
membership and a notarisation step. There is no free path to it that does not ask users to
disable SIP.

Practical consequence for Decanter's initial target list: **NI Multisim is 32-bit**, so it
needs this. Everything 64-bit works in the `--dev` build today.
