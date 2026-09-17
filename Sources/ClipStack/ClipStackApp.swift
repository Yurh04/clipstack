import SwiftUI

@main
struct ClipStackApp: App {
    var body: some Scene {
        MenuBarExtra("ClipStack", systemImage: "doc.on.clipboard") {
            Button("关于 ClipStack") {
                print("ClipStack v0.1.0")
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
