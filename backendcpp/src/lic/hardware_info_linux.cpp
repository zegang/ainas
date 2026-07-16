#include "ainas/lic/lic.h"

#include <fstream>
#include <string>
#include <cstring>
#include <memory>
#include <array>

namespace ainas::lic {
namespace {

bool readFile(const char* path, std::string& out) {
    std::ifstream ifs(path);
    if (!ifs.is_open()) return false;
    std::getline(ifs, out);
    return !out.empty();
}

// Read a sysfs entry, trimming whitespace.
std::string sysfsRead(const char* path) {
    std::string val;
    if (readFile(path, val)) {
        while (!val.empty() && (val.back() == '\n' || val.back() == '\r' ||
                                val.back() == ' ' || val.back() == '\t'))
            val.pop_back();
        return val;
    }
    return {};
}

// Find the root block device name from /proc/mounts or /etc/mtab.
std::string rootDevice() {
    std::ifstream mounts("/proc/mounts");
    if (!mounts.is_open()) return {};
    std::string dev, mp, fstype, opts;
    int dump, pass;
    while (mounts >> dev >> mp >> fstype >> opts >> dump >> pass) {
        if (mp == "/") {
            // Strip /dev/ prefix and partition number, keep base name
            if (dev.find("/dev/") == 0) dev = dev.substr(5);
            // Remove trailing digit(s) for partition
            while (!dev.empty() && dev.back() >= '0' && dev.back() <= '9')
                dev.pop_back();
            // Handle NVMe: nvme0n1p1 -> nvme0n1
            if (dev.rfind('p') != std::string::npos && dev.find("nvme") != std::string::npos) {
                auto p = dev.rfind('p');
                if (p > 0 && dev[p-1] >= '0' && dev[p-1] <= '9')
                    dev = dev.substr(0, p);
            }
            return dev;
        }
    }
    return {};
}

} // anonymous namespace

std::string getCpuSerial() {
    // On x86/x64 there is no portable CPU serial number exposed via sysfs.
    // Build a composite identifier from model name, flags, and core topology.
    std::string model;
    std::string flags;
    int physId = -1, coreId = -1;

    std::ifstream cpuinfo("/proc/cpuinfo");
    if (!cpuinfo.is_open()) return {};

    std::string line;
    while (std::getline(cpuinfo, line)) {
        auto colon = line.find(':');
        if (colon == std::string::npos) continue;
        auto key = line.substr(0, colon);
        auto val = line.substr(colon + 1);
        // Trim
        while (!key.empty() && (key.back() == ' ' || key.back() == '\t'))
            key.pop_back();
        while (!val.empty() && (val.front() == ' ' || val.front() == '\t'))
            val.erase(val.begin());

        if (key == "model name" && model.empty())         model = val;
        if (key == "flags" && flags.empty())              flags = val;
        if (key == "physical id" && physId < 0)           physId = std::stoi(val);
        if (key == "core id" && coreId < 0)               coreId = std::stoi(val);
        if (key == "processor") {
            // First processor entry parsed — stop.
            if (!model.empty() && !flags.empty()) break;
        }
    }

    if (model.empty()) model = "unknown";
    if (flags.empty()) flags = "unknown";

    return model + "::" + std::to_string(physId) + "::" +
           std::to_string(coreId) + "::" + flags;
}

std::string getMotherboardSerial() {
    std::string s = sysfsRead("/sys/class/dmi/id/board_serial");
    if (s.empty()) s = sysfsRead("/sys/devices/virtual/dmi/id/board_serial");
    // Some vendors use "To be filled by O.E.M." as placeholder — treat as empty
    if (s.find("O.E.M") != std::string::npos || s.find("Default") != std::string::npos)
        return {};
    return s;
}

std::string getDiskSerial() {
    auto dev = rootDevice();
    if (dev.empty()) return {};

    std::string path = "/sys/block/" + dev + "/serial";
    auto serial = sysfsRead(path.c_str());
    if (!serial.empty()) return serial;

    // Fallback: try device identifier
    path = "/sys/block/" + dev + "/device/model";
    auto model = sysfsRead(path.c_str());
    if (!model.empty()) return model;

    return {};
}

} // namespace ainas::lic
