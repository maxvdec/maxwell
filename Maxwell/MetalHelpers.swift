//
//  MetalHelpers.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

import Metal
import MetalKit
import Foundation
import SwiftUI

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
    func encode(_ commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, uniforms: inout Uniforms)
}

protocol ComputePass: MetalPass {
    func encodeCompute(_ commandBuffer: MTLCommandBuffer, uniforms: inout Uniforms)
}

extension ComputePass {
    func encode(_ commandBuffer: any MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, uniforms: inout Uniforms) {
        encodeCompute(commandBuffer, uniforms: &uniforms)
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
        descriptor: MTLRenderPassDescriptor,
        uniforms: inout Uniforms
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

func gaussianWeights(radius: Int, sigma: Float) -> [Float] {
    var weights = [Float]()

    var sum: Float = 0

    for x in 0...radius {
        let xf = Float(x)

        let weight = exp(
            -(xf * xf) / (2 * sigma * sigma)
        )

        weights.append(weight)

        if x == 0 {
            sum += weight
        } else {
            sum += weight * 2
        }
    }

    for i in weights.indices {
        weights[i] /= sum
    }

    return weights
}

class GaussianBlurPass: ComputePass {
    var inTexture: Reference<MTLTexture>
    var outTexture: MTLTexture
    let pipeline: MTLComputePipelineState
    let device: MTLDevice
    var blurAmount: Float = 2.0

    init(
        device: MTLDevice,
        library: MTLLibrary,
        inTexture: Reference<MTLTexture>,
        isHorizontal: Bool
    ) {
        self.outTexture = createRenderTexture(device: device, width: 1, height: 1)
        self.inTexture = inTexture
        self.device = device
        
        if isHorizontal {
            let function = library.makeFunction(name: "gaussianBlurHorizontal")!
            self.pipeline = try! device.makeComputePipelineState(function: function)
        } else {
            let function = library.makeFunction(name: "gaussianBlurVertical")!
            self.pipeline = try! device.makeComputePipelineState(function: function)
        }
    }
    
    func updateTexture() {
        let texture = self.inTexture.unwrap()
        if texture.width != outTexture.width || texture.height != outTexture.height {
            self.outTexture = createRenderTexture(device: device, width: texture.width, height: texture.height)
        }
    }

    func encodeCompute(
        _ commandBuffer: any MTLCommandBuffer,
        uniforms: inout Uniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        encoder.label = "Gaussian Blur Horizontal"
        
        encoder.setComputePipelineState(pipeline)
        
        let texture = inTexture.unwrap()
        
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outTexture, index: 1)
        
        let radius = Int(ceil(blurAmount * 3))
        let sigma = max(blurAmount, 0.001)
        
        var weights = gaussianWeights(radius: radius, sigma: sigma)
        
        weights.withUnsafeBytes { rawBuffer in
            encoder.setBytes(
                rawBuffer.baseAddress!,
                length: rawBuffer.count,
                index: 0
            )
        }
        
        var radius32 = UInt32(radius)
        
        encoder.setBytes(&radius32, length: MemoryLayout<UInt32>.stride, index: 1)
        
        let width = pipeline.threadExecutionWidth
        
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        
        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
        
        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        encoder.endEncoding()
    }
}

struct IntField: View {
    @Binding var value: Int

    let title: String
    let unit: String
    let isZeroPermitted: Bool
    let dragSensitivity: Float

    @State private var text: String = ""
    @State private var dragStartValue: Int?
    @State private var isDragging = false

    init(
        _ title: String,
        value: Binding<Int>,
        unit: String,
        isZeroPermitted: Bool = false,
        dragSensitivity: Float = 0.1
    ) {
        self.title = title
        self._value = value
        self.unit = unit
        self.isZeroPermitted = isZeroPermitted
        self.dragSensitivity = dragSensitivity
    }

    var body: some View {
        HStack {
            Text(title)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if dragStartValue == nil {
                                dragStartValue = value
                                isDragging = true
                            }

                            guard let startValue = dragStartValue else {
                                return
                            }

                            var sensitivity = dragSensitivity

                            if NSEvent.modifierFlags.contains(.shift) {
                                sensitivity *= 0.1
                            }

                            var newValue =
                                startValue
                                + Int(
                                    round(
                                        Float(gesture.translation.width)
                                            * sensitivity
                                    )
                                )

                            if !isZeroPermitted && newValue == 0 {
                                newValue = gesture.translation.width >= 0 ? 1 : -1
                            }

                            value = newValue
                            text = format(newValue)
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                            isDragging = false
                        }
                )
            
            Spacer()

            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, newValue in
                    guard !isDragging else {
                        return
                    }

                    guard let number = Int(newValue) else {
                        return
                    }

                    if number == 0 && !isZeroPermitted {
                        return
                    }

                    value = number
                }
            
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(alignment: .leading)
            }
        }
        .onAppear {
            text = format(value)
        }
        .onChange(of: value) { _, newValue in
            guard !isDragging else {
                return
            }

            if Int(text) != newValue {
                text = format(newValue)
            }
        }
    }

    private func format(_ value: Int) -> String {
        String(value)
    }
}

func safelyCheckUInt(_ value: Int) -> UInt32 {
    if value < 0 {
        return 0
    } else {
        return UInt32(value)
    }
}

struct UIntField: View {
    @Binding var value: UInt32

    let title: String
    let unit: String
    let isZeroPermitted: Bool
    let dragSensitivity: Float

    @State private var text: String = ""
    @State private var dragStartValue: UInt32?
    @State private var isDragging = false

    init(
        _ title: String,
        value: Binding<UInt32>,
        unit: String,
        isZeroPermitted: Bool = false,
        dragSensitivity: Float = 0.1
    ) {
        self.title = title
        self._value = value
        self.unit = unit
        self.isZeroPermitted = isZeroPermitted
        self.dragSensitivity = dragSensitivity
    }

    var body: some View {
        HStack {
            Text(title)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if dragStartValue == nil {
                                dragStartValue = value
                                isDragging = true
                            }

                            guard let startValue = dragStartValue else {
                                return
                            }

                            var sensitivity = dragSensitivity

                            if NSEvent.modifierFlags.contains(.shift) {
                                sensitivity *= 0.1
                            }

                            let delta = Int(
                                round(
                                    Float(gesture.translation.width) * sensitivity
                                )
                            )

                            var signedValue = Int(startValue) + delta

                            signedValue = max(signedValue, 0)

                            var newValue = UInt32(signedValue)

                            if !isZeroPermitted && newValue == 0 {
                                newValue = 1
                            }

                            value = newValue
                            text = format(Int(newValue))
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                            isDragging = false
                        }
                )
            
            Spacer()

            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, newValue in
                    guard !isDragging else {
                        return
                    }

                    guard let number = Int(newValue) else {
                        return
                    }

                    if number == 0 && !isZeroPermitted {
                        return
                    }

                    value = safelyCheckUInt(number)
                }
            
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(alignment: .leading)
            }
        }
        .onAppear {
            text = format(Int(value))
        }
        .onChange(of: value) { _, newValue in
            guard !isDragging else {
                return
            }

            if safelyCheckUInt(Int(text) ?? -1) != newValue {
                text = format(Int(newValue))
            }
        }
    }

    private func format(_ value: Int) -> String {
        String(value)
    }
}

struct FloatField: View {
    @Binding var value: Float

    let title: String
    let unit: String
    let isZeroPermitted: Bool
    let dragSensitivity: Float

    @State private var text: String = ""
    @State private var dragStartValue: Float?
    @State private var isDragging = false

    init(
        _ title: String,
        value: Binding<Float>,
        unit: String,
        isZeroPermitted: Bool = false,
        dragSensitivity: Float = 0.01
    ) {
        self.title = title
        self._value = value
        self.unit = unit
        self.isZeroPermitted = isZeroPermitted
        self.dragSensitivity = dragSensitivity
    }

    var body: some View {
        HStack {
            Text(title)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if dragStartValue == nil {
                                dragStartValue = value
                                isDragging = true
                            }

                            guard let startValue = dragStartValue else {
                                return
                            }

                            var sensitivity = dragSensitivity

                            if NSEvent.modifierFlags.contains(.shift) {
                                sensitivity *= 0.1
                            }

                            var newValue =
                                startValue
                                + Float(gesture.translation.width) * sensitivity

                            if !isZeroPermitted && abs(newValue) < 0.000001 {
                                newValue = sensitivity
                            }

                            value = newValue
                            text = format(newValue)
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                            isDragging = false
                        }
                )
            
            Spacer()

            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, newValue in
                    guard !isDragging else {
                        return
                    }

                    guard let number = Float(newValue) else {
                        return
                    }

                    if number == 0 && !isZeroPermitted {
                        return
                    }

                    value = number
                }

            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(alignment: .leading)
            }
        }
        .onAppear {
            text = format(value)
        }
        .onChange(of: value) { _, newValue in
            guard !isDragging else {
                return
            }

            if Float(text) != newValue {
                text = format(newValue)
            }
        }
    }

    private func format(_ value: Float) -> String {
        String(format: "%.3g", value)
    }
}

class MTLSyncBuffer<T> {
    private var array: [T]
    private var buffer: MTLBuffer!
    private let device: MTLDevice
    
    var count: Int {
        array.count
    }
    
    init(device: MTLDevice, values: [T] = []) {
        array = values
        self.device = device
        
        remakeBuffer()
    }
    
    func syncListToBuffer() {
        _ = array.withUnsafeBytes { bytes in
            memcpy(buffer.contents(), bytes.baseAddress!, bytes.count)
        }
    }
    
    func syncBufferToList() {
        let count = array.count
        let ptr = buffer.contents().bindMemory(to: T.self, capacity: count)
        array = Array(UnsafeBufferPointer(start: ptr, count: count))
    }
    
    private func syncElementToBuffer(_ index: Int) {
        let destination = buffer.contents()
            .advanced(by: index * MemoryLayout<T>.stride)

        _ = withUnsafePointer(to: &array[index]) { source in
            memcpy(
                destination,
                source,
                MemoryLayout<T>.stride
            )
        }
    }
    
    func remakeBuffer() {
        let size = MemoryLayout<T>.stride * array.count
        
        guard size > 0 else {
            fatalError("Cannot create a zero-length pointer")
        }
        
        buffer = device.makeBuffer(bytes: array, length: size, options: .storageModeShared)
    }
    
    subscript(index: Int) -> T {
        get {
            array[index]
        }
        
        set {
            array[index] = newValue
            syncElementToBuffer(index)
        }
        
        _modify {
            defer {
                syncElementToBuffer(index)
            }
            
            yield &array[index]
        }
    }
    
    func append(_ newElement: T) {
        array.append(newElement)
        remakeBuffer()
    }
    
    func removeAll() {
        array.removeAll()
        remakeBuffer()
    }
    
    func remove(at i: Int) {
        array.remove(at: i)
        remakeBuffer()
    }
    
    func assign(new: [T]) {
        array = new
        remakeBuffer()
    }
    
    func setAtEncoder(_ encoder: MTLComputeCommandEncoder, index: Int) {
        encoder.setBuffer(buffer, offset: 0, index: index)
    }

    func addBarrier(to encoder: MTLComputeCommandEncoder) {
        encoder.memoryBarrier(resources: [buffer])
    }
    
    func setAtVertexBuffer(_ encoder: MTLRenderCommandEncoder, index: Int) {
        encoder.setVertexBuffer(buffer, offset: 0, index: index)
    }
    
    func set(_ elem: T, at: Int) {
        if at > array.count {
            fatalError("Tried to access past the bounds of the array")
        }
        array[at] = elem
        syncElementToBuffer(at)
    }
    
    @available(*, deprecated, message: "Try not to access internal arrays or buffers")
    func getArray() -> [T] {
        return array
    }
    
    @available(*, deprecated, message: "Try not to access internal arrays or buffers")
    func getBuffer() -> MTLBuffer {
        return buffer
    }
}

final class Reference<T> {
    var value: T?

    init(_ value: T? = nil) {
        self.value = value
    }

    func unwrap() -> T {
        guard let value else {
            fatalError("Tried to unwrap a null reference")
        }

        return value
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
