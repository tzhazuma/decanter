# Tools

## vkprobe.c

Asks a Windows program's own Vulkan driver what it can do, from inside the Wine process.
Built for the question "why does vkd3d-proton say this driver has no transform feedback when
the same driver outside Wine says it has".

Build and run:

```sh
# needs Vulkan headers; Homebrew's vulkan-headers is enough
x86_64-w64-mingw32-clang -O1 -I/opt/homebrew/opt/vulkan-headers/include \
    -o vkprobe.exe tools/vkprobe.c
./cli/decanter run <bottle> ./vkprobe.exe
```

It prints the physical device it sees, and every device extension, one per line prefixed
`EXT `, so the list can be diffed against a native `vulkaninfo` run under the same
environment.

What it found: inside Wine the driver reports 126 device extensions, the same driver natively
reports 152, and the difference is not only the extensions that need `MESA_KK_EXPERIMENTAL`.
Extensions promoted to core in Vulkan 1.2 and 1.3 (`VK_EXT_descriptor_indexing`,
`VK_EXT_extended_dynamic_state`) appear in the Wine list *as extensions*, which is what a
driver reporting a lower device version looks like. `VK_EXT_transform_feedback` is absent
either way, at API version 1.1 and 1.3 alike.

So the list a Windows program sees is not the list the driver publishes, and that is where a
Direct3D 12 investigation should start next.
