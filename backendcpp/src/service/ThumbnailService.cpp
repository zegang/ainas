#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION

#include "ainas/service/ThumbnailService.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>

// Suppress some stb warnings
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wimplicit-float-conversion"
#elif defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

#include "stb_image.h"
#include "stb_image_resize.h"
#include "stb_image_write.h"

#ifdef __clang__
#pragma clang diagnostic pop
#elif defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

namespace ainas {

namespace {

constexpr int THUMBNAIL_SIZE = 200;

} // anonymous namespace

ThumbnailService::ThumbnailService(std::shared_ptr<Config> config)
    : m_config(std::move(config))
{}

bool ThumbnailService::generate(const std::filesystem::path& relPath) {
    auto source = m_config->dataPath / relPath;
    auto dest = thumbnailPath(relPath);
    std::error_code ec;

    if (!std::filesystem::is_regular_file(source, ec)) {
        LOG_WARN("Thumbnail: source not found: {}", source.string());
        return false;
    }

    // Ensure parent dir exists
    std::filesystem::create_directories(dest.parent_path(), ec);

    // Load image
    int w, h, channels;
    unsigned char* img = stbi_load(source.c_str(), &w, &h, &channels, 0);
    if (!img) {
        LOG_WARN("Thumbnail: failed to load {}", source.string());
        return false;
    }

    // Compute new size maintaining aspect ratio
    int newW, newH;
    if (w > h) {
        newW = THUMBNAIL_SIZE;
        newH = std::max(1, h * THUMBNAIL_SIZE / w);
    } else {
        newH = THUMBNAIL_SIZE;
        newW = std::max(1, w * THUMBNAIL_SIZE / h);
    }

    // Resize
    auto* resized = static_cast<unsigned char*>(std::malloc(newW * newH * channels));
    if (!resized) {
        stbi_image_free(img);
        LOG_ERROR("Thumbnail: malloc failed");
        return false;
    }

    stbir_resize_uint8_linear(img, w, h, 0, resized, newW, newH, 0,
                              static_cast<stbir_pixel_layout>(channels));

    stbi_image_free(img);

    // Save as JPEG
    int success;
    if (channels >= 3) {
        success = stbi_write_jpg(dest.c_str(), newW, newH, 3, resized, 90);
    } else {
        // Grayscale: expand to RGB
        auto* rgb = static_cast<unsigned char*>(std::malloc(newW * newH * 3));
        if (rgb) {
            for (int i = 0; i < newW * newH; ++i) {
                rgb[i * 3] = resized[i];
                rgb[i * 3 + 1] = resized[i];
                rgb[i * 3 + 2] = resized[i];
            }
            success = stbi_write_jpg(dest.c_str(), newW, newH, 3, rgb, 90);
            std::free(rgb);
        } else {
            success = 0;
        }
    }

    std::free(resized);

    if (!success) {
        LOG_ERROR("Thumbnail: failed to write {}", dest.string());
        return false;
    }

    LOG_DEBUG("Thumbnail created: {} ({}x{} -> {}x{})",
              dest.string(), w, h, newW, newH);
    return true;
}

bool ThumbnailService::exists(const std::filesystem::path& relPath) const {
    return std::filesystem::exists(thumbnailPath(relPath));
}

std::filesystem::path ThumbnailService::thumbnailPath(
    const std::filesystem::path& relPath) const {
    return m_config->thumbnailPath() / relPath;
}

bool ThumbnailService::remove(const std::filesystem::path& relPath) const {
    auto path = thumbnailPath(relPath);
    std::error_code ec;
    return std::filesystem::remove(path, ec);
}

bool ThumbnailService::move(const std::filesystem::path& oldRelPath,
                            const std::filesystem::path& newRelPath) {
    auto oldPath = thumbnailPath(oldRelPath);
    auto newPath = thumbnailPath(newRelPath);
    std::error_code ec;
    if (!std::filesystem::exists(oldPath, ec)) {
        return false;
    }
    std::filesystem::create_directories(newPath.parent_path(), ec);
    std::filesystem::rename(oldPath, newPath, ec);
    return !ec;
}

bool ThumbnailService::isSupportedImage(const std::filesystem::path& path) {
    auto ext = path.extension().string();
    // Case-insensitive comparison
    auto lower = [](std::string s) -> std::string {
        for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return s;
    };
    ext = lower(ext);
    return ext == ".jpg"  || ext == ".jpeg" ||
           ext == ".png"  || ext == ".bmp"  ||
           ext == ".gif"  || ext == ".webp" ||
           ext == ".tga"  || ext == ".psd"  ||
           ext == ".hdr"  || ext == ".pic"  ||
           ext == ".pnm";
}

} // namespace ainas
