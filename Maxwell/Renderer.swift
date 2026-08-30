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
    var texturePass: () -> TextureRenderPass?
    
    init(device: MTLDevice, library: MTLLibrary, texturePass: @escaping () -> TextureRenderPass?) {
        self.texturePass = texturePass
        let function = library.makeFunction(name: "renderEz")!
        self.pipeline = try! device.makeComputePipelineState(function: function)
    }
    
    func encodeCompute(_ commandBuffer: any MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = "Render Ez"
        
        encoder.setComputePipelineState(pipeline)
        
        guard let texture = self.texturePass()?.texture else {
            return
        }
        
        encoder.setTexture(texture, index: 0)
        
        let width = pipeline.threadExecutionWidth
        
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        
        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
        
        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        
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
        self.ezRenderPass = EzRenderPass(device: device, library: library, texturePass: { nil })
    }
    
    func updateRenderTexture(view: MTKView) {
        self.ezRenderPass.texturePass = { self.texturePass }
        self.texturePass.updateTexture(for: view.frame)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable
        else {
            return
        }
        
        updateRenderTexture(view: view)
        
        ezRenderPass.encodeCompute(commandBuffer)
        texturePass.encode(commandBuffer, descriptor: descriptor)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func draw(in view: MTKView) {}
}
