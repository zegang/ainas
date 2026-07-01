#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/logging/Logger.hpp"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace ainas {

class PdfService {
public:
    explicit PdfService(std::shared_ptr<Config> config);

    struct PdfToImagePage {
        int page{};
        std::string filename;
        std::string path;
    };

    std::vector<PdfToImagePage> pdfToImages(
        const std::filesystem::path& sourcePath,
        const std::filesystem::path& outputDir);

    void mergeToPdf(
        const std::vector<std::filesystem::path>& filePaths,
        const std::filesystem::path& outputPath);

    static bool isPdf(const std::filesystem::path& path);
    static bool isImage(const std::filesystem::path& path);

private:
    std::string createMinimalPdfFromImage(
        const std::filesystem::path& imagePath);

    std::filesystem::path resolvePath(const std::string& relPath) const;

    std::shared_ptr<Config> m_config;
};

} // namespace ainas
