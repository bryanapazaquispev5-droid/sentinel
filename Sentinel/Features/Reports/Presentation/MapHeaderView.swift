import SwiftUI

struct MapHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SENTINEL  /  PERÚ")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .background(Color(red: 0.025, green: 0.055, blue: 0.10).opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .allowsHitTesting(false)
    }

}
