#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace ainas::lic {

std::string getCpuSerial();
std::string getMotherboardSerial();
std::string getDiskSerial();
std::string generateDeviceFingerprint();
bool generateLicense(
    const std::string& machineFingerprint,
    const std::string& privateKeyPem,
    int validityDays,
    const std::vector<std::string>& permissions,
    const std::string& outputPath);
bool importLicense(const std::string& licenseFilePath);
bool isLicenseValid();
std::string licenseInfo();
bool isLicensed();
std::string defaultLicenseStoragePath();

} // namespace ainas::lic
