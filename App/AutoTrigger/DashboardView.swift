// App/AutoTrigger/DashboardView.swift
import SwiftUI
import AutoTriggerCore

struct DashboardView: View {
    @ObservedObject var model: MenuBarViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedTaskID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let selectedTaskID {
                TaskDetailView(model: model, taskID: selectedTaskID, onBack: {
                    self.selectedTaskID = nil
                })
            } else if model.rows.isEmpty {
                Text("暂无监控任务\n请在设置中添加")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(model.rows) { row in
                    Button {
                        selectedTaskID = row.id
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
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 260)

        Divider()

        HStack {
            #if DEBUG
            Button("演示数据") { model.seedDemoRuns() }
            #endif
            Button("刷新") { model.refresh() }
            Button("设置…") { openSettings() }
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
    }

    private func lastRunText(_ date: Date?) -> String {
        guard let date else { return "从未运行" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return "上次运行 " + f.localizedString(for: date, relativeTo: Date())
    }
}
