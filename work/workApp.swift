//
//  workApp.swift
//  work
//
//  Created by 杨忠洋 on 2026/5/19.
//

import SwiftUI
import SwiftData

@main
struct workApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            WorkLogEntry.self,
            WorkLogDayItem.self,
            WorkLogAttachment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
