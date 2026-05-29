// App/AutoTrigger/SettingsView.swift
import SwiftUI
import AutoTriggerCore

struct SettingsView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        TabView {
            TasksSettings(model: model)
                .tabItem { Label("任务", systemImage: "list.bullet") }
            WebhookSettings(model: model)
                .tabItem { Label("告警", systemImage: "bell") }
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
            Text("添加任务").font(.headline)
            TextField("任务标识", text: $id)
            TextField("显示名称", text: $name)
            HStack {
                TextField("间隔（分钟）", text: $intervalMinutes).frame(width: 120)
                TextField("宽限（分钟）", text: $graceMinutes).frame(width: 120)
            }
            Button("添加") {
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
            Text("告警 Webhook 地址").font(.headline)
            Text("指向 Slack / ntfy / Pushover 等服务，存储在钥匙串中")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://…", text: $url)
            HStack {
                Button("保存") {
                    model.setWebhookURL(url)
                    saved = true
                }
                if saved { Text("已保存").foregroundStyle(.green).font(.caption) }
            }
            Spacer()
        }
        .onAppear { url = model.webhookURL() }
    }
}
