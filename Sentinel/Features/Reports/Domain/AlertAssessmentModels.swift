import Foundation

struct AlertQuestionnaireResponse: Codable {
    let alert: OfficialAlertDTO
    let questions: [AssessmentQuestionDTO]
    let emergencyContacts: [EmergencyContactDTO]
}

struct AssessmentQuestionDTO: Codable, Identifiable {
    let id: String
    let prompt: String
    let type: String
    let options: [String]?
    let required: Bool?
}

struct EmergencyContactDTO: Codable, Identifiable {
    let name: String
    let number: String
    let reason: String
    var id: String { number }
}

struct AlertAssessmentRequest: Codable {
    let latitude: Double
    let longitude: Double
    let intensity: Int?
    let answers: [String: String]
}

struct AlertAssessmentResult: Codable {
    let id: String
    let alertId: String
    let intensity: Int?
    let answers: [String: String]
    let distanceKm: Double
    let updatedAt: String
}

struct AlertAssessmentResponse: Codable {
    let assessment: AlertAssessmentResult
}
