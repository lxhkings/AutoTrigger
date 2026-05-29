import Foundation

/// Single source for the on-disk locations AutoTrigger uses, so the app, the
/// daemon, and the stores all agree on one Application Support layout.
public enum AutoTriggerPaths {
    public static var applicationSupportDirectory: URL {
        let expanded = NSString(string: "~/Library/Application Support/AutoTrigger").expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    public static var monitoredTasksFile: URL {
        applicationSupportDirectory.appendingPathComponent("monitored-tasks.json")
    }

    public static var runStorePath: String {
        applicationSupportDirectory.appendingPathComponent("runs.sqlite").path
    }
}
