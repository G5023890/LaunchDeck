import SwiftUI

@main
struct LaunchDeckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1320, height: 860)
    }
}
