import SwiftUI
import MapKit

import Combine
import CoreLocation

@MainActor
final class AlertAssessmentViewModel: ObservableObject {
    @Published private(set) var questionnaire: AlertQuestionnaireResponse?
    @Published private(set) var officialAlertsSyncedAt: Date?
    @Published var answers: [String: String] = [:]
    @Published var isLoading = false
    @Published var isSending = false
    @Published var message: String?
    @Published var didSubmit = false
    private let service = ReportsService()

    func load(alertID: String) async {
        isLoading = true; message = nil
        defer { isLoading = false }
        do { questionnaire = try await service.questionnaire(alertId: alertID) }
        catch { message = error.localizedDescription }
        officialAlertsSyncedAt = try? await service.latestOfficialAlertSync()
    }

    func submit(alertID: String, location: CLLocation?) async {
        guard let location else { message = NSLocalizedString("assessment.locationRequired", comment: ""); return }
        guard let questionnaire else { return }
        let required = questionnaire.questions.filter { $0.required == true }.map(\.id)
        guard required.allSatisfy({ answers[$0]?.isEmpty == false }) else { message = NSLocalizedString("assessment.required", comment: ""); return }
        guard let token = KeychainStore.readToken() else { message = NSLocalizedString("assessment.sessionRequired", comment: ""); return }
        isSending = true; message = nil
        defer { isSending = false }
        let intensity = questionnaire.questions.first(where: { $0.id == "intensity" })?.options
            .flatMap { options in answers["intensity"].flatMap { selected in options.firstIndex(of: selected).map { $0 + 1 } } }
        do {
            _ = try await service.submitAssessment(alertId: alertID, request: AlertAssessmentRequest(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, intensity: intensity, answers: answers), token: token)
            didSubmit = true
            message = NSLocalizedString("assessment.saved", comment: "")
        } catch { message = error.localizedDescription }
    }
}

struct AlertAssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    let alert: OfficialAlertDTO
    let isNearby: Bool
    let location: CLLocation?
    @StateObject private var viewModel = AlertAssessmentViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ANÁLISIS DE ALERTA").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(SentinelTheme.primary)
                            Text(alert.categoryDisplayName)
                                .font(.largeTitle.bold())
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary).frame(width: 40, height: 40)
                                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                        }
                        .accessibilityLabel("Cerrar")
                    }
                    alertSummary
                    alertDetails
                    if isCriticalNearby { emergencyHelp }
                    emergencyContacts
                    if isNearby { assessmentForm } else { remoteNotice }
                }
                .padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load(alertID: alert.id) }
        }
    }

    private var isCriticalNearby: Bool {
        guard let location, location.horizontalAccuracy >= 0,
              Date().timeIntervalSince(location.timestamp) < 300,
              let latitude = alert.latitude, let longitude = alert.longitude else { return false }
        let eventLocation = CLLocation(latitude: latitude, longitude: longitude)
        return (alert.severity == "CRITICAL" || alert.severity == "HIGH")
            && location.distance(from: eventLocation) <= 50_000
    }

    private var alertDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Datos del evento", systemImage: "info.circle.fill").font(.headline)
            Text("Publicado · \(formattedPublishedDate)")
                .font(.footnote).foregroundStyle(.secondary)
            if let syncedAt = viewModel.officialAlertsSyncedAt {
                Label("Última actualización de fuentes: \(syncedAt.formatted(date: .abbreviated, time: .standard))",
                      systemImage: "arrow.clockwise").font(.footnote)
            }
            if let latitude = alert.latitude, let longitude = alert.longitude {
                if alert.category == "SISMO" {
                    Label("Epicentro reportado", systemImage: "waveform.path").font(.subheadline.weight(.semibold))
                } else {
                    Label("Ubicación reportada", systemImage: "mappin.and.ellipse").font(.subheadline.weight(.semibold))
                }
                Text(String(format: "%.5f°, %.5f°", latitude, longitude))
                    .font(.footnote.monospaced())
                Map {
                    Marker(alert.categoryDisplayName, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
                .frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Label("La fuente no proporcionó coordenadas para este evento.", systemImage: "location.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let source = alert.sourceUrl, let url = URL(string: source) {
                Link("Abrir reporte de la fuente oficial", destination: url)
                    .font(.footnote.weight(.semibold))
            }
            Text("Fuente: \(alert.source) · \(alert.categoryDisplayName)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var formattedPublishedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: alert.publishedAt)
            ?? ISO8601DateFormatter().date(from: alert.publishedAt)
        guard let date else { return alert.publishedAt }
        return date.formatted(date: .long, time: .shortened)
    }

    private var emergencyHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Alerta grave cerca de ti", systemImage: "sos.circle.fill")
                .font(.headline).foregroundStyle(.red)
            Text("Si estás en peligro o necesitas asistencia, contacta a emergencias.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                ForEach([("Policía", "105"), ("Bomberos", "116"), ("SAMU", "106")], id: \.1) { name, number in
                    if let url = URL(string: "tel://\(number)") {
                        Link(name, destination: url).buttonStyle(.borderedProminent).tint(.red)
                    }
                }
            }
        }
        .padding(16).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var alertSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(alert.title, systemImage: "exclamationmark.triangle.fill").font(.title3.bold())
            HStack(spacing: 8) {
                Text(alert.source.uppercased()).font(.caption2.bold()).tracking(0.6)
                Text("·")
                Text(alert.severity).font(.caption2.bold())
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background((alert.severity == "CRITICAL" || alert.severity == "HIGH" ? Color.red : SentinelTheme.primary).opacity(0.13), in: Capsule())
            }.foregroundStyle(alert.severity == "CRITICAL" || alert.severity == "HIGH" ? .red : SentinelTheme.primary)
            Text(alert.description).font(.body)
            if let distance = alert.distanceKm {
                Label(String(format: "%.1f km de tu ubicación", distance), systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(SentinelTheme.primary)
            } else {
                Text(alert.categoryDisplayName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var assessmentForm: some View {
        if viewModel.isLoading { ProgressView().frame(maxWidth: .infinity) }
        else if let questionnaire = viewModel.questionnaire {
            VStack(alignment: .leading, spacing: 16) {
                Text("assessment.prompt").font(.headline)
                ForEach(questionnaire.questions) { question in questionView(question) }
                if let message = viewModel.message { Text(message).foregroundStyle(viewModel.didSubmit ? .green : .red).font(.footnote) }
                Button { Task { await viewModel.submit(alertID: alert.id, location: location) } } label: {
                    HStack { Spacer(); if viewModel.isSending { ProgressView().tint(.white) } else { Text("assessment.submit").fontWeight(.bold) }; Spacer() }
                }
                .buttonStyle(.borderedProminent).tint(SentinelTheme.primary).disabled(viewModel.isSending || viewModel.didSubmit)
            }
        } else if let message = viewModel.message { Text(message).foregroundStyle(.red) }
    }

    @ViewBuilder private func questionView(_ question: AssessmentQuestionDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(question.prompt).font(.subheadline.weight(.semibold))
            if question.type == "text" { TextField("assessment.writeDetail", text: binding(for: question.id), axis: .vertical).textFieldStyle(.roundedBorder) }
            else { Picker(question.prompt, selection: binding(for: question.id)) { Text("assessment.select").tag(""); ForEach(question.options ?? [], id: \.self) { option in Text(option).tag(option) } }.pickerStyle(.menu).tint(SentinelTheme.primary) }
        }
    }

    private func binding(for key: String) -> Binding<String> { Binding(get: { viewModel.answers[key, default: ""] }, set: { viewModel.answers[key] = $0 }) }

    private var remoteNotice: some View {
        Label("assessment.remoteNotice", systemImage: "location.slash").font(.subheadline).foregroundStyle(.secondary)
    }

    private var emergencyContacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("assessment.emergencyTitle").font(.headline)
            if let contacts = viewModel.questionnaire?.emergencyContacts {
                ForEach(contacts) { contact in
                    Link(destination: URL(string: "tel://\(contact.number)")!) {
                        HStack { Image(systemName: "phone.fill"); VStack(alignment: .leading) { Text("\(contact.name) · \(contact.number)").fontWeight(.semibold); Text(contact.reason).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right") }
                    }.foregroundStyle(SentinelTheme.primary)
                }
            } else { Text("assessment.emergencyFallback").font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
