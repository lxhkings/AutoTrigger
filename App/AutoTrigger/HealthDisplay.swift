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
        case .ok:       return "正常"
        case .neverRan: return "未运行"
        case .overdue:  return "逾期"
        case .failed:   return "失败"
        }
    }
}
