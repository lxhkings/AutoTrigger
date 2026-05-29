// App/AutoTrigger/DashboardView.swift
import SwiftUI
import AutoTriggerCore

struct DashboardView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        NavigationStack {
            Group {
                if model.rows.isEmpty {
                    Text("No monitored tasks.\nAdd one in Settings.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.rows) { row in
                        NavigationLink {
                            TaskDetailView(model: model, taskID: row.id)
                        } label: {
                            HStack {
                                Image(systemName: row.health.symbolName)
                                    .foregroundStyle(row.health.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.task.displayName)
                                    Text(lastRunText(row.lastRun))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 260)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Refresh") { model.refresh() }
                }
            }
        }
        Divider()
        HStack {
            #if DEBUG
            Button("Seed demo") { model.seedDemoRuns() }
            #endif
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
    }

    private func lastRunText(_ date: Date?) -> String {
        guard let date else { return "never run" }
        let f = RelativeDateTimeFormatter()
        return "last run " + f.localizedString(for: date, relativeTo: Date())
    }
}
