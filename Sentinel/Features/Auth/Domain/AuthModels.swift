import Foundation

struct UserDTO: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let role: String
    let reputation: Int
    let gender: String?
    let birthYear: Int?
    let hasProfilePhoto: Bool?
    let createdAt: String?
}

struct AuthResponse: Codable {
    let user: UserDTO
    let accessToken: String
}

struct APIErrorResponse: Codable {
    let error: String
}

struct RegisterRequest: Codable {
    let name: String
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct MeResponse: Codable { let user: UserDTO }
