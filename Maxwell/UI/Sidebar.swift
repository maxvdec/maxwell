//
//  Sidebar.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 31/08/2026.
//

import SwiftUI

struct Sidebar: View {
    @Binding var currentTool: Tool

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                makeToolbarButton(
                    tool: .pointer,
                    image: "pointer.arrow",
                    name: "Select",
                    overrwriteWidth: 15
                )

                makeToolbarButton(
                    tool: .placePoint,
                    image: "target",
                    name: "Place a point source"
                )

                makeToolbarButton(
                    tool: .placeLine,
                    image: "line.diagonal.trianglehead.up.right",
                    name: "Place a line source"
                )

                makeToolbarButton(
                    tool: .placeBeam,
                    image: "angle",
                    name: "Place a beam source"
                )
            }
            .toolbarPalette()

            VStack(spacing: 4) {
                makeToolbarButton(
                    tool: .placeCollider(.rectangle),
                    image: "square",
                    name: "Draw a rectangular collider"
                )

                makeToolbarButton(
                    tool: .placeCollider(.circle),
                    image: "circle",
                    name: "Draw a circular collider"
                )

                makeToolbarButton(
                    tool: .placeCollider(.freehand),
                    image: "pencil.tip",
                    name: "Draw a freehand collider"
                )

                Menu {
                    ForEach(LensPreset.allCases) { preset in
                        Button {
                            withAnimation(.linear.speed(3)) {
                                currentTool = .placeCollider(.lens(preset))
                            }
                        } label: {
                            Label(preset.name, systemImage: preset.icon)
                        }
                    }
                } label: {
                    if let selectedLens {
                        Circle()
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: selectedLens.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 23, height: 23)
                                    .foregroundStyle(.background)
                            }
                    } else {
                        Image(systemName: "camera.aperture")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 23, height: 23)
                            .frame(width: 40, height: 40)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .focusable(false)
                .cursor(.pointingHand)
                .help("Choose a lens collider")
            }
            .toolbarPalette()
        }
    }

    func makeToolbarButton(
        tool: Tool,
        image: String,
        name: String,
        overrwriteWidth: CGFloat? = nil
    ) -> some View {
        Button {
            withAnimation(.linear.speed(3.0)) {
                currentTool = tool
            }
        } label: {
            if currentTool == tool {
                Circle()
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: overrwriteWidth ?? 25,
                                height: 25
                            )
                            .foregroundStyle(.background)
                    }
            } else {
                Image(systemName: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: overrwriteWidth ?? 25,
                        height: 25
                    )
                    .frame(width: 40, height: 40)
            }
        }
        .cursor(.pointingHand)
        .help(name)
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var selectedLens: LensPreset? {
        guard case let .placeCollider(.lens(preset)) = currentTool else {
            return nil
        }

        return preset
    }
}

private extension View {
    func toolbarPalette() -> some View {
        padding(.vertical, 10)
            .frame(width: 50)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .foregroundStyle(.background)
                    .glassEffect()
            }
    }
}

#Preview {
    Sidebar(currentTool: .constant(.placeBeam))
        .preferredColorScheme(.dark)
}
