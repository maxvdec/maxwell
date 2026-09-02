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
    case move
    case placePoint
    case placeLine
    case placeBeam
    case placeCollider(ColliderCreationTool)

    var sourceType: SourceType? {
        switch self {
        case .pointer, .move, .placeCollider:
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

    var isColliderTool: Bool {
        if case .placeCollider = self {
            return true
        }

        return false
    }
}

@Observable
final class EditorState {
    var currentTool: Tool = .pointer
    var hoveredGridPosition: SIMD2<UInt32>?

    var hoveredSource: Int?
    var hoveredCollider: UUID?

    var selection: InspectorSelection = .none
    var visualizationMode: VisualizationMode = .field2D

    var colliders: [FieldCollider] = []
    var colliderRevision = 0

    func addCollider(_ collider: FieldCollider) {
        colliders.append(collider)
        colliderRevision += 1
    }

    func updateCollider(_ collider: FieldCollider) {
        guard let index = colliders.firstIndex(where: {
            $0.id == collider.id
        }) else {
            return
        }

        colliders[index] = collider
        colliderRevision += 1
    }

    func previewColliderMove(_ collider: FieldCollider) {
        guard let index = colliders.firstIndex(where: {
            $0.id == collider.id
        }) else {
            return
        }

        colliders[index] = collider
    }

    func commitColliderMove() {
        colliderRevision += 1
    }

    func removeCollider(id: UUID) {
        colliders.removeAll { $0.id == id }
        colliderRevision += 1
    }

    func collider(id: UUID) -> FieldCollider? {
        colliders.first { $0.id == id }
    }

    func removeMaterialReferences(at index: Int) {
        for colliderIndex in colliders.indices {
            if colliders[colliderIndex].materialIndex == index {
                colliders[colliderIndex].materialIndex = 0
            } else if colliders[colliderIndex].materialIndex > index {
                colliders[colliderIndex].materialIndex -= 1
            }
        }

        colliderRevision += 1
    }
}


enum VisualizationMode: Int32, CaseIterable {
    case field2D = 0
    case energyGlow = 4
    case field3D = -1
    case electricMagnitude = 1
    case magneticMagnitude = 2
    case electricDensity = 3

    var name: String {
        switch self {
        case .field2D:
            "2D Field"
        case .energyGlow:
            "Energy Glow"
        case .field3D:
            "3D Graph"
        case .electricMagnitude:
            "Electric Magnitude"
        case .magneticMagnitude:
            "Magnetic Magnitude"
        case .electricDensity:
            "Electric Energy Density"
        }
    }

    var icon: String {
        switch self {
        case .field2D:
            "square.grid.2x2"
        case .energyGlow:
            "sparkles"
        case .field3D:
            "graph.3d"
        case .electricMagnitude:
            "bolt.fill"
        case .magneticMagnitude:
            "wave.3.left"
        case .electricDensity:
            "graph.2d"
        }
    }
    
    var color: Color {
        switch self {
        case .field2D:
                .red.opacity(0.7)
        case .energyGlow:
                .white.opacity(0.9)
        case .field3D:
                .blue.opacity(0.7)
        case .electricMagnitude:
                .yellow.opacity(0.7)
        case .magneticMagnitude:
                .green.opacity(0.7)
        case .electricDensity:
                .orange.opacity(0.7)
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
