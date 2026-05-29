import SwiftUI
import AutoTriggerCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    struct Row: Identifiable {
        let task: MonitoredTask
        let health: TaskHealth
        let lastRun: Date?
        var id: String { task.id }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var aggregate: TaskHealth = .ok

    private let taskStore: MonitoredTaskStore
    private let runStore: RunStore?
    private let secretStore: SecretStore
    private let evaluator = TaskHealthEvaluator()
    private let sleepTracker = SleepTracker()
    private var timer: Timer?

    init(
        taskStore: MonitoredTaskStore = MonitoredTaskStore(),
        runStore: RunStore? = try? RunStore(
            path: AutoTriggerPaths.runStorePath, retentionPerTask: 200, maxOutputChars: 10_000
        ),
        secretStore: SecretStore = KeychainSecretStore()
    ) {
        self.taskStore = taskStore
        self.runStore = runStore
        self.secretStore = secretStore
        sleepTracker.startObserving()
        refresh()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let tasks = (try? taskStore.load()) ?? []
        let now = Date()
        let asleep = sleepTracker.asleepSeconds(asOf: now)
        rows = tasks.map { task in
            let runs = recentRuns(for: task.id)
            let health = evaluator.health(task: task, recentRuns: runs, now: now, asleepSeconds: asleep)
            return Row(task: task, health: health, lastRun: runs.first?.finishedAt)
        }
        aggregate = TaskHealth.aggregate(rows.map(\.health))
    }

    func recentRuns(for taskID: String, limit: Int = 50) -> [RunRecord] {
        guard let runStore, let runs = try? runStore.recent(taskLabel: taskID, limit: limit) else { return [] }
        return runs
    }

    // MARK: Task config mutations
    func addTask(_ task: MonitoredTask) { try? taskStore.add(task); refresh() }
    func removeTask(id: String) { try? taskStore.remove(id: id); refresh() }

    // MARK: Webhook secret
    func webhookURL() -> String { (try? secretStore.get(SecretKeys.webhookURL)) ?? nil ?? "" }
    func setWebhookURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? secretStore.delete(SecretKeys.webhookURL)
        } else {
            try? secretStore.set(trimmed, for: SecretKeys.webhookURL)
        }
    }

    // MARK: Debug seeding (manual QA only; compiled out of Release)
    #if DEBUG
    func seedDemoRuns() {
        guard let runStore else { return }
        let now = Date()
        for task in (try? taskStore.load()) ?? [] {
            let rec = RunRecord(
                taskLabel: task.id,
                startedAt: now.addingTimeInterval(-5),
                finishedAt: now,
                exitCode: 0,
                stdout: "demo ok\n",
                stderr: ""
            )
            try? runStore.insert(rec)
        }
        refresh()
    }
    #endif
}
