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
    case collider(UUID)
}

struct Inspector: View {
    @State var elementName: String = "<none>"
    @State private var isEditingName = false
    @State private var editingName = ""

    @FocusState private var nameFieldFocused: Bool
    
    @State private var width: CGFloat = 300
    @Binding var settings: SimulationSettings
    @Binding var renderer: Renderer
    let editor: EditorState
    @Binding var selection: InspectorSelection
    
    @State private var desiredCellsPerWavelength: Int = 20
    
    private var isEditableSelection: Bool {
        switch selection {
        case .source, .collider:
            return true
        case .none:
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    if isEditingName {
                        TextField("", text: $editingName)
                            .textFieldStyle(.plain)
                            .font(.title)
                            .bold()
                            .focused($nameFieldFocused)
                            .onSubmit {
                                commitNameEdit()
                            }
                            .onExitCommand {
                                cancelNameEdit()
                            }
                    } else {
                        Text(elementName)
                            .font(.title)
                            .bold()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                beginNameEdit()
                            }
                            .cursor(isEditableSelection ? .iBeam : .arrow)
                    }
                }
                Divider()
                if case let .source(i) = selection,
                   renderer.getSource(i: i) != nil {
                    sourceSection
                }
                if case let .collider(id) = selection,
                   editor.collider(id: id) != nil {
                    colliderSection(id: id)
                }
                gridSection
                environmentSection
                visualizationSection
            }
            .frame(maxWidth: 300)
            .padding(30)
        }
        .glassEffect(
            .regular,
            in: .rect(cornerRadius: 40)
        )
        .onAppear {
            updateElementName()
        }
        .onChange(of: selection) {
            isEditingName = false
            nameFieldFocused = false

            updateElementName()
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused && isEditingName {
                commitNameEdit()
            }
        }
    }
    
    private func beginNameEdit() {
        guard isEditableSelection else {
            return
        }

        editingName = elementName
        isEditingName = true

        DispatchQueue.main.async {
            nameFieldFocused = true
        }
    }
    
    private func commitNameEdit() {
        let name =
            editingName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !name.isEmpty else {
            cancelNameEdit()
            return
        }

        switch selection {
        case let .source(i):
            renderer.renameSource(
                i: i,
                name: name
            )
        case let .collider(id):
            guard var collider = editor.collider(id: id) else {
                cancelNameEdit()
                return
            }

            collider.name = name
            editor.updateCollider(collider)
        case .none:
            cancelNameEdit()
            return
        }

        elementName = name

        isEditingName = false
        nameFieldFocused = false
    }
    
    private func cancelNameEdit() {
        editingName = elementName
        isEditingName = false
        nameFieldFocused = false
    }
    
    var sourceSection: some View {
        let _ = renderer.sourcesRevision
        return InspectorSectionView(title: "Source Configuration") {
            Text("Position in Grid:")
                .bold()
            HStack {
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
            HStack {
                Spacer()
                Button {
                    sourceSetProperty(\.y, value: 1)
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
                    sourceSetProperty(\.y, value: safelyCheckUInt(settings.Ny - 1))
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
            if getSourceType() != .point {
                UIntField("Width", value: sourceBinding(\.length, default: 0), unit: "")
                FloatField("Rotation", value: sourceBinding(\.rotation, default: 0), unit: "°")
            }
            
            if getSourceType() == .beam {
                FloatField("Beam Waist", value: sourceBinding(\.beamWaist, default: 0), unit: "")
            }
            
            FloatField("Amplitude", value: sourceBinding(\.amplitude, default: 0), unit: "V/m")
            if getSourceForm() != .gaussianPulse {
                FloatField("Frequency", value: sourceBinding(\.frequency, default: 0), unit: "GHz")
                FloatField("Phase", value: sourceBinding(\.phase, default: 0), unit: "rad")
            }
            
            if getSourceForm() == .pulse {
                FloatField(
                    "Duration",
                    value: sourceBinding(
                        \.duration,
                        default: 0
                    ),
                    unit: "ns"
                )

                FloatField(
                    "Duration in Cycles",
                    value: sourceBinding(
                        \.duration,
                        default: 0,
                        get: { durationNs in
                            let frequencyGHz =
                                sourceGetProperty(\.frequency) ?? 0

                            return durationNs * frequencyGHz
                        },
                        set: { cycles in
                            let frequencyGHz =
                                sourceGetProperty(\.frequency) ?? 0

                            guard frequencyGHz != 0 else {
                                return 0
                            }

                            return cycles / frequencyGHz
                        }
                    ),
                    unit: "cy."
                )
            }
            
            if getSourceForm() == .gaussianPulse || getSourceForm() == .gausianModulated {
                FloatField(
                    "Gaussian Width",
                    value: sourceBinding(
                        \.gaussianWidth,
                        default: 0
                    ),
                    unit: "ns"
                )
            }
            
            if getSourceForm() == .gausianModulated {
                FloatField(
                    "Width in Cycles",
                    value: sourceBinding(
                        \.gaussianWidth,
                        default: 0,
                        get: { widthNs in
                            let frequencyGHz =
                                sourceGetProperty(\.frequency) ?? 0

                            return widthNs * frequencyGHz
                        },
                        set: { cycles in
                            let frequencyGHz =
                                sourceGetProperty(\.frequency) ?? 0

                            guard frequencyGHz != 0 else {
                                return 0
                            }

                            return cycles / frequencyGHz
                        }
                    ),
                    unit: "cy."
                )
            }
            
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
                Picker("", selection: sourceBinding(\.type, default: 0)) {
                    ForEach(SourceType.allCases, id: \.rawValue) { mode in
                        Text(mode.name)
                            .tag(mode.rawValue)
                    }
                }
            }
            
            HStack {
                Text("Emission Form")
                Spacer()
                Picker("", selection: sourceBinding(\.form, default: 0)) {
                    ForEach(SourceForm.allCases, id: \.rawValue) { mode in
                        Text(mode.name)
                            .tag(mode.rawValue)
                    }
                }
            }
            
            Button {
                let index = getSourceIndex()

                selection = .none
                renderer.removeSource(i: index)
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
    
    private func getSourceForm() -> SourceForm? {
        guard
            case let .source(i) = selection,
            let source = renderer.getSource(i: i)
        else {
            return nil
        }

        return SourceForm(rawValue: source.form)
    }
    
    private func getSourceType() -> SourceType? {
        guard
            case let .source(i) = selection,
            let source = renderer.getSource(i: i)
        else {
            return nil
        }

        return SourceType(rawValue: source.type)
    }
    
    private func getSourceIndex() -> Int {
        switch selection {
        case .none:
            return -1
        case let .source(int):
            return int
        case .collider:
            return -1
        }
    }
    
    private func updateElementName() {
        switch selection {
        case .none:
            elementName = "World"

        case let .source(i):
            let name =
                renderer.getNameForSource(i: i)

            elementName =
                name ?? "Source \(i)"

        case let .collider(id):
            elementName =
                editor.collider(id: id)?.name ?? "Collider"
        }

        editingName = elementName
    }
    
    private func sourceSetProperty<T>(
        _ keyPath: WritableKeyPath<ElectricSource, T>,
        value: T
    ) {
        guard
            case let .source(i) = selection,
            var source = renderer.getSource(i: i)
        else {
            return
        }

        source[keyPath: keyPath] = value
        renderer.updateSource(i: i, source: source)
    }
    
    private func sourceGetProperty<T>(
        _ keyPath: WritableKeyPath<ElectricSource, T>
    ) -> T? {
        guard
            case let .source(i) = selection,
            let source = renderer.getSource(i: i)
        else {
            return nil
        }

        return source[keyPath: keyPath]
    }
    
    private func sourceBinding<T>(
        _ keyPath: WritableKeyPath<ElectricSource, T>,
        default defaultValue: T,
        get: @escaping (T) -> T = { $0 },
        set: @escaping (T) -> T = { $0 }
    ) -> Binding<T> {
        Binding(
            get: {
                guard case let .source(i) = selection,
                      let source = renderer.getSource(i: i)
                else {
                    return defaultValue
                }

                return get(source[keyPath: keyPath])
            },

            set: { newValue in
                sourceSetProperty(
                    keyPath,
                    value: set(newValue)
                )
            }
        )
    }

    @ViewBuilder
    private func colliderSection(id: UUID) -> some View {
        let _ = renderer.materialsRevision

        if let collider = editor.collider(id: id) {
            InspectorSectionView(title: "Collider") {
                HStack {
                    Text("Shape")
                    Spacer()
                    Text(collider.geometry.name)
                        .foregroundStyle(.secondary)
                }

                Picker(
                    "Material",
                    selection: colliderMaterialBinding(id: id)
                ) {
                    ForEach(renderer.materialOptions, id: \.index) { option in
                        Text(option.name)
                            .tag(option.index)
                    }
                }

                materialEditor(index: collider.materialIndex)

                Button {
                    selection = .none
                    editor.removeCollider(id: id)
                } label: {
                    Text("Remove Collider")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .cursor(.pointingHand)
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.35, green: 0, blue: 0))
                .glassEffect(.regular.tint(.red))
                .focusable(false)

                Divider()
            }
        }
    }

    @ViewBuilder
    private func materialEditor(index: Int) -> some View {
        if renderer.getMaterial(i: index) != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Material")
                        .font(.headline)

                    Spacer()

                    Button {
                        createMaterial()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glass)
                    .focusable(false)
                    .help("Create and assign a reusable material")

                    Button {
                        deleteMaterial(index: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .focusable(false)
                    .disabled(index == 0)
                    .help(
                        index == 0
                            ? "Vacuum is the fallback material"
                            : "Delete this material"
                    )
                }

                TextField(
                    "Material name",
                    text: materialNameBinding(index: index)
                )
                .textFieldStyle(.roundedBorder)

                FloatField(
                    "Relative Permittivity",
                    value: materialBinding(
                        index: index,
                        keyPath: \.epsilonR,
                        default: 1
                    ),
                    unit: "εr"
                )

                FloatField(
                    "Relative Permeability",
                    value: materialBinding(
                        index: index,
                        keyPath: \.muR,
                        default: 1
                    ),
                    unit: "μr"
                )

                FloatField(
                    "Conductivity",
                    value: materialBinding(
                        index: index,
                        keyPath: \.sigma,
                        default: 0
                    ),
                    unit: "S/m"
                )

                Text("Materials are reusable across colliders and affect wave propagation immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

    private func colliderMaterialBinding(id: UUID) -> Binding<Int> {
        Binding(
            get: {
                editor.collider(id: id)?.materialIndex ?? 0
            },
            set: { materialIndex in
                guard var collider = editor.collider(id: id) else {
                    return
                }

                collider.materialIndex = materialIndex
                editor.updateCollider(collider)
            }
        )
    }

    private func createMaterial() {
        let index = renderer.addMaterial(
            EMMaterial(
                epsilonR: 2.25,
                muR: 1,
                sigma: 0
            ),
            name: "Material \(renderer.materialCount + 1)"
        )

        guard case let .collider(id) = selection,
              var collider = editor.collider(id: id)
        else {
            return
        }

        collider.materialIndex = index
        editor.updateCollider(collider)
    }

    private func deleteMaterial(index: Int) {
        guard index > 0 else {
            return
        }

        renderer.removeMaterial(i: index)
        editor.removeMaterialReferences(at: index)
    }

    private func materialNameBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                renderer.getNameForMaterial(i: index) ?? "Material"
            },
            set: { name in
                renderer.renameMaterial(i: index, name: name)
            }
        )
    }

    private func materialBinding(
        index: Int,
        keyPath: WritableKeyPath<EMMaterial, Float>,
        default defaultValue: Float
    ) -> Binding<Float> {
        Binding(
            get: {
                renderer.getMaterial(i: index)?[keyPath: keyPath] ?? defaultValue
            },
            set: { value in
                guard var material = renderer.getMaterial(i: index) else {
                    return
                }

                material[keyPath: keyPath] = value
                renderer.updateMaterial(i: index, material: material)
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
    Inspector(
        settings: .constant(.init()),
        renderer: .constant(.init(settings: .init())),
        editor: .init(),
        selection: .constant(.source(0))
    )
        .padding()
        .preferredColorScheme(.dark)
}
