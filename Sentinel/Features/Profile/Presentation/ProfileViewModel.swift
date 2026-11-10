import Foundation
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var gender: ProfileGender?
    @Published var birthYear: Int?
    @Published var avatarData: Data?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let service = ProfileService()

    func load(user: UserDTO, token: String) async {
        name = user.name
        gender = user.gender.flatMap(ProfileGender.init(rawValue:))
        birthYear = user.birthYear
        do {
            if let base64 = try await service.avatar(token: token), let data = Data(base64Encoded: base64) { avatarData = data }
        } catch { /* El perfil sigue disponible aunque la foto no cargue. */ }
    }

    func save(userSession: AppSession, token: String) async {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { errorMessage = "El nombre debe tener al menos 2 caracteres."; return }
        isSaving = true; errorMessage = nil; successMessage = nil
        defer { isSaving = false }
        do {
            let base64 = avatarData?.base64EncodedString()
            let user = try await service.updateProfile(ProfileUpdateRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines), gender: gender?.rawValue, birthYear: birthYear, avatarBase64: base64), token: token)
            userSession.updateUser(user)
            successMessage = "Perfil actualizado correctamente."
        } catch { errorMessage = error.localizedDescription }
    }

    func changePassword(currentPassword: String, newPassword: String, token: String) async -> Bool {
        guard newPassword.count >= 8 else { errorMessage = "La nueva contraseña debe tener al menos 8 caracteres."; return false }
        isLoading = true; errorMessage = nil; successMessage = nil
        defer { isLoading = false }
        do {
            try await service.updatePassword(PasswordUpdateRequest(currentPassword: currentPassword, newPassword: newPassword), token: token)
            successMessage = "Contraseña actualizada correctamente."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}
