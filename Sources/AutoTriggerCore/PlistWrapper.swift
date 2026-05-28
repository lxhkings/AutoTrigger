import Foundation

public enum PlistWrapperError: Error, Equatable {
    case missingProgramArguments
    case notADictionary
}

/// Wraps a launchd plist's `ProgramArguments` by prepending the wrapper
/// executable path, so launchd runs `wrapper <original args...>`.
/// `wrapperPath` doubles as the "is this ours?" marker.
public struct PlistWrapper {
    public let wrapperPath: String

    public init(wrapperPath: String) {
        self.wrapperPath = wrapperPath
    }

    public func isWrapped(_ data: Data) throws -> Bool {
        let args = try programArguments(from: try dictionary(from: data))
        return args.first == wrapperPath
    }

    public func wrap(_ data: Data) throws -> Data {
        var dict = try dictionary(from: data)
        var args = try programArguments(from: dict)
        if args.first == wrapperPath { return data } // idempotent
        args.insert(wrapperPath, at: 0)
        dict["ProgramArguments"] = args
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func dictionary(from data: Data) throws -> [String: Any] {
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = obj as? [String: Any] else { throw PlistWrapperError.notADictionary }
        return dict
    }

    private func programArguments(from dict: [String: Any]) throws -> [String] {
        guard let args = dict["ProgramArguments"] as? [String], !args.isEmpty else {
            throw PlistWrapperError.missingProgramArguments
        }
        return args
    }
}
