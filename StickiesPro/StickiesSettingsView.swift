//
//  StickiesSettingsView.swift
//  StickiesPro
//

import SwiftUI

struct StickiesSettingsView: View {
    @ObservedObject private var windowManager = StickyWindowManager.shared
    @AppStorage(StickyTextStyle.fontSizeKey) private var noteFontSize = StickyTextStyle.defaultFontSize
    @AppStorage(StickyTextStyle.designKey) private var noteFontDesign = StickyTextStyle.defaultDesign
    @State private var newNotespaceName = ""
    
    var body: some View {
        Form {
            Section("Default Text Style") {
                Stepper(value: $noteFontSize, in: 11...22, step: 1) {
                    Text("Body Size: \(Int(noteFontSize)) pt")
                }
                
                Picker("Typeface", selection: $noteFontDesign) {
                    ForEach(StickyTextStyle.designOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Notespaces") {
                Picker("Active Notespace", selection: activeNotespaceBinding) {
                    ForEach(windowManager.notespaces) { notespace in
                        Text(notespace.displayName).tag(notespace.id)
                    }
                }
                
                HStack {
                    TextField("New notespace", text: $newNotespaceName)
                        .onSubmit(createNotespace)
                    Button("Create", action: createNotespace)
                        .disabled(newNotespaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
    
    private var activeNotespaceBinding: Binding<UUID> {
        Binding(
            get: { windowManager.activeNotespaceID ?? windowManager.notespaces.first?.id ?? UUID() },
            set: { newValue in
                guard let notespace = windowManager.notespaces.first(where: { $0.id == newValue }) else { return }
                windowManager.switchNotespace(to: notespace)
            }
        )
    }
    
    private func createNotespace() {
        windowManager.createNotespace(named: newNotespaceName)
        newNotespaceName = ""
    }
}

struct StickyTextStyleOption: Identifiable {
    let id: String
    let name: String
}

enum StickyTextStyle {
    static let fontSizeKey = "stickyTextFontSize"
    static let designKey = "stickyTextDesign"
    static let defaultFontSize = 13.0
    static let defaultDesign = "default"
    
    static let designOptions = [
        StickyTextStyleOption(id: "default", name: "System"),
        StickyTextStyleOption(id: "serif", name: "Serif"),
        StickyTextStyleOption(id: "monospaced", name: "Mono"),
        StickyTextStyleOption(id: "rounded", name: "Rounded")
    ]
    
    static func fontDesign(for id: String) -> Font.Design {
        switch id {
        case "serif":
            return .serif
        case "monospaced":
            return .monospaced
        case "rounded":
            return .rounded
        default:
            return .default
        }
    }
}

#Preview {
    StickiesSettingsView()
}
