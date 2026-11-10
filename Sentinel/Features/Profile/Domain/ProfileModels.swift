import Foundation

enum ProfileGender: String, CaseIterable, Identifiable {
    case female = "FEMALE"
    case male = "MALE"
    case nonBinary = "NON_BINARY"
    case preferNotToSay = "PREFER_NOT_TO_SAY"

    var id: String { rawValue }
    var localizationKey: String {
        switch self {
        case .female: return "gender.female"
        case .male: return "gender.male"
        case .nonBinary: return "gender.nonBinary"
        case .preferNotToSay: return "gender.preferNot"
        }
    }
}

struct ProfileUpdateRequest: Encodable {
    let name: String
    let gender: String?
    let birthYear: Int?
    let avatarBase64: String?
}

struct PasswordUpdateRequest: Encodable {
    let currentPassword: String
    let newPassword: String
}

struct ProfileAvatarResponse: Decodable {
    let avatarBase64: String?
}
