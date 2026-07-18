#include "crypto_detail.h"

namespace ainas::lic {

std::string sha256Hex(const std::string& data) {
    return {};
}

std::string rsaSign(const std::string& data, const std::string& privateKeyPem) {
    return {};
}

bool rsaVerify(const std::string& data, const std::string& signature,
               const std::string& publicKeyPem) {
    return false;
}

std::vector<uint8_t> aesEncrypt(const std::vector<uint8_t>& plaintext,
                                 const std::vector<uint8_t>& key) {
    return {};
}

std::vector<uint8_t> aesDecrypt(const std::vector<uint8_t>& cipherBlob,
                                 const std::vector<uint8_t>& key) {
    return {};
}

const std::string& embeddedPublicKey() {
    static const std::string empty;
    return empty;
}

} // namespace ainas::lic
