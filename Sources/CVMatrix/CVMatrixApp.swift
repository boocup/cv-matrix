import SwiftUI

@main
struct CVMatrixApp: App {
    @State private var store: MatrixStore
    @State private var player: Player

    init() {
        let s = MatrixStore()
        _store = State(initialValue: s)
        _player = State(initialValue: Player(store: s))
    }

    var body: some Scene {
        WindowGroup("CV Matrix") {
            ContentView(store: store, player: player)
        }
    }
}
