//
//  Inspector.swift
//  Maxwell
//
//  Created by Max Van den Eynde on 31/08/2026.
//

import Foundation
import SwiftUI

struct InspectorSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title3)
                .bold()
                .padding(.bottom, 2)
            
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding(.top, 4)
    }
}

enum InspectorSelection: Equatable {
    case none
    case source(Int)
}

struct Inspector: View {
    @State var elementName: String = "<none>"
    @State private var width: CGFloat = 300
    @Binding var settings: SimulationSettings
    @Binding var renderer: Renderer
    @Binding var selection: InspectorSelection
    
    @State private var desiredCellsPerWavelength: Int = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(elementName)
                    .font(.title)
                    .bold()
                Divider()
                if case .source = selection {
                    sourceSection
                }
                gridSection
                environmentSection
                visualizationSection
            }
            .frame(maxWidth: 300)
            .padding(30)
        }
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.4)
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: 40)
                )
        }
        .onAppear {
            updateElementName()
        }
        .onChange(of: selection) {
            updateElementName()
        }
    }
    
    var sourceSection: some View {
        let _ = renderer.sourcesRevision
        return InspectorSectionView(title: "Source Configuration") {
            Text("Position in Grid:")
                .bold()
            HStack() {
                Spacer()
                Button {
                    sourceSetProperty(\.x, value: 1)
                } label: {
                    Image(systemName: "align.horizontal.left")
                        .resizable()
                        .foregroundStyle(.blue)
                        .padding(3)
                        .frame(width: 40, height: 40)
                }
                .focusable(false)
                .cursor(.pointingHand)
                .buttonStyle(.glass)
                Button {
                    sourceSetProperty(\.x, value: safelyCheckUInt(settings.Nx / 2))
                } label: {
                    Image(systemName: "align.horizontal.center")
                        .resizable()
                        .foregroundStyle(.blue)
                        .padding(3)
                        .frame(width: 40, height: 40)
                }
                .focusable(false)
                .cursor(.pointingHand)
                .buttonStyle(.glass)
                Button {
                    sourceSetProperty(\.x, value: safelyCheckUInt(settings.Nx - 1))
                } label: {
                    Image(systemName: "align.horizontal.right")
                        .resizable()
                        .foregroundStyle(.blue)
                        .padding(3)
                        .frame(width: 40, height: 40)
                }
                .focusable(false)
                .cursor(.pointingHand)
                .buttonStyle(.glass)
                Spacer()
            }
            HStack() {
                Spacer()
                Button {
                    sourceSetProperty(\.y, value: safelyCheckUInt(settings.Ny - 1))
                } label: {
                    Image(systemName: "align.vertical.top")
                        .resizable()
                        .foregroundStyle(.blue)
                        .padding(3)
                        .frame(width: 40, height: 40)
                }
                .focusable(false)
                .cursor(.pointingHand)
                .buttonStyle(.glass)
                Button {
                    sourceSetProperty(\.y, value: safelyCheckUInt(settings.Ny / 2))
                } label: {
                    Image(systemName: "align.vertical.center")
                        .resizable()
                        .foregroundStyle(.blue)
                        .padding(3)
                        .frame(width: 40, height: 40)
                }
                .focusable(false)
                .cursor(.pointingHand)
                .buttonStyle(.glass)
                Button {
                    sourceSetProperty(\.y, value: 1)
                } label: {
                    Image(systemName: "align.vertical.bottom")
                        .resizable()
                        .foregroundStyle(.blue)
                        .padding(3)
                        .frame(width: 40, height: 40)
                }
                .focusable(false)
                .cursor(.pointingHand)
                .buttonStyle(.glass)
                Spacer()
            }
            HStack {
                UIntField("X:", value: sourceBinding(\.x, default: 0), unit: "")
                Spacer()
                UIntField("Y:", value: sourceBinding(\.y, default: 0), unit: "")
            }
            
            FloatField("Frequency", value: sourceBinding(\.frequency, default: 0), unit: "GHz")
            FloatField("Amplitude", value: sourceBinding(\.amplitude, default: 0), unit: "V/m")
            FloatField("Phase", value: sourceBinding(\.phase, default: 0), unit: "rad")
            
            IntField("Cells per wavelength", value: $desiredCellsPerWavelength, unit: "cpw")
            VStack(spacing: 3) {
                Button {
                    let freq = calculateFrequency(cellsPerWavelength: Float(desiredCellsPerWavelength), settings: settings)
                    sourceSetProperty(\.frequency, value: freq)
                } label: {
                    Text("Match Frequency to Dimensions")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .cursor(.pointingHand)
                .buttonStyle(.plain)
                .glassEffect()
                .focusable(false)
                HStack {
                    Spacer()
                    Text("Matching calculates the frequency based on the cells per wavelength parameter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            
            HStack {
                Text("Source Type")
                Spacer()
                Picker("", selection: sourceBinding(\.type, default: 0))
                {
                    ForEach(SourceType.allCases, id: \.rawValue) { mode in
                        Text(mode.name)
                            .tag(mode.rawValue)
                    }
                }
            }
            
            HStack {
                Text("Emission Form")
                Spacer()
                Picker("", selection: sourceBinding(\.form, default: 0))
                {
                    ForEach(SourceForm.allCases, id: \.rawValue) { mode in
                        Text(mode.name)
                            .tag(mode.rawValue)
                    }
                }
            }
            
            Button {
                renderer.removeSource(i: getSourceIndex())
                selection = .none
            } label: {
                Text("Remove Source")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .cursor(.pointingHand)
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.35, green: 0.0, blue: 0.0))
            .glassEffect(.regular.tint(.red))
            .focusable(false)
            
            Divider()
        }
    }
    
    private func getSourceIndex() -> Int {
        switch selection {
        case .none:
            return -1
        case .source(let int):
            return int
        }
    }
    
    private func updateElementName() {
        switch selection {
        case .none:
            elementName = "World"

        case let .source(i):
            let name = renderer.getNameForSource(i: i)
            elementName = name ?? "Source \(i)"
        }
    }
    
    private func sourceSetProperty<T>(_ keyPath: WritableKeyPath<ElectricSource, T>, value: T) {
        guard case let .source(i) = selection else {
            return
        }
        
        var oldSource = renderer.getSource(i: i)!
        oldSource[keyPath: keyPath] = value

        renderer.updateSource(i: i, source: oldSource)
    }
    
    private func sourceBinding<T>(_ keyPath: WritableKeyPath<ElectricSource, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                guard case let .source(i) = selection,
                      let source = renderer.getSource(i: i)
                else {
                    return defaultValue
                }

                return source[keyPath: keyPath]
            },

            set: { newValue in
                sourceSetProperty(keyPath, value: newValue)
            }
        )
    }
    
    var gridSection: some View {
        InspectorSectionView(title: "Simulation") {
            HStack {
                IntField("Nx", value: $settings.Nx, unit: "")
                Spacer()
                IntField("Ny", value: $settings.Ny, unit: "")
            }
            VStack(spacing: 3) {
                Button {
                    let gridConfig = gridConfiguration(for: renderer.drawableSize, maxCells: settings.Nx, physicalWidth: settings.width)
                    settings.Nx = gridConfig.nx
                    settings.Ny = gridConfig.ny
                    settings.width = gridConfig.width
                    settings.height = gridConfig.height
                } label: {
                    Text("Match Grid to Screen")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .cursor(.pointingHand)
                .buttonStyle(.plain)
                .glassEffect()
                .focusable(false)
                HStack {
                    Spacer()
                    Text("Matching uses Nx as the maximum number of cells and width as the physical width from which all other properties will be calculated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            
            HStack {
                FloatField("W (m):", value: $settings.width, unit: "")
                Spacer()
                FloatField("H (m):", value: $settings.height, unit: "")
            }
            
            IntField("PML Thickness", value: $settings.pmlThickness, unit: "")
            
            IntField("Steps per frame", value: $settings.stepsPerFrame, unit: "")
            
            Divider()
        }
    }
    
    var environmentSection: some View {
        InspectorSectionView(title: "Environment") {
            Toggle(isOn: $settings.reflectWalls) {
                Text("Walls Reflect Waves")
            }
            
            Divider()
        }
    }
    
    var visualizationSection: some View {
        InspectorSectionView(title: "Visualization") {
            FloatField("Visualization Scale", value: $settings.visualizationScale, unit: "")
            FloatField("Blur Amount", value: $settings.blurAmount, unit: "")
        }
    }
}

#Preview {
    Inspector(settings: .constant(.init()), renderer: .constant(.init(settings: .init())), selection: .constant(.source(0)))
        .padding()
        .preferredColorScheme(.dark)
}
