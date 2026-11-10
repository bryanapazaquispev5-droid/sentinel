import Foundation
import Combine
import CoreLocation

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published private(set) var reports: [ReportDTO] = []
    @Published private(set) var alerts: [OfficialAlertDTO] = []
    @Published private(set) var nearbyAlerts: [OfficialAlertDTO] = []
    @Published private(set) var predictions: [OfficialAlertDTO] = []
    @Published private(set) var historicalAlerts: [OfficialAlertDTO] = []
    @Published private(set) var historicalReports: [ReportDTO] = []
    @Published private(set) var officialAlertsSyncedAt: Date?
    @Published private(set) var lastDataSyncAt: Date?
    @Published private(set) var isConnectedToAPI = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let service = ReportsService()
    private let notificationService = LocalNotificationService()
    private var lastLoadAt: Date?
    private var lastLoadLocation: CLLocation?
    private var queuedReloadLocation: CLLocation?

    func load(location: CLLocation?, force: Bool = false) async {
        guard let location else { errorMessage = "Activa la ubicación para ver reportes cercanos."; return }
        if isLoading {
            if force { queuedReloadLocation = location }
            return
        }
        guard force || shouldRefresh(for: location) else { return }
        isLoading = true; errorMessage = nil
        defer {
            isLoading = false
            if let queuedLocation = queuedReloadLocation {
                queuedReloadLocation = nil
                Task { await load(location: queuedLocation, force: true) }
            }
        }
        do {
            async let peruReports = service.peruReports()
            async let peruAlerts = service.peruAlerts()
            async let archivedAlerts = service.alertHistory()
            async let archivedReports = service.reportHistory()
            async let latestSync = service.latestOfficialAlertSync()
            async let nearbyReports = service.nearby(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            async let localAlerts = service.nearbyAlerts(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            async let officialPredictions = service.peruPredictions()

            let loadedReports = try await peruReports
            let localReports = try await nearbyReports
            reports = mergeDistances(allReports: loadedReports, nearbyReports: localReports)
            alerts = try await peruAlerts
            historicalAlerts = (try? await archivedAlerts) ?? []
            historicalReports = (try? await archivedReports) ?? []
            nearbyAlerts = try await localAlerts
            predictions = (try? await officialPredictions) ?? []
            if let syncedAt = try? await latestSync { officialAlertsSyncedAt = syncedAt }
            await notificationService.processNearbyAlerts(nearbyAlerts)
            lastLoadAt = Date()
            lastLoadLocation = location
            lastDataSyncAt = lastLoadAt
            isConnectedToAPI = true
        } catch APIClientError.cancelled {
            // La vista puede desaparecer o volver a cargarse; no es un error de red para el usuario.
        } catch {
            isConnectedToAPI = false
            errorMessage = error.localizedDescription
        }
    }

    func vote(report: ReportDTO, type: String, location: CLLocation, token: String) async {
        do {
            let updated = try await service.vote(reportId: report.id, type: type, location: location, token: token)
            if let index = reports.firstIndex(where: { $0.id == updated.id }) { reports[index] = updated }
        } catch { errorMessage = error.localizedDescription }
    }

    private func shouldRefresh(for location: CLLocation) -> Bool {
        guard let lastLoadAt, let lastLoadLocation else { return true }
        let isRecent = Date().timeIntervalSince(lastLoadAt) < 30
        return !isRecent || location.distance(from: lastLoadLocation) >= 100
    }

    private func mergeDistances(allReports: [ReportDTO], nearbyReports: [ReportDTO]) -> [ReportDTO] {
        let distances = Dictionary(uniqueKeysWithValues: nearbyReports.compactMap { report in
            report.distanceKm.map { (report.id, $0) }
        })
        return allReports.map { $0.withDistance(distances[$0.id]) }
    }
}

@MainActor
final class CreateReportViewModel: ObservableObject {
    @Published var category = "SISMO"
    @Published var incidentLabel = ""
    @Published var description = ""
    @Published var severity: ReportSeverity = .medium
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let service = ReportsService()

    let categories = ["SISMO", "TSUNAMI", "INUNDACION", "LLUVIA_INTENSA", "HUAICO", "DERRUMBE", "DESLIZAMIENTO", "ALUVION", "PELIGRO_GLACIAR", "INCENDIO", "VOLCAN", "CENIZA_VOLCANICA", "LAHAR", "FLUJO_PIROCLASTICO", "TORMENTA", "CICLON_TROPICAL", "SEQUIA", "FRIAJE", "HELADA", "GRANIZADA", "NEVADA", "OLA_CALOR", "OLEAJE", "EL_NINO", "ACCIDENTE", "OTRO"]

    func submit(location: CLLocation?, token: String, creationType: ReportCreationType, photoData: String?) async -> Bool {
        guard let location else { errorMessage = "Necesitamos tu ubicación para crear el reporte."; return false }
        guard description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 else { errorMessage = "Describe brevemente lo que está ocurriendo."; return false }
        if creationType == .otherIncident && incidentLabel.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            errorMessage = "Escribe qué tipo de incidente observaste."
            return false
        }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let reportCategory = creationType == .otherIncident ? "OTRO" : category
            let reportDescription = creationType == .otherIncident
                ? "Incidente descrito por el usuario: \(incidentLabel.trimmingCharacters(in: .whitespacesAndNewlines)).\n\(description.trimmingCharacters(in: .whitespacesAndNewlines))"
                : description.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await service.create(CreateReportRequest(incidentType: creationType == .otherIncident ? "OTHER_INCIDENT" : "NATURAL_DISASTER", category: reportCategory, description: reportDescription, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, severity: severity, photoUrl: nil, photoData: photoData), token: token)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}
