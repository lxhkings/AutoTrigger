import Foundation

/// Wraps the command portion of a crontab line, leaving the schedule fields,
/// comments, blank lines, and environment assignments untouched.
public struct CrontabWrapper {
    public let wrapperPath: String

    public init(wrapperPath: String) {
        self.wrapperPath = wrapperPath
    }

    public func isWrapped(_ line: String) -> Bool {
        guard let split = scheduleCommandSplit(line) else { return false }
        return split.command.hasPrefix(wrapperPath + " ") || split.command == wrapperPath
    }

    public func wrap(_ line: String) -> String {
        guard let split = scheduleCommandSplit(line) else { return line } // comment/blank/env
        if split.command.hasPrefix(wrapperPath + " ") { return line }     // idempotent
        return split.schedule + " " + wrapperPath + " " + split.command
    }

    /// Returns (schedule, command) for a runnable crontab line, or nil for a
    /// comment, blank line, or environment assignment that must not be wrapped.
    private func scheduleCommandSplit(_ line: String) -> (schedule: String, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        // Environment assignment: NAME=value as the first token, no schedule.
        if let eq = trimmed.firstIndex(of: "="),
           !trimmed[..<eq].contains(" "),
           !trimmed.hasPrefix("@"),
           !trimmed.hasPrefix("*"),
           trimmed.first.map({ !$0.isNumber }) ?? false {
            return nil
        }

        if trimmed.hasPrefix("@") {
            // @shortcut command...
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
        }

        // 5 schedule fields, then the command (which may contain spaces).
        let fields = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard fields.count == 6 else { return nil }
        let schedule = fields[0..<5].joined(separator: " ")
        let command = String(fields[5]).trimmingCharacters(in: .whitespaces)
        return (schedule, command)
    }
}
