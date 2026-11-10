import Foundation
import UserNotifications

@MainActor
final class LocalNotificationService {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let seenIDsKey = "sentinel.notifications.officialAlertIDs"
    private let initializedKey = "sentinel.notifications.officialAlertsInitialized"

    func processNearbyAlerts(_ alerts: [OfficialAlertDTO]) async {
        let currentIDs = Set(alerts.map(deduplicationID(for:)))
        guard defaults.bool(forKey: initializedKey) else {
            saveSeenIDs(currentIDs)
            defaults.set(true, forKey: initializedKey)
            return
        }

        let seenIDs = loadSeenIDs()
        let newAlerts = alerts.filter { !seenIDs.contains(deduplicationID(for: $0)) }
        var updatedSeenIDs = seenIDs.union(currentIDs)

        for alert in newAlerts {
            guard await isAuthorized() else { break }
            do {
                try await scheduleNotification(for: alert)
                updatedSeenIDs.insert(deduplicationID(for: alert))
            } catch {
                // Se reintentará en la siguiente sincronización si la entrega falla.
            }
        }

        saveSeenIDs(updatedSeenIDs)
    }

    private func scheduleNotification(for alert: OfficialAlertDTO) async throws {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.official.title", comment: "")
        content.subtitle = alert.title
        content.body = alert.description
        content.sound = .default
        content.threadIdentifier = "sentinel.official-alerts"

        let request = UNNotificationRequest(
            identifier: "sentinel.official-alert.\(deduplicationID(for: alert))",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    private func isAuthorized() async -> Bool {
        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private func deduplicationID(for alert: OfficialAlertDTO) -> String {
        alert.externalId.isEmpty ? alert.id : alert.externalId
    }

    private func loadSeenIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: seenIDsKey) ?? [])
    }

    private func saveSeenIDs(_ ids: Set<String>) {
        defaults.set(Array(ids).sorted(), forKey: seenIDsKey)
    }
}
