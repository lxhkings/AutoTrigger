// App/AutoTrigger/TaskDetailView.swift
import SwiftUI
import AutoTriggerCore

struct TaskDetailView: View {
    @ObservedObject var model: MenuBarViewModel
    let taskID: String

    var body: some View {
        let runs = model.recentRuns(for: taskID)
        List {
            if runs.isEmpty {
                Text("No runs recorded yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: run.exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(run.exitCode == 0 ? .green : .red)
                        Text(run.finishedAt.formatted(date: .abbreviated, time: .standard))
                        Spacer()
                        Text("exit \(run.exitCode)").font(.caption)
                        Text(durationText(run)).font(.caption).foregroundStyle(.secondary)
                    }
                    let tail = run.stderr.isEmpty ? run.stdout : run.stderr
                    if !tail.isEmpty {
                        Text(tail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Runs")
    }

    private func durationText(_ run: RunRecord) -> String {
        String(format: "%.1fs", run.finishedAt.timeIntervalSince(run.startedAt))
    }
}
