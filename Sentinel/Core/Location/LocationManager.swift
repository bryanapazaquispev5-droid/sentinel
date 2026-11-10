import MapKit
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var areaName: String?
    @Published private(set) var errorMessage: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    func requestPermission() {
        errorMessage = nil
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Activa la ubicación en Ajustes para consultar alertas de tu zona."
        @unknown default:
            errorMessage = "No se pudo determinar el permiso de ubicación."
        }
    }

    func requestCurrentLocation() {
        guard isAuthorized else { requestPermission(); return }
        errorMessage = nil
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized { startUpdates(); manager.requestLocation() }
        else if isDenied { errorMessage = "Activa la ubicación en Ajustes para consultar alertas de tu zona." }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newestLocation = locations.last, newestLocation.horizontalAccuracy >= 0 else { return }
        location = newestLocation
        errorMessage = nil
        Task { await reverseGeocode(newestLocation) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "No se pudo obtener tu ubicación. Intenta actualizar nuevamente."
    }

    private func startUpdates() {
        manager.startUpdatingLocation()
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let request = MKReverseGeocodingRequest(location: location)
            let items = try await request?.mapItems
            guard let address = items?.first?.address else { return }
            areaName = address.shortAddress ?? address.fullAddress
        } catch {
            // Las coordenadas siguen disponibles aunque falle la geocodificación.
        }
    }
}
