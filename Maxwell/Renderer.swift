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
    
    var visualizationScale: Float = 30.0
    
    var reflectWalls: Bool = false
    var stepsPerFrame: Int = 3
    
    var blurAmount: Float = 7.0
    
}

struct MetalView: NSViewRepresentable {
    let renderer: Renderer
    
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        
        view.device = renderer.device
        view.delegate = renderer
        
        view.colorPixelFormat = .bgra8Unorm
        
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        view.sampleCount = 4
        
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        
        return view
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
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
    
    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>) {
        self.cells = cells
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
    
    private var cells: MTLSyncBuffer<GridCell>
    
    private var uniforms: Uniforms
    private var simTime: Float = 0.0
    
    private var stepSingle: Bool = false
    
    var drawableSize: CGSize = .zero
    
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
        
        self.ezUpdatePass = EzUpdatePass(device: device, library: library, cells: Reference())
        self.hUpdatePass = HFieldUpdatePass(device: device, library: library, cells: Reference())
        self.uniforms = Uniforms()
        
    }
    
    static func makeCells(nx: Int, ny: Int) -> [GridCell] {
        return Array(repeating: GridCell(Ez: 0, H: .zero), count: nx * ny)
    }
    
    func updateRenderTexture(view: MTKView) {
        ezRenderPass.texturePass.value = texturePass
        texturePass.updateTexture(for: view.frame)
        gaussianHorizontal.inTexture.value = self.texturePass.texture
        gaussianHorizontal.updateTexture()
        gaussianVertical.inTexture.value = gaussianHorizontal.outTexture
        gaussianVertical.updateTexture()
    }
    
    func updateUniforms(view: MTKView) {
        self.ezRenderPass.cells.value = cells
        self.ezUpdatePass.cells.value = cells
        self.hUpdatePass.cells.value = cells
        
        self.gaussianVertical.blurAmount = settings.blurAmount
        self.gaussianHorizontal.blurAmount = settings.blurAmount
        
        uniforms.dx = settings.width / Float(settings.Nx)
        uniforms.dy = settings.height / Float(settings.Ny)
        
        uniforms.dt = calculateDt(dx: uniforms.dx, dy: uniforms.dy)
        
        uniforms.Nx = UInt32(makeSimCount().0)
        uniforms.Ny = UInt32(makeSimCount().1)
        
        uniforms.sourceFrequency = settings.sourceFrequency * 1e9 // Transform to Hz
        
        uniforms.visualizationScale = settings.visualizationScale
        uniforms.reflectingWalls = settings.reflectWalls ? 1 : 0
        
        uniforms.pmlThickness = settings.reflectWalls ? 0 : UInt32(settings.pmlThickness)
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
        self.drawableSize = view.drawableSize
        
        let gridConfig = gridConfiguration(for: drawableSize, maxCells: settings.Nx, physicalWidth: settings.width)
        settings.Nx = gridConfig.nx
        settings.Ny = gridConfig.ny
        settings.width = gridConfig.width
        settings.height = gridConfig.height
        calculateFrequency(cellsPerWavelength: settings.cellsPerWavelength, settings: &settings)
    }
    
    func stepFrame(commandBuffer: MTLCommandBuffer) {
        for _ in 0..<settings.stepsPerFrame {
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
        
        texturePass.texture = gaussianVertical.outTexture
        texturePass.encode(commandBuffer, descriptor: descriptor, uniforms: &uniforms)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func gridSize(
        for resolution: CGSize,
        maxCells: Int = 500
    ) -> (nx: Int, ny: Int) {
        guard resolution.width > 0,
              resolution.height > 0 else {
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
}
