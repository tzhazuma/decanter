# How Wine finds a Vulkan driver, and what it does with it

Notes from the Direct3D 12 investigation, for whoever picks it up next. Wine 11.18.

## Wine loads the loader itself

`dlls/win32u/vulkan.c` dlopens `SONAME_LIBVULKAN`, which `configure` sets to **either**
`libvulkan.1.dylib` (the Khronos loader, when it is found at configure time) **or**
`libMoltenVK.dylib` (`configure` line 19728 has that as the fallback). This build has
`#define SONAME_LIBVULKAN "libvulkan.1.dylib"` in `include/config.h`, which is what we want:
the loader then honours `VK_DRIVER_FILES` and can be pointed at KosmicKrisp.

A build that resolves to MoltenVK instead will ignore `VK_DRIVER_FILES` entirely and report
MoltenVK's extensions, which is a confusing thing to debug from the outside.

## The PE side of winevulkan filters extensions

`dlls/winevulkan/loader.c`, `vkEnumerateDeviceExtensionProperties`, passes each host extension
through:

```c
if (!is_device_extension_supported(physical_device, extension, &extensions)) continue;
```

and that function is generated:

```c
#define USE_VK_EXT(x) if (!strcmp(extension, #x)) return (extensions->has_ ## x = physical_device->extensions.has_ ## x);
ALL_VK_CLIENT_DEVICE_EXTS
```

`ALL_VK_CLIENT_DEVICE_EXTS` comes from `make_vulkan`, which writes an entry for every
extension where `ext.type == "device" and ext.is_exposed`. `is_exposed` is false for
`UNEXPOSED_PLATFORMS` (macos, metal, wayland, xlib) and for `UNEXPOSED_EXTENSIONS`.
`VK_EXT_transform_feedback` is in neither list, so it would pass through if the host reported
it. The flag it reads, `physical_device->extensions.has_…`, is what the host answered during
instance creation.

So: an extension a Windows program sees requires both that Wine has a thunk for it **and**
that the host reported it. A missing extension is ambiguous from the client side; Wine's own
log resolves the ambiguity.

## The channel is called `vulkan`

`WINE_DEFAULT_DEBUG_CHANNEL(vulkan)`, not `winevulkan`. This prints Wine's view of the host:

```
WINEDEBUG=+vulkan
  trace:vulkan:init_physical_device Host physical device extensions:
  trace:vulkan:init_physical_device   - VK_KHR_16bit_storage
  ...
  warn:vulkan:is_device_extension_supported Extension "VK_MVK_moltenvk" is not supported.
```

That host list is the ground truth for "what did the driver tell Wine", and it is the fastest
way to tell a driver problem from a Wine problem.

## Checking an ICD from outside

```sh
VK_DRIVER_FILES=<icd.json> DYLD_FALLBACK_LIBRARY_PATH=<dir with libvulkan> vulkaninfo
VK_LOADER_DEBUG=driver            # which manifests the loader opened
VK_LOADER_DRIVERS_DISABLE='*MoltenVK*'
```

When Wine is involved, set these in the bottle (`./cli/decanter env <bottle> NAME=value`).
Note that an empty value now unsets the variable instead of setting it to the empty string —
an empty `VK_DRIVER_FILES` silently defeats the runtime's own path and lets the loader fall
back to whatever it finds, which is exactly the sort of thing that wastes an afternoon.
