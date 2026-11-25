import SwiftUI

@main
struct BooksApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
