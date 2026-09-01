import Playgrounds
import SwiftUI

struct WindowSizeReader: NSViewRepresentable {
    let onChange: (CGSize) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }

            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                onChange(window.frame.size)
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct MyApp: App {
    @AppStorage("windowWidth") private var windowWidth = 1200.0
    @AppStorage("windowHeight") private var windowHeight = 800.0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background {
                    WindowSizeReader { size in
                        windowWidth = size.width
                        windowHeight = size.height
                    }
                }
                .preferredColorScheme(.dark)
        }
        .defaultSize(
            width: windowWidth,
            height: windowHeight
        )
    }
}

struct ContentView: View {
    @State private var renderer: Renderer
    @State private var settings: SimulationSettings
    @State private var selection: InspectorSelection = .source(0)
    @State private var currentTool: Tool = .pointer
    
    init() {
        let settings = SimulationSettings()
        
        self._renderer = State(initialValue: Renderer(settings: settings))
        self._settings = State(initialValue: settings)
    }
    
    var body: some View {
        VStack {
            MetalView(renderer: renderer)
        }.overlay {
            VStack {
                TopBar(renderer: $renderer, settings: $settings)
                Spacer()
                HStack {
                    Sidebar(currentTool: $currentTool)
                    Spacer()
                    Inspector(settings: $settings, renderer: $renderer, selection: $selection)
                }
                Spacer()
            }.padding()
        }
    }
}
