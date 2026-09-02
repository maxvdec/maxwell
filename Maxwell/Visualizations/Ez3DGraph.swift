//
//  Ez3DGraph.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 02/09/2026.
//

import Charts
import SwiftUI

struct EzFieldSnapshot: Sendable {
    let nx: Int
    let ny: Int

    let physicalWidth: Double
    let physicalHeight: Double

    let values: [Double]

    subscript(x: Int, y: Int) -> Double {
        values[y * nx + x]
    }

    func value(x: Double, z: Double) -> Double {
        guard nx > 1,
              ny > 1,
              physicalWidth > 0,
              physicalHeight > 0
        else {
            return 0
        }

        let gridX = max(
            0,
            min(1, x / physicalWidth)
        ) * Double(nx - 1)

        let gridY = max(
            0,
            min(1, z / physicalHeight)
        ) * Double(ny - 1)

        let x0 = Int(gridX.rounded(.down))
        let y0 = Int(gridY.rounded(.down))
        let x1 = min(x0 + 1, nx - 1)
        let y1 = min(y0 + 1, ny - 1)

        let tx = gridX - Double(x0)
        let ty = gridY - Double(y0)

        let top = self[x0, y0] * (1 - tx) + self[x1, y0] * tx
        let bottom = self[x0, y1] * (1 - tx) + self[x1, y1] * tx

        return top * (1 - ty) + bottom * ty
    }
}

struct Ez3DVisualizationView: View {
    let renderer: Renderer

    @State private var pose: Chart3DPose = .default
    @State private var selectedX: Double?
    @State private var selectedZ: Double?
    @State private var recentPeaks: [Double] = []
    @State private var displayedAmplitude = 0.000001

    private let fieldGradient = Gradient(colors: [
        .purple,
        .blue,
        .cyan,
        .white,
        .yellow,
        .orange,
        .red
    ])

    var body: some View {
        Group {
            if let snapshot = renderer.ez3DSnapshot {
                chart(snapshot)
                    .onChange(
                        of: snapshot.values,
                        initial: true
                    ) { _, values in
                        updateAmplitude(values)
                    }
            } else {
                ProgressView("Preparing 3D field…")
            }
        }
    }

    @ViewBuilder
    private func chart(
        _ snapshot: EzFieldSnapshot
    ) -> some View {
        let range = -displayedAmplitude...displayedAmplitude

        Chart3D {
            SurfacePlot(
                x: "X (m)",
                y: "Ez (V/m)",
                z: "Y (m)"
            ) { x, z in
                snapshot.value(
                    x: x,
                    z: z
                )
            }
            .foregroundStyle(
                .heightBased(
                    fieldGradient,
                    yRange: CGFloat(range.lowerBound)...CGFloat(range.upperBound)
                )
            )
            .roughness(0.28)

            if let point = selectedPoint(in: snapshot) {
                PointMark(
                    x: .value("X (m)", point.x),
                    y: .value("Ez (V/m)", point.value),
                    z: .value("Y (m)", point.z)
                )
                .foregroundStyle(.white)
                .symbol(.sphere)
                .symbolSize(70)
            }
        }
        .chartXScale(
            domain: 0...snapshot.physicalWidth,
            range: -0.5...0.5
        )
        .chartZScale(
            domain: 0...snapshot.physicalHeight,
            range: -0.5...0.5
        )
        .chartYScale(
            domain: range,
            range: -0.5...0.5
        )
        .chartXAxis {
            AxisMarks(
                format: FloatingPointFormatStyle<Double>.number
                    .precision(.fractionLength(2))
            )
        }
        .chartZAxis {
            AxisMarks(
                format: FloatingPointFormatStyle<Double>.number
                    .precision(.fractionLength(2))
            )
        }
        .chartYAxis {
            AxisMarks(
                format: FloatingPointFormatStyle<Double>.number
                    .notation(.scientific)
                    .precision(.significantDigits(3))
            )
        }
        .chartXAxisLabel("X (m)")
        .chartYAxisLabel("Ez (V/m)")
        .chartZAxisLabel("Y (m)")
        .chartXSelection(value: $selectedX)
        .chartZSelection(value: $selectedZ)
        .chart3DPose($pose)
        .chart3DCameraProjection(.perspective)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                colorLegend(range: range)

                if let point = selectedPoint(in: snapshot) {
                    pointReadout(point)
                } else {
                    Text("Move across the surface to inspect a point")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.leading, 76)
            .padding(.top, 72)
            .allowsHitTesting(false)
        }
    }

    private func updateAmplitude(_ values: [Double]) {
        let peak = values
            .filter(\.isFinite)
            .map(abs)
            .max() ?? 0

        recentPeaks.append(peak)

        if recentPeaks.count > 120 {
            recentPeaks.removeFirst(recentPeaks.count - 120)
        }

        displayedAmplitude = max(
            (recentPeaks.max() ?? 0) * 1.08,
            0.000001
        )
    }

    private func selectedPoint(
        in snapshot: EzFieldSnapshot
    ) -> (x: Double, z: Double, value: Double)? {
        guard let selectedX,
              let selectedZ
        else {
            return nil
        }

        let x = max(0, min(snapshot.physicalWidth, selectedX))
        let z = max(0, min(snapshot.physicalHeight, selectedZ))

        return (
            x,
            z,
            snapshot.value(x: x, z: z)
        )
    }

    private func colorLegend(
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ez field")
                .font(.caption)
                .bold()

            HStack(spacing: 8) {
                LinearGradient(
                    gradient: fieldGradient,
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(width: 12, height: 96)
                .clipShape(.capsule)

                VStack(alignment: .leading) {
                    Text(formatFieldValue(range.upperBound))
                    Spacer()
                    Text("0 V/m")
                    Spacer()
                    Text(formatFieldValue(range.lowerBound))
                }
                .font(.caption2.monospacedDigit())
            }
        }
    }

    private func pointReadout(
        _ point: (x: Double, z: Double, value: Double)
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Selected point")
                .font(.caption)
                .bold()

            Text("x = \(point.x, format: .number.precision(.fractionLength(3))) m")
            Text("y = \(point.z, format: .number.precision(.fractionLength(3))) m")
            Text("Ez = \(formatFieldValue(point.value))")
        }
        .font(.caption.monospacedDigit())
    }

    private func formatFieldValue(_ value: Double) -> String {
        value.formatted(
            .number
                .notation(.scientific)
                .precision(.significantDigits(3))
        ) + " V/m"
    }
}
