//
//  SentinelApp.swift
//  Sentinel
//
//  Created by Ivan Apaza on 29/10/26.
//

import SwiftUI
import UserNotifications

@main
struct SentinelApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
