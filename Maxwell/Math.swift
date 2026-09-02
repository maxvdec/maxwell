//
//  Math.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 31/08/2026.
//

import Foundation

let c: Float = 299_792_459.0

func calculateDt(dx: Float, dy: Float) -> Float {
    let dtMaxDenom = sqrt(1.0 / (dx * dx) + 1.0 / (dy * dy))
    let dtMax = 1.0 / (c * dtMaxDenom)
    let courant: Float = 0.95
    return courant * dtMax
}

func calculateFrequency(cellsPerWavelength: Float, settings: SimulationSettings) -> Float {
    let dx = settings.width / Float(settings.Nx)
    let wavelength = dx * cellsPerWavelength
    let frequency = c / wavelength
    return frequency / 1e9
}

struct GridConfiguration {
    let nx: Int
    let ny: Int

    let width: Float
    let height: Float
}

func gridConfiguration(
    for resolution: CGSize,
    maxCells: Int = 500,
    physicalWidth: Float = 2.0
) -> GridConfiguration {
    guard resolution.width > 0,
          resolution.height > 0
    else {
        return GridConfiguration(
            nx: maxCells,
            ny: maxCells,
            width: physicalWidth,
            height: physicalWidth
        )
    }

    let aspect =
        Float(resolution.width / resolution.height)

    let nx: Int
    let ny: Int

    if aspect >= 1 {
        nx = maxCells
        ny = max(
            1,
            Int(round(Float(maxCells) / aspect))
        )
    } else {
        ny = maxCells
        nx = max(
            1,
            Int(round(Float(maxCells) * aspect))
        )
    }

    let height =
        physicalWidth * Float(ny) / Float(nx)

    return GridConfiguration(
        nx: nx,
        ny: ny,
        width: physicalWidth,
        height: height
    )
}

enum SourceType: UInt32, CaseIterable, Hashable {
    case line = 0
    case point = 1
    case beam = 2

    var name: String {
        switch self {
        case .line: "Line"
        case .point: "Point"
        case .beam: "Gaussian Beam"
        }
    }
}

enum SourceForm: UInt32, CaseIterable, Hashable {
    case sine = 0
    case pulse = 1
    case gaussianPulse = 2
    case gausianModulated = 3

    var name: String {
        switch self {
        case .sine:
            "Sinusoidal wave"
        case .pulse:
            "Simple Pulse"
        case .gaussianPulse:
            "Pure Gaussian"
        case .gausianModulated:
            "Gaussian-modulated Sine"
        }
    }
}

struct GridViewport {
    let nx: Int
    let ny: Int
    let viewSize: CGSize

    func gridPosition(from point: CGPoint) -> SIMD2<UInt32>? {
        guard nx > 0,
              ny > 0,
              viewSize.width > 0,
              viewSize.height > 0
        else {
            return nil
        }

        let u = point.x / viewSize.width
        let v = point.y / viewSize.height

        guard u >= 0,
              u <= 1,
              v >= 0,
              v <= 1
        else {
            return nil
        }

        let x: Int

        if nx == 1 {
            x = 0
        } else {
            x = Int(
                round(
                    u * CGFloat(nx - 1)
                )
            )
        }

        let y: Int

        if ny == 1 {
            y = 0
        } else {
            y = Int(
                round(
                    v * CGFloat(ny - 1)
                )
            )
        }

        return SIMD2(
            UInt32(clamping: x),
            UInt32(clamping: y)
        )
    }

    func screenPosition(
        from gridPosition: SIMD2<UInt32>
    ) -> CGPoint {
        let x: CGFloat

        if nx <= 1 {
            x = 0
        } else {
            x =
                CGFloat(gridPosition.x)
                    / CGFloat(nx - 1)
                    * viewSize.width
        }

        let y: CGFloat

        if ny <= 1 {
            y = 0
        } else {
            y =
                CGFloat(gridPosition.y)
                    / CGFloat(ny - 1)
                    * viewSize.height
        }

        return CGPoint(x: x, y: y)
    }
}

func calculateSigmaMax(pmlPhysical: Float) -> Float {
    let R: Float = 1e-6
    let m: Float = 3
    let eta0: Float = 377
    return -1 * ((m + 1) * log(R) / 2 * eta0 * pmlPhysical)
}

struct SourceSample: Identifiable {
    let id = UUID()
    let time: Double
    let value: Double
}

extension ElectricSource {
    func value(at t: Float) -> Float {
        switch SourceForm(rawValue: form)! {
        case .sine:
            let frequencyHz = frequency * 1e9
            return amplitude * sin(2 * .pi * frequencyHz * t + phase)
        case .pulse:
            let frequencyHz = frequency * 1e9
            if t < (duration / 1e9) {
                return amplitude * sin(2 * .pi * frequencyHz * t + phase)
            } else {
                return 0
            }
        case .gaussianPulse:
            let sigma = (gaussianWidth / 1e9) / 2.35482
            let t0 = 4 * sigma
            return amplitude * exp(-1 * (pow(t - t0, 2) / (2 * pow(sigma, 2))))
        case .gausianModulated:
            let sigma = (gaussianWidth / 1e9) / 2.35482
            let t0 = 4 * sigma
            let gaussian = exp(-1 * (pow(t - t0, 2) / (2 * pow(sigma, 2))))
            let frequencyHz = frequency * 1e9
            let sine = sin(2 * .pi * frequencyHz * (t - t0) + phase)
            return amplitude * gaussian * sine
        }
    }
}

extension ElectricSource {
    var previewTimeRange: ClosedRange<Double> {
        switch SourceForm(rawValue: form)! {
        case .sine:
            let frequencyHz = Double(frequency) * 1e9

            guard frequencyHz > 0 else {
                return 0...1e-9
            }

            let period = 1.0 / frequencyHz

            return 0...(5 * period)

        case .pulse:
            let durationSeconds = Double(duration) * 1e-9
            let frequencyHz = Double(frequency) * 1e9

            guard frequencyHz > 0 else {
                return 0...max(durationSeconds * 1.2, 1e-9)
            }

            let period = 1.0 / frequencyHz

            return 0...(durationSeconds + period)

        case .gaussianPulse:
            let fwhm = Double(gaussianWidth) * 1e-9
            let sigma = fwhm / 2.35482
            let t0 = 4 * sigma

            return 0...(t0 + 4 * sigma)

        case .gausianModulated:
            let fwhm = Double(gaussianWidth) * 1e-9
            let sigma = fwhm / 2.35482
            let t0 = 4 * sigma

            return 0...(t0 + 4 * sigma)
        }
    }
}

func getSourceSamples(for source: ElectricSource, from start: Double, to end: Double, count: Int = 300) -> [SourceSample] {
    guard count >= 2 else {
        return [
            SourceSample(
                time: start,
                value: Double(source.value(at: Float(start)))
            )
        ]
    }

    return (0 ..< count).map { i in
        let alpha = Double(i) / Double(count - 1)
        let t = start + alpha * (end - start)

        return SourceSample(
            time: t,
            value: Double(source.value(at: Float(t)))
        )
    }
}

func cycleNumber(at time: Double, for source: ElectricSource) -> Int? {
    let frequencyHz = Double(source.frequency) * 1e9

    guard frequencyHz > 0 else {
        return nil
    }

    let period = 1.0 / frequencyHz

    return Int(floor(time / period)) + 1
}
