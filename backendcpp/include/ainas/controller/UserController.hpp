#pragma once

#include "ainas/database/UserRepository.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <memory>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

class UserController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<UserRepository> m_repo;

public:
    UserController(const std::shared_ptr<ObjectMapper>& objectMapper,
                   std::shared_ptr<UserRepository> repo)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_repo(std::move(repo))
    {}

    static std::shared_ptr<UserController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        std::shared_ptr<UserRepository> repo)
    {
        return std::make_shared<UserController>(objectMapper, std::move(repo));
    }

    ENDPOINT("POST", "/api/user/login", login,
             BODY_DTO(Object<LoginRequestDto>, body)) {
        LOG_INFO("POST /api/user/login");

        auto response = UserLoginResponseDto::createShared();

        if (!body->username || !body->password ||
            body->username->empty() || body->password->empty()) {
            response->success = false;
            response->message = "Username and password are required";
            return createDtoResponse(Status::CODE_400, response);
        }

        auto user = m_repo->findByUsername(body->username->data());
        if (!user) {
            response->success = false;
            response->message = "Invalid username or password";
            return createDtoResponse(Status::CODE_401, response);
        }

        auto hash = UserRepository::hashPassword(body->password->data());
        if (hash != user->passwordHash) {
            response->success = false;
            response->message = "Invalid username or password";
            return createDtoResponse(Status::CODE_401, response);
        }

        response->success = true;
        response->message = "Login successful";
        response->username = oatpp::String(user->username);
        response->role = oatpp::String(user->role);
        response->vipStatus = "VIP Member";
        LOG_INFO("User logged in: {} (role: {})", user->username, user->role);
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("POST", "/api/user/logout", logout) {
        LOG_INFO("POST /api/user/logout");
        auto response = UserActionResponseDto::createShared();
        response->success = true;
        response->message = "Logged out";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/user/info", getInfo,
             QUERY(String, qUsername, "username", "")) {
        LOG_INFO("GET /api/user/info");

        if (qUsername && qUsername->empty()) {
            // Frontend calls without ?username= — try the first registered user
            // by attempting known usernames.
            for (auto& name : {"admin", "user", "ainas"}) {
                auto found = m_repo->findByUsername(name);
                if (found) {
                    auto response = UserInfoDto::createShared();
                    response->id = found->id;
                    response->username = oatpp::String(found->username);
                    response->role = oatpp::String(found->role);
                    response->createdAt = found->createdAt;
                    response->vipStatus = "VIP Member";
                    return createDtoResponse(Status::CODE_200, response);
                }
            }
        }

        if (qUsername && !qUsername->empty()) {
            auto user = m_repo->findByUsername(qUsername->data());
            if (user) {
                auto response = UserInfoDto::createShared();
                response->id = user->id;
                response->username = oatpp::String(user->username);
                response->role = oatpp::String(user->role);
                response->createdAt = user->createdAt;
                response->vipStatus = "VIP Member";
                return createDtoResponse(Status::CODE_200, response);
            }
        }

        auto error = UserActionResponseDto::createShared();
        error->success = false;
        error->message = "User not found";
        return createDtoResponse(Status::CODE_404, error);
    }

    ENDPOINT("POST", "/api/user/register", registerUser,
             BODY_DTO(Object<RegisterRequestDto>, body)) {
        LOG_INFO("POST /api/user/register");

        auto response = UserActionResponseDto::createShared();

        if (!body->username || !body->password ||
            body->username->empty() || body->password->empty()) {
            response->success = false;
            response->message = "Username and password are required";
            return createDtoResponse(Status::CODE_400, response);
        }

        auto username = std::string(body->username->data());
        auto password = std::string(body->password->data());
        auto role = (body->role && !body->role->empty())
            ? std::string(body->role->data())
            : std::string("user");

        if (m_repo->findByUsername(username)) {
            response->success = false;
            response->message = "User already exists";
            return createDtoResponse(Status::CODE_409, response);
        }

        if (m_repo->registerUser(username, password, role)) {
            response->success = true;
            response->message = oatpp::String("User '" + username + "' registered");
            LOG_INFO("User registered: {}", username);
            return createDtoResponse(Status::CODE_201, response);
        } else {
            response->success = false;
            response->message = "Failed to register user";
            return createDtoResponse(Status::CODE_500, response);
        }
    }

    ENDPOINT("POST", "/api/user/unregister", unregisterUser,
             BODY_DTO(Object<LoginRequestDto>, body)) {
        LOG_INFO("POST /api/user/unregister");

        auto response = UserActionResponseDto::createShared();

        if (!body->username || body->username->empty()) {
            response->success = false;
            response->message = "Username is required";
            return createDtoResponse(Status::CODE_400, response);
        }

        auto username = std::string(body->username->data());

        if (body->password && !body->password->empty()) {
            auto user = m_repo->findByUsername(username);
            if (!user) {
                response->success = false;
                response->message = "User not found";
                return createDtoResponse(Status::CODE_404, response);
            }
            auto hash = UserRepository::hashPassword(body->password->data());
            if (hash != user->passwordHash) {
                response->success = false;
                response->message = "Invalid password";
                return createDtoResponse(Status::CODE_401, response);
            }
        }

        if (m_repo->deleteUser(username)) {
            response->success = true;
            response->message = oatpp::String("User '" + username + "' unregistered");
            LOG_INFO("User unregistered: {}", username);
            return createDtoResponse(Status::CODE_200, response);
        } else {
            response->success = false;
            response->message = "User not found";
            return createDtoResponse(Status::CODE_404, response);
        }
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
