//
//  BottomInspector.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 02/09/2026.
//

import Charts
import SwiftUI

@ViewBuilder
private func hoverAnnotation(
    time: Double,
    value: Double,
    source: ElectricSource
) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text("t = \(time * 1e9, specifier: "%.3f") ns")
        Text("Ez = \(value, specifier: "%.3f") V/m")

        if let cycle = cycleNumber(at: time, for: source) {
            Text("Cycle \(cycle)")
                .foregroundStyle(.secondary)
        }
    }
    .font(.caption)
    .padding(10)
    .background {
        RoundedRectangle(cornerRadius: 16)
            .fill(.regularMaterial)
    }
}

struct BottomInspectorView: View {
    @Binding var settings: SimulationSettings
    @Binding var renderer: Renderer
    @Binding var selection: InspectorSelection

    @State private var data: [SourceSample] = []

    @State private var domainInformation = DomainInformation(
        amplitude: 1,
        time: 0...1e-9
    )

    @State private var hoveredTime: Double?
    @State private var hoveredValue: Double?
    
    private var displayedSimulationTime: Double? {
        guard let source = getSource() else {
            return nil
        }

        let simTime = Double(renderer.simTime)
        let range = domainInformation.time
        let width = range.upperBound - range.lowerBound

        guard width > 0 else {
            return nil
        }

        switch SourceForm(rawValue: source.form) {
        case .sine:
            let wrapped =
                (simTime - range.lowerBound)
                    .truncatingRemainder(dividingBy: width)

            return range.lowerBound + wrapped

        case .pulse, .gaussianPulse, .gausianModulated:
            return range.contains(simTime) ? simTime : nil

        case nil:
            return nil
        }
    }

    struct DomainInformation {
        var amplitude: Double
        var time: ClosedRange<Double>
    }

    var body: some View {
        VStack {
            if case .none = selection {
                Text("No source is selected")
                    .foregroundStyle(.secondary)
            } else {
                header

                sourceChart
            }
        }
        .padding(30)
        .frame(maxWidth: 800, maxHeight: 250)
        .glassEffect(
            .regular,
            in: .rect(cornerRadius: 40)
        )
        .onAppear {
            guard getSource() != nil else {
                return
            }

            autoFit()
        }
        .onChange(of: selection) {
            guard getSource() != nil else {
                return
            }
            
            autoFit()
        }
        .onChange(of: renderer.sourcesRevision) {
            guard getSource() != nil else {
                return
            }
            updateSamples()
        }
    }

    private var header: some View {
        HStack {
            Text(
                "Emission for source: \(renderer.getNameForSource(i: getSourceIndex())!)"
            )
            .bold()

            Spacer()

            Button {
                withAnimation {
                    autoFit()
                }
            } label: {
                Label("Auto Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Fit the graph to the current source waveform")
        }
    }

    private var sourceChart: some View {
        Chart {
            ForEach(data) { sample in
                LineMark(
                    x: .value("Time", sample.time),
                    y: .value("Ez", sample.value)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.linear)
            }
            
            RuleMark(
                x: .value("Current Time", displayedSimulationTime ?? 0)
            )
            
            if let hoveredTime,
               let hoveredValue {
                
                RuleMark(
                    x: .value("Hovered Time", hoveredTime)
                )
                .foregroundStyle(.secondary)
                
                PointMark(
                    x: .value("Time", hoveredTime),
                    y: .value("Ez", hoveredValue)
                )
                .symbolSize(35)
                
                PointMark(
                    x: .value("Time", hoveredTime),
                    y: .value("Ez", hoveredValue)
                )
                .annotation(position: .top) {
                    if let source = getSource() {
                        hoverAnnotation(
                            time: hoveredTime,
                            value: hoveredValue,
                            source: source
                        )
                    }
                }
            }
        }
        .chartXScale(domain: domainInformation.time)
        .chartYScale(domain: -domainInformation.amplitude...domainInformation.amplitude)
        .chartXAxis {
            AxisMarks { value in
                AxisTick()
                
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(
                            "\(seconds * 1e9, specifier: "%.2f")"
                        )
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxisLabel("Time (ns)")
        .chartYAxisLabel("Ez (V/m)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else {
                                return
                            }
                            
                            let frame = geometry[plotFrame]
                            let x = location.x - frame.origin.x
                            
                            guard
                                x >= 0,
                                x <= frame.width,
                                let time: Double = proxy.value(
                                    atX: x,
                                    as: Double.self
                                )
                                    else {
                                hoveredTime = nil
                                hoveredValue = nil
                                return
                            }
                            
                            hoveredTime = time
                            
                            if let source = getSource() {
                                hoveredValue = Double(
                                    source.value(
                                        at: Float(time)
                                    )
                                )
                            }
                            
                        case .ended:
                            hoveredTime = nil
                            hoveredValue = nil
                        }
                    }
            }
        }
    }

    private func updateSamples() {
        guard let source = getSource() else {
            data = []
            return
        }

        let range = domainInformation.time

        data = getSourceSamples(
            for: source,
            from: range.lowerBound,
            to: range.upperBound
        )

        if let hoveredTime {
            hoveredValue = Double(
                source.value(
                    at: Float(hoveredTime)
                )
            )
        }
    }

    private func autoFit() {
        guard let source = getSource() else {
            return
        }

        let range = source.previewTimeRange

        domainInformation.time = range

        domainInformation.amplitude = max(
            abs(Double(source.amplitude)) * 1.1,
            0.001
        )

        data = getSourceSamples(
            for: source,
            from: range.lowerBound,
            to: range.upperBound
        )
    }

    private func getSource() -> ElectricSource? {
        guard
            case let .source(i) = selection,
            let source = renderer.getSource(i: i)
        else {
            return nil
        }

        return source
    }

    private func getSourceIndex() -> Int {
        switch selection {
        case .none:
            return -1

        case .source(let index):
            return index
        }
    }
}
