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

    var Nx = 1000
    var Ny = 1000
    var pmlThickness: Int = 40

    var width: Float = 2.0
    var height: Float = 2.0

    var sourceFrequency: Float = 1.0 // In GHz
    var cellsPerWavelength: Float = 20.0

    var visualizationScale: Float = 15.0

    var reflectWalls: Bool = false
    var stepsPerFrame: Int = 3

    var blurAmount: Float = 3.0
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

        case .move:
            return

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

        case .placeCollider:
            return
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

        source.amplitude = 10.0
        source.phase = 0.0

        source.gaussianWidth = 1.0
        source.length = safelyCheckUInt(renderer.settings.Nx / 2)
        source.rotation = 0.0

        source.beamWaist = Float(source.length) * 0.25

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
    var cells: Reference<MTLSyncBuffer<GridCell>>
    var materials: Reference<[EMMaterial]>
    var outputTexture: MTLTexture

    private let device: MTLDevice

    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>, materials: Reference<[EMMaterial]>) {
        self.device = device
        let function = library.makeFunction(name: "renderEz")!
        self.pipeline = try! device.makeComputePipelineState(function: function)
        self.cells = cells
        self.materials = materials
        self.outputTexture = createRenderTexture(
            device: device,
            width: 1,
            height: 1
        )
    }

    func updateTexture(for size: CGSize) {
        if Int(size.width) != outputTexture.width ||
            Int(size.height) != outputTexture.height {
            outputTexture = createRenderTexture(
                device: device,
                width: Int(size.width),
                height: Int(size.height)
            )
        }
    }

    func encodeCompute(_ commandBuffer: any MTLCommandBuffer, uniforms: inout Uniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        encoder.label = "Render Ez"

        encoder.setComputePipelineState(pipeline)

        encoder.setTexture(outputTexture, index: 0)

        cells.unwrap().setAtEncoder(encoder, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        materials.unwrap().withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 2)
        }

        let width = pipeline.threadExecutionWidth

        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)

        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)

        let threadsPerGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()
    }
}

class EzUpdatePass: ComputePass {
    let pipeline: MTLComputePipelineState
    var cells: Reference<MTLSyncBuffer<GridCell>>
    var sources: Reference<[ElectricSource]>
    var materials: Reference<[EMMaterial]>

    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>, sources: Reference<[ElectricSource]>, materials: Reference<[EMMaterial]>) {
        self.cells = cells
        self.materials = materials
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

        materials.unwrap().withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 3)
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
    var materials: Reference<[EMMaterial]>

    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>, materials: Reference<[EMMaterial]>) {
        self.cells = cells
        self.materials = materials
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

        materials.unwrap().withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 2)
        }

        let threadsPerGrid = MTLSize(width: Int(uniforms.Nx), height: Int(uniforms.Ny), depth: 1)

        let width = pipeline.threadExecutionWidth

        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)

        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()
    }
}

class ColliderMaterialPass {
    let pipeline: MTLComputePipelineState

    init(device: MTLDevice, library: MTLLibrary) {
        let function = library.makeFunction(name: "applyColliderMaterials")!
        pipeline = try! device.makeComputePipelineState(function: function)
    }

    func encodeCompute(
        _ commandBuffer: MTLCommandBuffer,
        cells: MTLSyncBuffer<GridCell>,
        materialIndices: MTLSyncBuffer<Int32>
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        encoder.label = "Apply Collider Materials"
        encoder.setComputePipelineState(pipeline)
        cells.setAtEncoder(encoder, index: 0)
        materialIndices.setAtEncoder(encoder, index: 1)

        var count = UInt32(materialIndices.count)
        encoder.setBytes(
            &count,
            length: MemoryLayout<UInt32>.stride,
            index: 2
        )

        let width = pipeline.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: width, height: 1, depth: 1)
        let threads = MTLSize(width: materialIndices.count, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
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

class SourceGeometryRenderer {
    let pass: RectangleOverlayRenderPass

    init(
        device: MTLDevice,
        library: MTLLibrary
    ) {
        self.pass =
            RectangleOverlayRenderPass(
                device: device,
                library: library
            )
    }

    func dispatchAll(
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        sources: [ElectricSource],
        uniforms: Uniforms,
        drawableSize: CGSize,
        encoder: MTLRenderCommandEncoder
    ) {
        for source in sources {
            dispatchSource(
                source,
                commandBuffer: commandBuffer,
                descriptor: descriptor,
                drawableSize: drawableSize,
                uniforms: uniforms,
                encoder: encoder,
                opacity: 1.0
            )
        }
    }

    private func dispatchSource(
        _ source: ElectricSource,
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        uniforms: Uniforms,
        encoder: MTLRenderCommandEncoder,
        opacity: Float
    ) {
        guard drawableSize.width > 0,
              drawableSize.height > 0
        else {
            return
        }

        let badgeSize: Float = 64

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

        let center = SIMD2<Float>(
            u * 2 - 1,
            1 - v * 2
        )

        let cellWidthNDC =
            2.0 / Float(visibleNx)

        let angle =
            source.rotation * .pi / 180

        let direction = SIMD2<Float>(
            cos(angle),
            -sin(angle)
        )

        let normal = SIMD2<Float>(
            -direction.y,
            direction.x
        )

        let halfLength =
            Float(source.length) * 0.5

        let cellSizeNDC = SIMD2<Float>(
            2.0 / Float(visibleNx),
            2.0 / Float(visibleNy)
        )

        let along =
            direction *
            SIMD2<Float>(
                halfLength * cellSizeNDC.x,
                halfLength * cellSizeNDC.y
            )

        let thicknessCells: Float = 2

        let perpendicular = SIMD2<Float>(
            normal.x * thicknessCells * cellSizeNDC.x,
            normal.y * thicknessCells * cellSizeNDC.y
        )

        let p0 = center - along - perpendicular
        let p1 = center + along - perpendicular
        let p2 = center + along + perpendicular
        let p3 = center - along + perpendicular

        let vertices: [SimpleOverlayVertex] = [
            .init(
                position: p0,
                uv: [0, 0]
            ),

            .init(
                position: p1,
                uv: [1, 0]
            ),

            .init(
                position: p2,
                uv: [1, 1]
            ),

            .init(
                position: p0,
                uv: [0, 0]
            ),

            .init(
                position: p2,
                uv: [1, 1]
            ),

            .init(
                position: p3,
                uv: [0, 1]
            )
        ]

        let cellSizePx = SIMD2<Float>(
            Float(drawableSize.width) / Float(visibleNx),
            Float(drawableSize.height) / Float(visibleNy)
        )

        let lengthPx =
            Float(source.length) * cellSizePx.x

        let thicknessPx: Float = 14

        var geometryUniforms = LineGeometryUniforms(
            sizePx: SIMD2<Float>(
                lengthPx,
                thicknessPx
            ),
            borderPx: 2.0,
            borderColor: SIMD4<Float>(
                1.0,
                0.23,
                0.19,
                1.0
            ),
            beamWaistPx: source.beamWaist * cellSizePx.x,
            isBeam: source.type == SourceType.beam.rawValue ? 1 : 0
        )

        pass
            .dispatchWithVertices(
                commandBuffer,
                descriptor: descriptor,
                uniforms: &geometryUniforms,
                vertices: vertices,
                opacity: opacity,
                encoder: encoder
            )
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
    private let energyBloomExtract: EnergyBloomExtractPass
    private let energyGlowComposite: EnergyGlowCompositePass

    private let ezUpdatePass: EzUpdatePass
    private let hUpdatePass: HFieldUpdatePass
    private let colliderMaterialPass: ColliderMaterialPass

    private let sourceGeometryRenderer: SourceGeometryRenderer
    private let sourceOverlayRenderer: SourceOverlayRenderer

    private var cells: MTLSyncBuffer<GridCell>
    private var colliderMaterialIndices: MTLSyncBuffer<Int32>
    private var sources: [ElectricSource] = []
    private var materials: [EMMaterial] = [EMMaterial(epsilonR: 1.0, muR: 1.0, sigma: 0.0, pec: 0.0)] // Vaccum material
    private var materialNames: [String] = ["Vacuum"]
    private var sourceNames: [String] = []

    private var uniforms: Uniforms
    var simTime: Float = 0.0

    private var stepSingle: Bool = false

    var sourcesRevision = 0
    var materialsRevision = 0

    var drawableSize: CGSize = .zero

    var editor: EditorState?

    private var didCreateDefaultSource = false

    @MainActor
    var ez3DSnapshot: EzFieldSnapshot?

    private let ez3DResolution = 64

    private var frameNumber = 0
    private var appliedColliderRevision = -1
    private var shouldApplyColliderMaterials = false
    
    var visualizationMethod: VisualizationMode = .field2D

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
        self.ezRenderPass = EzRenderPass(device: device, library: library, cells: Reference(), materials: Reference())
        self.gaussianHorizontal = GaussianBlurPass(device: device, library: library, inTexture: Reference(), isHorizontal: true)
        self.gaussianVertical = GaussianBlurPass(device: device, library: library, inTexture: Reference(), isHorizontal: false)
        self.energyBloomExtract = EnergyBloomExtractPass(
            device: device,
            library: library,
            inputTexture: Reference()
        )
        self.energyGlowComposite = EnergyGlowCompositePass(
            device: device,
            library: library,
            energyTexture: Reference(),
            bloomTexture: Reference()
        )

        self.cells = MTLSyncBuffer(device: device, values: Renderer.makeCells(nx: settings.Nx + 2 * settings.pmlThickness, ny: settings.Ny + 2 * settings.pmlThickness))
        self.colliderMaterialIndices = MTLSyncBuffer(
            device: device,
            values: Array(
                repeating: 0,
                count: (settings.Nx + 2 * settings.pmlThickness) *
                    (settings.Ny + 2 * settings.pmlThickness)
            )
        )

        self.ezUpdatePass = EzUpdatePass(device: device, library: library, cells: Reference(), sources: Reference(), materials: Reference())
        self.hUpdatePass = HFieldUpdatePass(device: device, library: library, cells: Reference(), materials: Reference())
        self.colliderMaterialPass = ColliderMaterialPass(device: device, library: library)
        self.uniforms = Uniforms()

        self.sourceGeometryRenderer = SourceGeometryRenderer(device: device, library: library)
        self.sourceOverlayRenderer = SourceOverlayRenderer(device: device, library: library)
        
        materials = [
            EMMaterial(epsilonR: 1.0, muR: 1.0, sigma: 0.0, pec: 0), // Vaccum
            EMMaterial(epsilonR: 1.0006, muR: 1.0000004, sigma: 0.0, pec: 0), // Air
            EMMaterial(epsilonR: 2.1, muR: 1.0, sigma: 1e-15, pec: 0), // PTFE
            EMMaterial(epsilonR: 4.0, muR: 1.0, sigma: 1e-12, pec: 0), // Glass
            EMMaterial(epsilonR: 11.7, muR: 1.0, sigma: 0.0, pec: 0), // Silicon
            EMMaterial(epsilonR: 4.5, muR: 1.0, sigma: 0.02, pec: 0), // Concrete
            EMMaterial(epsilonR: 75, muR: 1.0, sigma: 4.0, pec: 0), // Seawater
            EMMaterial(epsilonR: 12, muR: 100, sigma: 0.01, pec: 0), // Ferrite
            EMMaterial(epsilonR: 1, muR: 1, sigma: 5.8e7, pec: 0), // Copper
            EMMaterial(epsilonR: 1, muR: 1, sigma: 0, pec: 1) // PEC
        ]
        
        materialNames = [
            "Vacuum",
            "Air",
            "Polytetrafluoroethylene (PTFE)",
            "Glass",
            "Silicon",
            "Concrete",
            "Seawater (approximate preset - should vary with wavelength)",
            "Ferrite (approximate preset - should vary with wavelength)",
            "Copper",
            "Perfect Electric Conductor",
        ]
    }

    static func makeCells(nx: Int, ny: Int) -> [GridCell] {
        return Array(
            repeating: GridCell(Ez: 0, H: .zero, materialIndex: 0),
            count: nx * ny
        )
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

    func renameSource(
        i: Int,
        name: String
    ) {
        guard sourceNames.indices.contains(i) else {
            return
        }

        sourceNames[i] = name
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
        guard sourceNames.indices.contains(i) else {
            return nil
        }

        return sourceNames[i]
    }

    func getSource(i: Int) -> ElectricSource? {
        guard sources.indices.contains(i) else {
            return nil
        }

        return sources[i]
    }
    
    @discardableResult
    func addMaterial(
        _ material: EMMaterial,
        name: String
    ) -> Int {
        materials.append(material)
        materialNames.append(name)

        materialsRevision += 1

        return materials.count - 1
    }

    func updateMaterial(i: Int, material: EMMaterial) {
        guard materials.indices.contains(i) else {
            return
        }

        materials[i] = material
        materialsRevision += 1
    }

    func renameMaterial(
        i: Int,
        name: String
    ) {
        guard materialNames.indices.contains(i) else {
            return
        }

        materialNames[i] = name
        materialsRevision += 1
    }

    func removeMaterial(i: Int) {
        guard i > 0,
              materials.indices.contains(i)
        else {
            return
        }

        materials.remove(at: i)

        if materialNames.indices.contains(i) {
            materialNames.remove(at: i)
        }

        materialsRevision += 1
    }

    func getNameForMaterial(i: Int) -> String? {
        guard materialNames.indices.contains(i) else {
            return nil
        }

        return materialNames[i]
    }

    func getMaterial(i: Int) -> EMMaterial? {
        guard materials.indices.contains(i) else {
            return nil
        }

        return materials[i]
    }

    var materialCount: Int {
        materials.count
    }

    var materialOptions: [(index: Int, name: String)] {
        materialNames.enumerated().map {
            (index: $0.offset, name: $0.element)
        }
    }

    func updateRenderTexture(view: MTKView) {
        ezRenderPass.updateTexture(for: view.drawableSize / 2)
        gaussianHorizontal.inTexture.value = ezRenderPass.outputTexture
        gaussianHorizontal.updateTexture()
        gaussianVertical.inTexture.value = gaussianHorizontal.outTexture
        gaussianVertical.updateTexture()

        energyBloomExtract.inputTexture.value = ezRenderPass.outputTexture
        energyBloomExtract.updateTexture()
        energyGlowComposite.energyTexture.value = ezRenderPass.outputTexture
        energyGlowComposite.bloomTexture.value = gaussianVertical.outTexture
        energyGlowComposite.updateTexture()
    }

    func calculateSigmaMaxXY() {
        let pmlPhysicalWidthX = Float(uniforms.pmlThickness) * uniforms.dx
        let sigmaMaxX = calculateSigmaMax(pmlPhysical: pmlPhysicalWidthX)

        let pmlPhysicalWidthY = Float(uniforms.pmlThickness) * uniforms.dy
        let sigmaMaxY = calculateSigmaMax(pmlPhysical: pmlPhysicalWidthY)

        uniforms.sigmaMaxX = sigmaMaxX
        uniforms.sigmaMaxY = sigmaMaxY
    }

    func updateUniforms(view: MTKView) {
        ezRenderPass.cells.value = cells
        ezRenderPass.materials.value = materials
        ezUpdatePass.cells.value = cells
        ezUpdatePass.sources.value = sources
        ezUpdatePass.materials.value = materials
        hUpdatePass.cells.value = cells
        hUpdatePass.materials.value = materials

        gaussianVertical.blurAmount = settings.blurAmount
        gaussianHorizontal.blurAmount = settings.blurAmount

        uniforms.dx = settings.width / Float(settings.Nx)
        uniforms.dy = settings.height / Float(settings.Ny)

        uniforms.dt = calculateDt(dx: uniforms.dx, dy: uniforms.dy)

        uniforms.Nx = UInt32(makeSimCount().0)
        uniforms.Ny = UInt32(makeSimCount().1)

        calculateSigmaMaxXY()

        uniforms.sourceFrequency = settings.sourceFrequency * 1e9 // Transform to Hz

        uniforms.visualizationScale = settings.visualizationScale
        uniforms.reflectingWalls = settings.reflectWalls ? 1 : 0

        uniforms.pmlThickness = settings.reflectWalls ? 0 : UInt32(settings.pmlThickness)

        uniforms.sourceCount = UInt32(sources.count)
        uniforms.materialCount = Int32(materials.count)
        
        uniforms.visualizationMode = visualizationMethod.rawValue
    }

    func resetSimulation() {
        simTime = 0.0
        settings.paused = true

        cells.assign(new: Renderer.makeCells(nx: makeSimCount().0, ny: makeSimCount().1))
        appliedColliderRevision = -1
    }

    func rasterizeColliderMaterialsIfNeeded() {
        guard let editor,
              appliedColliderRevision != editor.colliderRevision
        else {
            return
        }

        let colliders = editor.colliders
        let nx = settings.Nx
        let ny = settings.Ny
        let simNx = makeSimCount().0
        let pml = effectivePMLThickness
        let materialCount = materials.count

        var indices = Array(
            repeating: Int32(0),
            count: makeSimCount().0 * makeSimCount().1
        )

        if nx > 0,
           ny > 0 {
            for y in 0 ..< ny {
                for x in 0 ..< nx {
                    let point = NormalizedPoint(
                        x: (Double(x) + 0.5) / Double(nx),
                        y: (Double(y) + 0.5) / Double(ny)
                    )

                    var selectedMaterial = 0

                    for collider in colliders where collider.geometry.contains(point) {
                        if collider.materialIndex >= 0,
                           collider.materialIndex < materialCount {
                            selectedMaterial = collider.materialIndex
                        }
                    }

                    let index = (y + pml) * simNx + x + pml
                    indices[index] = Int32(selectedMaterial)
                }
            }
        }

        colliderMaterialIndices.assign(new: indices)
        appliedColliderRevision = editor.colliderRevision
        shouldApplyColliderMaterials = true
    }

    func checkRemakeCells() {
        let (nx, ny) = makeSimCount()

        if cells.count != nx * ny {
            resetSimulation()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateRenderTexture(view: view)
        drawableSize = size

        let gridConfig = gridConfiguration(for: size, maxCells: settings.Nx, physicalWidth: settings.width)
        settings.Nx = gridConfig.nx
        settings.Ny = gridConfig.ny
        settings.width = gridConfig.width
        settings.height = gridConfig.height

        if !didCreateDefaultSource {
            sources = [ElectricSource(x: safelyCheckUInt(settings.Nx / 2), y: safelyCheckUInt(settings.Ny / 2), length: 0, rotation: 0, beamWaist: 0.0,
                                      frequency: calculateFrequency(cellsPerWavelength: 20.0, settings: settings),
                                      amplitude: 10.0,
                                      phase: 0.0,
                                      type: SourceType.point.rawValue, form: SourceForm.sine.rawValue, duration: 0.0, gaussianWidth: 0.0)]
            sourceNames = ["Point Source 1"]
            print(sources[0])
            didCreateDefaultSource = true
        }
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
        rasterizeColliderMaterialsIfNeeded()
        updateRenderTexture(view: view)
        updateUniforms(view: view)

        if shouldApplyColliderMaterials {
            colliderMaterialPass.encodeCompute(
                commandBuffer,
                cells: cells,
                materialIndices: colliderMaterialIndices
            )
            shouldApplyColliderMaterials = false
        }

        if !settings.paused {
            stepFrame(commandBuffer: commandBuffer)
        }

        if stepSingle {
            stepFrame(commandBuffer: commandBuffer)
            stepSingle = false
        }

        ezRenderPass.encodeCompute(commandBuffer, uniforms: &uniforms)

        if visualizationMethod == .energyGlow {
            energyBloomExtract.encodeCompute(
                commandBuffer,
                uniforms: &uniforms
            )

            gaussianHorizontal.blurAmount = max(
                settings.blurAmount,
                2.5
            )

            for iteration in 0 ..< 3 {
                gaussianHorizontal.inTexture.value =
                    iteration == 0
                    ? energyBloomExtract.outputTexture
                    : gaussianVertical.outTexture
                gaussianHorizontal.encodeCompute(
                    commandBuffer,
                    uniforms: &uniforms
                )

                gaussianVertical.inTexture.value =
                    gaussianHorizontal.outTexture
                gaussianVertical.encodeCompute(
                    commandBuffer,
                    uniforms: &uniforms
                )
            }

            energyGlowComposite.bloomTexture.value =
                gaussianVertical.outTexture
            energyGlowComposite.encodeCompute(
                commandBuffer,
                uniforms: &uniforms
            )
        } else if visualizationMethod != .poynting {
            gaussianHorizontal.inTexture.value =
                ezRenderPass.outputTexture
            gaussianHorizontal.encodeCompute(
                commandBuffer,
                uniforms: &uniforms
            )
            gaussianVertical.inTexture.value =
                gaussianHorizontal.outTexture
            gaussianVertical.encodeCompute(
                commandBuffer,
                uniforms: &uniforms
            )
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        switch visualizationMethod {
        case .energyGlow:
            texturePass.texture = energyGlowComposite.outputTexture
        case .poynting:
            texturePass.texture = ezRenderPass.outputTexture
        default:
            texturePass.texture = gaussianVertical.outTexture
        }
        texturePass.encode(commandBuffer, descriptor: descriptor, uniforms: &uniforms, renderEncoder: encoder)

        sourceGeometryRenderer.dispatchAll(commandBuffer: commandBuffer, descriptor: descriptor, sources: sources, uniforms: uniforms, drawableSize: view.drawableSize, encoder: encoder)
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

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else {
                return
            }

            guard self.editor?.visualizationMode == .field3D else {
                return
            }

            self.frameNumber += 1
            if self.frameNumber % 3 == 0 {
                let result = self.makeEz3DSnapshot()
                Task { @MainActor in
                    self.ez3DSnapshot = result
                }
            }
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

    func makeEz3DSnapshot() -> EzFieldSnapshot {
        let targetNx = ez3DResolution
        let targetNy = ez3DResolution

        let simNx = makeSimCount().0

        let pml = effectivePMLThickness

        var values = Array(
            repeating: 0.0,
            count: targetNx * targetNy
        )

        cells.withBufferContents { grid in
            for y in 0 ..< targetNy {
                for x in 0 ..< targetNx {
                    let normalizedX =
                        Double(x) / Double(targetNx - 1)

                    let normalizedY =
                        Double(y) / Double(targetNy - 1)

                    let gridX =
                        pml +
                        Int(
                            normalizedX *
                                Double(settings.Nx - 1)
                        )

                    let gridY =
                        pml +
                        Int(
                            normalizedY *
                                Double(settings.Ny - 1)
                        )

                    let index =
                        gridY * simNx + gridX

                    let value = Double(grid[index].Ez)
                    values[y * targetNx + x] =
                        value.isFinite ? value : 0
                }
            }
        }

        return EzFieldSnapshot(
            nx: targetNx,
            ny: targetNy,
            physicalWidth: Double(settings.width),
            physicalHeight: Double(settings.height),
            values: values
        )
    }
}
