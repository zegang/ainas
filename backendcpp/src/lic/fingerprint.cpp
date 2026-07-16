#include "ainas/lic/lic.h"
#include "crypto_detail.h"

#include <sstream>

namespace ainas::lic {

std::string generateDeviceFingerprint() {
    std::string cpu  = getCpuSerial();
    std::string mb   = getMotherboardSerial();
    std::string disk = getDiskSerial();

    if (cpu.empty() && mb.empty() && disk.empty())
        return {};

    std::ostringstream ss;
    ss << cpu << "|" << mb << "|" << disk;
    return sha256Hex(ss.str());
}

} // namespace ainas::lic
