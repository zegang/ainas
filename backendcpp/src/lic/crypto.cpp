#include "crypto_detail.h"

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/sha.h>
#include <openssl/err.h>
#include <openssl/rand.h>
#include <openssl/bio.h>

#include <cstring>
#include <memory>
#include <vector>
#include <stdexcept>

namespace ainas::lic {
namespace {

// ── RAII wrappers for OpenSSL types ──────────────────────────────────

struct BioFree {
    void operator()(BIO* p) const { if (p) BIO_free(p); }
};
using BioPtr = std::unique_ptr<BIO, BioFree>;

struct EvpPkeyFree {
    void operator()(EVP_PKEY* p) const { if (p) EVP_PKEY_free(p); }
};
using EvpPkeyPtr = std::unique_ptr<EVP_PKEY, EvpPkeyFree>;

struct EvpMdCtxFree {
    void operator()(EVP_MD_CTX* p) const { if (p) EVP_MD_CTX_free(p); }
};
using EvpMdCtxPtr = std::unique_ptr<EVP_MD_CTX, EvpMdCtxFree>;

struct EvpCipherCtxFree {
    void operator()(EVP_CIPHER_CTX* p) const { if (p) EVP_CIPHER_CTX_free(p); }
};
using EvpCipherCtxPtr = std::unique_ptr<EVP_CIPHER_CTX, EvpCipherCtxFree>;

// ── PEM helpers ──────────────────────────────────────────────────────

EVP_PKEY* readPrivateKey(const std::string& pem) {
    BioPtr bio(BIO_new_mem_buf(pem.data(), static_cast<int>(pem.size())));
    if (!bio) return nullptr;
    return PEM_read_bio_PrivateKey(bio.get(), nullptr, nullptr, nullptr);
}

EVP_PKEY* readPublicKey(const std::string& pem) {
    BioPtr bio(BIO_new_mem_buf(pem.data(), static_cast<int>(pem.size())));
    if (!bio) return nullptr;
    return PEM_read_bio_PUBKEY(bio.get(), nullptr, nullptr, nullptr);
}

} // anonymous namespace

// ── SHA-256 ─────────────────────────────────────────────────────────

std::string sha256Hex(const std::string& data) {
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(data.data()), data.size(), hash);
    const char hex[] = "0123456789abcdef";
    std::string out;
    out.reserve(SHA256_DIGEST_LENGTH * 2);
    for (auto b : hash) {
        out += hex[b >> 4];
        out += hex[b & 0xf];
    }
    return out;
}

// ── RSA Sign ────────────────────────────────────────────────────────

std::string rsaSign(const std::string& data, const std::string& privateKeyPem) {
    EvpPkeyPtr pkey(readPrivateKey(privateKeyPem));
    if (!pkey) return {};

    EvpMdCtxPtr ctx(EVP_MD_CTX_new());
    if (!ctx) return {};

    if (EVP_DigestSignInit(ctx.get(), nullptr, EVP_sha256(), nullptr,
                           pkey.get()) != 1)
        return {};

    if (EVP_DigestSignUpdate(ctx.get(), data.data(), data.size()) != 1)
        return {};

    size_t sigLen = 0;
    if (EVP_DigestSignFinal(ctx.get(), nullptr, &sigLen) != 1)
        return {};

    std::string sig(sigLen, '\0');
    if (EVP_DigestSignFinal(ctx.get(),
                            reinterpret_cast<unsigned char*>(sig.data()),
                            &sigLen) != 1)
        return {};

    sig.resize(sigLen);
    return sig;
}

// ── RSA Verify ──────────────────────────────────────────────────────

bool rsaVerify(const std::string& data, const std::string& signature,
               const std::string& publicKeyPem) {
    EvpPkeyPtr pkey(readPublicKey(publicKeyPem));
    if (!pkey) return false;

    EvpMdCtxPtr ctx(EVP_MD_CTX_new());
    if (!ctx) return false;

    if (EVP_DigestVerifyInit(ctx.get(), nullptr, EVP_sha256(), nullptr,
                             pkey.get()) != 1)
        return false;

    if (EVP_DigestVerifyUpdate(ctx.get(), data.data(), data.size()) != 1)
        return false;

    int ret = EVP_DigestVerifyFinal(
        ctx.get(),
        reinterpret_cast<const unsigned char*>(signature.data()),
        signature.size());
    return ret == 1;
}

// ── AES-256-GCM Encrypt ──────────────────────────────────────────────
// Returns: [12-byte IV] [ciphertext + 16-byte GCM tag]
// The key is 32 bytes (SHA-256 of the keyMaterial).

std::vector<uint8_t> aesEncrypt(const std::vector<uint8_t>& plaintext,
                                 const std::vector<uint8_t>& key) {
    if (key.size() != 32) return {};

    EvpCipherCtxPtr ctx(EVP_CIPHER_CTX_new());
    if (!ctx) return {};

    if (EVP_EncryptInit_ex(ctx.get(), EVP_aes_256_gcm(), nullptr,
                           nullptr, nullptr) != 1)
        return {};

    // 12-byte random IV
    std::vector<uint8_t> iv(12);
    if (RAND_bytes(iv.data(), static_cast<int>(iv.size())) != 1)
        return {};

    if (EVP_EncryptInit_ex(ctx.get(), nullptr, nullptr, key.data(),
                           iv.data()) != 1)
        return {};

    std::vector<uint8_t> out(plaintext.size() + 16);
    int outLen = 0;

    if (EVP_EncryptUpdate(ctx.get(), out.data(), &outLen,
                          plaintext.data(),
                          static_cast<int>(plaintext.size())) != 1)
        return {};

    int totalLen = outLen;
    if (EVP_EncryptFinal_ex(ctx.get(), out.data() + totalLen,
                            &outLen) != 1)
        return {};
    totalLen += outLen;

    // Get GCM tag (last 16 bytes)
    std::vector<uint8_t> tag(16);
    if (EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_GET_TAG, 16,
                            tag.data()) != 1)
        return {};

    // Assemble: IV + ciphertext + tag
    std::vector<uint8_t> result;
    result.reserve(iv.size() + totalLen + tag.size());
    result.insert(result.end(), iv.begin(), iv.end());
    result.insert(result.end(), out.begin(), out.begin() + totalLen);
    result.insert(result.end(), tag.begin(), tag.end());
    return result;
}

// ── AES-256-GCM Decrypt ──────────────────────────────────────────────
// Input format: [12-byte IV] [ciphertext] [16-byte GCM tag]

std::vector<uint8_t> aesDecrypt(const std::vector<uint8_t>& cipherBlob,
                                 const std::vector<uint8_t>& key) {
    if (key.size() != 32 || cipherBlob.size() < 12 + 16) return {};

    const size_t ivSize = 12;
    const size_t tagSize = 16;
    const size_t ctSize = cipherBlob.size() - ivSize - tagSize;

    const uint8_t* iv = cipherBlob.data();
    const uint8_t* ct = cipherBlob.data() + ivSize;
    const uint8_t* tag = cipherBlob.data() + ivSize + ctSize;

    EvpCipherCtxPtr ctx(EVP_CIPHER_CTX_new());
    if (!ctx) return {};

    if (EVP_DecryptInit_ex(ctx.get(), EVP_aes_256_gcm(), nullptr,
                           nullptr, nullptr) != 1)
        return {};

    if (EVP_DecryptInit_ex(ctx.get(), nullptr, nullptr, key.data(),
                           iv) != 1)
        return {};

    std::vector<uint8_t> out(ctSize);
    int outLen = 0;

    if (EVP_DecryptUpdate(ctx.get(), out.data(), &outLen, ct,
                          static_cast<int>(ctSize)) != 1)
        return {};

    // Set expected tag
    if (EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_SET_TAG,
                            static_cast<int>(tagSize),
                            const_cast<uint8_t*>(tag)) != 1)
        return {};

    int finalLen = 0;
    if (EVP_DecryptFinal_ex(ctx.get(), out.data() + outLen,
                            &finalLen) != 1)
        return {}; // authentication failed

    out.resize(static_cast<size_t>(outLen + finalLen));
    return out;
}

// ── Embedded Public Key ──────────────────────────────────────────────
// The actual key is generated by CMake's configure_file at build time.
#include "lic_public_key.h"

const std::string& embeddedPublicKey() {
    static const std::string key(kLicPublicKey);
    return key;
}

} // namespace ainas::lic
