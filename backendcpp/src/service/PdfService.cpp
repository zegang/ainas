#include "ainas/service/PdfService.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>

#ifdef AINAS_HAVE_POPPLER
#include <poppler/cpp/poppler-document.h>
#include <poppler/cpp/poppler-page.h>
#include <poppler/cpp/poppler-image.h>
#include <poppler/cpp/poppler-page-renderer.h>
#endif

#ifdef AINAS_HAVE_QPDF
#include <qpdf/QPDF.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <qpdf/QUtil.hh>
#endif

// stb implementation macros are in ThumbnailService.cpp — only declarations here
#include "stb_image.h"
#include "stb_image_write.h"

namespace ainas {

namespace {

const std::unordered_set<std::string> s_supportedImageExts = {
    ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"};

std::string toLower(const std::string& s) {
    std::string r = s;
    for (auto& c : r) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return r;
}

std::string safeFilename(const std::string& base, int page, int digits) {
    std::ostringstream ss;
    ss << base << "_page_" << std::setw(digits) << std::setfill('0') << page << ".png";
    return ss.str();
}

// Write a callback-compatible wrapper for stbi_write_png_to_func
struct MemWriter {
    std::vector<unsigned char> buf;
    static void writeFn(void* context, void* data, int size) {
        auto* w = static_cast<MemWriter*>(context);
        auto* bytes = static_cast<const unsigned char*>(data);
        w->buf.insert(w->buf.end(), bytes, bytes + size);
    }
};

} // anonymous namespace

PdfService::PdfService(std::shared_ptr<Config> config)
    : m_config(std::move(config)) {}

std::vector<PdfService::PdfToImagePage> PdfService::pdfToImages(
    const std::filesystem::path& sourcePath,
    const std::filesystem::path& outputDir)
{
#ifndef AINAS_HAVE_POPPLER
    throw std::runtime_error("pdfToImages: poppler not available (recompile with poppler-cpp)");
#else
    auto srcStr = sourcePath.string();
    auto start = std::chrono::steady_clock::now();
    LOG_DEBUG("pdfToImages: loading PDF \"{}\"", srcStr);

    auto doc = poppler::document::load_from_file(srcStr);
    if (!doc) {
        LOG_ERROR("pdfToImages: failed to load PDF \"{}\"", srcStr);
        throw std::runtime_error("Failed to load PDF: " + srcStr);
    }
    if (doc->is_locked()) {
        LOG_ERROR("pdfToImages: PDF is password-protected \"{}\"", srcStr);
        throw std::runtime_error("PDF is password-protected: " + srcStr);
    }

    int totalPages = doc->pages();
    auto fileSize = std::filesystem::file_size(sourcePath);
    LOG_INFO("pdfToImages: loaded \"{}\" ({} pages, {} bytes)", srcStr, totalPages, fileSize);

    std::filesystem::create_directories(outputDir);
    // Clear any stale files from previous runs so orphaned images don't persist
    for (auto& entry : std::filesystem::directory_iterator(outputDir)) {
        std::error_code ec;
        std::filesystem::remove(entry.path(), ec);
    }
    LOG_DEBUG("pdfToImages: output directory \"{}\"", outputDir.string());

    auto base = sourcePath.stem().string();
    int digits = (totalPages < 100) ? 2 : (totalPages < 1000 ? 3 : 4);

    std::vector<PdfToImagePage> results;
    results.reserve(static_cast<size_t>(totalPages));

    for (int i = 0; i < totalPages; ++i) {
        auto pageStart = std::chrono::steady_clock::now();

        auto page = doc->create_page(i);
        if (!page) {
            LOG_WARN("pdfToImages: page {}/{} – create_page returned null", i + 1, totalPages);
            continue;
        }

        // Render at 2x (144 DPI) matching Python's render(scale=2.0)
        poppler::page_renderer renderer;
        poppler::image img = renderer.render_page(page, 144.0, 144.0);
        int w = img.width();
        int h = img.height();
        if (w <= 0 || h <= 0) {
            LOG_WARN("pdfToImages: page {}/{} – zero-size render", i + 1, totalPages);
            continue;
        }

        const char* pixels = img.data();
        int stride = img.bytes_per_row();
        auto fmt = img.format();

        // Convert to packed RGB for stb_image_write
        std::vector<unsigned char> rgb(static_cast<size_t>(w) * h * 3);
        if (fmt == poppler::image::format_rgb24) {
            for (int y = 0; y < h; ++y) {
                std::memcpy(&rgb[static_cast<size_t>(y) * w * 3],
                            pixels + static_cast<size_t>(y) * stride,
                            static_cast<size_t>(w) * 3);
            }
        } else {
            // ARGB32 (format_argb32) – most common output from poppler
            // Byte order on little-endian: B, G, R, A
            for (int y = 0; y < h; ++y) {
                for (int x = 0; x < w; ++x) {
                    size_t si = static_cast<size_t>(y) * stride + static_cast<size_t>(x) * 4;
                    size_t di = (static_cast<size_t>(y) * w + static_cast<size_t>(x)) * 3;
                    rgb[di + 0] = static_cast<unsigned char>(pixels[si + 2]);
                    rgb[di + 1] = static_cast<unsigned char>(pixels[si + 1]);
                    rgb[di + 2] = static_cast<unsigned char>(pixels[si + 0]);
                }
            }
        }

        auto fname = safeFilename(base, i + 1, digits);
        auto dest = outputDir / fname;
        auto destStr = dest.string();

        int ok = stbi_write_png(destStr.c_str(), w, h, 3, rgb.data(), w * 3);
        if (!ok) {
            LOG_ERROR("pdfToImages: failed to write PNG for page {}: \"{}\"", i + 1, destStr);
            throw std::runtime_error("Failed to write PNG: " + destStr);
        }

        results.push_back({i + 1, fname, destStr});

        auto pageElapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - pageStart).count();
        LOG_DEBUG("pdfToImages: page {}/{} rendered ({}x{}) in {}ms -> \"{}\"",
                  i + 1, totalPages, w, h, pageElapsed, fname);
    }

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    LOG_INFO("pdfToImages: done ({} pages, {} images, {}ms)", totalPages, results.size(), elapsed);
    return results;
#endif
}

void PdfService::mergeToPdf(
    const std::vector<std::filesystem::path>& filePaths,
    const std::filesystem::path& outputPath)
{
#ifndef AINAS_HAVE_QPDF
    throw std::runtime_error("mergeToPdf: qpdf not available (recompile with libqpdf)");
#else
    auto start = std::chrono::steady_clock::now();
    LOG_INFO("mergeToPdf: merging {} files -> \"{}\"", filePaths.size(), outputPath.string());

    std::vector<std::filesystem::path> pdfPaths;
    std::vector<std::filesystem::path> tmpFiles;

    try {
        // Convert images to single-page PDFs first
        for (size_t i = 0; i < filePaths.size(); ++i) {
            const auto& path = filePaths[i];
            auto ext = toLower(path.extension().string());
            LOG_DEBUG("mergeToPdf: [{}/{}] processing \"{}\" (ext={})", i + 1, filePaths.size(), path.string(), ext);
            if (ext == ".pdf") {
                pdfPaths.push_back(path);
                LOG_DEBUG("mergeToPdf: [{}/{}] queued PDF directly", i + 1, filePaths.size());
            } else if (s_supportedImageExts.count(ext)) {
                auto imgStart = std::chrono::steady_clock::now();
                auto tmp = createMinimalPdfFromImage(path);
                auto imgElapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - imgStart).count();
                pdfPaths.push_back(tmp);
                tmpFiles.push_back(tmp);
                LOG_DEBUG("mergeToPdf: [{}/{}] image converted to temp PDF \"{}\" in {}ms",
                          i + 1, filePaths.size(), tmp, imgElapsed);
            } else {
                LOG_WARN("mergeToPdf: [{}/{}] unsupported file type \"{}\" skipped",
                         i + 1, filePaths.size(), path.string());
            }
        }

        if (pdfPaths.empty()) {
            LOG_ERROR("mergeToPdf: no valid PDF or image files to merge");
            throw std::runtime_error("No valid PDF or image files to merge");
        }

        LOG_INFO("mergeToPdf: merging {} PDF sources into \"{}\"", pdfPaths.size(), outputPath.string());

        // Use QPDF to merge all PDFs into one
        QPDF out;
        out.emptyPDF();
        QPDFPageDocumentHelper outHelper(out);

        int totalPagesMerged = 0;
        for (size_t i = 0; i < pdfPaths.size(); ++i) {
            const auto& p = pdfPaths[i];
            LOG_DEBUG("mergeToPdf: processing source [{}/{}] \"{}\"", i + 1, pdfPaths.size(), p.string());
            QPDF in;
            in.processFile(p.string().c_str());
            QPDFPageDocumentHelper inHelper(in);
            auto pages = inHelper.getAllPages();
            LOG_DEBUG("mergeToPdf: source [{}/{}] has {} pages", i + 1, pdfPaths.size(), pages.size());
            for (auto& page : pages) {
                outHelper.addPage(page, false);
                ++totalPagesMerged;
            }
        }

        LOG_INFO("mergeToPdf: writing {} pages to \"{}\"", totalPagesMerged, outputPath.string());
        QPDFWriter writer(out, outputPath.string().c_str());
        writer.write();
        LOG_DEBUG("mergeToPdf: QPDFWriter::write() completed");

    } catch (...) {
        LOG_ERROR("mergeToPdf: exception thrown, cleaning up {} temp files", tmpFiles.size());
        for (const auto& t : tmpFiles) {
            std::error_code ec;
            std::filesystem::remove(t, ec);
            LOG_DEBUG("mergeToPdf: cleaned up temp file \"{}\"", t.string());
        }
        throw;
    }

    for (const auto& t : tmpFiles) {
        std::error_code ec;
        std::filesystem::remove(t, ec);
        LOG_DEBUG("mergeToPdf: removed temp file \"{}\"", t.string());
    }

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    LOG_INFO("mergeToPdf: done -> \"{}\" ({}ms)", outputPath.string(), elapsed);
#endif
}

std::string PdfService::createMinimalPdfFromImage(
    const std::filesystem::path& imagePath)
{
    auto start = std::chrono::steady_clock::now();
    LOG_DEBUG("createMinimalPdfFromImage: loading \"{}\"", imagePath.string());

    int w, h, channels;
    unsigned char* imgData = stbi_load(imagePath.string().c_str(), &w, &h, &channels, 3);
    if (!imgData) {
        LOG_ERROR("createMinimalPdfFromImage: failed to load image \"{}\"", imagePath.string());
        throw std::runtime_error("Failed to load image: " + imagePath.string());
    }
    LOG_DEBUG("createMinimalPdfFromImage: loaded \"{}\" ({}x{}x{})", imagePath.string(), w, h, channels);

    MemWriter writer;
    int jpegLen = stbi_write_jpg_to_func(MemWriter::writeFn, &writer, w, h, 3, imgData, 95);
    stbi_image_free(imgData);

    if (jpegLen <= 0) {
        LOG_ERROR("createMinimalPdfFromImage: JPEG encoding failed for \"{}\"", imagePath.string());
        throw std::runtime_error("Failed to encode JPEG from: " + imagePath.string());
    }
    LOG_DEBUG("createMinimalPdfFromImage: JPEG encoded ({} bytes)", writer.buf.size());

    std::string content = "q " + std::to_string(w) + " 0 0 " + std::to_string(h) + " 0 0 cm /Im0 Do Q\n";

    // Build PDF body tracking object offsets
    std::ostringstream body;
    std::vector<size_t> offsets(6, 0); // objects 0-5

    auto writeObj = [&](int num, const std::string& data) {
        offsets[static_cast<size_t>(num)] = static_cast<size_t>(body.tellp());
        body << num << " 0 obj " << data << " endobj\n";
    };

    writeObj(1, "<</Type/Catalog/Pages 2 0 R>>");
    writeObj(2, "<</Type/Pages/Kids[3 0 R]/Count 1>>");

    std::string page = "<</Type/Page/Parent 2 0 R"
                       "/MediaBox[0 0 " + std::to_string(w) + " " + std::to_string(h) + "]"
                       "/Contents 4 0 R"
                       "/Resources<</XObject<</Im0 5 0 R>>>>>>";
    writeObj(3, page);

    std::string stream = "<</Length " + std::to_string(content.size()) + ">>stream\n" + content + "endstream";
    writeObj(4, stream);

    // Object 5: Image XObject with embedded JPEG stream — write manually to include binary data
    offsets[5] = static_cast<size_t>(body.tellp());
    body << "5 0 obj<</Type/XObject/Subtype/Image"
         << "/Width " << w
         << "/Height " << h
         << "/ColorSpace/DeviceRGB"
         << "/BitsPerComponent 8"
         << "/Filter/DCTDecode"
         << "/Length " << writer.buf.size()
         << ">>stream\n";
    body.write(reinterpret_cast<const char*>(writer.buf.data()),
               static_cast<std::streamsize>(writer.buf.size()));
    body << "\nendstream\nendobj\n";

    std::string bodyStr = body.str();

    // Assemble full PDF
    std::ostringstream pdf;
    std::string header = "%PDF-1.4\n";
    pdf << header;
    size_t baseOffset = header.size(); // xref offsets are relative to body, not final pdf
    pdf << bodyStr;
    size_t xrefOffset = static_cast<size_t>(pdf.tellp());

    pdf << "xref\n";
    pdf << "0 " << offsets.size() << "\n";
    pdf << "0000000000 65535 f \n";
    for (size_t i = 1; i < offsets.size(); ++i) {
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%010zu", offsets[i] + baseOffset);
        pdf << buf << " 00000 n \n";
    }
    pdf << "trailer<</Size " << offsets.size() << "/Root 1 0 R>>\n";
    pdf << "startxref\n" << xrefOffset << "\n%%EOF\n";

    auto tmpName = imagePath.stem().string() + "_tmp.pdf";
    auto tmpPath = std::filesystem::temp_directory_path() / tmpName;
    {
        std::ofstream out(tmpPath, std::ios::binary);
        if (!out) {
            LOG_ERROR("createMinimalPdfFromImage: failed to write temp PDF \"{}\"", tmpPath.string());
            throw std::runtime_error("Failed to create temp PDF: " + tmpPath.string());
        }
        auto s = pdf.str();
        out.write(s.data(), static_cast<std::streamsize>(s.size()));
    }

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    LOG_INFO("createMinimalPdfFromImage: \"{}\" -> \"{}\" ({}x{}, {}ms)",
             imagePath.string(), tmpPath.string(), w, h, elapsed);
    return tmpPath.string();
}

bool PdfService::isPdf(const std::filesystem::path& path) {
    return toLower(path.extension().string()) == ".pdf";
}

bool PdfService::isImage(const std::filesystem::path& path) {
    return s_supportedImageExts.count(toLower(path.extension().string())) > 0;
}

} // namespace ainas
