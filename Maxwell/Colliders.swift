import SwiftUI

struct NormalizedPoint: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    init(_ point: CGPoint, in size: CGSize) {
        self.init(
            x: size.width > 0 ? point.x / size.width : 0,
            y: size.height > 0 ? point.y / size.height : 0
        )
    }

    func point(in size: CGSize) -> CGPoint {
        CGPoint(
            x: x * size.width,
            y: y * size.height
        )
    }
}

struct NormalizedRect: Equatable, Hashable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(start: NormalizedPoint, end: NormalizedPoint) {
        minX = min(start.x, end.x)
        minY = min(start.y, end.y)
        maxX = max(start.x, end.x)
        maxY = max(start.y, end.y)
    }

    var width: Double {
        maxX - minX
    }

    var height: Double {
        maxY - minY
    }

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= minX &&
            point.x <= maxX &&
            point.y >= minY &&
            point.y <= maxY
    }
}

enum LensPreset: String, CaseIterable, Identifiable, Sendable {
    case biconvex
    case biconcave
    case planoConvex
    case planoConcave

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .biconvex:
            "Biconvex"
        case .biconcave:
            "Biconcave"
        case .planoConvex:
            "Plano-convex"
        case .planoConcave:
            "Plano-concave"
        }
    }

    var icon: String {
        switch self {
        case .biconvex:
            "capsule.portrait"
        case .biconcave:
            "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .planoConvex:
            "circle.lefthalf.filled"
        case .planoConcave:
            "circle.righthalf.filled"
        }
    }
}

enum ColliderCreationTool: Equatable, Sendable {
    case rectangle
    case circle
    case freehand
    case lens(LensPreset)

    var name: String {
        switch self {
        case .rectangle:
            "Rectangle Collider"
        case .circle:
            "Circle Collider"
        case .freehand:
            "Freehand Collider"
        case let .lens(preset):
            "\(preset.name) Lens"
        }
    }

    var icon: String {
        switch self {
        case .rectangle:
            "square"
        case .circle:
            "circle"
        case .freehand:
            "pencil.tip"
        case let .lens(preset):
            preset.icon
        }
    }
}

enum ColliderGeometry: Equatable, Sendable {
    case rectangle(NormalizedRect)
    case circle(NormalizedRect)
    case polygon([NormalizedPoint])
    case lens(NormalizedRect, LensPreset)

    var name: String {
        switch self {
        case .rectangle:
            "Rectangle"
        case .circle:
            "Circle"
        case .polygon:
            "Freehand Polygon"
        case let .lens(_, preset):
            "\(preset.name) Lens"
        }
    }

    var bounds: NormalizedRect {
        switch self {
        case let .rectangle(rect),
             let .circle(rect),
             let .lens(rect, _):
            return rect
        case let .polygon(points):
            let minX = points.map(\.x).min() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let maxY = points.map(\.y).max() ?? 0
            return NormalizedRect(
                start: NormalizedPoint(x: minX, y: minY),
                end: NormalizedPoint(x: maxX, y: maxY)
            )
        }
    }

    func translated(dx: Double, dy: Double) -> ColliderGeometry {
        let bounds = bounds
        let clampedX = min(max(dx, -bounds.minX), 1 - bounds.maxX)
        let clampedY = min(max(dy, -bounds.minY), 1 - bounds.maxY)

        func translatedPoint(_ point: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(
                x: point.x + clampedX,
                y: point.y + clampedY
            )
        }

        func translatedRect(_ rect: NormalizedRect) -> NormalizedRect {
            NormalizedRect(
                start: translatedPoint(
                    NormalizedPoint(x: rect.minX, y: rect.minY)
                ),
                end: translatedPoint(
                    NormalizedPoint(x: rect.maxX, y: rect.maxY)
                )
            )
        }

        switch self {
        case let .rectangle(rect):
            return .rectangle(translatedRect(rect))
        case let .circle(rect):
            return .circle(translatedRect(rect))
        case let .polygon(points):
            return .polygon(points.map(translatedPoint))
        case let .lens(rect, preset):
            return .lens(translatedRect(rect), preset)
        }
    }

    func contains(_ point: NormalizedPoint) -> Bool {
        switch self {
        case let .rectangle(rect):
            return rect.contains(point)

        case let .circle(rect):
            guard rect.width > 0,
                  rect.height > 0
            else {
                return false
            }

            let x = (point.x - (rect.minX + rect.maxX) * 0.5) / (rect.width * 0.5)
            let y = (point.y - (rect.minY + rect.maxY) * 0.5) / (rect.height * 0.5)
            return x * x + y * y <= 1

        case let .polygon(points):
            guard points.count >= 3 else {
                return false
            }

            var inside = false
            var previous = points.count - 1

            for current in points.indices {
                let a = points[current]
                let b = points[previous]
                let crosses =
                    (a.y > point.y) != (b.y > point.y) &&
                    point.x <
                    (b.x - a.x) * (point.y - a.y) /
                    (b.y - a.y) + a.x

                if crosses {
                    inside.toggle()
                }

                previous = current
            }

            return inside

        case let .lens(rect, preset):
            guard rect.contains(point),
                  rect.width > 0,
                  rect.height > 0
            else {
                return false
            }

            let x = (point.x - rect.minX) / rect.width
            let y = (point.y - rect.minY) / rect.height
            let profile = sin(.pi * y)

            switch preset {
            case .biconvex:
                let halfWidth = 0.08 + 0.42 * profile
                return abs(x - 0.5) <= halfWidth
            case .biconcave:
                return x >= 0.22 * profile && x <= 1 - 0.22 * profile
            case .planoConvex:
                return x >= 0.12 && x <= 0.12 + 0.88 * profile
            case .planoConcave:
                return x >= 0 && x <= 1 - 0.3 * profile
            }
        }
    }
}

struct FieldCollider: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var geometry: ColliderGeometry
    var materialIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        geometry: ColliderGeometry,
        materialIndex: Int
    ) {
        self.id = id
        self.name = name
        self.geometry = geometry
        self.materialIndex = materialIndex
    }
}

struct ColliderCanvasOverlay: View {
    let editor: EditorState
    let renderer: Renderer

    @State private var dragStart: NormalizedPoint?
    @State private var freehandPoints: [NormalizedPoint] = []
    @State private var draftGeometry: ColliderGeometry?
    @State private var moveTarget: MoveTarget?

    private enum MoveTarget {
        case collider(FieldCollider)
        case source(index: Int, start: SIMD2<UInt32>)
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for collider in editor.colliders {
                    draw(
                        collider.geometry,
                        selected: editor.selection == .collider(collider.id),
                        hovered: editor.hoveredCollider == collider.id,
                        draft: false,
                        context: &context,
                        size: size
                    )
                }

                if let draftGeometry {
                    draw(
                        draftGeometry,
                        selected: false,
                        hovered: false,
                        draft: true,
                        context: &context,
                        size: size
                    )
                }
            }

            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
                .onContinuousHover { phase in
                    handleHover(phase, size: geometry.size)
                }
                .cursor(cursor)
        }
        .onChange(of: editor.currentTool) {
            cancelDraft()
            moveTarget = nil
        }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value, size: size)
            }
            .onEnded { value in
                handleDragEnded(value, size: size)
            }
    }

    private func handleDragChanged(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        if editor.currentTool == .move {
            handleMoveChanged(value, size: size)
            return
        }

        guard case let .placeCollider(tool) = editor.currentTool else {
            if dragStart == nil {
                select(at: value.startLocation, size: size)
                dragStart = NormalizedPoint(value.startLocation, in: size)
            }
            return
        }

        let start = dragStart ?? NormalizedPoint(value.startLocation, in: size)
        let current = NormalizedPoint(value.location, in: size)
        dragStart = start

        switch tool {
        case .rectangle:
            draftGeometry = .rectangle(
                NormalizedRect(start: start, end: current)
            )
        case .circle:
            draftGeometry = .circle(
                NormalizedRect(start: start, end: current)
            )
        case .freehand:
            if freehandPoints.isEmpty {
                freehandPoints = [start]
            }

            if let last = freehandPoints.last {
                let dx = (last.x - current.x) * size.width
                let dy = (last.y - current.y) * size.height

                if hypot(dx, dy) >= 3 {
                    freehandPoints.append(current)
                }
            }

            draftGeometry = .polygon(freehandPoints)
        case let .lens(preset):
            draftGeometry = .lens(
                NormalizedRect(start: start, end: current),
                preset
            )
        }
    }

    private func handleDragEnded(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        defer {
            cancelDraft()
            moveTarget = nil
        }

        if editor.currentTool == .move {
            if case .collider = moveTarget {
                editor.commitColliderMove()
            }
            return
        }

        guard case let .placeCollider(tool) = editor.currentTool,
              let geometry = draftGeometry,
              isValid(geometry, in: size)
        else {
            return
        }

        let count = editor.colliders.filter {
            $0.geometry.name == geometry.name
        }.count + 1

        let materialIndex = min(3, max(0, renderer.materialCount - 1))
        let collider = FieldCollider(
            name: "\(tool.name) \(count)",
            geometry: geometry,
            materialIndex: materialIndex
        )

        editor.addCollider(collider)
        editor.selection = .collider(collider.id)
    }

    private func isValid(
        _ geometry: ColliderGeometry,
        in size: CGSize
    ) -> Bool {
        switch geometry {
        case let .rectangle(rect),
             let .circle(rect),
             let .lens(rect, _):
            return rect.width * size.width >= 6 &&
                rect.height * size.height >= 6
        case let .polygon(points):
            return points.count >= 3
        }
    }

    private func select(at point: CGPoint, size: CGSize) {
        let normalized = NormalizedPoint(point, in: size)

        if let collider = editor.colliders.last(where: {
            $0.geometry.contains(normalized)
        }) {
            editor.selection = .collider(collider.id)
            return
        }

        if let source = renderer.hitTestSource(
            at: point,
            viewSize: size
        ) {
            editor.selection = .source(source)
        } else {
            editor.selection = .none
        }
    }

    private func handleHover(
        _ phase: HoverPhase,
        size: CGSize
    ) {
        guard editor.currentTool == .pointer ||
                editor.currentTool == .move
        else {
            editor.hoveredCollider = nil
            editor.hoveredSource = nil
            return
        }

        switch phase {
        case let .active(location):
            let normalized = NormalizedPoint(location, in: size)
            editor.hoveredCollider = editor.colliders.last(where: {
                $0.geometry.contains(normalized)
            })?.id

            if editor.hoveredCollider == nil {
                editor.hoveredSource = renderer.hitTestSource(
                    at: location,
                    viewSize: size
                )
            } else {
                editor.hoveredSource = nil
            }
        case .ended:
            editor.hoveredCollider = nil
            editor.hoveredSource = nil
        }
    }

    private func cancelDraft() {
        dragStart = nil
        freehandPoints = []
        draftGeometry = nil
    }

    private func handleMoveChanged(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        let start = NormalizedPoint(value.startLocation, in: size)
        let current = NormalizedPoint(value.location, in: size)

        if moveTarget == nil {
            if let collider = editor.colliders.last(where: {
                $0.geometry.contains(start)
            }) {
                moveTarget = .collider(collider)
                editor.selection = .collider(collider.id)
            } else if let sourceIndex = renderer.hitTestSource(
                at: value.startLocation,
                viewSize: size
            ), let source = renderer.getSource(i: sourceIndex) {
                moveTarget = .source(
                    index: sourceIndex,
                    start: SIMD2(source.x, source.y)
                )
                editor.selection = .source(sourceIndex)
            } else {
                editor.selection = .none
            }
        }

        switch moveTarget {
        case var .collider(collider):
            collider.geometry = collider.geometry.translated(
                dx: current.x - start.x,
                dy: current.y - start.y
            )
            editor.previewColliderMove(collider)

        case let .source(index, sourceStart):
            guard var source = renderer.getSource(i: index) else {
                return
            }

            let viewport = GridViewport(
                nx: renderer.settings.Nx,
                ny: renderer.settings.Ny,
                viewSize: size
            )

            guard let startGrid = viewport.gridPosition(
                from: value.startLocation
            ), let currentGrid = viewport.gridPosition(
                from: value.location
            ) else {
                return
            }

            let x = Int(sourceStart.x) +
                Int(currentGrid.x) - Int(startGrid.x)
            let y = Int(sourceStart.y) +
                Int(currentGrid.y) - Int(startGrid.y)

            source.x = UInt32(
                clamping: min(max(x, 0), renderer.settings.Nx - 1)
            )
            source.y = UInt32(
                clamping: min(max(y, 0), renderer.settings.Ny - 1)
            )
            renderer.updateSource(i: index, source: source)

        case nil:
            return
        }
    }

    private var cursor: NSCursor {
        if editor.currentTool.isColliderTool {
            return .crosshair
        }

        if editor.currentTool == .move {
            return moveTarget == nil ? .openHand : .closedHand
        }

        return .arrow
    }

    private func draw(
        _ geometry: ColliderGeometry,
        selected: Bool,
        hovered: Bool,
        draft: Bool,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let path = colliderPath(geometry, in: size)
        let fillOpacity = draft ? 0.2 : selected ? 0.38 : hovered ? 0.34 : 0.29

        context.fill(
            path,
            with: .color(.black.opacity(fillOpacity))
        )

        if selected || hovered {
            context.stroke(
                path,
                with: .color(.cyan.opacity(selected ? 0.65 : 0.35)),
                style: StrokeStyle(lineWidth: selected ? 7 : 5)
            )
        }

        context.stroke(
            path,
            with: .color(.white.opacity(draft ? 0.7 : 0.95)),
            style: StrokeStyle(
                lineWidth: selected ? 3 : 2,
                dash: draft ? [7, 5] : []
            )
        )
    }
}

func colliderPath(
    _ geometry: ColliderGeometry,
    in size: CGSize
) -> Path {
    switch geometry {
    case let .rectangle(rect):
        return Path(
            roundedRect: rect.rect(in: size),
            cornerRadius: 4
        )

    case let .circle(rect):
        return Path(ellipseIn: rect.rect(in: size))

    case let .polygon(points):
        var path = Path()

        guard let first = points.first else {
            return path
        }

        path.move(to: first.point(in: size))

        for point in points.dropFirst() {
            path.addLine(to: point.point(in: size))
        }

        path.closeSubpath()
        return path

    case let .lens(rect, preset):
        return lensPath(
            rect: rect.rect(in: size),
            preset: preset
        )
    }
}

private func lensPath(
    rect: CGRect,
    preset: LensPreset
) -> Path {
    var path = Path()
    let top = rect.minY
    let bottom = rect.maxY
    let middleY = rect.midY
    let left = rect.minX
    let right = rect.maxX

    switch preset {
    case .biconvex:
        path.move(to: CGPoint(x: rect.midX, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: bottom),
            control: CGPoint(x: right, y: middleY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: top),
            control: CGPoint(x: left, y: middleY)
        )
    case .biconcave:
        path.move(to: CGPoint(x: left, y: top))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom),
            control: CGPoint(x: rect.minX + rect.width * 0.28, y: middleY)
        )
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top),
            control: CGPoint(x: rect.maxX - rect.width * 0.28, y: middleY)
        )
    case .planoConvex:
        let plane = rect.minX + rect.width * 0.12
        path.move(to: CGPoint(x: plane, y: top))
        path.addQuadCurve(
            to: CGPoint(x: plane, y: bottom),
            control: CGPoint(x: right, y: middleY)
        )
        path.addLine(to: CGPoint(x: plane, y: top))
    case .planoConcave:
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top),
            control: CGPoint(x: rect.maxX - rect.width * 0.38, y: middleY)
        )
    }

    path.closeSubpath()
    return path
}
