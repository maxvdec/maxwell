//
//  Interaction.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 01/09/2026.
//

import AppKit
import MetalKit
import Observation
import SwiftUI

enum Tool: Equatable {
    case pointer
    case placePoint
    case placeLine
    case placeBeam

    var sourceType: SourceType? {
        switch self {
        case .pointer:
            nil
        case .placePoint:
            .point
        case .placeLine:
            .line
        case .placeBeam:
            .beam
        }
    }

    var isPlacementTool: Bool {
        sourceType != nil
    }
}

@Observable
final class EditorState {
    var currentTool: Tool = .pointer
    var hoveredGridPosition: SIMD2<UInt32>?

    var hoveredSource: Int?

    var selection: InspectorSelection = .none
    var visualizationMode: VisualizationMode = .field2D
}


enum VisualizationMode: CaseIterable {
    case field2D
    case field3D

    var name: String {
        switch self {
        case .field2D:
            "2D Field"
        case .field3D:
            "3D Graph"
        }
    }

    var icon: String {
        switch self {
        case .field2D:
            "square.grid.2x2"
        case .field3D:
            "graph.3d"
        }
    }
    
    var color: Color {
        switch self {
        case .field2D:
                .red.opacity(0.7)
        case .field3D:
                .blue.opacity(0.7)
        }
    }
}
final class MaxwellMTKView: MTKView {

    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    var onLeftMouseDown: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?
    
    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach(removeTrackingArea)

        let tracking = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseMoved,
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect
            ],
            owner: self
        )

        addTrackingArea(tracking)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        onLeftMouseDown?(point)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            // Escape
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
