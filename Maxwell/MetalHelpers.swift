//
//  MetalHelpers.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

import Metal
import MetalKit
import Foundation

func createRenderPipeline(vertex: String, fragment: String, device: MTLDevice) throws -> MTLRenderPipelineState {
    guard let library = device.makeDefaultLibrary() else {
        fatalError("Could not load Metal Library")
    }
    
    let vertexFunction = library.makeFunction(name: vertex)!
    let fragmentFunction = library.makeFunction(name: fragment)!

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    descriptor.rasterSampleCount = 4

    return try device.makeRenderPipelineState(descriptor: descriptor)
}

protocol MetalPass {
    func encode(_ commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor)
}

protocol ComputePass: MetalPass {
    func encodeCompute(_ commandBuffer: MTLCommandBuffer)
}

extension ComputePass {
    func encode(_ commandBuffer: any MTLCommandBuffer, descriptor: MTLRenderPassDescriptor) {
        encodeCompute(commandBuffer)
    }
}

protocol RenderPass: MetalPass {}

func createRenderTexture(
    device: MTLDevice,
    width: Int,
    height: Int
) -> MTLTexture {
    let descriptor =
        MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )

    descriptor.usage = [
        .shaderRead,
        .shaderWrite
    ]

    descriptor.storageMode = .private

    return device.makeTexture(
        descriptor: descriptor
    )!
}

class TextureRenderPass: RenderPass {
    var texture: MTLTexture
    let renderPipeline: MTLRenderPipelineState
    let device: MTLDevice

    init(
        device: MTLDevice,
        library: MTLLibrary
    ) {
        self.texture = createRenderTexture(device: device, width: 1, height: 1)
        self.device = device

        self.renderPipeline = try! createRenderPipeline(
            vertex: "fullscreenVertex",
            fragment: "fullscreenFragment",
            device: device
        )
    }
    
    func updateTexture(for size: CGRect) {
        if Int(size.width) != texture.width || Int(size.height) != texture.height {
            self.texture = createRenderTexture(device: device, width: Int(size.width), height: Int(size.height))
        }
    }

    func encode(
        _ commandBuffer: any MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return
        }

        encoder.label = "Texture Render Pass"

        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )

        encoder.endEncoding()
    }
}
