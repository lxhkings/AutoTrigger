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
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

// TEMP stub — replaced by SettingsView.swift in Task 9
struct SettingsView: View { @ObservedObject var model: MenuBarViewModel; var body: some View { Text("Settings") } }
