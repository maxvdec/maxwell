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

    var body: some View {
        HStack(spacing: 4) {
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
            .help("Pause or play the simulation")
            .buttonStyle(.plain)
            .focusable(false)
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
            .cursor(.pointingHand)
            .help("Pause or play the simulation")
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .foregroundStyle(.background)
                .glassEffect()
        }
    }
}

#Preview {
    TopBar(renderer: .constant(.init(settings: .init())), settings: .constant(.init()))
        .preferredColorScheme(.dark)
}
