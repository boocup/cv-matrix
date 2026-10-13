import SwiftUI

@main
struct CVMatrixApp: App {
    @State private var store = MatrixStore()

    var body: some Scene {
        WindowGroup("CV Matrix") {
            ContentView(store: store)
        }
    }
}
