//
//  Renderer.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

import Combine
import Foundation
import Metal
import MetalKit
import Observation
import QuartzCore
import simd
import SwiftUI

@Observable
final class SimulationSettings {
    var paused = true

    var Nx = 500
    var Ny = 500
    var pmlThickness: Int = 40

    var width: Float = 2.0
    var height: Float = 2.0

    var sourceFrequency: Float = 1.0 // In GHz
    var cellsPerWavelength: Float = 20.0

    var visualizationScale: Float = 15.0

    var reflectWalls: Bool = false
    var stepsPerFrame: Int = 3

    var blurAmount: Float = 7.0
}

struct MetalView: NSViewRepresentable {
    let renderer: Renderer
    let editor: EditorState

    func makeNSView(
        context: Context
    ) -> MaxwellMTKView {
        let view = MaxwellMTKView()

        view.device = renderer.device
        view.delegate = renderer

        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )

        view.sampleCount = 4

        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.isPaused = false

        renderer.editor = editor

        configureInteraction(view)

        return view
    }

    func updateNSView(
        _ view: MaxwellMTKView,
        context: Context
    ) {
        renderer.editor = editor

        configureInteraction(view)
    }

    private func configureInteraction(
        _ view: MaxwellMTKView
    ) {
        view.onMouseMoved = { [weak view] point in
            guard let view else {
                return
            }

            handleMouseMoved(
                point,
                view: view
            )
        }

        view.onMouseExited = {
            editor.hoveredGridPosition = nil
            editor.hoveredSource = nil
        }

        view.onLeftMouseDown = { [weak view] point in
            guard let view else {
                return
            }

            handleLeftClick(
                point,
                view: view
            )
        }

        view.onEscape = {
            editor.currentTool = .pointer
            editor.hoveredGridPosition = nil
        }
    }

    private func handleMouseMoved(
        _ point: CGPoint,
        view: MaxwellMTKView
    ) {
        let viewport = GridViewport(
            nx: renderer.settings.Nx,
            ny: renderer.settings.Ny,
            viewSize: view.bounds.size
        )

        editor.hoveredGridPosition =
            viewport.gridPosition(
                from: point
            )

        if editor.currentTool == .pointer {
            editor.hoveredSource =
                renderer.hitTestSource(
                    at: point,
                    viewSize: view.bounds.size
                )
        } else {
            editor.hoveredSource = nil
        }
    }

    private func handleLeftClick(
        _ point: CGPoint,
        view: MaxwellMTKView
    ) {
        let viewport = GridViewport(
            nx: renderer.settings.Nx,
            ny: renderer.settings.Ny,
            viewSize: view.bounds.size
        )

        guard let gridPosition =
            viewport.gridPosition(
                from: point
            )
        else {
            return
        }

        switch editor.currentTool {
        case .pointer:
            let result =
                renderer.hitTestSource(
                    at: point,
                    viewSize: view.bounds.size
                )

            if let sourceIndex = result {
                editor.selection =
                    .source(sourceIndex)
            } else {
                editor.selection =
                    .none
            }

        case .placePoint:
            placeSource(
                type: .point,
                at: gridPosition
            )

        case .placeLine:
            placeSource(
                type: .line,
                at: gridPosition
            )

        case .placeBeam:
            placeSource(
                type: .beam,
                at: gridPosition
            )
        }
    }

    private func placeSource(
        type: SourceType,
        at position: SIMD2<UInt32>
    ) {
        var source = ElectricSource()

        source.x = position.x
        source.y = position.y

        source.type = type.rawValue
        source.form = SourceForm.sine.rawValue

        source.frequency =
            calculateFrequency(
                cellsPerWavelength:
                renderer.settings.cellsPerWavelength,
                settings:
                renderer.settings
            )

        source.amplitude = 1.0
        source.phase = 0.0

        let index =
            renderer.addSource(
                source,
                name: renderer.makeNameForSource(
                    type: type
                )
            )

        editor.selection =
            .source(index)
    }
}

class EzRenderPass: ComputePass {
    let pipeline: MTLComputePipelineState
    var texturePass: Reference<TextureRenderPass>
    var cells: Reference<MTLSyncBuffer<GridCell>>

    init(device: MTLDevice, library: MTLLibrary, texturePass: Reference<TextureRenderPass>, cells: Reference<MTLSyncBuffer<GridCell>>) {
        self.texturePass = texturePass
        let function = library.makeFunction(name: "renderEz")!
        self.pipeline = try! device.makeComputePipelineState(function: function)
        self.cells = cells
    }

    func encodeCompute(_ commandBuffer: any MTLCommandBuffer, uniforms: inout Uniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        encoder.label = "Render Ez"

        encoder.setComputePipelineState(pipeline)

        let texture = texturePass.unwrap().texture

        encoder.setTexture(texture, index: 0)

        cells.unwrap().setAtEncoder(encoder, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        let width = pipeline.threadExecutionWidth

        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)

        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)

        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()
    }
}

class EzUpdatePass: ComputePass {
    let pipeline: MTLComputePipelineState
    var cells: Reference<MTLSyncBuffer<GridCell>>
    var sources: Reference<[ElectricSource]>

    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>, sources: Reference<[ElectricSource]>) {
        self.cells = cells
        self.sources = sources
        let function = library.makeFunction(name: "updateEz")!
        self.pipeline = try! device.makeComputePipelineState(function: function)
    }

    func encodeCompute(_ commandBuffer: any MTLCommandBuffer, uniforms: inout Uniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }

        encoder.label = "Update Ez"

        encoder.setComputePipelineState(pipeline)

        cells.unwrap().setAtEncoder(encoder, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        if sources.unwrap().count == 0 {
            let empty: [ElectricSource] = [ElectricSource()]
            empty.withUnsafeBytes { bytes in
                encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 2)
            }
        } else {
            sources.unwrap().withUnsafeBytes { bytes in
                encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 2)
            }
        }

        let threadsPerGrid = MTLSize(width: Int(uniforms.Nx), height: Int(uniforms.Ny), depth: 1)

        let width = pipeline.threadExecutionWidth

        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)

        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()
    }
}

class HFieldUpdatePass: ComputePass {
    let pipeline: MTLComputePipelineState
    var cells: Reference<MTLSyncBuffer<GridCell>>

    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>) {
        self.cells = cells
        let function = library.makeFunction(name: "updateH")!
        self.pipeline = try! device.makeComputePipelineState(function: function)
    }

    func encodeCompute(_ commandBuffer: any MTLCommandBuffer, uniforms: inout Uniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }

        encoder.label = "Update H Field"

        encoder.setComputePipelineState(pipeline)

        cells.unwrap().setAtEncoder(encoder, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        let threadsPerGrid = MTLSize(width: Int(uniforms.Nx), height: Int(uniforms.Ny), depth: 1)

        let width = pipeline.threadExecutionWidth

        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)

        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()
    }
}

class SourceOverlayRenderer {
    let lineTexture: MTLTexture
    let pointTexture: MTLTexture
    let beamTexture: MTLTexture

    let overlayPass: ImageOverlayRenderPass

    init(
        device: MTLDevice,
        library: MTLLibrary
    ) {
        let loader =
            MTKTextureLoader(
                device: device
            )

        let imageLine =
            NSImage(
                named: "LineSource"
            )!

        let imagePoint =
            NSImage(
                named: "PointSource"
            )!

        let imageBeam =
            NSImage(
                named: "BeamSource"
            )!

        let cgImageLine =
            imageLine.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )!

        let cgImagePoint =
            imagePoint.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )!

        let cgImageBeam =
            imageBeam.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )!

        self.lineTexture =
            try! loader.newTexture(
                cgImage: cgImageLine,
                options: [
                    .SRGB: false
                ]
            )

        self.pointTexture =
            try! loader.newTexture(
                cgImage: cgImagePoint,
                options: [
                    .SRGB: false
                ]
            )

        self.beamTexture =
            try! loader.newTexture(
                cgImage: cgImageBeam,
                options: [
                    .SRGB: false
                ]
            )

        self.overlayPass =
            ImageOverlayRenderPass(
                device: device,
                library: library
            )
    }

    func dispatchAll(
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        uniforms: inout Uniforms,
        sources: [ElectricSource],
        drawableSize: CGSize,
        encoder: MTLRenderCommandEncoder
    ) {
        for source in sources {
            dispatchSource(
                source,
                commandBuffer: commandBuffer,
                descriptor: descriptor,
                uniforms: &uniforms,
                drawableSize: drawableSize,
                encoder: encoder,
                opacity: 1.0
            )
        }
    }

    func dispatchPreview(
        position: SIMD2<UInt32>,
        type: SourceType,
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        uniforms: inout Uniforms,
        drawableSize: CGSize,
        encoder: MTLRenderCommandEncoder
    ) {
        var source = ElectricSource()

        source.x = position.x
        source.y = position.y
        source.type = type.rawValue

        dispatchSource(
            source,
            commandBuffer: commandBuffer,
            descriptor: descriptor,
            uniforms: &uniforms,
            drawableSize: drawableSize,
            encoder: encoder,
            opacity: 0.45
        )
    }

    private func dispatchSource(
        _ source: ElectricSource,
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        uniforms: inout Uniforms,
        drawableSize: CGSize,
        encoder: MTLRenderCommandEncoder,
        opacity: Float
    ) {
        guard drawableSize.width > 0,
              drawableSize.height > 0
        else {
            return
        }

        let badgeSize: Float = 64

        let halfWidth =
            badgeSize
                / Float(drawableSize.width)

        let halfHeight =
            badgeSize
                / Float(drawableSize.height)

        let visibleNx =
            uniforms.Nx
                - 2 * uniforms.pmlThickness

        let visibleNy =
            uniforms.Ny
                - 2 * uniforms.pmlThickness

        guard visibleNx > 1,
              visibleNy > 1
        else {
            return
        }

        let u =
            Float(source.x)
                / Float(visibleNx - 1)

        let v =
            Float(source.y)
                / Float(visibleNy - 1)

        let ndcX =
            u * 2.0 - 1.0

        let ndcY =
            1.0 - v * 2.0

        let left =
            ndcX - halfWidth

        let right =
            ndcX + halfWidth

        let top =
            ndcY + halfHeight

        let bottom =
            ndcY - halfHeight

        let vertices: [SimpleOverlayVertex] = [
            .init(
                position: [left, top],
                uv: [0, 0]
            ),

            .init(
                position: [left, bottom],
                uv: [0, 1]
            ),

            .init(
                position: [right, bottom],
                uv: [1, 1]
            ),

            .init(
                position: [left, top],
                uv: [0, 0]
            ),

            .init(
                position: [right, bottom],
                uv: [1, 1]
            ),

            .init(
                position: [right, top],
                uv: [1, 0]
            )
        ]

        let texture =
            textureForSourceType(
                source.type
            )

        overlayPass
            .dispatchWithVerticesAndTexture(
                commandBuffer,
                descriptor: descriptor,
                uniforms: &uniforms,
                tex: texture,
                vertices: vertices,
                opacity: opacity,
                encoder: encoder
            )
    }

    private func textureForSourceType(
        _ rawType: UInt32
    ) -> MTLTexture {
        switch SourceType(
            rawValue: rawType
        ) {
        case .point:
            return pointTexture

        case .line:
            return lineTexture

        case .beam:
            return beamTexture

        case nil:
            return pointTexture
        }
    }
}

@Observable
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice

    var settings: SimulationSettings

    private let commandQueue: MTLCommandQueue

    private let texturePass: TextureRenderPass
    private let gaussianHorizontal: GaussianBlurPass
    private let gaussianVertical: GaussianBlurPass
    private let ezRenderPass: EzRenderPass

    private let ezUpdatePass: EzUpdatePass
    private let hUpdatePass: HFieldUpdatePass

    private let sourceOverlayRenderer: SourceOverlayRenderer

    private var cells: MTLSyncBuffer<GridCell>
    private var sources: [ElectricSource] = []
    private var sourceNames: [String] = []

    private var uniforms: Uniforms
    private var simTime: Float = 0.0

    private var stepSingle: Bool = false

    var sourcesRevision = 0

    var drawableSize: CGSize = .zero

    var editor: EditorState?

    var effectivePMLThickness: Int {
        settings.reflectWalls ? 0 : settings.pmlThickness
    }

    func makeSimCount() -> (Int, Int) {
        let pml = effectivePMLThickness

        return (
            settings.Nx + 2 * pml,
            settings.Ny + 2 * pml
        )
    }

    init(settings: SimulationSettings) {
        self.settings = settings

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not available")
        }

        self.device = device

        guard let queue = self.device.makeCommandQueue() else {
            fatalError("Cannot create command queue")
        }

        self.commandQueue = queue

        guard let library = self.device.makeDefaultLibrary() else {
            fatalError("Could not create library")
        }

        self.texturePass = TextureRenderPass(device: device, library: library)
        self.ezRenderPass = EzRenderPass(device: device, library: library, texturePass: Reference(), cells: Reference())
        self.gaussianHorizontal = GaussianBlurPass(device: device, library: library, inTexture: Reference(), isHorizontal: true)
        self.gaussianVertical = GaussianBlurPass(device: device, library: library, inTexture: Reference(), isHorizontal: false)

        self.cells = MTLSyncBuffer(device: device, values: Renderer.makeCells(nx: settings.Nx + 2 * settings.pmlThickness, ny: settings.Ny + 2 * settings.pmlThickness))

        self.ezUpdatePass = EzUpdatePass(device: device, library: library, cells: Reference(), sources: Reference())
        self.hUpdatePass = HFieldUpdatePass(device: device, library: library, cells: Reference())
        self.uniforms = Uniforms()

        self.sourceOverlayRenderer = SourceOverlayRenderer(device: device, library: library)
    }

    static func makeCells(nx: Int, ny: Int) -> [GridCell] {
        return Array(repeating: GridCell(Ez: 0, H: .zero), count: nx * ny)
    }

    @discardableResult
    func addSource(
        _ source: ElectricSource,
        name: String
    ) -> Int {
        sources.append(source)
        sourceNames.append(name)

        sourcesRevision += 1

        return sources.count - 1
    }

    func updateSource(i: Int, source: ElectricSource) {
        sources[i] = source
        sourcesRevision += 1
    }

    func makeNameForSource(
        type: SourceType
    ) -> String {
        let count =
            sources.filter {
                $0.type == type.rawValue
            }
            .count + 1

        switch type {
        case .point:
            return "Point Source \(count)"

        case .line:
            return "Line Source \(count)"

        case .beam:
            return "Beam Source \(count)"
        }
    }

    func removeSource(i: Int) {
        guard sources.indices.contains(i) else {
            return
        }

        sources.remove(at: i)

        if sourceNames.indices.contains(i) {
            sourceNames.remove(at: i)
        }

        sourcesRevision += 1
    }

    func getNameForSource(i: Int) -> String? {
        return sourceNames[i]
    }

    func getSource(i: Int) -> ElectricSource? {
        return sources[i]
    }

    func updateRenderTexture(view: MTKView) {
        ezRenderPass.texturePass.value = texturePass
        texturePass.updateTexture(for: view.drawableSize)
        gaussianHorizontal.inTexture.value = texturePass.texture
        gaussianHorizontal.updateTexture()
        gaussianVertical.inTexture.value = gaussianHorizontal.outTexture
        gaussianVertical.updateTexture()
    }

    func updateUniforms(view: MTKView) {
        ezRenderPass.cells.value = cells
        ezUpdatePass.cells.value = cells
        ezUpdatePass.sources.value = sources
        hUpdatePass.cells.value = cells

        gaussianVertical.blurAmount = settings.blurAmount
        gaussianHorizontal.blurAmount = settings.blurAmount

        uniforms.dx = settings.width / Float(settings.Nx)
        uniforms.dy = settings.height / Float(settings.Ny)

        uniforms.dt = calculateDt(dx: uniforms.dx, dy: uniforms.dy)

        uniforms.Nx = UInt32(makeSimCount().0)
        uniforms.Ny = UInt32(makeSimCount().1)

        uniforms.sourceFrequency = settings.sourceFrequency * 1e9 // Transform to Hz

        uniforms.visualizationScale = settings.visualizationScale
        uniforms.reflectingWalls = settings.reflectWalls ? 1 : 0

        uniforms.pmlThickness = settings.reflectWalls ? 0 : UInt32(settings.pmlThickness)

        uniforms.sourceCount = UInt32(sources.count)
    }

    func resetSimulation() {
        uniforms.t = 0
        settings.paused = true

        cells.assign(new: Renderer.makeCells(nx: makeSimCount().0, ny: makeSimCount().1))
    }

    func checkRemakeCells() {
        let (nx, ny) = makeSimCount()

        if cells.count != nx * ny {
            resetSimulation()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateRenderTexture(view: view)
        drawableSize = view.drawableSize

        let gridConfig = gridConfiguration(for: drawableSize, maxCells: settings.Nx, physicalWidth: settings.width)
        settings.Nx = gridConfig.nx
        settings.Ny = gridConfig.ny
        settings.width = gridConfig.width
        settings.height = gridConfig.height
    }

    func stepFrame(commandBuffer: MTLCommandBuffer) {
        for _ in 0 ..< settings.stepsPerFrame {
            uniforms.t = simTime

            hUpdatePass.encodeCompute(
                commandBuffer,
                uniforms: &uniforms
            )

            ezUpdatePass.encodeCompute(
                commandBuffer,
                uniforms: &uniforms
            )

            simTime += uniforms.dt
        }
    }

    func stepOneFrame() {
        stepSingle = true
    }

    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable
        else {
            return
        }

        checkRemakeCells()
        updateRenderTexture(view: view)
        updateUniforms(view: view)

        if !settings.paused {
            stepFrame(commandBuffer: commandBuffer)
        }

        if stepSingle {
            stepFrame(commandBuffer: commandBuffer)
            stepSingle = false
        }

        ezRenderPass.encodeCompute(commandBuffer, uniforms: &uniforms)
        gaussianHorizontal.encodeCompute(commandBuffer, uniforms: &uniforms)
        gaussianVertical.encodeCompute(commandBuffer, uniforms: &uniforms)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        texturePass.texture = gaussianVertical.outTexture
        texturePass.encode(commandBuffer, descriptor: descriptor, uniforms: &uniforms, renderEncoder: encoder)

        sourceOverlayRenderer.dispatchAll(commandBuffer: commandBuffer, descriptor: descriptor, uniforms: &uniforms, sources: sources, drawableSize: view.drawableSize, encoder: encoder)
        
        if let editor,
           let position = editor.hoveredGridPosition,
           let type = editor.currentTool.sourceType
        {
            sourceOverlayRenderer.dispatchPreview(
                position: position,
                type: type,
                commandBuffer: commandBuffer,
                descriptor: descriptor,
                uniforms: &uniforms,
                drawableSize: view.drawableSize,
                encoder: encoder
            )
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func gridSize(
        for resolution: CGSize,
        maxCells: Int = 500
    ) -> (nx: Int, ny: Int) {
        guard resolution.width > 0,
              resolution.height > 0
        else {
            return (maxCells, maxCells)
        }

        let aspect = resolution.width / resolution.height

        if aspect >= 1 {
            let nx = maxCells
            let ny = Int(round(Double(maxCells) / aspect))

            return (nx, max(1, ny))
        } else {
            let ny = maxCells
            let nx = Int(round(Double(maxCells) * aspect))

            return (max(1, nx), ny)
        }
    }

    func hitTestSource(
        at point: CGPoint,
        viewSize: CGSize,
        hitRadius: CGFloat = 26
    ) -> Int? {
        guard !sources.isEmpty else {
            return nil
        }

        let viewport = GridViewport(
            nx: settings.Nx,
            ny: settings.Ny,
            viewSize: viewSize
        )

        let radiusSquared =
            hitRadius * hitRadius

        for index in sources.indices.reversed() {
            let source = sources[index]

            let gridPosition = SIMD2<UInt32>(
                source.x,
                source.y
            )

            let sourcePoint =
                viewport.screenPosition(
                    from: gridPosition
                )

            let dx =
                point.x - sourcePoint.x

            let dy =
                point.y - sourcePoint.y

            let distanceSquared =
                dx * dx + dy * dy

            if distanceSquared <= radiusSquared {
                return index
            }
        }

        return nil
    }
}
