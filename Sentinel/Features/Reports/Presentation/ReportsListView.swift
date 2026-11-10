import SwiftUI
import CoreLocation
import MapKit

struct ReportsListView: View {
    @ObservedObject var reportsViewModel: ReportsViewModel
    @ObservedObject var locationManager: LocationManager
    @State private var selectedAlert: OfficialAlertDTO?
    @State private var selectedAlertIsNearby = false
    @State private var alertFilter: AlertFilter = .nearby

    private enum AlertFilter: String, CaseIterable {
        case nearby = "Cerca de ti"
        case all = "Todas"
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline)
    }

    private var distantOfficialAlerts: [OfficialAlertDTO] {
        let nearbyIDs = Set(reportsViewModel.nearbyAlerts.map(\.id))
        let alerts = reportsViewModel.alerts.filter { !nearbyIDs.contains($0.id) }
        return alertFilter == .nearby ? [] : sortAlerts(alerts)
    }

    private var nearbyOfficialAlerts: [OfficialAlertDTO] {
        let alerts = reportsViewModel.nearbyAlerts
        return sortAlerts(alerts)
    }
    private var nearbyCommunityReports: [ReportDTO] {
        reportsViewModel.reports.filter { $0.distanceKm != nil }
            .sorted {
                if abs(($0.distanceKm ?? 0) - ($1.distanceKm ?? 0)) > 0.1 {
                    return ($0.distanceKm ?? .greatestFiniteMagnitude) < ($1.distanceKm ?? .greatestFiniteMagnitude)
                }
                return severityRank($0.severity) > severityRank($1.severity)
            }
    }

    private var distantCommunityReports: [ReportDTO] {
        guard alertFilter == .all else { return [] }
        let nearbyIDs = Set(nearbyCommunityReports.map(\.id))
        return reportsViewModel.reports.filter { !nearbyIDs.contains($0.id) }
            .sorted { severityRank($0.severity) > severityRank($1.severity) }
    }

    private func sortAlerts(_ alerts: [OfficialAlertDTO]) -> [OfficialAlertDTO] {
        alerts.sorted {
            let firstDistance = $0.distanceKm ?? .greatestFiniteMagnitude
            let secondDistance = $1.distanceKm ?? .greatestFiniteMagnitude
            if abs(firstDistance - secondDistance) > 0.1 { return firstDistance < secondDistance }
            return severityRank($0.severity) > severityRank($1.severity)
        }
    }

    private func severityRank(_ value: String) -> Int {
        switch value.uppercased() {
        case "CRITICAL": 4
        case "HIGH": 3
        case "MEDIUM": 2
        default: 1
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Centro de alertas").font(.largeTitle.bold())
                        Text("Eventos oficiales y reportes de tu comunidad").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "dot.radiowaves.left.and.right").font(.title2).foregroundStyle(SentinelTheme.primary)
                }
                .padding(.top, 8)
                Picker("Filtrar", selection: $alertFilter) {
                    ForEach(AlertFilter.allCases, id: \.self) { filter in Text(filter.rawValue).tag(filter) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Alertas observadas · fuentes oficiales", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(SentinelTheme.primary)
                    Group {
                    if let syncedAt = reportsViewModel.officialAlertsSyncedAt {
                        Text(syncedAt, format: .dateTime.day().month().year().hour().minute().second())
                    } else {
                        Text("home.officialSyncUnavailable")
                    }
                }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(SentinelTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    Label("Predicciones y perspectivas oficiales", systemImage: "sparkles")
                        .font(.headline)
                    if reportsViewModel.predictions.isEmpty {
                        Text("No hay comunicados ENFEN vigentes en este momento.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Perspectivas climáticas y del fenómeno El Niño/La Niña emitidas por ENFEN. Son pronósticos oficiales, separados de las alertas de eventos observados.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(reportsViewModel.predictions) { prediction in
                            OfficialPredictionRow(prediction: prediction)
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(SentinelTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                if !nearbyOfficialAlerts.isEmpty {
                    sectionHeading("Alertas cerca de ti", symbol: "location.circle.fill")
                    VStack(spacing: 10) {
                        ForEach(nearbyOfficialAlerts) { alert in
                            OfficialAlertRow(alert: alert, isNearby: true) { selectedAlertIsNearby = true; selectedAlert = alert }
                                .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }

                if alertFilter == .all && !distantOfficialAlerts.isEmpty {
                    sectionHeading("Alertas en Perú", symbol: "map.fill")
                    VStack(spacing: 10) {
                        ForEach(distantOfficialAlerts) { alert in
                            OfficialAlertRow(alert: alert, isNearby: false) { selectedAlertIsNearby = false; selectedAlert = alert }
                                .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }

                NavigationLink {
                    AlertHistoryView(reportsViewModel: reportsViewModel, locationManager: locationManager)
                } label: {
                    HStack {
                        Label("Historial · últimos 12 meses", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(SentinelTheme.primary)
                    .padding(20)
                    .background(SentinelTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)

                sectionHeading(alertFilter == .nearby ? "Reportes de la comunidad cerca de ti" : "Reportes de la comunidad cerca de ti", symbol: "person.3.fill")
                if reportsViewModel.reports.isEmpty {
                    ContentUnavailableView("Sin reportes por ahora", systemImage: "checkmark.shield",
                                           description: Text("Cuando la comunidad informe un incidente aparecerá aquí."))
                } else {
                    ForEach(nearbyCommunityReports) { report in
                        ReportRow(report: report, location: locationManager.location) { type in
                            guard let location = locationManager.location,
                                  let token = KeychainStore.readToken() else { return }
                            Task {
                                await reportsViewModel.vote(report: report, type: type, location: location, token: token)
                            }
                        }
                        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if alertFilter == .all && nearbyCommunityReports.isEmpty {
                        Text("No hay reportes comunitarios dentro del radio de atención.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if alertFilter == .all && !distantCommunityReports.isEmpty {
                    sectionHeading("Otros reportes en Perú", symbol: "map")
                    ForEach(distantCommunityReports) { report in
                        ReportRow(report: report, location: locationManager.location) { type in
                            guard let location = locationManager.location, let token = KeychainStore.readToken() else { return }
                            Task { await reportsViewModel.vote(report: report, type: type, location: location, token: token) }
                        }
                        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }

            if let errorMessage = reportsViewModel.errorMessage, !reportsViewModel.reports.isEmpty {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .onAppear { alertFilter = .nearby }
        .overlay {
            if reportsViewModel.isLoading && reportsViewModel.reports.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("home.reports")
        .sheet(item: $selectedAlert) { alert in
            AlertAssessmentView(alert: alert, isNearby: selectedAlertIsNearby, location: locationManager.location)
        }
    }
}


private struct AlertHistoryView: View {
    @ObservedObject var reportsViewModel: ReportsViewModel
    @ObservedObject var locationManager: LocationManager
    @State private var selectedAlert: OfficialAlertDTO?

    private var orderedAlerts: [OfficialAlertDTO] {
        reportsViewModel.historicalAlerts.sorted {
            $0.publishedAt > $1.publishedAt
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Historial de eventos")
                    .font(.largeTitle.bold())
                Text("Alertas oficiales y reportes comunitarios de los últimos 12 meses.")
                    .font(.subheadline).foregroundStyle(.secondary)

                if orderedAlerts.isEmpty && reportsViewModel.historicalReports.isEmpty {
                    ContentUnavailableView("Sin eventos anteriores", systemImage: "clock.arrow.circlepath",
                                           description: Text("Los eventos pasan aquí cuando dejan de estar vigentes."))
                        .padding(.top, 24)
                }

                if !orderedAlerts.isEmpty {
                    Label("Alertas oficiales", systemImage: "checkmark.shield.fill").font(.headline)
                    ForEach(orderedAlerts) { alert in
                        OfficialAlertRow(alert: alert, isNearby: false) { selectedAlert = alert }
                            .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }

                if !reportsViewModel.historicalReports.isEmpty {
                    Label("Reportes comunitarios", systemImage: "person.3.fill")
                        .font(.headline).padding(.top, 8)
                    ForEach(reportsViewModel.historicalReports) { report in
                        ReportRow(report: report, location: locationManager.location) { _ in }
                            .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle("Historial")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAlert) { alert in
            AlertAssessmentView(alert: alert, isNearby: false, location: locationManager.location)
        }
    }
}
