#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace ainas::lic {

// Internal crypto primitives shared across lic/ source files.

std::string sha256Hex(const std::string& data);

std::string rsaSign(const std::string& data, const std::string& privateKeyPem);

bool rsaVerify(const std::string& data, const std::string& signature,
               const std::string& publicKeyPem);

std::vector<uint8_t> aesEncrypt(const std::vector<uint8_t>& plaintext,
                                 const std::vector<uint8_t>& key);

std::vector<uint8_t> aesDecrypt(const std::vector<uint8_t>& cipherBlob,
                                 const std::vector<uint8_t>& key);

const std::string& embeddedPublicKey();

} // namespace ainas::lic
