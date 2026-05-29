// App/AutoTrigger/AutoTriggerApp.swift
import SwiftUI
import AutoTriggerCore

@main
struct AutoTriggerApp: App {
    @StateObject private var model = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
        } label: {
            Image(systemName: model.aggregate.symbolName)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
