//
//  Sidebar.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 31/08/2026.
//

import SwiftUI

enum Tool {
    case pointer
    case placePoint
    case placeLine
    case placeBeam
}

struct Sidebar: View {
    @Binding var currentTool: Tool
    var body: some View {
        VStack(spacing: 4) {
            makeToolbarButton(tool: .pointer, image: "pointer.arrow", name: "Select", overrwriteWidth: 15)
            makeToolbarButton(tool: .placePoint, image: "target", name: "Place a point source", )
            makeToolbarButton(tool: .placeLine, image: "line.diagonal.trianglehead.up.right", name: "Place a line source")
            makeToolbarButton(tool: .placeBeam, image: "angle", name: "Place a beam source")
        }
        .padding(.vertical, 10)
        .frame(width: 50)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .foregroundStyle(.background)
                .glassEffect()
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
}

#Preview {
    Sidebar(currentTool: .constant(.placeBeam))
        .preferredColorScheme(.dark)
}
