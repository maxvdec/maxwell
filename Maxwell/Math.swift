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
        case .beam: "Beam"
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
