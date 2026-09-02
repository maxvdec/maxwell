//
//  TopBar.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 01/09/2026.
//

import SwiftUI

struct TopBar: View {
    @Binding var renderer: Renderer
    @Binding var settings: SimulationSettings
    @Binding var visualizationMode: VisualizationMode

    var body: some View {
        HStack(spacing: 4) {
            Button {
                renderer.resetSimulation()
            } label: {
                Image(systemName: "arrow.trianglehead.counterclockwise")
                    .resizable()
                    .bold()
                    .scaledToFit()
                    .frame(
                        width: 25,
                        height: 25
                    )
                    .frame(width: 40, height: 40)
            }
            .keyboardShortcut(.init(.leftArrow, modifiers: .command))
            .cursor(.pointingHand)
            .help("Reset the simulation (Cmd + Left)")
            .buttonStyle(.plain)
            .focusable(false)
            Button {
                settings.paused.toggle()
            } label: {
                if settings.paused {
                    Image(systemName: "play.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: 25,
                            height: 25
                        )
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "pause.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: 25,
                            height: 25
                        )
                        .frame(width: 40, height: 40)
                }
            }
           
            .cursor(.pointingHand)
            .help("Pause or play the simulation (Space)")
            .buttonStyle(.plain)
            .focusable(false)
            
            Button {
                renderer.stepOneFrame()
            } label: {
                Image(systemName: "arrow.right")
                    .resizable()
                    .bold()
                    .scaledToFit()
                    .frame(
                        width: 25,
                        height: 25
                    )
                    .frame(width: 40, height: 40)
            }
            .keyboardShortcut(.init(.rightArrow, modifiers: .command))
            .cursor(.pointingHand)
            .help("Step one frame (Cmd + Right)")
            .buttonStyle(.plain)
            .focusable(false)
            
            Menu {
                ForEach(VisualizationMode.allCases, id: \.self) { mode in
                    Button {
                        visualizationMode = mode
                    } label: {
                        Label(mode.name, systemImage: mode.icon)
                            .font(.system(size: 25))
                            .frame(width: 25, height: 25)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: visualizationMode.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .frame(width: 40, height: 40)
                    Text(visualizationMode.name)
                        .font(.headline)
                        .foregroundStyle(visualizationMode.color)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .focusable(false)
            .help("Switch Visualization Mode")
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .foregroundStyle(.background)
                .glassEffect()
        }
        .onKeyPress(.space) {
            settings.paused.toggle()
            return .handled
        }
    }
}

#Preview {
    TopBar(renderer: .constant(.init(settings: .init())), settings: .constant(.init()), visualizationMode: .constant(.field2D))
        .preferredColorScheme(.dark)
}
