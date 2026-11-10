import SwiftUI

struct WelcomeView: View {
    @ObservedObject var session: AppSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                SentinelBackground()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, SentinelTheme.primary.opacity(0.10)], startPoint: .center, endPoint: .bottom)
                    }
                VStack(spacing: 28) {
                    Spacer()
                    ZStack {
                        Circle().fill(SentinelTheme.primary.opacity(0.15)).frame(width: 190, height: 190)
                        Circle().stroke(SentinelTheme.primary.opacity(0.35), lineWidth: 1).frame(width: 152, height: 152)
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 66, weight: .medium))
                            .foregroundStyle(SentinelTheme.primary)
                            .symbolEffect(.pulse, options: .repeating.speed(0.5))
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(SentinelTheme.accent)
                            .offset(x: 52, y: -49)
                    }
                    .accessibilityLabel("Sentinel, centro de alertas")
                    VStack(spacing: 10) {
                        Text("SENTINEL")
                            .tracking(5)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(heroPrimaryColor)
                        Text("welcome.subtitle")
                            .font(.subheadline)
                            .foregroundStyle(heroSecondaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                    VStack(spacing: 14) {
                        NavigationLink { LoginView(session: session) } label: {
                            Text("auth.login").sentinelPrimaryButton()
                        }
                        NavigationLink { RegisterView(session: session) } label: {
                            Text("auth.register").sentinelSecondaryButton()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .ignoresSafeArea()
        }
        .tint(heroPrimaryColor)
    }

    private var heroPrimaryColor: Color { colorScheme == .dark ? .white : SentinelTheme.textPrimary }
    private var heroSecondaryColor: Color { colorScheme == .dark ? .white.opacity(0.78) : SentinelTheme.textSecondary }
}
