// App/AutoTrigger/SettingsView.swift
import SwiftUI
import AutoTriggerCore

struct SettingsView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        TabView {
            TasksSettings(model: model)
                .tabItem { Label("Tasks", systemImage: "list.bullet") }
            WebhookSettings(model: model)
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 480, height: 380)
        .padding()
    }
}

private struct TasksSettings: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var id = ""
    @State private var name = ""
    @State private var intervalMinutes = "60"
    @State private var graceMinutes = "10"

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(model.rows) { row in
                    HStack {
                        Text(row.task.displayName)
                        Spacer()
                        Text(row.task.id).font(.caption).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.removeTask(id: row.task.id) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            Divider()
            Text("Add task").font(.headline)
            TextField("Task label (RunStore id)", text: $id)
            TextField("Display name", text: $name)
            HStack {
                TextField("Interval (min)", text: $intervalMinutes).frame(width: 120)
                TextField("Grace (min)", text: $graceMinutes).frame(width: 120)
            }
            Button("Add") {
                guard !id.isEmpty,
                      let interval = Double(intervalMinutes),
                      let grace = Double(graceMinutes) else { return }
                model.addTask(MonitoredTask(
                    id: id,
                    displayName: name.isEmpty ? id : name,
                    expectedInterval: interval * 60,
                    grace: grace * 60,
                    source: .manual
                ))
                id = ""; name = ""
            }
        }
    }
}

private struct WebhookSettings: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var url = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alert webhook URL").font(.headline)
            Text("Point this at Slack / ntfy / Pushover. Stored in the Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://…", text: $url)
            HStack {
                Button("Save") {
                    model.setWebhookURL(url)
                    saved = true
                }
                if saved { Text("Saved").foregroundStyle(.green).font(.caption) }
            }
            Spacer()
        }
        .onAppear { url = model.webhookURL() }
    }
}
