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

struct Inspector: View {
    @State var elementName: String = "World"
    @State private var width: CGFloat = 300
    @Binding var settings: SimulationSettings
    @Binding var renderer: Renderer
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(elementName)
                    .font(.title)
                    .bold()
                Divider()
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
    }
    
    var gridSection: some View {
        InspectorSectionView(title: "Simulation") {
            HStack {
                IntField("Nx", value: $settings.Nx, unit: "")
                Spacer()
                IntField("Ny", value: $settings.Ny, unit: "")
            }
            Button {
                
            } label: {
                Text("Match Grid to Screen")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect()
            .focusable(false)
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
    Inspector()
        .padding()
        .preferredColorScheme(.dark)
}
