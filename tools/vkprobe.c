/* What does the Vulkan driver report from inside the Wine process?
 * Run inside a bottle: it is the only side that can see what a Windows
 * program's Vulkan calls actually reach. */
#include <windows.h>
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <string.h>

#define WANT(ext) (!strcmp(props[i].extensionName, ext))

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("vkprobe: asking the driver from inside Windows\n");

    HMODULE mod = LoadLibraryA("vulkan-1.dll");
    printf("  vulkan-1.dll loaded: %s\n", mod ? "yes" : "NO");
    if (!mod) return 1;

    PFN_vkGetInstanceProcAddr gipa =
        (PFN_vkGetInstanceProcAddr)GetProcAddress(mod, "vkGetInstanceProcAddr");
    printf("  vkGetInstanceProcAddr: %s\n", gipa ? "yes" : "NO");
    if (!gipa) return 1;

    PFN_vkCreateInstance createInstance =
        (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    printf("  vkCreateInstance: %s\n", createInstance ? "yes" : "NO");
    if (!createInstance) return 1;

    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "vkprobe";
    app.apiVersion = VK_API_VERSION_1_3;

    VkInstanceCreateInfo info = {0};
    info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    info.pApplicationInfo = &app;

    VkInstance instance = VK_NULL_HANDLE;
    VkResult r = createInstance(&info, NULL, &instance);
    printf("  vkCreateInstance: %d\n", (int)r);
    if (r != VK_SUCCESS) return 1;

    /* Instance-level entry points only resolve once there is an instance. */
    PFN_vkEnumeratePhysicalDevices enumerate =
        (PFN_vkEnumeratePhysicalDevices)gipa(instance, "vkEnumeratePhysicalDevices");
    PFN_vkGetPhysicalDeviceProperties getProps =
        (PFN_vkGetPhysicalDeviceProperties)gipa(instance, "vkGetPhysicalDeviceProperties");
    PFN_vkEnumerateDeviceExtensionProperties enumExt =
        (PFN_vkEnumerateDeviceExtensionProperties)gipa(instance, "vkEnumerateDeviceExtensionProperties");
    printf("  instance entry points: enumerate=%s props=%s extensions=%s\n",
           enumerate ? "yes" : "NO", getProps ? "yes" : "NO", enumExt ? "yes" : "NO");
    if (!enumerate || !getProps || !enumExt) return 1;

    uint32_t count = 0;
    r = enumerate(instance, &count, NULL);
    printf("  physical devices: %u (result %d)\n", count, (int)r);
    if (r != VK_SUCCESS || count == 0) return 1;

    VkPhysicalDevice devices[8];
    if (count > 8) count = 8;
    enumerate(instance, &count, devices);

    VkPhysicalDeviceProperties props0;
    getProps(devices[0], &props0);
    printf("  device 0: %s\n", props0.deviceName);

    uint32_t n = 0;
    enumExt(devices[0], NULL, &n, NULL);
    printf("  device extensions: %u\n", n);
    if (n == 0) return 1;

    static VkExtensionProperties props[1024];
    if (n > 1024) n = 1024;
    enumExt(devices[0], NULL, &n, props);

    for (uint32_t i = 0; i < n; i++)
        printf("EXT %s\n", props[i].extensionName);
    return 0;
}
