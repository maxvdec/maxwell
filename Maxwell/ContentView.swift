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
    }
}

struct ContentView: View {
    @State private var renderer: Renderer
    @State private var settings: SimulationSettings
    @State private var editor: EditorState

    init() {
        let settings = SimulationSettings()
        let editor = EditorState()

        self._settings =
            State(initialValue: settings)

        self._editor =
            State(initialValue: editor)

        self._renderer =
            State(
                initialValue: Renderer(
                    settings: settings
                )
            )
    }

    var body: some View {
        VStack {
            MetalView(
                renderer: renderer,
                editor: editor
            )
        }
        .onKeyPress(.space) {
            settings.paused.toggle()
            return .handled
        }
        .overlay {
            VStack {
                TopBar(
                    renderer: $renderer,
                    settings: $settings
                )

                Spacer()

                HStack {
                    Sidebar(
                        currentTool: Binding(
                            get: {
                                editor.currentTool
                            },
                            set: {
                                editor.currentTool = $0
                            }
                        )
                    )

                    Spacer()

                    Inspector(
                        settings: $settings,
                        renderer: $renderer,
                        selection: Binding(
                            get: {
                                editor.selection
                            },
                            set: {
                                editor.selection = $0
                            }
                        )
                    )
                }

                Spacer()
            }
            .padding()
        }
    }
}
