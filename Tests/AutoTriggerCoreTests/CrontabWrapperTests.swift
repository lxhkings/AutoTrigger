import Testing
@testable import AutoTriggerCore

@Test func wrapsFiveFieldScheduleCommand() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "*/5 * * * * /bin/bash /x/run.sh arg"
    #expect(w.wrap(line) == "*/5 * * * * /usr/local/bin/autotrigger-wrap /bin/bash /x/run.sh arg")
}

@Test func wrapsAtShortcutSchedule() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "@daily /x/backup.sh"
    #expect(w.wrap(line) == "@daily /usr/local/bin/autotrigger-wrap /x/backup.sh")
}

@Test func leavesCommentsBlanksAndEnvUntouched() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    #expect(w.wrap("# a comment") == "# a comment")
    #expect(w.wrap("") == "")
    #expect(w.wrap("PATH=/usr/bin:/bin") == "PATH=/usr/bin:/bin")
}

@Test func crontabWrapIsIdempotent() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "0 9 * * 1 /x/weekly.sh"
    let once = w.wrap(line)
    #expect(w.wrap(once) == once)
}

@Test func crontabIsWrappedReflectsState() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "0 9 * * 1 /x/weekly.sh"
    #expect(w.isWrapped(line) == false)
    #expect(w.isWrapped(w.wrap(line)) == true)
}
