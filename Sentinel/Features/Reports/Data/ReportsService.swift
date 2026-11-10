import Foundation
import CoreLocation

struct ReportsService {
    private let client = APIClient()
    nonisolated static let regionRadiusKm = 50.0

    func peruReports() async throws -> [ReportDTO] {
        let response: ReportsResponse = try await client.request("reports/peru")
        return response.reports
    }

    func reportHistory() async throws -> [ReportDTO] {
        let response: ReportsResponse = try await client.request("reports/history")
        return response.reports
    }

    func peruAlerts() async throws -> [OfficialAlertDTO] {
        let response: AlertsResponse = try await client.request("alerts/peru")
        return response.alerts
    }

    func alertHistory() async throws -> [OfficialAlertDTO] {
        let response: AlertsResponse = try await client.request("alerts/history")
        return response.alerts
    }

    func peruPredictions() async throws -> [OfficialAlertDTO] {
        let response: PredictionsResponse = try await client.request("predictions/peru")
        return response.predictions
    }

    func latestOfficialAlertSync() async throws -> Date? {
        struct Source: Decodable { let lastSuccessAt: String? }
        struct Response: Decodable { let sources: [Source] }

        let response: Response = try await client.request("alerts/sources")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return response.sources.compactMap { source in
            source.lastSuccessAt.flatMap { formatter.date(from: $0) }
        }.max()
    }

    func nearby(latitude: Double, longitude: Double, radiusKm: Double = ReportsService.regionRadiusKm) async throws -> [ReportDTO] {
        let path = "reports/nearby?latitude=\(latitude)&longitude=\(longitude)&radiusKm=\(radiusKm)"
        let response: ReportsResponse = try await client.request(path)
        return response.reports
    }

    func nearbyAlerts(latitude: Double, longitude: Double, radiusKm: Double = 100, since: Date? = nil) async throws -> [OfficialAlertDTO] {
        var path = "alerts/nearby?latitude=\(latitude)&longitude=\(longitude)&radiusKm=\(radiusKm)"
        if let since {
            let formatter = ISO8601DateFormatter()
            let encodedDate = formatter.string(from: since).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path += "&since=\(encodedDate)"
        }
        let response: AlertsResponse = try await client.request(path)
        return response.alerts
    }

    func impactGeometry(alertID: String) async throws -> AlertGeometryResponse {
        try await client.request("alerts/\(alertID)/geometry")
    }

    func questionnaire(alertId: String) async throws -> AlertQuestionnaireResponse {
        try await client.request("alerts/(alertId)/questionnaire")
    }

    func submitAssessment(alertId: String, request: AlertAssessmentRequest, token: String) async throws -> AlertAssessmentResult {
        let response: AlertAssessmentResponse = try await client.request("alerts/(alertId)/assessment", method: "POST", body: request, token: token)
        return response.assessment
    }

    func create(_ request: CreateReportRequest, token: String) async throws -> ReportDTO {
        struct Response: Codable { let report: ReportDTO }
        let response: Response = try await client.request("reports", method: "POST", body: request, token: token)
        return response.report
    }

    func vote(reportId: String, type: String, location: CLLocation, token: String) async throws -> ReportDTO {
        struct VoteRequest: Codable { let type: String; let latitude: Double; let longitude: Double }
        struct Response: Codable { let report: ReportDTO }
        let request = VoteRequest(type: type, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let response: Response = try await client.request("reports/\(reportId)/vote", method: "POST", body: request, token: token)
        return response.report
    }
}
