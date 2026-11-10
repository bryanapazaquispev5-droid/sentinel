import Foundation

struct AuthService {
    private let client = APIClient()

    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await client.request("auth/register", method: "POST", body: RegisterRequest(name: name, email: email, password: password))
        try KeychainStore.saveToken(response.accessToken)
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await client.request("auth/login", method: "POST", body: LoginRequest(email: email, password: password))
        try KeychainStore.saveToken(response.accessToken)
        return response
    }

    func currentUser() async throws -> UserDTO {
        guard let token = KeychainStore.readToken() else { throw APIClientError.server("Sesión no encontrada") }
        let response: MeResponse = try await client.request("me", token: token)
        return response.user
    }

    func logout() { KeychainStore.deleteToken() }
}
