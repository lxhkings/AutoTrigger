// App/AutoTrigger/TaskDetailView.swift
import SwiftUI
import AutoTriggerCore

struct TaskDetailView: View {
    @ObservedObject var model: MenuBarViewModel
    let taskID: String
    var onBack: (() -> Void)?

    var body: some View {
        let runs = model.recentRuns(for: taskID)
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack?()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("运行记录").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                if runs.isEmpty {
                    Text("暂无运行记录").foregroundStyle(.secondary)
                }
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: run.exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(run.exitCode == 0 ? .green : .red)
                            Text(run.finishedAt.formatted(date: .abbreviated, time: .standard))
                            Spacer()
                            Text("退出码 \(run.exitCode)").font(.caption)
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
        }
    }

    private func durationText(_ run: RunRecord) -> String {
        String(format: "%.1fs", run.finishedAt.timeIntervalSince(run.startedAt))
    }
}
