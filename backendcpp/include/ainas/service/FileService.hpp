#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/database/FileRepository.hpp"
#include "ainas/dto/DTOs.hpp"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace ainas {

class FileServiceError : public std::runtime_error {
public:
    enum class Kind { NotFound, BadRequest, Conflict, Internal };
    Kind kind;
    FileServiceError(Kind k, const std::string& msg)
        : std::runtime_error(msg), kind(k) {}
};

class FileService {
public:
    explicit FileService(std::shared_ptr<Config> config,
                         Database& database);

    oatpp::Object<FileListResponseDto> listFiles(const oatpp::String& pathStr);
    oatpp::Object<UploadResponseDto> uploadFile(const std::string& tmpPath,
                                                  const oatpp::String& filename,
                                                  const oatpp::String& targetDir);
    oatpp::Object<ApiResponseDto> deleteFile(const oatpp::String& pathStr);
    oatpp::Object<ApiResponseDto> moveFile(const oatpp::Object<MoveRequestDto>& body);
    oatpp::Object<ApiResponseDto> copyFile(const oatpp::Object<CopyRequestDto>& body);
    oatpp::Object<ApiResponseDto> renameFile(const oatpp::Object<RenameRequestDto>& body);
    oatpp::Object<ApiResponseDto> createFolder(const oatpp::String& pathStr);

    oatpp::Object<FileDetailResponseDto> getFileById(int64_t id);
    oatpp::Object<FileDetailResponseDto> updateFile(int64_t id,
        const oatpp::Object<UpdateFileRequestDto>& body);
    oatpp::Object<ApiResponseDto> deleteFileById(int64_t id);

    static std::string generateRandomString(size_t length);

    std::filesystem::path resolvePath(const std::string& relativePath) const;
    std::filesystem::path resolveExistingPath(const std::string& relativePath) const;

private:
    std::shared_ptr<Config> m_config;
    FileRepository m_repo;

    v_int64 formatTime(std::filesystem::file_time_type ftime) const;
    oatpp::Object<FileItemDto> makeFileItem(const std::filesystem::directory_entry& entry,
                                              const std::filesystem::path& relPath) const;
    oatpp::Object<FileItemDto> recordToDto(const FileRepository::Record& record) const;

    int64_t syncDirectory(const std::filesystem::path& fullPath,
                           const std::string& relPath,
                           std::optional<int64_t> parentId);
};

} // namespace ainas
