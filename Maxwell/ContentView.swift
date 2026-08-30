import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var renderer: Renderer
    @State private var settings: SimulationSettings
    
    init() {
        let settings = SimulationSettings()
        
        self._renderer = State(initialValue: Renderer(settings: settings))
        self._settings = State(initialValue: settings)
    }
    
    var body: some View {
        VStack {
            MetalView(renderer: renderer)
        }
    }
}
