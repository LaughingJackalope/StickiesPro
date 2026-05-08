//
//  StickiesProApp.swift
//  StickiesPro
//
//  Created by Michael Perez on 1/5/26.
//

import SwiftUI
import AppKit
import SwiftData

@main
struct StickiesProApp: App {
    static let sharedModelContainer: ModelContainer = {
        do {
            return try StickiesModelContainer.make()
        } catch {
            fatalError("Failed to create SwiftData model container: \(error)")
        }
    }()
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No main window - just like Stickies.app!
        Settings {
            EmptyView()
        }
        .modelContainer(Self.sharedModelContainer)
        .commands {
            StickiesCommands()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowManager = StickyWindowManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app in the menu bar so note colors and windows are easy to manage.
        NSApplication.shared.setActivationPolicy(.regular)
        
        windowManager.configure(modelContext: StickiesProApp.sharedModelContainer.mainContext)
        Task {
            await AnalyticsStore.shared.prepare()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        windowManager.flushPendingSave()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running even with no windows
    }
}

struct StickiesCommands: Commands {
    @ObservedObject private var windowManager = StickyWindowManager.shared
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Sticky") {
                windowManager.createSticky()
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        
        CommandMenu("Color") {
            ForEach(StickyPalette.colors) { item in
                Button(item.name) {
                    windowManager.setColor(item.color)
                }
                .disabled(windowManager.keySticky == nil)
            }
        }
        
        CommandGroup(replacing: .windowList) {
            if windowManager.stickies.isEmpty {
                Text("No Stickies")
            } else {
                ForEach(windowManager.stickies) { sticky in
                    Button(sticky.displayTitle) {
                        sticky.focus()
                    }
                }
            }
        }
    }
}

struct StickyPaletteItem: Identifiable {
    let id: String
    let name: String
    let color: Color
}

enum StickyPalette {
    static let colors: [StickyPaletteItem] = [
        StickyPaletteItem(id: "yellow", name: "Yellow", color: .yellow),
        StickyPaletteItem(id: "blue", name: "Blue", color: .blue),
        StickyPaletteItem(id: "green", name: "Green", color: .green),
        StickyPaletteItem(id: "pink", name: "Pink", color: .pink),
        StickyPaletteItem(id: "purple", name: "Purple", color: .purple),
        StickyPaletteItem(id: "orange", name: "Orange", color: .orange),
        StickyPaletteItem(id: "gray", name: "Gray", color: .gray)
    ]
    
    static func creationColor(at index: Int) -> Color {
        colors[index % colors.count].color
    }
}
