#include "ainas/lic/lic.h"

#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#ifdef AINAS_HAVE_OPENSSL
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#endif

// ── Help text ──────────────────────────────────────────────────────────

static const char* kHelp =
    "Usage: lic_gen <command> [options]\n"
    "\n"
    "Commands:\n"
    "  keygen              Generate an RSA-2048 key pair\n"
    "    -k, --private-key PATH   Output path for private key (default: private.pem)\n"
    "    -p, --public-key  PATH   Output path for public  key (default: public.pem)\n"
    "\n"
    "  generate            Create a signed license file\n"
    "    -k, --private-key PATH   RSA private key PEM file (required)\n"
    "    -f, --fingerprint HEX    Device fingerprint hex (required)\n"
    "    -d, --days        NUM    Validity in days (default: 365)\n"
    "    -P, --permissions LIST   Comma-separated permissions (default: all)\n"
    "                             Use \"list-features\" to see known values\n"
    "    -o, --output      PATH   Output license file (default: license.lic)\n"
    "\n"
    "  list-features       List known feature permissions\n"
    "\n"
    "  -h, --help                Show this help\n"
    "\n"
    "Workflow:\n"
    "  1. On the target device:  GET /api/license/hardware-info  →  deviceFingerprint\n"
    "  2. On the developer machine:\n"
    "       lic_gen generate -k private.pem -f <fingerprint> -o license.lic\n"
    "  3. On the target device:  POST /api/license/import  (body = content of license.lic)\n"
;

// ── File I/O helpers ───────────────────────────────────────────────────

static std::string readFile(const std::string& path) {
    std::ifstream ifs(path, std::ios::binary | std::ios::ate);
    if (!ifs.is_open()) {
        std::cerr << "error: cannot open " << path << "\n";
        std::exit(1);
    }
    auto size = ifs.tellg();
    ifs.seekg(0);
    std::string buf(static_cast<size_t>(size), '\0');
    ifs.read(buf.data(), static_cast<std::streamsize>(buf.size()));
    return buf;
}

static void writeFile(const std::string& path, const std::string& data) {
    std::ofstream ofs(path, std::ios::binary);
    if (!ofs.is_open()) {
        std::cerr << "error: cannot write " << path << "\n";
        std::exit(1);
    }
    ofs.write(data.data(), static_cast<std::streamsize>(data.size()));
}

// ── Key generation ─────────────────────────────────────────────────────

#ifdef AINAS_HAVE_OPENSSL
static void cmdKeygen(const std::string& privPath, const std::string& pubPath) {
    EVP_PKEY* pkey = EVP_PKEY_new();
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nullptr);
    if (!ctx) { std::cerr << "EVP_PKEY_CTX_new_id failed\n"; std::exit(1); }

    if (EVP_PKEY_keygen_init(ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, 2048) <= 0 ||
        EVP_PKEY_keygen(ctx, &pkey) <= 0) {
        std::cerr << "RSA key generation failed\n";
        std::exit(1);
    }
    EVP_PKEY_CTX_free(ctx);

    // Write private key
    {
        BIO* bio = BIO_new_file(privPath.c_str(), "w");
        if (!bio || !PEM_write_bio_PrivateKey(bio, pkey, nullptr, nullptr, 0, nullptr, nullptr)) {
            std::cerr << "failed to write private key\n";
            std::exit(1);
        }
        BIO_free(bio);
    }

    // Write public key
    {
        BIO* bio = BIO_new_file(pubPath.c_str(), "w");
        if (!bio || !PEM_write_bio_PUBKEY(bio, pkey)) {
            std::cerr << "failed to write public key\n";
            std::exit(1);
        }
        BIO_free(bio);
    }

    EVP_PKEY_free(pkey);
    std::cout << "Generated RSA-2048 key pair:\n"
              << "  private: " << privPath << "\n"
              << "  public:  " << pubPath << "\n";
}
#else
static void cmdKeygen(const std::string&, const std::string&) {
    std::cerr << "error: keygen requires OpenSSL (not available in this build)\n";
    std::exit(1);
}
#endif

// ── License generation ─────────────────────────────────────────────────

static void cmdGenerate(const std::string& privKeyPath,
                         const std::string& fingerprint,
                         int days,
                         const std::vector<std::string>& permissions,
                         const std::string& outputPath) {
    auto pem = readFile(privKeyPath);

    bool ok = ainas::lic::generateLicense(
        fingerprint, pem, days, permissions, outputPath);

    if (!ok) {
        std::cerr << "error: license generation failed\n";
        std::exit(1);
    }
    std::cout << "License written to " << outputPath << "\n";
}

// ── Argument helpers ───────────────────────────────────────────────────

static std::string shift(int& argc, char const* argv[], int& i) {
    if (i >= argc) {
        std::cerr << "error: expected value after " << argv[argc - 1] << "\n";
        std::exit(1);
    }
    return argv[i++];
}

static bool match(const char* arg, const char* shortForm, const char* longForm) {
    return (shortForm && strcmp(arg, shortForm) == 0) ||
           (longForm && strcmp(arg, longForm) == 0);
}

// ── List features ──────────────────────────────────────────────────────

struct FeatureInfo { const char* name; const char* desc; };
static const FeatureInfo kFeatures[] = {
    {"all",       "All features (grants every permission)"},
    {"ai",        "AI assistant and AI configuration"},
    {"multiuser", "Multi-user login and user management"},
    {"sync",      "File synchronization across devices"},
    {"storage",   "Storage management and quotas"},
};

static void cmdListFeatures() {
    std::cout << "Known feature permissions:\n\n";
    for (const auto& f : kFeatures) {
        std::cout << "  " << f.name;
        size_t pad = 16;
        size_t len = std::strlen(f.name);
        if (len < pad) std::cout << std::string(pad - len, ' ');
        else std::cout << "  ";
        std::cout << f.desc << "\n";
    }
    std::cout << "\nUse with: lic_gen generate -P <comma-separated-values>\n";
}

// ── Main ───────────────────────────────────────────────────────────────

int main(int argc, char const* argv[]) {
    if (argc < 2) {
        std::cout << kHelp;
        return 0;
    }

    std::string cmd = argv[1];
    if (cmd == "-h" || cmd == "--help") {
        std::cout << kHelp;
        return 0;
    }

    if (cmd == "keygen") {
        std::string privPath = "private.pem";
        std::string pubPath = "public.pem";
        int i = 2;
        while (i < argc) {
            std::string arg = argv[i++];
            if (match(arg.c_str(), "-k", "--private-key"))
                privPath = shift(argc, argv, i);
            else if (match(arg.c_str(), "-p", "--public-key"))
                pubPath = shift(argc, argv, i);
            else {
                std::cerr << "unknown option: " << arg << "\n";
                return 1;
            }
        }
        cmdKeygen(privPath, pubPath);
        return 0;
    }

    if (cmd == "generate") {
        std::string privKeyPath;
        std::string fingerprint;
        int days = 365;
        std::vector<std::string> permissions = {"all"};
        std::string outputPath = "license.lic";

        int i = 2;
        while (i < argc) {
            std::string arg = argv[i++];
            if (match(arg.c_str(), "-k", "--private-key"))
                privKeyPath = shift(argc, argv, i);
            else if (match(arg.c_str(), "-f", "--fingerprint"))
                fingerprint = shift(argc, argv, i);
            else if (match(arg.c_str(), "-d", "--days"))
                days = std::stoi(shift(argc, argv, i));
            else if (match(arg.c_str(), "-P", "--permissions")) {
                permissions.clear();
                auto raw = shift(argc, argv, i);
                std::istringstream ss(raw);
                std::string tok;
                while (std::getline(ss, tok, ','))
                    permissions.push_back(tok);
            } else if (match(arg.c_str(), "-o", "--output"))
                outputPath = shift(argc, argv, i);
            else {
                std::cerr << "unknown option: " << arg << "\n";
                return 1;
            }
        }

        if (privKeyPath.empty()) {
            std::cerr << "error: --private-key is required\n";
            return 1;
        }
        if (fingerprint.empty()) {
            std::cerr << "error: --fingerprint is required\n";
            return 1;
        }

        cmdGenerate(privKeyPath, fingerprint, days, permissions, outputPath);
        return 0;
    }

    if (cmd == "list-features") {
        cmdListFeatures();
        return 0;
    }

    std::cerr << "unknown command: " << cmd << "\n";
    std::cout << kHelp;
    return 1;
}
