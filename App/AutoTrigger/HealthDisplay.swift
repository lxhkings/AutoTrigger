import SwiftUI
import AutoTriggerCore

extension TaskHealth {
    var symbolName: String {
        switch self {
        case .ok:       return "checkmark.circle.fill"
        case .neverRan: return "clock"
        case .overdue:  return "exclamationmark.triangle.fill"
        case .failed:   return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok:       return .green
        case .neverRan: return .gray
        case .overdue:  return .yellow
        case .failed:   return .red
        }
    }

    var label: String {
        switch self {
        case .ok:       return "OK"
        case .neverRan: return "Never ran"
        case .overdue:  return "Overdue"
        case .failed:   return "Failed"
        }
    }
}
