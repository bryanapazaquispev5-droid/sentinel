import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: AppSession
    @ObservedObject var locationManager: LocationManager
    @StateObject private var reportsViewModel = ReportsViewModel()
    @State private var cameraPosition: MapCameraPosition = .region(Self.peruRegion)
    @State private var cameraPositionBeforeAlert: MapCameraPosition?
    @State private var latestMapCamera: MapCamera?
    @State private var mapCameraBeforeAlert: MapCamera?
    @State private var showingCreateReport = false
    @State private var reportCreationType: ReportCreationType = .naturalDisaster
    @State private var dismissedEmergencyID: String?
    @State private var selectedMapAlertID: String?
    @State private var mapAlertDetail: OfficialAlertDTO?
    @State private var impactPolygons: [AlertImpactPolygon] = []
    @State private var estimatedImpactRadiusKm: Double?
    @State private var impactGeometryAlertID: String?
    @State private var isLoadingImpactPolygons = false
    @State private var impactPolygonLoadFailed = false

    private static let peruRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -12.0464, longitude: -77.0428),
        span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 10.5)
    )

    var body: some View {
        TabView {
            mapTab
                .tabItem { Label("home.map", systemImage: "map.fill") }
            reportsTab
                .tabItem { Label("home.reports", systemImage: "list.bullet.rectangle.fill") }
            NavigationStack { ProfileView(session: session) }
                .tabItem { Label("home.profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(SentinelTheme.primary)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { locationManager.requestCurrentLocation() }
        .task(id: locationManager.location?.timestamp) {
            guard let location = locationManager.location else { return }
            if isInPeru(location.coordinate) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(center: location.coordinate,
                        latitudinalMeters: 180_000, longitudinalMeters: 180_000))
                }
            }
            await reportsViewModel.load(location: location)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if let location = locationManager.location {
                await reportsViewModel.load(location: location, force: true)
            }
            await observeOfficialAlerts()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                if let location = locationManager.location {
                    await reportsViewModel.load(location: location, force: true)
                }
            }
        }
    }

    private func observeOfficialAlerts() async {
        guard var url = URLComponents(
            url: APIClient.baseURL.appendingPathComponent("alerts/live"),
            resolvingAgainstBaseURL: true
        ) else { return }
        url.scheme = url.scheme == "https" ? "wss" : "ws"
        guard let endpoint = url.url else { return }

        while !Task.isCancelled {
            let socket = URLSession.shared.webSocketTask(with: endpoint)
            socket.resume()
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    guard let message = try? await socket.receive() else { break }
                    guard case .string(let payload) = message,
                          let event = try? JSONDecoder().decode(AlertUpdate.self, from: Data(payload.utf8)),
                          ["alerts.updated", "reports.updated"].contains(event.type),
                          let location = locationManager.location else { continue }
                    await reportsViewModel.load(location: location, force: true)
                }
            } onCancel: {
                socket.cancel(with: .goingAway, reason: nil)
            }
            socket.cancel()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private struct AlertUpdate: Decodable {
        let type: String
    }

    private var mapTab: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    ForEach(reportsViewModel.reports) { report in
                        Marker(report.category, coordinate: CLLocationCoordinate2D(latitude: report.latitude, longitude: report.longitude))
                            .tint(mapAlertColor(report.severity))
                    }
                    if let selected = reportsViewModel.alerts.first(where: { $0.id == selectedMapAlertID }),
                       impactGeometryAlertID == selected.id {
                        if !impactPolygons.isEmpty {
                            ForEach(impactPolygons) { polygon in
                                let coordinates = polygon.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                                if coordinates.count >= 3 {
                                    MapPolygon(coordinates: coordinates)
                                        .foregroundStyle(mapAlertColor(selected.severity).opacity(0.18))
                                        .stroke(mapAlertColor(selected.severity).opacity(0.9), lineWidth: 2)
                                }
                            }
                        } else if let latitude = selected.latitude,
                                  let longitude = selected.longitude,
                                  let radiusKm = estimatedImpactRadiusKm {
                            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                            MapCircle(center: center, radius: radiusKm * 1_000)
                                .foregroundStyle(mapAlertColor(selected.severity).opacity(0.08))
                                .stroke(mapAlertColor(selected.severity).opacity(0.72), lineWidth: 2)
                            MapCircle(center: center, radius: radiusKm * 650)
                                .foregroundStyle(.clear)
                                .stroke(mapAlertColor(selected.severity).opacity(0.42), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            MapCircle(center: center, radius: radiusKm * 330)
                                .foregroundStyle(.clear)
                                .stroke(mapAlertColor(selected.severity).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        }
                    }
                    ForEach(reportsViewModel.alerts) { alert in
                        if let latitude = alert.latitude, let longitude = alert.longitude {
                            Annotation(alert.categoryDisplayName, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                                VStack(spacing: 7) {
                                    if selectedMapAlertID == alert.id {
                                        MapAlertPreviewCard(alert: alert,
                                            impactAreaDescription: impactAreaDescription,
                                            onOpen: { mapAlertDetail = alert },
                                            onClose: closeSelectedMapAlert)
                                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    }
                                    Button {
                                        toggleMapAlertSelection(alert)
                                    } label: {
                                        VStack(spacing: 2) {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.system(size: 42, weight: .semibold))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, mapAlertColor(alert.severity))
                                                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                                            Text(alert.categoryDisplayName.uppercased())
                                                .font(.caption2.weight(.heavy))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.black.opacity(0.58), in: Capsule())
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(alert.categoryDisplayName), \(alert.severity). Mostrar resumen")
                                }
                            }
                        }
                    }
                }
                .onTapGesture {
                    if selectedMapAlertID != nil { closeSelectedMapAlert() }
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    if selectedMapAlertID == nil { latestMapCamera = context.camera }
                }
                .mapStyle(.standard(elevation: colorScheme == .dark ? .realistic : .flat))
                .mapControls { MapCompass() }
                .overlay(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 230, height: 48)
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea(edges: .bottom)

                MapHeaderView()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 12) {
                    Button(action: centerOnCurrentLocation) {
                        Image(systemName: "location.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SentinelTheme.primary)
                            .frame(width: 46, height: 46)
                            .background(.regularMaterial, in: Circle())
                            .overlay { Circle().stroke(SentinelTheme.border, lineWidth: 1) }
                            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                    }
                    .accessibilityLabel(Text("home.centerLocation"))
                    Button { reportCreationType = .naturalDisaster; showingCreateReport = true } label: {
                        Label("home.newReport", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(SentinelTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                    }
                    Button { reportCreationType = .otherIncident; showingCreateReport = true } label: {
                        Label("Reportar otro incidente", systemImage: "square.and.pencil")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.black.opacity(0.82))
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(Color.yellow.gradient, in: RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .overlay {
                if let emergency = nearbyConfirmedEmergency, dismissedEmergencyID != emergency.id {
                    EmergencyAlertOverlay(
                        title: emergency.title,
                        category: emergency.category,
                        severity: emergency.severity,
                        distanceKm: emergency.distanceKm,
                        onDismiss: { dismissedEmergencyID = emergency.id }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .overlay {
                if let emergency = nearbyConfirmedEmergency {
                    EmergencyEdgeBorder(severity: emergency.severity)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCreateReport) {
                CreateReportView(session: session, locationManager: locationManager, creationType: reportCreationType) {
                    showingCreateReport = false
                    Task { if let location = locationManager.location { await reportsViewModel.load(location: location) } }
                }
            }
            .sheet(item: $mapAlertDetail, onDismiss: {
                closeSelectedMapAlert()
            }) { alert in
                AlertAssessmentView(alert: alert,
                                    isNearby: reportsViewModel.nearbyAlerts.contains(where: { $0.id == alert.id }),
                                    location: locationManager.location)
            }
            .task(id: selectedMapAlertID) {
                impactPolygons = []
                estimatedImpactRadiusKm = nil
                impactGeometryAlertID = nil
                impactPolygonLoadFailed = false
                guard let selectedMapAlertID else { isLoadingImpactPolygons = false; return }
                isLoadingImpactPolygons = true
                defer { isLoadingImpactPolygons = false }
                do {
                    let geometry = try await ReportsService().impactGeometry(alertID: selectedMapAlertID)
                    guard !Task.isCancelled, self.selectedMapAlertID == selectedMapAlertID else { return }
                    impactPolygons = geometry.polygons
                    estimatedImpactRadiusKm = geometry.estimatedRadiusKm
                    impactGeometryAlertID = selectedMapAlertID
                    if let alert = reportsViewModel.alerts.first(where: { $0.id == selectedMapAlertID }) {
                        focusMap(on: alert, polygons: geometry.polygons, estimatedRadiusKm: geometry.estimatedRadiusKm)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    impactPolygonLoadFailed = true
                }
            }
        }
    }

    private func mapAlertColor(_ severity: String) -> Color {
        switch severity.uppercased() {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MEDIUM": .yellow
        default: .green
        }
    }

    private func toggleMapAlertSelection(_ alert: OfficialAlertDTO) {
        if selectedMapAlertID == alert.id {
            closeSelectedMapAlert()
            return
        }
        if selectedMapAlertID == nil {
            cameraPositionBeforeAlert = cameraPosition
            mapCameraBeforeAlert = latestMapCamera
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedMapAlertID = alert.id
            if let latitude = alert.latitude, let longitude = alert.longitude {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    latitudinalMeters: 120_000,
                    longitudinalMeters: 120_000
                ))
            }
        }
    }

    private func closeSelectedMapAlert() {
        let previousCamera = cameraPositionBeforeAlert
        let previousMapCamera = mapCameraBeforeAlert
        withAnimation(.easeInOut(duration: 0.42)) {
            selectedMapAlertID = nil
            if let previousMapCamera {
                cameraPosition = .camera(previousMapCamera)
            } else if let previousCamera {
                cameraPosition = previousCamera
            }
        }
        cameraPositionBeforeAlert = nil
        mapCameraBeforeAlert = nil
        impactGeometryAlertID = nil
        impactPolygons = []
        estimatedImpactRadiusKm = nil
    }

    private func focusMap(on alert: OfficialAlertDTO, polygons: [AlertImpactPolygon], estimatedRadiusKm: Double?) {
        guard let latitude = alert.latitude, let longitude = alert.longitude else { return }
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        if !polygons.isEmpty {
            let points = polygons.flatMap(\.coordinates).map {
                MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            if let first = points.first {
                let bounds = points.dropFirst().reduce(into: (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)) { bounds, point in
                    bounds.minX = min(bounds.minX, point.x)
                    bounds.minY = min(bounds.minY, point.y)
                    bounds.maxX = max(bounds.maxX, point.x)
                    bounds.maxY = max(bounds.maxY, point.y)
                }
                let width = max(bounds.maxX - bounds.minX, 1_000)
                let height = max(bounds.maxY - bounds.minY, 1_000)
                let horizontalPadding = width * 0.22
                // Shift the event footprint slightly toward the top of the
                // screen, leaving room below for the map controls and tabs.
                let topPadding = height * 0.24
                let bottomPadding = height * 0.62
                let fittedRect = MKMapRect(
                    x: bounds.minX - horizontalPadding,
                    y: bounds.minY - topPadding,
                    width: width + horizontalPadding * 2,
                    height: height + topPadding + bottomPadding
                )
                withAnimation(.easeInOut(duration: 0.72)) { cameraPosition = .rect(fittedRect) }
                return
            }
        }
        let radiusMeters = max((estimatedRadiusKm ?? 30) * 1_000 * 3.6, 45_000)
        let latitudeSpan = radiusMeters / 111_000
        let shiftedCenter = CLLocationCoordinate2D(
            latitude: center.latitude - latitudeSpan * 0.18,
            longitude: center.longitude
        )
        withAnimation(.easeInOut(duration: 0.72)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: shiftedCenter,
                latitudinalMeters: radiusMeters,
                longitudinalMeters: radiusMeters
            ))
        }
    }

    private var impactAreaDescription: String {
        if isLoadingImpactPolygons { return "Consultando perímetro de la fuente…" }
        if !impactPolygons.isEmpty {
            let labels = Array(Set(impactPolygons.compactMap(\.label))).sorted()
            return labels.isEmpty ? "Perímetro oficial del proveedor" : labels.prefix(2).joined(separator: " · ")
        }
        if impactPolygonLoadFailed { return "El perímetro de la fuente no está disponible ahora." }
        if let radiusKm = estimatedImpactRadiusKm {
            let radius = radiusKm.formatted(.number.precision(.fractionLength(0...1)))
            return "Zona referencial estimada · radio ~\(radius) km · no es un perímetro oficial."
        }
        return "El proveedor no publica un perímetro para este evento."
    }

    private var nearbyConfirmedEmergency: (id: String, title: String, category: String, severity: String, distanceKm: Double?)? {
        let official = reportsViewModel.nearbyAlerts
            .sorted {
                let left = emergencySeverityRank($0.severity)
                let right = emergencySeverityRank($1.severity)
                if left != right { return left > right }
                return ($0.distanceKm ?? .greatestFiniteMagnitude) < ($1.distanceKm ?? .greatestFiniteMagnitude)
            }
        if let alert = official.first {
            return (alert.id, alert.title, alert.category, alert.severity, alert.distanceKm)
        }
        let confirmed = reportsViewModel.reports
            .filter { ["COMMUNITY_VERIFIED", "OFFICIALLY_VERIFIED"].contains($0.status) }
            .sorted { ($0.distanceKm ?? .greatestFiniteMagnitude) < ($1.distanceKm ?? .greatestFiniteMagnitude) }
        guard let report = confirmed.first else { return nil }
        return (report.id, report.category, report.category, report.severity, report.distanceKm)
    }

    private func emergencySeverityRank(_ severity: String) -> Int {
        switch severity {
        case "CRITICAL": 4
        case "HIGH": 3
        case "MEDIUM": 2
        default: 1
        }
    }

    private func centerOnCurrentLocation() {
        locationManager.requestCurrentLocation()
        guard let location = locationManager.location, isInPeru(location.coordinate) else {
            withAnimation(.easeInOut(duration: 0.8)) { cameraPosition = .region(Self.peruRegion) }
            return
        }
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 12_000,
                longitudinalMeters: 12_000
            )
        )
    }

    private func isInPeru(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (-18.5 ... 0.5).contains(coordinate.latitude) && (-82.0 ... -68.0).contains(coordinate.longitude)
    }

    private var reportsTab: some View {
        NavigationStack {
            ReportsListView(reportsViewModel: reportsViewModel, locationManager: locationManager)
            .refreshable { if let location = locationManager.location { await reportsViewModel.load(location: location) } }
        }
    }
}

private struct EmergencyAlertOverlay: View {
    let title: String
    let category: String
    let severity: String
    let distanceKm: Double?
    let onDismiss: () -> Void

    private var tint: Color {
        switch severity {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MEDIUM": .yellow
        default: SentinelTheme.success
        }
    }

    private var advice: String {
        switch category.uppercased() {
        case "SISMO", "EARTHQUAKE": "Aléjate de ventanas, cúbrete y protege la cabeza. Cuando pare el movimiento, evacúa por rutas seguras."
        case "INUNDACION", "HUAICO", "ALUVION", "FLOOD": "Aléjate de ríos y quebradas. Dirígete a una zona alta y no cruces corrientes de agua."
        case "INCENDIO", "FIRE": "Aléjate del humo y del fuego. Evacúa siguiendo indicaciones de las autoridades."
        case "DERRUMBE", "DESLIZAMIENTO", "PELIGRO_GLACIAR": "Aléjate de laderas, taludes y cauces. Sigue las indicaciones de las autoridades locales."
        case "TSUNAMI", "OLEAJE": "Aléjate de la costa y dirígete a una zona alta por rutas seguras."
        case "CENIZA_VOLCANICA": "Cubre nariz y boca, protege tus ojos y sigue el aviso del IGP y las autoridades."
        case "LAHAR", "FLUJO_PIROCLASTICO", "VOLCAN": "Aléjate del volcán y de quebradas; sigue las rutas de evacuación oficiales."
        case "LLUVIA_INTENSA", "TORMENTA", "CICLON_TROPICAL": "Busca refugio seguro y evita cauces, árboles y estructuras expuestas."
        case "FRIAJE", "HELADA", "NEVADA", "GRANIZADA": "Refúgiate del frío y evita desplazarte durante condiciones peligrosas."
        case "OLA_CALOR": "Busca sombra, hidrátate y evita actividad física durante las horas de más calor."
        case "SEQUIA", "EL_NINO": "Consulta las recomendaciones oficiales de gestión de agua y preparación local."
        default: "Aléjate de la zona de peligro y sigue las indicaciones de las autoridades locales."
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(severity == "CRITICAL" ? "ALERTA CRÍTICA" : "ALERTA CERCANA",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.black)).tracking(0.8).foregroundStyle(tint)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                            .frame(width: 32, height: 32).background(.quaternary, in: Circle())
                    }
                    .accessibilityLabel("Cerrar alerta")
                }
                Text(title).font(.title3.bold()).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 8) {
                    Text(severity).font(.caption.bold())
                    if let distanceKm { Text("·"); Text(String(format: "%.1f km de ti", distanceKm)) }
                }.font(.caption).foregroundStyle(.secondary)
                Text(advice).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    emergencyLink("Policía", number: "105")
                    emergencyLink("Bomberos", number: "116")
                    emergencyLink("SAMU", number: "106")
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(tint.opacity(0.75), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .padding(.horizontal, 28)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func emergencyLink(_ label: String, number: String) -> some View {
        Link(destination: URL(string: "tel://\(number)")!) {
            VStack(spacing: 4) {
                Image(systemName: "phone.fill")
                Text(label).font(.caption2.weight(.bold))
                Text(number).font(.caption.monospacedDigit())
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct EmergencyEdgeBorder: View {
    let severity: String
    @State private var glowing = false

    private var tint: Color {
        switch severity {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MEDIUM": .yellow
        default: SentinelTheme.success
        }
    }

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .stroke(tint.opacity(glowing ? 0.92 : 0.22), lineWidth: glowing ? 1.25 : 0.8)
                .shadow(color: tint.opacity(glowing ? 0.22 : 0.04), radius: glowing ? 4 : 1)
                .padding(5)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .animation(.easeInOut(duration: severity == "CRITICAL" ? 0.45 : 0.9).repeatForever(autoreverses: true), value: glowing)
        }
        .onAppear { glowing = true }
    }
}

private struct MapAlertPreviewCard: View {
    let alert: OfficialAlertDTO
    let impactAreaDescription: String
    let onOpen: () -> Void
    let onClose: () -> Void

    private var tint: Color {
        switch alert.severity.uppercased() {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MEDIUM": .yellow
        default: .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(alert.source.uppercased()).tracking(0.6)
                        Circle().frame(width: 3, height: 3)
                        Text(alert.severity)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(tint.opacity(0.18), in: Capsule())
                    }
                    .font(.caption2.weight(.heavy)).foregroundStyle(tint)
                    Text(alert.title)
                        .font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(alert.description)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Label("Ver detalles completos", systemImage: "arrow.up.right")
                        .font(.caption2.weight(.bold)).foregroundStyle(SentinelTheme.primary)
                        .padding(.top, 1)
                    Label(impactAreaDescription, systemImage: "map")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 25, height: 25).background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Cerrar resumen")
            .padding(.leading, 5)
        }
        .padding(12)
        .frame(width: 270)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.72), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }
}

