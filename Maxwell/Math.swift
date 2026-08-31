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
