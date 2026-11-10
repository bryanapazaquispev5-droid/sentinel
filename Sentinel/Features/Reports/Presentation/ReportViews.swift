import SwiftUI
import CoreLocation
import UIKit

struct OfficialAlertRow: View {
    let alert: OfficialAlertDTO
    let isNearby: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: alert.categorySymbol)
                    .font(.headline).foregroundStyle(severityColor)
                Text(alert.title).font(.headline).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(severityLabel)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(severityColor)
                    .background(severityColor.opacity(0.12), in: Capsule())
            }
            Text("\(alert.source) · \(alert.categoryDisplayName)").font(.caption).foregroundStyle(.secondary)
            if let magnitude = earthquakeMagnitude {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.subheadline.weight(.bold))
                    Text("MAGNITUD")
                        .font(.caption2.weight(.black)).tracking(1)
                    Text(String(format: "M %.1f", magnitude))
                        .font(.headline.weight(.black)).monospacedDigit()
                    Text(magnitudeDescription)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(magnitudeColor)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(magnitudeColor.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(magnitudeColor.opacity(0.28), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            Text(alert.description).font(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                if let distance = alert.distanceKm { Text(String(format: "%.1f km", distance)).font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Label("assessment.open", systemImage: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SentinelTheme.primary)
            }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private var severityLabel: String {
        switch alert.severity.uppercased() {
        case "CRITICAL": "CRÍTICO"
        case "HIGH": "ALTO"
        case "MEDIUM": "MEDIO"
        default: "BAJO"
        }
    }

    private var severityColor: Color {
        switch alert.severity.uppercased() {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MEDIUM": .yellow
        default: SentinelTheme.success
        }
    }

    private var earthquakeMagnitude: Double? {
        guard alert.category.uppercased().contains("SISMO") || alert.category.uppercased().contains("EARTHQUAKE") else { return nil }
        let text = "\(alert.title) \(alert.description)"
        guard let range = text.range(of: #"(?:M\s*|magnitud\s*)(\d{1,2}(?:[\.,]\d+)?)"#, options: .regularExpression) else { return nil }
        let match = String(text[range])
        let number = match.replacingOccurrences(of: #"[Mm]\s*|magnitud\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: ".")
        return Double(number)
    }

    private var magnitudeColor: Color {
        guard let magnitude = earthquakeMagnitude else { return SentinelTheme.primary }
        return switch magnitude {
        case ..<3: SentinelTheme.success
        case ..<4: Color.green
        case ..<5: Color.yellow
        case ..<6: Color.orange
        default: Color.red
        }
    }

    private var magnitudeDescription: String {
        guard let magnitude = earthquakeMagnitude else { return "" }
        return switch magnitude {
        case ..<3: "Muy leve"
        case ..<4: "Leve"
        case ..<5: "Moderado"
        case ..<6: "Fuerte"
        default: "Muy fuerte"
        }
    }
}

struct OfficialPredictionRow: View {
    let prediction: OfficialAlertDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: prediction.categorySymbol).foregroundStyle(SentinelTheme.accent)
                Text(prediction.categoryDisplayName.uppercased())
                    .font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(SentinelTheme.accent)
                Spacer()
                Text(prediction.source).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(prediction.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
            Text(prediction.description).font(.footnote).foregroundStyle(.secondary).lineLimit(7)
            if let source = prediction.sourceUrl, let url = URL(string: source) {
                Link("Leer comunicado oficial", destination: url)
                    .font(.footnote.weight(.semibold)).foregroundStyle(SentinelTheme.primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SentinelTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ReportRow: View {
    let report: ReportDTO
    let location: CLLocation?
    let onVote: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(report.category).font(.headline)
                Spacer()
                StatusBadge(status: report.status)
            }
            Text(report.description).font(.subheadline)
            if let count = report.clusterReportCount, let minimum = report.clusterMinimumReports {
                Label("\(count)/\(minimum) reportes en un radio de \(String(format: "%.0f", report.clusterRadiusKm ?? 0)) km", systemImage: "person.3.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(count >= minimum ? SentinelTheme.primary : .secondary)
            }
            HStack(spacing: 12) {
                Label("\(report.confirmations)", systemImage: "checkmark.circle")
                Label("\(report.disputes)", systemImage: "xmark.circle")
                Spacer()
                if let distance = report.distanceKm { Text(String(format: "%.1f km", distance)).font(.caption) }
            }
            .foregroundStyle(.secondary)
            if report.status == "UNDER_REVIEW", let distance = report.distanceKm, distance <= report.validationRadiusKm {
                HStack {
                    Button("report.confirm") { onVote("CONFIRM") }.buttonStyle(.borderedProminent).tint(SentinelTheme.primary)
                    Button("report.dispute") { onVote("DISPUTE") }.buttonStyle(.bordered).tint(.red)
                }
            } else if report.status == "COLLECTING" {
                Label("Esperando más reportes independientes en esta zona", systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.secondary)
            } else if report.distanceKm != nil {
                Label("report.validationNearbyOnly", systemImage: "location.slash")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("report.validationLocationOnly", systemImage: "location.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status == "COLLECTING" ? "REUNIENDO REPORTES" : status == "UNDER_REVIEW" ? "EN EVALUACIÓN" : status.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == "COMMUNITY_VERIFIED" || status == "OFFICIALLY_VERIFIED" ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}

enum ReportCreationType: Equatable {
    case naturalDisaster
    case otherIncident
}

struct CreateReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: AppSession
    @ObservedObject var locationManager: LocationManager
    let creationType: ReportCreationType
    let onCreated: () -> Void
    @StateObject private var viewModel = CreateReportViewModel()
    @State private var confirmingSubmission = false
    @State private var countdownRemaining: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var evidenceData: Data?
    @State private var cameraPresented = false
    @State private var severitySelected = false

    private var categories: [String] {
        creationType == .naturalDisaster
            ? ["SISMO", "TSUNAMI", "INUNDACION", "LLUVIA_INTENSA", "HUAICO", "DERRUMBE", "DESLIZAMIENTO", "ALUVION", "PELIGRO_GLACIAR", "INCENDIO", "VOLCAN", "CENIZA_VOLCANICA", "LAHAR", "FLUJO_PIROCLASTICO", "TORMENTA", "CICLON_TROPICAL", "SEQUIA", "FRIAJE", "HELADA", "GRANIZADA", "NEVADA", "OLA_CALOR", "OLEAJE", "EL_NINO", "OTRO"]
            : []
    }

    private func icon(for category: String) -> String {
        switch category {
        case "SISMO": "waveform.path"
        case "INUNDACION", "HUAICO", "ALUVION", "TSUNAMI", "OLEAJE": "water.waves"
        case "DESLIZAMIENTO", "PELIGRO_GLACIAR", "VOLCAN", "CENIZA_VOLCANICA", "LAHAR", "FLUJO_PIROCLASTICO": "mountain.2.fill"
        case "INCENDIO": "flame.fill"
        case "DERRUMBE": "mountain.2.fill"
        case "LLUVIA_INTENSA", "TORMENTA", "CICLON_TROPICAL", "CLIMA": "cloud.bolt.rain.fill"
        case "SEQUIA", "OLA_CALOR", "EL_NINO": "sun.max.fill"
        case "FRIAJE", "HELADA", "GRANIZADA", "NEVADA": "snowflake"
        case "ACCIDENTE": "car.fill"
        default: "questionmark.circle.fill"
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("report.incident").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(categories, id: \.self) { category in
                    ReportCategoryButton(title: category == "OTRO" ? "Otro / No estoy seguro" : category.replacingOccurrences(of: "_", with: " ").capitalized,
                                         symbol: icon(for: category), isSelected: viewModel.category == category) {
                        viewModel.category = category
                    }
                }
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Foto (opcional)").font(.headline)
            Text("Si puedes, adjunta una foto tomada en el momento para ayudar a verificar el incidente. Evita incluir primeros planos de personas heridas.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    viewModel.errorMessage = "La cámara no está disponible en este dispositivo."
                    return
                }
                cameraPresented = true
            } label: {
                Label(evidenceData == nil ? "Tomar foto" : "Volver a tomar foto", systemImage: "camera.fill")
                    .font(.headline.weight(.bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(LinearGradient(colors: [SentinelTheme.accent, Color(red: 0.86, green: 0.20, blue: 0.08)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.20), lineWidth: 1))
                    .shadow(color: SentinelTheme.accent.opacity(0.28), radius: 8, y: 4)
            }
            if let evidenceData, let image = UIImage(data: evidenceData) {
                HStack(spacing: 12) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                    Label("Foto adjunta", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Quitar", role: .destructive) { self.evidenceData = nil }.font(.footnote)
                }
            } else {
                Label("Puedes enviar el reporte sin foto.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                    if creationType == .naturalDisaster {
                        categorySection
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("¿Qué ocurrió?").font(.headline)
                            HStack(spacing: 12) {
                                Image(systemName: "text.alignleft").foregroundStyle(SentinelTheme.primary)
                                TextField("Ejemplo: choque entre dos vehículos", text: $viewModel.incidentLabel, axis: .vertical)
                                    .textFieldStyle(.plain).foregroundStyle(.primary)
                            }
                            .padding(15)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SentinelTheme.primary.opacity(0.72), lineWidth: 1.3))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("report.severity").font(.headline)
                        SeverityLevelSelector(selection: $viewModel.severity) { severitySelected = true }
                        Text("Ajusta la gravedad según lo que observas ahora.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    evidenceSection
                    VStack(alignment: .leading, spacing: 8) {
                    Text(creationType == .otherIncident ? "Describe lo que viste" : "Descripción").font(.headline)
                    TextEditor(text: $viewModel.description)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.primary)
                        .overlay(alignment: .topLeading) {
                            if viewModel.description.isEmpty { Text(creationType == .otherIncident ? "Añade detalles útiles: qué pasó, cuántas personas o vehículos están involucrados y si alguien necesita ayuda." : viewModel.category == "OTRO" ? "Describe lo que ves. Puedes reportarlo aunque no sepas qué tipo de evento es." : "Describe brevemente qué ocurre, dónde y si hay personas en riesgo.").foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 4).allowsHitTesting(false) }
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SentinelTheme.primary.opacity(0.72), lineWidth: 1.3))
                    }
                }
                .padding(20)
                }
                VStack(spacing: 12) {
                    Label(locationManager.location == nil ? "home.locationRequired" : "report.currentLocation", systemImage: "location.fill")
                        .foregroundStyle(locationManager.location == nil ? .red : .secondary)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if locationManager.location == nil { Button("home.refreshLocation") { locationManager.requestCurrentLocation() }.frame(maxWidth: .infinity, alignment: .leading) }
                    if let error = viewModel.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                    if let countdownRemaining {
                        ProgressView(value: Double(10 - countdownRemaining), total: 10)
                        Text("El reporte se enviará en \(countdownRemaining) s. Todavía puedes modificarlo o cancelar.")
                            .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("Modificar") { cancelCountdown() }.buttonStyle(.bordered)
                            Button("Cancelar envío", role: .destructive) { cancelCountdown(); dismiss() }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Button {
                            if creationType == .otherIncident {
                                guard viewModel.incidentLabel.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { viewModel.errorMessage = "Completa el campo ‘¿Qué ocurrió?’ antes de continuar."; return }
                                guard viewModel.description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 else { viewModel.errorMessage = "Completa la descripción del incidente antes de continuar."; return }
                                guard severitySelected else { viewModel.errorMessage = "Selecciona la gravedad del incidente."; return }
                            }
                            confirmingSubmission = true
                        } label: {
                            Label("home.sendReport", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .disabled(viewModel.isLoading || locationManager.location == nil)
                    }
                }.padding(20).background(.regularMaterial)
            }
            .navigationTitle("home.newReport")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
            .confirmationDialog("¿Confirmas el reporte?", isPresented: $confirmingSubmission, titleVisibility: .visible) {
                Button("Sí, continuar") { startCountdown() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Tendrás 10 segundos para modificar o cancelar antes de enviarlo para validación.")
            }
            .onDisappear { countdownTask?.cancel() }
            .fullScreenCover(isPresented: $cameraPresented) {
                ReportCameraCaptureView(onCapture: { image in
                    evidenceData = Self.compressedJPEG(image)
                    viewModel.errorMessage = evidenceData == nil ? "No se pudo procesar la foto. Intenta tomarla otra vez." : nil
                    cameraPresented = false
                }, onCancel: { cameraPresented = false })
                .ignoresSafeArea()
            }
            .onAppear {
                if creationType == .otherIncident {
                    viewModel.category = "OTRO"
                } else if creationType == .naturalDisaster, viewModel.category == "ACCIDENTE" {
                    viewModel.category = "SISMO"
                }
            }
        }
    }

    private static func compressedJPEG(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in stride(from: 0.78, through: 0.30, by: -0.08) {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 1_100_000 { return data }
        }
        return resized.jpegData(compressionQuality: 0.25)
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownRemaining = 10
        countdownTask = Task { @MainActor in
            for second in stride(from: 10, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countdownRemaining = second
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            countdownRemaining = nil
            guard let token = KeychainStore.readToken() else { viewModel.errorMessage = "La sesión expiró."; return }
            let photoData = evidenceData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
            if await viewModel.submit(location: locationManager.location, token: token, creationType: creationType, photoData: photoData) { onCreated() }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
    }
}

private struct ReportCategoryButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isSelected ? SentinelTheme.primary.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? SentinelTheme.primary : .clear))
        }
        .buttonStyle(.plain)
    }
}

private struct SeverityLevelSelector: View {
    @Binding var selection: ReportSeverity
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ReportSeverity.allCases) { level in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = level }
                    onSelect()
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(selection == level ? Color.black.opacity(0.65) : level.tint)
                            .frame(width: 7, height: 7)
                        Text(level.title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(selection == level ? Color.black.opacity(0.88) : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(selection == level ? level.tint : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == level ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
        .overlay(Capsule().stroke(selection.tint.opacity(0.7), lineWidth: 1.2))
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
}

private struct ReportCameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            else { onCancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}
