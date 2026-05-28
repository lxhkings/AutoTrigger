import Testing
import Foundation
@testable import AutoTriggerCore

private func plistData(label: String, programArguments: [String]) throws -> Data {
    let dict: [String: Any] = [
        "Label": label,
        "ProgramArguments": programArguments
    ]
    return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
}

private func programArguments(of data: Data) throws -> [String] {
    let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
    let dict = obj as! [String: Any]
    return dict["ProgramArguments"] as! [String]
}

@Test func wrapPrependsWrapperPath() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let original = try plistData(label: "com.x.job", programArguments: ["/bin/bash", "/x/run.sh"])

    let wrapped = try w.wrap(original)

    #expect(try programArguments(of: wrapped) == ["/usr/local/bin/autotrigger-wrap", "/bin/bash", "/x/run.sh"])
}

@Test func wrapIsIdempotent() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let original = try plistData(label: "com.x.job", programArguments: ["/bin/bash", "/x/run.sh"])

    let once = try w.wrap(original)
    let twice = try w.wrap(once)

    #expect(try programArguments(of: twice) == ["/usr/local/bin/autotrigger-wrap", "/bin/bash", "/x/run.sh"])
}

@Test func isWrappedReflectsState() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let original = try plistData(label: "com.x.job", programArguments: ["/bin/bash", "/x/run.sh"])

    #expect(try w.isWrapped(original) == false)
    #expect(try w.isWrapped(w.wrap(original)) == true)
}

@Test func wrapThrowsWhenNoProgramArguments() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    // A plist with no ProgramArguments (e.g. uses Program key only) is unsupported in v1.
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["Label": "com.x.job"] as [String: Any], format: .xml, options: 0)

    #expect(throws: PlistWrapperError.missingProgramArguments) {
        try w.wrap(data)
    }
}
