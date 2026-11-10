import Foundation

struct ProfileService {
    private let client = APIClient()

    func updateProfile(_ request: ProfileUpdateRequest, token: String) async throws -> UserDTO {
        struct Response: Decodable { let user: UserDTO }
        let response: Response = try await client.request("me/profile", method: "PATCH", body: request, token: token)
        return response.user
    }

    func avatar(token: String) async throws -> String? {
        let response: ProfileAvatarResponse = try await client.request("me/avatar", token: token)
        return response.avatarBase64
    }

    func updatePassword(_ request: PasswordUpdateRequest, token: String) async throws {
        try await client.requestVoid("me/password", method: "POST", body: request, token: token)
    }
}
