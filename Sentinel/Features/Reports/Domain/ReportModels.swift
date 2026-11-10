import Foundation
import SwiftUI

enum ReportSeverity: String, Codable, CaseIterable, Identifiable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "Bajo"
        case .medium: "Medio"
        case .high: "Alto"
        case .critical: "Crítico"
        }
    }

    var tint: Color {
        switch self {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

struct ReportDTO: Codable, Identifiable {
    let id: String
    let category: String
    let description: String
    let latitude: Double
    let longitude: Double
    let severity: String
    let status: String
    let clusterId: String?
    let clusterReportCount: Int?
    let clusterMinimumReports: Int?
    let clusterRadiusKm: Double?
    let photoUrl: String?
    let validationRadiusKm: Double
    let confirmations: Int
    let disputes: Int
    let createdAt: String
    let updatedAt: String
    var distanceKm: Double?
    let user: ReportAuthor?

    func withDistance(_ distanceKm: Double?) -> ReportDTO {
        var copy = self
        copy.distanceKm = distanceKm
        return copy
    }
}

struct ReportAuthor: Codable {
    let name: String
    let reputation: Int?
}

struct OfficialAlertDTO: Codable, Identifiable {
    let id: String
    let externalId: String
    let source: String
    let title: String
    let description: String
    let category: String
    let latitude: Double?
    let longitude: Double?
    let severity: String
    let sourceUrl: String?
    let publishedAt: String
    var expiresAt: String?
    var recordType: String?
    var distanceKm: Double?
    var isActive: Bool?

    var categoryDisplayName: String {
        switch category.uppercased() {
        case "SISMO": "Sismo"
        case "INUNDACION": "Inundación"
        case "INCENDIO": "Incendio forestal"
        case "VOLCAN": "Actividad volcánica"
        case "CLIMA": "Clima severo"
        case "TSUNAMI": "Tsunami / maremoto"
        case "HUAICO": "Huaico / flujo de detritos"
        case "DERRUMBE": "Derrumbe / caída de rocas"
        case "DESLIZAMIENTO": "Deslizamiento"
        case "ALUVION": "Aluvión / alud"
        case "PELIGRO_GLACIAR": "Peligro glaciar"
        case "CENIZA_VOLCANICA": "Ceniza volcánica"
        case "LAHAR": "Lahar"
        case "FLUJO_PIROCLASTICO": "Flujo piroclástico"
        case "LLUVIA_INTENSA": "Lluvia intensa"
        case "TORMENTA": "Vientos / tormenta"
        case "SEQUIA": "Sequía / déficit hídrico"
        case "FRIAJE": "Friaje"
        case "HELADA": "Helada / frío extremo"
        case "GRANIZADA": "Granizada"
        case "NEVADA": "Nevada"
        case "OLA_CALOR": "Ola de calor"
        case "OLEAJE": "Oleaje anómalo / erosión costera"
        case "CICLON_TROPICAL": "Ciclón tropical"
        case "EL_NINO": "El Niño / La Niña"
        default: category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var categorySymbol: String {
        switch category.uppercased() {
        case "SISMO": "waveform.path"
        case "INUNDACION", "HUAICO", "ALUVION": "water.waves"
        case "INCENDIO": "flame.fill"
        case "VOLCAN", "CENIZA_VOLCANICA", "LAHAR", "FLUJO_PIROCLASTICO": "mountain.2.fill"
        case "TSUNAMI", "OLEAJE": "water.waves.and.arrow.down"
        case "DERRUMBE", "DESLIZAMIENTO", "PELIGRO_GLACIAR": "mountain.2.fill"
        case "SEQUIA", "OLA_CALOR", "EL_NINO": "sun.max.fill"
        case "FRIAJE", "HELADA", "NEVADA", "GRANIZADA": "snowflake"
        case "TORMENTA", "CICLON_TROPICAL", "LLUVIA_INTENSA", "CLIMA": "cloud.bolt.rain.fill"
        default: "exclamationmark.triangle.fill"
        }
    }
}

struct ReportsResponse: Codable { let reports: [ReportDTO] }
struct AlertsResponse: Codable { let alerts: [OfficialAlertDTO] }
struct PredictionsResponse: Codable { let predictions: [OfficialAlertDTO] }

struct AlertGeometryCoordinate: Codable {
    let longitude: Double
    let latitude: Double
}

struct AlertImpactPolygon: Codable, Identifiable {
    let id: String
    let label: String?
    let coordinates: [AlertGeometryCoordinate]
}

struct AlertGeometryResponse: Codable {
    let source: String
    let polygons: [AlertImpactPolygon]
    let geometryAvailable: Bool
    let areaType: String?
    let estimatedRadiusKm: Double?
}

struct CreateReportRequest: Codable {
    let incidentType: String
    let category: String
    let description: String
    let latitude: Double
    let longitude: Double
    let severity: ReportSeverity
    let photoUrl: String?
    let photoData: String?
}
