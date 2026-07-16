#include "ainas/lic/lic.h"

#include <sys/types.h>
#include <sys/sysctl.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOBlockStorageDriver.h>
#include <IOKit/storage/IOMedia.h>
#include <IOKit/IOBSD.h>

#include <cstring>
#include <string>
#include <vector>

namespace ainas::lic {
namespace {

// Convenience: query a sysctl by name, return as string.
std::string sysctlString(const char* name) {
    size_t len = 0;
    if (sysctlbyname(name, nullptr, &len, nullptr, 0) != 0 || len == 0)
        return {};
    std::string buf(len - 1, '\0');
    if (sysctlbyname(name, buf.data(), &len, nullptr, 0) != 0)
        return {};
    return buf;
}

// Get an IORegistry property as a C-string.
std::string ioRegistryString(io_registry_entry_t entry, CFStringRef key) {
    CFStringRef val = (CFStringRef)IORegistryEntryCreateCFProperty(
        entry, key, kCFAllocatorDefault, 0);
    if (!val) return {};
    char buf[256];
    if (CFStringGetCString(val, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        CFRelease(val);
        return buf;
    }
    CFRelease(val);
    return {};
}

// Find the IOMedia entry for the root device.
io_registry_entry_t rootMediaEntry() {
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (!root) return IO_OBJECT_NULL;

    CFMutableDictionaryRef matching = IOServiceMatching("IOMedia");
    if (!matching) return IO_OBJECT_NULL;

    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        != KERN_SUCCESS)
        return IO_OBJECT_NULL;

    io_registry_entry_t media = IO_OBJECT_NULL;
    io_registry_entry_t candidate;
    while ((candidate = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        // Check if this media is the root device (BSD name starts with "disk0")
        auto bsdName = ioRegistryString(candidate, CFSTR(kIOBSDNameKey));
        if (bsdName == "disk0") {
            media = candidate;
            IOObjectRelease(candidate);
            break;
        }
        IOObjectRelease(candidate);
    }
    IOObjectRelease(iter);
    return media;
}

} // anonymous namespace

std::string getCpuSerial() {
    // macOS doesn't expose a CPU serial number. Build a composite identifier.
    auto brand    = sysctlString("machdep.cpu.brand_string");
    auto features = sysctlString("machdep.cpu.features");
    auto extFeatures = sysctlString("machdep.cpu.extfeatures");

    if (brand.empty()) brand = "unknown";
    if (features.empty()) features = "";
    if (extFeatures.empty()) extFeatures = "";

    return brand + "::" + features + "::" + extFeatures;
}

std::string getMotherboardSerial() {
    // IOPlatformSerialNumber is the system-wide unique identifier.
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (!root) return {};

    auto serial = ioRegistryString(root, CFSTR("IOPlatformSerialNumber"));
    IOObjectRelease(root);
    return serial;
}

std::string getDiskSerial() {
    auto media = rootMediaEntry();
    if (!media) return {};

    // Navigate up to the provider (e.g. AppleNVMeController, AppleAHCI)
    io_registry_entry_t provider = IO_OBJECT_NULL;
    IORegistryEntryGetParentEntry(media, kIOServicePlane, &provider);
    IOObjectRelease(media);

    if (!provider) return {};

    // Try to get serial number from the provider
    auto serial = ioRegistryString(provider, CFSTR("Serial Number"));
    if (serial.empty())
        serial = ioRegistryString(provider, CFSTR("Device Characteristics"));
    IOObjectRelease(provider);

    if (serial.empty())
        serial = sysctlString("hw.model"); // weak fallback

    return serial;
}

} // namespace ainas::lic
