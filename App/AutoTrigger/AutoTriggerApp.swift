import SwiftUI

@main
struct AutoTriggerApp: App {
    var body: some Scene {
        MenuBarExtra("AutoTrigger", systemImage: "bolt.horizontal.circle") {
            Text("AutoTrigger")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
