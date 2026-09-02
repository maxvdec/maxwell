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
        ZStack {
            MetalView(
                renderer: renderer,
                editor: editor
            )
            .opacity(editor.visualizationMode == .field2D ? 1 : 0)
            .allowsHitTesting(editor.visualizationMode == .field2D)

            if editor.visualizationMode == .field2D {
                ColliderCanvasOverlay(
                    editor: editor,
                    renderer: renderer
                )
                .allowsHitTesting(
                    editor.currentTool == .pointer ||
                        editor.currentTool == .move ||
                        editor.currentTool.isColliderTool
                )
            }
            
            if editor.visualizationMode == .field3D {
                Ez3DVisualizationView(renderer: renderer)
                    .background(.background)
            }
        }
        .onKeyPress(.space) {
            settings.paused.toggle()
            return .handled
        }
        .onExitCommand {
            editor.currentTool = .pointer
        }
        .overlay {
            ZStack {
                VStack {
                    TopBar(
                        renderer: $renderer,
                        settings: $settings,
                        visualizationMode: Binding(
                            get: { editor.visualizationMode },
                            set: { editor.visualizationMode = $0 }
                        )
                    )

                    Spacer()
                }

                HStack {
                    Sidebar(
                        currentTool: Binding(
                            get: { editor.currentTool },
                            set: { editor.currentTool = $0 }
                        )
                    )

                    Spacer()
                }

                HStack {
                    Spacer()

                    Inspector(
                        settings: $settings,
                        renderer: $renderer,
                        editor: editor,
                        selection: Binding(
                            get: { editor.selection },
                            set: { editor.selection = $0 }
                        )
                    )
                }

                VStack {
                    Spacer()

                    BottomInspectorView(
                        settings: $settings,
                        renderer: $renderer,
                        selection: Binding(
                            get: { editor.selection },
                            set: { editor.selection = $0 }
                        )
                    )
                }
            }
            .padding()
        }
    }
}
