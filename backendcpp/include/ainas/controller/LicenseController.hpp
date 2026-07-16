#pragma once

#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"

#include "ainas/lic/lic.h"

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <filesystem>
#include <fstream>
#include <memory>
#include <cstdlib>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

class LicenseController : public oatpp::web::server::api::ApiController {
public:
    LicenseController(const std::shared_ptr<ObjectMapper>& objectMapper)
        : oatpp::web::server::api::ApiController(objectMapper)
    {}

    static std::shared_ptr<LicenseController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper)
    {
        return std::make_shared<LicenseController>(objectMapper);
    }

    ENDPOINT("GET", "/api/license/status", getLicenseStatus) {
        LOG_INFO("GET /api/license/status");
        auto response = LicenseStatusDto::createShared();
        response->licensed = lic::isLicensed();
        auto info = lic::licenseInfo();
        response->info = oatpp::String(info);
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/license/hardware-info", getHardwareInfo) {
        LOG_INFO("GET /api/license/hardware-info");
        auto response = LicenseHardwareInfoDto::createShared();
        response->cpuSerial = oatpp::String(lic::getCpuSerial());
        response->motherboardSerial = oatpp::String(lic::getMotherboardSerial());
        response->diskSerial = oatpp::String(lic::getDiskSerial());
        response->deviceFingerprint = oatpp::String(lic::generateDeviceFingerprint());
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("POST", "/api/license/import", importLicense,
             BODY_DTO(Object<LicenseImportRequestDto>, body)) {
        LOG_INFO("POST /api/license/import");

        if (!body->content || body->content->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "license content is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        // Write content to a temp file
        auto tmpPath = std::filesystem::temp_directory_path() / "ainas_license_import.lic";
        {
            std::ofstream ofs(tmpPath, std::ios::binary);
            if (!ofs.is_open()) {
                auto error = ApiResponseDto::createShared();
                error->success = false;
                error->message = "failed to create temp file";
                return createDtoResponse(Status::CODE_500, error);
            }
            auto content = std::string(body->content->data(), body->content->size());
            ofs << content;
        }

        bool ok = lic::importLicense(tmpPath.string());
        std::filesystem::remove(tmpPath);

        auto response = ApiResponseDto::createShared();
        response->success = ok;
        response->message = ok
            ? oatpp::String("License imported successfully")
            : oatpp::String("License import failed - invalid or mismatched license");
        return createDtoResponse(ok ? Status::CODE_200 : Status::CODE_400, response);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
