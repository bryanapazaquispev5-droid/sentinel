import SwiftUI
import CoreLocation
import UIKit

struct PermissionGateView: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            SentinelBackground().ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(heroPrimaryColor)
                VStack(spacing: 10) {
                    Text("permission.title")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(heroPrimaryColor)
                        .multilineTextAlignment(.center)
                    Text("permission.subtitle")
                        .foregroundStyle(heroSecondaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button { handlePermissionAction() } label: {
                        Text(locationManager.isDenied ? "permission.openSettings" : "permission.allow")
                            .sentinelPrimaryButton()
                    }
                    if locationManager.isDenied {
                        Text("permission.settingsHint")
                            .font(.caption)
                            .foregroundStyle(heroSecondaryColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 42)
            }
        }
    }

    private var heroPrimaryColor: Color { colorScheme == .dark ? .white : SentinelTheme.textPrimary }
    private var heroSecondaryColor: Color { colorScheme == .dark ? .white.opacity(0.78) : SentinelTheme.textSecondary }

    private func handlePermissionAction() {
        if locationManager.isDenied {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } else {
            locationManager.requestPermission()
        }
    }
}
