import SwiftUI

@main
struct FastCardCopierApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
