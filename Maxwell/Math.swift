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
    return courant * dtMax;
}

func calculateFrequency(cellsPerWavelength: Float, settings: inout SimulationSettings) {
    let dx = settings.width / Float(settings.Nx)
    let wavelength = dx * cellsPerWavelength
    let frequency = c / wavelength
    settings.sourceFrequency = (frequency / 1e9)
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
          resolution.height > 0 else {
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
