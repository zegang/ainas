#include "ainas/lic/lic.h"
#include "crypto_detail.h"

#include <fstream>
#include <sstream>
#include <vector>
#include <ctime>
#include <chrono>
#include <cstdlib>

#ifdef _WIN32
#include <windows.h>
#include <shlobj.h>
#pragma comment(lib, "shell32.lib")
#else
#include <unistd.h>
#include <sys/stat.h>
#include <pwd.h>
#endif

namespace ainas::lic {
namespace {

// ── Base64 (RFC 4648) helpers for embedding binary signatures ─────────

static const char kBase64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64Encode(const std::string& in) {
    std::string out;
    out.reserve(((in.size() + 2) / 3) * 4);
    unsigned val = 0;
    int bits = 0;
    for (unsigned char c : in) {
        val = (val << 8) | c;
        bits += 8;
        while (bits >= 6) {
            bits -= 6;
            out += kBase64[(val >> bits) & 0x3f];
        }
    }
    if (bits > 0) {
        out += kBase64[(val << (6 - bits)) & 0x3f];
        while (out.size() % 4) out += '=';
    }
    return out;
}

std::string base64Decode(const std::string& in) {
    std::string out;
    out.reserve((in.size() / 4) * 3);
    unsigned val = 0;
    int bits = 0;
    for (unsigned char c : in) {
        if (c == '=') break;
        int idx = -1;
        if (c >= 'A' && c <= 'Z') idx = c - 'A';
        else if (c >= 'a' && c <= 'z') idx = c - 'a' + 26;
        else if (c >= '0' && c <= '9') idx = c - '0' + 52;
        else if (c == '+') idx = 62;
        else if (c == '/') idx = 63;
        if (idx < 0) continue;
        val = (val << 6) | idx;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out += static_cast<char>((val >> bits) & 0xff);
        }
    }
    return out;
}

// ── Platform storage directory ────────────────────────────────────────

std::string configDir() {
#ifdef _WIN32
    wchar_t path[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA,
                                    nullptr, 0, path))) {
        char buf[MAX_PATH];
        WideCharToMultiByte(CP_UTF8, 0, path, -1, buf, sizeof(buf),
                            nullptr, nullptr);
        return std::string(buf) + "\\ainas";
    }
    return {};
#else
    const char* home = getenv("HOME");
    if (!home) {
        struct passwd* pw = getpwuid(getuid());
        if (pw) home = pw->pw_dir;
    }
    if (!home) return {};
    std::string dir = std::string(home) + "/.config/ainas";
    mkdir(dir.c_str(), 0700);
    return dir;
#endif
}

// ── Now helpers ────────────────────────────────────────────────────────

std::string nowIsoTimestamp() {
    auto now = std::chrono::system_clock::now();
    auto tt = std::chrono::system_clock::to_time_t(now);
    auto tm = std::gmtime(&tt);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", tm);
    return std::string(buf);
}

int64_t isoToEpochMs(const std::string& iso) {
    // Parse "YYYY-MM-DDTHH:MM:SSZ"
    int y = 0, M = 0, d = 0, h = 0, m = 0, s = 0;
    if (sscanf(iso.c_str(), "%d-%d-%dT%d:%d:%dZ", &y, &M, &d, &h, &m, &s) < 3)
        return 0;
    struct tm tm = {};
    tm.tm_year = y - 1900;
    tm.tm_mon  = M - 1;
    tm.tm_mday = d;
    tm.tm_hour = h;
    tm.tm_min  = m;
    tm.tm_sec  = s;
#ifdef _MSC_VER
    auto tt = _mkgmtime(&tm);
#else
    auto tt = timegm(&tm);
#endif
    return static_cast<int64_t>(tt) * 1000;
}

// ── Build license payload JSON (before signing) ───────────────────────

std::string buildLicenseJson(const std::string& fingerprint,
                              int validityDays,
                              const std::vector<std::string>& permissions) {
    auto issued = nowIsoTimestamp();
    // Compute expiry as ISO timestamp by adding days to current time
    auto nowMs = isoToEpochMs(issued);
    auto expMs = nowMs + static_cast<int64_t>(validityDays) * 86400000LL;
    // Convert back to ISO
    time_t expT = static_cast<time_t>(expMs / 1000);
    auto tm = std::gmtime(&expT);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", tm);
    std::string expires(buf);

    std::ostringstream json;
    json << "{\"machine_fingerprint\":\""
         << fingerprint
         << "\",\"issued\":\"" << issued
         << "\",\"expires\":\"" << expires
         << "\",\"permissions\":[";
    for (size_t i = 0; i < permissions.size(); ++i) {
        if (i > 0) json << ",";
        json << "\"" << permissions[i] << "\"";
    }
    json << "]}";
    return json.str();
}

// Parse a license JSON string and extract fields.
bool parseLicenseJson(const std::string& json, std::string& fingerprint,
                      std::string& issued, std::string& expires,
                      std::vector<std::string>& permissions) {
    // Simple JSON parser for known key-value format. Not a full JSON parser.
    auto extract = [&](const std::string& key) -> std::string {
        auto pos = json.find("\"" + key + "\"");
        if (pos == std::string::npos) return {};
        auto colon = json.find(':', pos + key.size() + 2);
        if (colon == std::string::npos) return {};
        auto start = json.find_first_not_of(" \t\"", colon + 1);
        if (start == std::string::npos) return {};
        if (json[start] == '{' || json[start] == '[') {
            // Complex value — not handled for scalar fields
            return {};
        }
        auto end = json.find_first_of(",\"", start);
        if (end == std::string::npos)
            end = json.find('}', start);
        if (json[start] == '"') {
            start++;
            end = json.find('"', start);
        }
        if (start >= end) return {};
        return json.substr(start, end - start);
    };

    fingerprint = extract("machine_fingerprint");
    issued = extract("issued");
    expires = extract("expires");

    // Extract permissions array
    auto permStart = json.find("\"permissions\"");
    if (permStart != std::string::npos) {
        auto arrStart = json.find('[', permStart);
        if (arrStart != std::string::npos) {
            auto arrEnd = json.find(']', arrStart);
            if (arrEnd != std::string::npos) {
                auto content = json.substr(arrStart + 1, arrEnd - arrStart - 1);
                size_t p = 0;
                while (true) {
                    auto q = content.find('"', p);
                    if (q == std::string::npos) break;
                    auto r = content.find('"', q + 1);
                    if (r == std::string::npos) break;
                    permissions.push_back(content.substr(q + 1, r - q - 1));
                    p = r + 1;
                }
            }
        }
    }

    return true;
}

// Storage key: SHA-256 of the device fingerprint (32 bytes).
std::vector<uint8_t> storageKey() {
    auto fp = generateDeviceFingerprint();
    if (fp.empty()) return {};
    auto hash = sha256Hex(fp);
    return std::vector<uint8_t>(hash.begin(), hash.end());
}

} // anonymous namespace

// ── Public functions ───────────────────────────────────────────────────

std::string defaultLicenseStoragePath() {
    auto dir = configDir();
    if (dir.empty()) return {};
    return dir + "/license.enc";
}

bool generateLicense(const std::string& machineFingerprint,
                     const std::string& privateKeyPem,
                     int validityDays,
                     const std::vector<std::string>& permissions,
                     const std::string& outputPath) {
    if (machineFingerprint.empty() || privateKeyPem.empty() || outputPath.empty())
        return false;

    auto payload = buildLicenseJson(machineFingerprint, validityDays,
                                    permissions);
    if (payload.empty()) return false;

    auto sig = rsaSign(payload, privateKeyPem);
    if (sig.empty()) return false;

    // Write: line1=JSON payload, line2=base64 signature
    std::ofstream ofs(outputPath, std::ios::binary);
    if (!ofs.is_open()) return false;

    ofs << payload << "\n" << base64Encode(sig) << "\n";
    return ofs.good();
}

bool importLicense(const std::string& licenseFilePath) {
    // Read the license file
    std::ifstream ifs(licenseFilePath, std::ios::binary);
    if (!ifs.is_open()) return false;

    std::string payload, sigB64;
    std::getline(ifs, payload);
    std::getline(ifs, sigB64);
    if (payload.empty() || sigB64.empty()) return false;

    auto signature = base64Decode(sigB64);
    if (signature.empty()) return false;

    // Verify signature against embedded public key
    if (!rsaVerify(payload, signature, embeddedPublicKey()))
        return false;

    // Verify device binding
    std::string fp;
    std::string issued, expires;
    std::vector<std::string> permissions;
    if (!parseLicenseJson(payload, fp, issued, expires, permissions))
        return false;

    auto deviceFp = generateDeviceFingerprint();
    if (deviceFp.empty() || fp != deviceFp)
        return false;

    auto nowMs = isoToEpochMs(nowIsoTimestamp());

    // Check not before issued
    if (nowMs < isoToEpochMs(issued))
        return false;

    // Check expiry
    if (nowMs > isoToEpochMs(expires))
        return false;

    // Encrypt and store locally
    auto key = storageKey();
    if (key.empty()) return false;

    std::vector<uint8_t> plaintext(payload.begin(), payload.end());
    auto encrypted = aesEncrypt(plaintext, key);
    if (encrypted.empty()) return false;

    auto storagePath = defaultLicenseStoragePath();
    if (storagePath.empty()) return false;

    // Ensure directory exists
    auto dir = configDir();
    (void)dir; // already created in configDir()

    std::ofstream storage(storagePath, std::ios::binary);
    if (!storage.is_open()) return false;

    storage.write(reinterpret_cast<const char*>(encrypted.data()),
                  static_cast<std::streamsize>(encrypted.size()));
    return storage.good();
}

bool isLicenseValid() {
    auto storagePath = defaultLicenseStoragePath();
    if (storagePath.empty()) return false;

    std::ifstream storage(storagePath, std::ios::binary | std::ios::ate);
    if (!storage.is_open()) return false;

    auto size = storage.tellg();
    if (size <= 0) return false;
    storage.seekg(0);

    std::vector<uint8_t> blob(static_cast<size_t>(size));
    if (!storage.read(reinterpret_cast<char*>(blob.data()),
                      static_cast<std::streamsize>(blob.size())))
        return false;

    auto key = storageKey();
    if (key.empty()) return false;

    auto plaintext = aesDecrypt(blob, key);
    if (plaintext.empty()) return false;

    std::string payload(plaintext.begin(), plaintext.end());

    // Parse and verify
    std::string fp;
    std::string issued, expires;
    std::vector<std::string> permissions;
    if (!parseLicenseJson(payload, fp, issued, expires, permissions))
        return false;

    // Check device binding
    auto deviceFp = generateDeviceFingerprint();
    if (deviceFp.empty() || fp != deviceFp)
        return false;

    auto nowMs = isoToEpochMs(nowIsoTimestamp());

    // Check not before issued
    if (nowMs < isoToEpochMs(issued))
        return false;

    // Check expiry
    if (nowMs > isoToEpochMs(expires))
        return false;

    return true;
}

std::string licenseInfo() {
    auto storagePath = defaultLicenseStoragePath();
    if (storagePath.empty()) return {};

    std::ifstream storage(storagePath, std::ios::binary | std::ios::ate);
    if (!storage.is_open()) return {};

    auto size = storage.tellg();
    if (size <= 0) return {};
    storage.seekg(0);

    std::vector<uint8_t> blob(static_cast<size_t>(size));
    if (!storage.read(reinterpret_cast<char*>(blob.data()),
                      static_cast<std::streamsize>(blob.size())))
        return {};

    auto key = storageKey();
    if (key.empty()) return {};

    auto plaintext = aesDecrypt(blob, key);
    if (plaintext.empty()) return {};

    return std::string(plaintext.begin(), plaintext.end());
}

bool isLicensed() {
    return isLicenseValid();
}

bool hasPermission(const std::string& permission) {
    auto info = licenseInfo();
    if (info.empty()) return false;
    std::string fp, issued, expires;
    std::vector<std::string> perms;
    if (!parseLicenseJson(info, fp, issued, expires, perms))
        return false;
    for (const auto& p : perms) {
        if (p == "all" || p == permission)
            return true;
    }
    return false;
}

std::vector<std::string> grantedPermissions() {
    auto info = licenseInfo();
    if (info.empty()) return {};
    std::string fp, issued, expires;
    std::vector<std::string> perms;
    parseLicenseJson(info, fp, issued, expires, perms);
    return perms;
}

} // namespace ainas::lic
