import Metal

final class EnergyBloomExtractPass: ComputePass {
    var inputTexture: Reference<MTLTexture>
    var outputTexture: MTLTexture

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState

    init(
        device: MTLDevice,
        library: MTLLibrary,
        inputTexture: Reference<MTLTexture>
    ) {
        self.device = device
        self.inputTexture = inputTexture
        outputTexture = createRenderTexture(
            device: device,
            width: 1,
            height: 1
        )

        let function = library.makeFunction(name: "extractEnergyBloom")!
        pipeline = try! device.makeComputePipelineState(function: function)
    }

    func updateTexture() {
        let input = inputTexture.unwrap()

        if outputTexture.width != input.width ||
            outputTexture.height != input.height {
            outputTexture = createRenderTexture(
                device: device,
                width: input.width,
                height: input.height
            )
        }
    }

    func encodeCompute(
        _ commandBuffer: MTLCommandBuffer,
        uniforms: inout Uniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let input = inputTexture.unwrap()
        var threshold: Float = 0.16

        encoder.label = "Extract Energy Bloom"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(
            &threshold,
            length: MemoryLayout<Float>.stride,
            index: 0
        )

        dispatch(
            encoder,
            width: input.width,
            height: input.height
        )
        encoder.endEncoding()
    }

    private func dispatch(
        _ encoder: MTLComputeCommandEncoder,
        width: Int,
        height: Int
    ) {
        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = max(
            1,
            pipeline.maxTotalThreadsPerThreadgroup / groupWidth
        )

        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: groupWidth,
                height: groupHeight,
                depth: 1
            )
        )
    }
}

final class EnergyGlowCompositePass: ComputePass {
    var energyTexture: Reference<MTLTexture>
    var bloomTexture: Reference<MTLTexture>
    var outputTexture: MTLTexture

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState

    init(
        device: MTLDevice,
        library: MTLLibrary,
        energyTexture: Reference<MTLTexture>,
        bloomTexture: Reference<MTLTexture>
    ) {
        self.device = device
        self.energyTexture = energyTexture
        self.bloomTexture = bloomTexture
        outputTexture = createRenderTexture(
            device: device,
            width: 1,
            height: 1
        )

        let function = library.makeFunction(name: "compositeEnergyGlow")!
        pipeline = try! device.makeComputePipelineState(function: function)
    }

    func updateTexture() {
        let input = energyTexture.unwrap()

        if outputTexture.width != input.width ||
            outputTexture.height != input.height {
            outputTexture = createRenderTexture(
                device: device,
                width: input.width,
                height: input.height
            )
        }
    }

    func encodeCompute(
        _ commandBuffer: MTLCommandBuffer,
        uniforms: inout Uniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let energy = energyTexture.unwrap()

        encoder.label = "Composite Energy Glow"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(energy, index: 0)
        encoder.setTexture(bloomTexture.unwrap(), index: 1)
        encoder.setTexture(outputTexture, index: 2)

        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = max(
            1,
            pipeline.maxTotalThreadsPerThreadgroup / groupWidth
        )

        encoder.dispatchThreads(
            MTLSize(
                width: energy.width,
                height: energy.height,
                depth: 1
            ),
            threadsPerThreadgroup: MTLSize(
                width: groupWidth,
                height: groupHeight,
                depth: 1
            )
        )
        encoder.endEncoding()
    }
}
