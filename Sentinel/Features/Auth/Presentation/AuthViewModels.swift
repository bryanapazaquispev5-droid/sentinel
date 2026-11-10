import Foundation
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: UserDTO?
    private let authService = AuthService()

    func restoreSession() async {
        guard KeychainStore.readToken() != nil else { return }
        do {
            user = try await authService.currentUser()
            isAuthenticated = true
        } catch let error as APIClientError {
            if case .unauthorized = error {
                logout()
            } else {
                // Conserva el token ante una caída temporal de la API.
                isAuthenticated = true
            }
        } catch {
            isAuthenticated = true
        }
    }

    func authenticate(_ response: AuthResponse) {
        user = response.user
        isAuthenticated = true
    }

    func updateUser(_ updatedUser: UserDTO) {
        user = updatedUser
    }

    func logout() {
        authService.logout()
        user = nil
        isAuthenticated = false
    }
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let authService = AuthService()

    func login(session: AppSession) async {
        guard !email.isEmpty, !password.isEmpty else { errorMessage = "Completa tu correo y contraseña."; return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { session.authenticate(try await authService.login(email: email, password: password)) }
        catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var repeatedPassword = ""
    @Published var acceptedTerms = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let authService = AuthService()

    func register(session: AppSession) async {
        guard name.count >= 2, email.contains("@"), password.count >= 8 else { errorMessage = "Revisa los datos ingresados."; return }
        guard password == repeatedPassword else { errorMessage = "Las contraseñas no coinciden."; return }
        guard acceptedTerms else { errorMessage = "Debes aceptar los términos de uso."; return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { session.authenticate(try await authService.register(name: name, email: email, password: password)) }
        catch { errorMessage = error.localizedDescription }
    }
}
