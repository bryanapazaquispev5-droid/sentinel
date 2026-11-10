import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var session = AppSession()
    @StateObject private var settings = AppSettings()
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        Group {
            if !locationManager.isAuthorized {
                PermissionGateView(locationManager: locationManager)
            } else if session.isAuthenticated {
                MainView(session: session, locationManager: locationManager)
            } else {
                WelcomeView(session: session)
            }
        }
        .task {
            locationManager.requestPermission()
            await NotificationPermissionManager.shared.requestAuthorizationIfNeeded()
        }
        .task(id: locationManager.isAuthorized) {
            guard locationManager.isAuthorized else { return }
            await session.restoreSession()
        }
        .environmentObject(settings)
        // preferredColorScheme updates the hosting controller, while this
        // explicit environment keeps every SwiftUI child in sync immediately.
        .environment(\.colorScheme, appColorScheme)
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.locale, Locale(identifier: settings.language.rawValue))
        .background(WindowAppearanceView(theme: settings.theme))
    }

    private var appColorScheme: ColorScheme {
        settings.theme.colorScheme ?? systemColorScheme
    }
}

#Preview { ContentView() }
