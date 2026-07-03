#pragma once

#include "oatpp/macro/codegen.hpp"
#include "oatpp/Types.hpp"

#include OATPP_CODEGEN_BEGIN(DTO)

namespace ainas {

class FileItemDto : public oatpp::DTO {
    DTO_INIT(FileItemDto, DTO)
    DTO_FIELD(Int64, id, "id");
    DTO_FIELD(String, name);
    DTO_FIELD(String, path);
    DTO_FIELD(Int64, size);
    DTO_FIELD(Boolean, isDirectory, "is_dir");
    DTO_FIELD(Int64, createdAt, "created_at");
    DTO_FIELD(Int64, updatedAt, "updated_at");
    DTO_FIELD(Vector<String>, tags);
};

class FileDetailResponseDto : public oatpp::DTO {
    DTO_INIT(FileDetailResponseDto, DTO)
    DTO_FIELD(Boolean, success);
    DTO_FIELD(String, message);
    DTO_FIELD(Object<FileItemDto>, file);
};

class UpdateFileRequestDto : public oatpp::DTO {
    DTO_INIT(UpdateFileRequestDto, DTO)
    DTO_FIELD(String, name);
    DTO_FIELD(Int64, parentId, "parent_id");
    DTO_FIELD(Vector<String>, tags);
};

class FileListResponseDto : public oatpp::DTO {
    DTO_INIT(FileListResponseDto, DTO)
    DTO_FIELD(Vector<Object<FileItemDto>>, items);
    DTO_FIELD(String, path);
    DTO_FIELD(Boolean, success);
    DTO_FIELD(String, message);
};

class ApiResponseDto : public oatpp::DTO {
    DTO_INIT(ApiResponseDto, DTO)
    DTO_FIELD(Boolean, success);
    DTO_FIELD(String, message);
    DTO_FIELD(String, path);
    DTO_FIELD(Vector<String>, files);
    DTO_FIELD(Vector<String>, sources);
};

class UploadResponseDto : public oatpp::DTO {
    DTO_INIT(UploadResponseDto, DTO)
    DTO_FIELD(Boolean, success);
    DTO_FIELD(String, message);
    DTO_FIELD(String, name);
    DTO_FIELD(String, path);
    DTO_FIELD(Int64, size);
};

class DeleteRequestDto : public oatpp::DTO {
    DTO_INIT(DeleteRequestDto, DTO)
    DTO_FIELD(String, path);
};

class MoveRequestDto : public oatpp::DTO {
    DTO_INIT(MoveRequestDto, DTO)
    DTO_FIELD(String, path);
    DTO_FIELD(String, newPath, "new_path");
    DTO_FIELD(Int64, id, "id");
    DTO_FIELD(String, itemId, "item_id");
    DTO_FIELD(Int64, targetParentId, "target_parent_id");
    DTO_FIELD(String, targetParentPath, "target_parent_path");
};

class CopyRequestDto : public oatpp::DTO {
    DTO_INIT(CopyRequestDto, DTO)
    DTO_FIELD(Vector<String>, paths);
    DTO_FIELD(Vector<Int64>, ids, "ids");
    DTO_FIELD(String, targetDir, "target_dir");
    DTO_FIELD(Int64, targetDirId, "target_dir_id");
};

class RenameRequestDto : public oatpp::DTO {
    DTO_INIT(RenameRequestDto, DTO)
    DTO_FIELD(String, path);
    DTO_FIELD(String, newName, "new_name");
};

class CreateFolderRequestDto : public oatpp::DTO {
    DTO_INIT(CreateFolderRequestDto, DTO)
    DTO_FIELD(String, path);
};

class StatusResponseDto : public oatpp::DTO {
    DTO_INIT(StatusResponseDto, DTO)
    DTO_FIELD(String, status, "status");
    DTO_FIELD(String, aiStatus, "ai_status");
    DTO_FIELD(Boolean, aiEnabled, "ai_enabled");
};

class SystemUsageDto : public oatpp::DTO {
    DTO_INIT(SystemUsageDto, DTO)
    DTO_FIELD(Float64, free_gb);
    DTO_FIELD(Float64, total_gb);
    DTO_FIELD(Float64, percent_used);
    DTO_FIELD(Float64, percent);
};

// Generic request DTO for AI stub endpoints that accept arbitrary JSON body
class GenericJsonDto : public oatpp::DTO {
    DTO_INIT(GenericJsonDto, DTO)
};

class AiStatusDto : public oatpp::DTO {
    DTO_INIT(AiStatusDto, DTO)
    DTO_FIELD(String, status);
    DTO_FIELD(String, error);
    DTO_FIELD(Int32, elapsed, "elapsed");
    DTO_FIELD(Int32, models_available, "models_available");
    DTO_FIELD(Int32, pid, "pid");
    DTO_FIELD(String, binary, "binary");
    DTO_FIELD(Int32, port, "port");
    DTO_FIELD(String, models_folder, "models_folder");
};

class SystemConfigResponseDto : public oatpp::DTO {
    DTO_INIT(SystemConfigResponseDto, DTO)
    DTO_FIELD(String, storageRoot, "storage_root");
    DTO_FIELD(String, dataPath, "data_path");
    DTO_FIELD(String, dbPath, "db_path");
    DTO_FIELD(String, nasmetadataPath, "nasmetadata_path");
    DTO_FIELD(Boolean, aiEnabled, "ai_enabled");
    DTO_FIELD(String, cllamaBinary, "cllama_binary");
    DTO_FIELD(Int32, cllamaPort, "cllama_port");
    DTO_FIELD(String, cllamaModelsFolder, "cllama_models_folder");
};

class ConfigEntryDto : public oatpp::DTO {
    DTO_INIT(ConfigEntryDto, DTO)
    DTO_FIELD(String, key);
    DTO_FIELD(String, value);
};

class ConfigListResponseDto : public oatpp::DTO {
    DTO_INIT(ConfigListResponseDto, DTO)
    DTO_FIELD(Boolean, success);
    DTO_FIELD(Vector<Object<ConfigEntryDto>>, configs);
};

class ConfigUpdateRequestDto : public oatpp::DTO {
    DTO_INIT(ConfigUpdateRequestDto, DTO)
    DTO_FIELD(String, value);
};

class UpdateStorageRootDto : public oatpp::DTO {
    DTO_INIT(UpdateStorageRootDto, DTO)
    DTO_FIELD(String, path);
};

class RagStatusDto : public oatpp::DTO {
    DTO_INIT(RagStatusDto, DTO)
    DTO_FIELD(String, status);
    DTO_FIELD(String, address);
    DTO_FIELD(String, index);
    DTO_FIELD(Int32, usage_docs);
};

class PdfToImagePageDto : public oatpp::DTO {
    DTO_INIT(PdfToImagePageDto, DTO)
    DTO_FIELD(Int32, page);
    DTO_FIELD(String, filename);
    DTO_FIELD(String, path);
};

class PdfToImageRequestDto : public oatpp::DTO {
    DTO_INIT(PdfToImageRequestDto, DTO)
    DTO_FIELD(String, path);
    DTO_FIELD(String, outputDir, "output_dir");
};

class MergeToPdfRequestDto : public oatpp::DTO {
    DTO_INIT(MergeToPdfRequestDto, DTO)
    DTO_FIELD(Vector<String>, filePaths, "file_paths");
    DTO_FIELD(String, outputPath, "output_path");
};

class PdfToImageResponseDto : public oatpp::DTO {
    DTO_INIT(PdfToImageResponseDto, DTO)
    DTO_FIELD(Int32, totalPages, "total_pages");
    DTO_FIELD(Vector<Object<PdfToImagePageDto>>, images);
};

class MergeToPdfResponseDto : public oatpp::DTO {
    DTO_INIT(MergeToPdfResponseDto, DTO)
    DTO_FIELD(String, pdfPath, "pdf_path");
    DTO_FIELD(Int32, fileCount, "file_count");
};

// ── User DTOs ────────────────────────────────────────────────────────

class LoginRequestDto : public oatpp::DTO {
    DTO_INIT(LoginRequestDto, DTO)
    DTO_FIELD(String, username);
    DTO_FIELD(String, password);
};

class RegisterRequestDto : public oatpp::DTO {
    DTO_INIT(RegisterRequestDto, DTO)
    DTO_FIELD(String, username);
    DTO_FIELD(String, password);
    DTO_FIELD(String, role);
};

class UserInfoDto : public oatpp::DTO {
    DTO_INIT(UserInfoDto, DTO)
    DTO_FIELD(Int64, id, "id");
    DTO_FIELD(String, username);
    DTO_FIELD(String, role);
    DTO_FIELD(Int64, createdAt, "created_at");
    DTO_FIELD(String, vipStatus, "vip_status");
};

class UserLoginResponseDto : public oatpp::DTO {
    DTO_INIT(UserLoginResponseDto, DTO)
    DTO_FIELD(Boolean, success);
    DTO_FIELD(String, message);
    DTO_FIELD(String, username);
    DTO_FIELD(String, role);
    DTO_FIELD(String, vipStatus, "vip_status");
};

class UserActionResponseDto : public oatpp::DTO {
    DTO_INIT(UserActionResponseDto, DTO)
    DTO_FIELD(Boolean, success);
    DTO_FIELD(String, message);
};

} // namespace ainas

#include OATPP_CODEGEN_END(DTO)
