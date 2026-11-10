import SwiftUI

struct FormScreen<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }

    var body: some View {
        ZStack {
            SentinelTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(SentinelTheme.textPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(SentinelTheme.textSecondary)
                    }
                    content
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LoginView: View {
    @ObservedObject var session: AppSession
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        FormScreen(title: "auth.login", subtitle: "auth.login.subtitle") {
            VStack(spacing: 18) {
                SentinelTextField(title: "auth.email", text: $viewModel.email, systemImage: "envelope", keyboard: .emailAddress)
                SentinelSecureField(title: "auth.password", text: $viewModel.password, systemImage: "lock")
                if let error = viewModel.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                Button { Task { await viewModel.login(session: session) } } label: {
                    Group { if viewModel.isLoading { ProgressView().tint(.white) } else { Text("auth.login") } }.sentinelPrimaryButton()
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

struct RegisterView: View {
    @ObservedObject var session: AppSession
    @StateObject private var viewModel = RegisterViewModel()

    var body: some View {
        FormScreen(title: "auth.register", subtitle: "auth.register.subtitle") {
            VStack(spacing: 16) {
                SentinelTextField(title: "auth.name", text: $viewModel.name, systemImage: "person", keyboard: .default)
                SentinelTextField(title: "auth.email", text: $viewModel.email, systemImage: "envelope", keyboard: .emailAddress)
                SentinelSecureField(title: "auth.password", text: $viewModel.password, systemImage: "lock")
                SentinelSecureField(title: "auth.password.repeat", text: $viewModel.repeatedPassword, systemImage: "lock.rotation")
                Toggle("auth.terms", isOn: $viewModel.acceptedTerms).font(.caption).tint(SentinelTheme.primary)
                if let error = viewModel.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                if viewModel.errorMessage?.localizedCaseInsensitiveContains("registrado") == true {
                    NavigationLink("Ir a iniciar sesión") { LoginView(session: session) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SentinelTheme.primary)
                }
                Button { Task { await viewModel.register(session: session) } } label: {
                    Group { if viewModel.isLoading { ProgressView().tint(.white) } else { Text("auth.register") } }.sentinelPrimaryButton()
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

struct SentinelTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let systemImage: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(SentinelTheme.primary).frame(width: 20)
            TextField(title, text: $text).textInputAutocapitalization(.never).keyboardType(keyboard)
        }
        .foregroundStyle(.primary)
        .tint(SentinelTheme.primary)
        .padding(.horizontal, 16).frame(height: 54).background(SentinelTheme.fieldBackground).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(SentinelTheme.border, lineWidth: 1) }
    }
}

struct SentinelSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(SentinelTheme.primary).frame(width: 20)
            SecureField(title, text: $text)
        }
        .foregroundStyle(.primary)
        .tint(SentinelTheme.primary)
        .padding(.horizontal, 16).frame(height: 54).background(SentinelTheme.fieldBackground).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(SentinelTheme.border, lineWidth: 1) }
    }
}
