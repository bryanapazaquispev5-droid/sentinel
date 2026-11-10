import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @ObservedObject var session: AppSession
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPasswordSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarView.frame(width: 104, height: 104).clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Image(systemName: "camera.fill").font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 34, height: 34).background(SentinelTheme.accent, in: Circle())
                        }
                    }
                    .onChange(of: selectedPhoto) { _, item in loadPhoto(item) }
                    Text(viewModel.name.isEmpty ? (session.user?.name ?? "Tu perfil") : viewModel.name)
                        .font(.title2.bold())
                    Text(session.user?.email ?? "").font(.subheadline).foregroundStyle(.secondary)
                    if viewModel.avatarData != nil {
                        Button("profile.removePhoto", role: .destructive) { viewModel.avatarData = nil }
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity).padding(24)
                .background(LinearGradient(colors: [SentinelTheme.primary.opacity(0.12), SentinelTheme.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Tu información", systemImage: "person.text.rectangle").font(.headline)
                    TextField("auth.name", text: $viewModel.name).textContentType(.name).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    Label(session.user?.email ?? "Correo de la cuenta", systemImage: "envelope")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                }.padding(18).background(SentinelTheme.surface, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Preferencias", systemImage: "slider.horizontal.3").font(.headline)
                    Picker("profile.language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }.padding(.horizontal, 12).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    Picker("profile.theme", selection: $settings.theme) {
                        Text("common.system").tag(AppThemeMode.system)
                        Text("common.light").tag(AppThemeMode.light)
                        Text("common.dark").tag(AppThemeMode.dark)
                    }.pickerStyle(.segmented)
                }.padding(18).background(SentinelTheme.surface, in: RoundedRectangle(cornerRadius: 22))

                if let error = viewModel.errorMessage { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                if let success = viewModel.successMessage { Label(success, systemImage: "checkmark.circle.fill").foregroundStyle(SentinelTheme.success) }

                Button { saveProfile() } label: {
                    Label(viewModel.isSaving ? "Guardando…" : "profile.save", systemImage: "checkmark.circle.fill")
                        .sentinelPrimaryButton()
                }.disabled(viewModel.isSaving)

                Button { showingPasswordSheet = true } label: {
                    Label("profile.changePassword", systemImage: "lock.rotation").frame(maxWidth: .infinity).padding(16)
                        .background(SentinelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                Button(role: .destructive) { session.logout() } label: {
                    Label("profile.logout", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).padding(16)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaPadding(.bottom, 84)
        .navigationTitle("home.profile")
        .task { await loadProfile() }
        .sheet(isPresented: $showingPasswordSheet) { ChangePasswordView() }
    }

    @ViewBuilder private var avatarView: some View {
        if let data = viewModel.avatarData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(SentinelTheme.primary)
        }
    }

    private func loadProfile() async {
        guard let user = session.user, let token = KeychainStore.readToken() else { return }
        await viewModel.load(user: user, token: token)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        Task {
            guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
            if let image = UIImage(data: data), let compressed = image.jpegData(compressionQuality: 0.78) { viewModel.avatarData = compressed }
        }
    }

    private func saveProfile() {
        guard let token = KeychainStore.readToken() else { return }
        Task { await viewModel.save(userSession: session, token: token) }
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = ProfileViewModel()
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var repeatedPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("profile.currentPassword", text: $currentPassword)
                    SecureField("profile.newPassword", text: $newPassword)
                    SecureField("auth.password.repeat", text: $repeatedPassword)
                }
                if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red) }
                if let success = viewModel.successMessage { Text(success).foregroundStyle(.green) }
                Button {
                    guard newPassword == repeatedPassword else { viewModel.errorMessage = "Las contraseñas no coinciden."; return }
                    guard let token = KeychainStore.readToken() else { return }
                    Task {
                        if await viewModel.changePassword(currentPassword: currentPassword, newPassword: newPassword, token: token) { dismiss() }
                    }
                } label: {
                    HStack { Spacer(); if viewModel.isLoading { ProgressView() } else { Text("profile.updatePassword").fontWeight(.semibold) }; Spacer() }
                }
                .disabled(viewModel.isLoading)
            }
            .navigationTitle("profile.changePassword")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
        .environmentObject(settings)
    }
}
