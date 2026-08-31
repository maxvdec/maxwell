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
        }
        .defaultSize(
            width: windowWidth,
            height: windowHeight
        )
    }
}

struct ParametersView: View {
    @Binding var settings: SimulationSettings
    @Binding var renderer: Renderer
    
    var body: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 16)
                .frame(maxWidth: 300, maxHeight: .infinity)
                .foregroundStyle(.white)
                .overlay {
                    HStack {
                        parameterList
                            .padding()
                        Spacer()
                    }
                }
                .padding()
        }.padding()
    }
    
    var parameterList: some View {
        ScrollView {
            VStack {
                Text("Parameters")
                    .font(.largeTitle)
                    .bold()
                
                IntField("Nx", value: $settings.Nx, unit: "")
                IntField("Ny", value: $settings.Ny, unit: "")
                
                FloatField("Width", value: $settings.width, unit: "m")
                FloatField("Height", value: $settings.height, unit: "m")
                
                IntField("Steps per frame", value: $settings.stepsPerFrame, unit: "")
                
                Toggle(isOn: $settings.reflectWalls) {
                    Text("Walls Reflect")
                }
                
                Divider()
                
                FloatField("Source Frequency", value: $settings.sourceFrequency, unit: "GHz")
                Button {
                    calculateFrequency(cellsPerWavelength: 20, settings: &settings)
                } label: {
                    Text("Calculate frequency")
                }
                
                Divider()
                
                FloatField("Visualization Scale", value: $settings.visualizationScale, unit: "")
                
                Spacer()
                
                HStack {
                    Button {
                        settings.paused.toggle()
                    } label: {
                        if settings.paused {
                            Image(systemName: "play")
                        } else {
                            Image(systemName: "pause")
                        }
                    }
                    Button {
                        renderer.resetSimulation()
                    } label: {
                        Image(systemName: "arrow.trianglehead.counterclockwise")
                    }
                }
            }
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
        }.overlay {
            ParametersView(settings: $settings, renderer: $renderer)
        }
    }
}
