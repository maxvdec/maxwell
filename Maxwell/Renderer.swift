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
    
    var width: Float = 2.0
    var height: Float = 2.0
    
    var sourceFrequency: Float = 1.0 // In GHz
    var visualizationScale: Float = 15.0
    
    var reflectWalls: Bool = false
    var stepsPerFrame: Int = 1
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

class EzBoundaryPass: ComputePass {
    let pipeline: MTLComputePipelineState
    var cells: Reference<MTLSyncBuffer<GridCell>>
    
    init(device: MTLDevice, library: MTLLibrary, cells: Reference<MTLSyncBuffer<GridCell>>) {
        self.cells = cells
        let function = library.makeFunction(name: "absorbEzBoundary")!
        self.pipeline = try! device.makeComputePipelineState(function: function)
    }
    
    func encodeCompute(_ commandBuffer: any MTLCommandBuffer, uniforms: inout Uniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }
        
        encoder.label = "Absorb Ez Boundary"
        
        encoder.setComputePipelineState(pipeline)
        
        cells.unwrap().setAtEncoder(encoder, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        
        let threadsPerGrid = MTLSize(width: Int(max(uniforms.Nx, uniforms.Ny)), height: 1, depth: 1)
        
        let width = pipeline.threadExecutionWidth
        
        let threadsPerThreadgroup = MTLSize(width: width, height: 1, depth: 1)
        
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
    private let ezRenderPass: EzRenderPass
    
    private let ezUpdatePass: EzUpdatePass
    private let ezBoundaryPass: EzBoundaryPass
    private let hUpdatePass: HFieldUpdatePass
    
    private var cells: MTLSyncBuffer<GridCell>
    
    private var uniforms: Uniforms
    private var simTime: Float = 0.0
    
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
        self.cells = MTLSyncBuffer(device: device, values: Renderer.makeCells(nx: settings.Nx, ny: settings.Ny))
        
        self.ezUpdatePass = EzUpdatePass(device: device, library: library, cells: Reference())
        self.ezBoundaryPass = EzBoundaryPass(device: device, library: library, cells: Reference())
        self.hUpdatePass = HFieldUpdatePass(device: device, library: library, cells: Reference())
        self.uniforms = Uniforms()
    }
    
    static func makeCells(nx: Int, ny: Int) -> [GridCell] {
        return Array(repeating: GridCell(Ez: 0, previousEz: 0, H: .zero), count: nx * ny)
    }
    
    func updateRenderTexture(view: MTKView) {
        ezRenderPass.texturePass.value = texturePass
        texturePass.updateTexture(for: view.frame)
    }
    
    func updateUniforms(view: MTKView) {
        self.ezRenderPass.cells.value = cells
        self.ezUpdatePass.cells.value = cells
        self.ezBoundaryPass.cells.value = cells
        self.hUpdatePass.cells.value = cells
        
        uniforms.dx = settings.width / Float(settings.Nx)
        uniforms.dy = settings.height / Float(settings.Ny)
        
        uniforms.dt = calculateDt(dx: uniforms.dx, dy: uniforms.dy)
        
        uniforms.Nx = UInt32(settings.Nx)
        uniforms.Ny = UInt32(settings.Ny)
        
        uniforms.sourceFrequency = settings.sourceFrequency * 1e9 // Transform to Hz
        
        uniforms.visualizationScale = settings.visualizationScale
        uniforms.reflectingWalls = settings.reflectWalls ? 1 : 0
    }
    
    func resetSimulation() {
        uniforms.t = 0
        settings.paused = true
        
        cells.assign(new: Renderer.makeCells(nx: settings.Nx, ny: settings.Ny))
    }
    
    func checkRemakeCells() {
        if cells.count != settings.Nx * settings.Ny {
            resetSimulation()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateRenderTexture(view: view)
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
                
                if !settings.reflectWalls {
                    ezBoundaryPass.encodeCompute(commandBuffer, uniforms: &uniforms)
                }

                simTime += uniforms.dt
            }
        }
        ezRenderPass.encodeCompute(commandBuffer, uniforms: &uniforms)
        texturePass.encode(commandBuffer, descriptor: descriptor, uniforms: &uniforms)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
