//
//  StickyWindowManager.swift
//  StickiesPro
//
//  Created by Michael Perez on 1/5/26.
//

import SwiftUI
import AppKit
import Combine
import SwiftData

/// Manages all the floating sticky note windows
@MainActor
class StickyWindowManager: ObservableObject {
    static let shared = StickyWindowManager()
    
    @Published var stickies: [StickyWindow] = []
    
    private(set) var modelContext: ModelContext?
    private var saveTask: Task<Void, Never>?
    private var pendingAnalyticsNoteIDs = Set<UUID>()
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPersistedStickies()
    }
    
    /// Create a new sticky note window
    func createSticky(
        content: String = "",
        color: Color? = nil,
        position: CGPoint? = nil
    ) {
        let resolvedColor = color ?? StickyPalette.creationColor(at: stickies.count)
        let resolvedPosition = position ?? nextStickyPosition()
        let stickyModel = Sticky(
            content: content,
            color: StickyColorCodec.hex(from: resolvedColor),
            positionX: resolvedPosition.x,
            positionY: resolvedPosition.y
        )
        
        modelContext?.insert(stickyModel)
        saveImmediately()
        openWindow(for: stickyModel)
    }
    
    /// Remove a sticky window and its persisted note.
    func removeSticky(_ sticky: StickyWindow) {
        sticky.close()
        stickies.removeAll { $0.id == sticky.id }
        modelContext?.delete(sticky.model)
        saveImmediately()
    }
    
    var keySticky: StickyWindow? {
        let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow
        return stickies.first { $0.panel === keyWindow }
    }
    
    func setColor(_ color: Color) {
        keySticky?.setColor(color)
    }
    
    func scheduleSave(contentChangedNoteID: UUID? = nil) {
        if let contentChangedNoteID {
            pendingAnalyticsNoteIDs.insert(contentChangedNoteID)
        }
        
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.saveImmediately()
            }
        }
    }
    
    func saveImmediately() {
        do {
            try modelContext?.save()
            enqueuePendingAnalyticsNotes()
        } catch {
            assertionFailure("Failed to save stickies: \(error)")
        }
    }
    
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveImmediately()
    }
    
    private func enqueuePendingAnalyticsNotes() {
        let noteIDs = pendingAnalyticsNoteIDs
        pendingAnalyticsNoteIDs.removeAll()
        
        for noteID in noteIDs {
            Task {
                await AnalyticsStore.shared.enqueueNoteForProcessing(noteID)
            }
        }
    }
    
    private func loadPersistedStickies() {
        guard let modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Sticky>(sortBy: [SortDescriptor(\.createdAt)])
            let persistedStickies = try modelContext.fetch(descriptor)
            if persistedStickies.isEmpty {
                createWelcomeSticky()
            } else {
                persistedStickies.forEach(openWindow(for:))
            }
        } catch {
            assertionFailure("Failed to load persisted stickies: \(error)")
        }
    }
    
    private func openWindow(for stickyModel: Sticky) {
        guard !stickies.contains(where: { $0.id == stickyModel.id }) else { return }
        
        let sticky = StickyWindow(model: stickyModel)
        stickies.append(sticky)
        sticky.show()
    }
    
    private func createWelcomeSticky() {
        createSticky(
            content: "# Welcome to StickiesPro\n\nUse Command-N to create a new sticky whenever you need one.",
            color: StickyPalette.creationColor(at: 0)
        )
    }
    
    private func nextStickyPosition() -> CGPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let basePosition: CGPoint
        
        if let lastSticky = stickies.last {
            basePosition = CGPoint(x: lastSticky.position.x + 32, y: lastSticky.position.y - 32)
        } else {
            basePosition = CGPoint(
                x: screenFrame.minX + 100,
                y: screenFrame.maxY - 100
            )
        }
        
        return CGPoint(
            x: min(max(basePosition.x, screenFrame.minX + 20), screenFrame.maxX - 300),
            y: min(max(basePosition.y, screenFrame.minY + 60), screenFrame.maxY - 60)
        )
    }
}

/// Represents a single floating sticky note window
@MainActor
class StickyWindow: NSObject, ObservableObject, Identifiable, NSWindowDelegate {
    let model: Sticky
    
    var id: UUID {
        model.id
    }
    
    @Published var content: String {
        didSet {
            guard content != oldValue else { return }
            model.content = content
            model.modifiedAt = Date()
            updateWindowTitle()
            StickyWindowManager.shared.objectWillChange.send()
            StickyWindowManager.shared.scheduleSave(contentChangedNoteID: id)
        }
    }
    
    @Published var color: Color {
        didSet {
            model.color = StickyColorCodec.hex(from: color)
            model.modifiedAt = Date()
            panel?.backgroundColor = NSColor(color.opacity(0.05))
            StickyWindowManager.shared.objectWillChange.send()
            StickyWindowManager.shared.scheduleSave()
        }
    }
    
    @Published var position: CGPoint {
        didSet {
            guard position != oldValue else { return }
            model.positionX = position.x
            model.positionY = position.y
            model.modifiedAt = Date()
            StickyWindowManager.shared.scheduleSave()
        }
    }
    
    private(set) var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var expandedHeight: CGFloat = 320
    private var isClosing = false
    
    init(model: Sticky) {
        self.model = model
        self.content = model.content
        self.color = StickyColorCodec.color(from: model.color)
        self.position = CGPoint(x: model.positionX, y: model.positionY)
        super.init()
    }
    
    var displayTitle: String {
        StickyNoteTitle.make(from: content)
    }
    
    func show() {
        // Create the SwiftUI view with a proper binding
        let stickyView = StickyNoteView(
            content: Binding(
                get: { [weak self] in self?.content ?? "" },
                set: { [weak self] newValue in self?.content = newValue }
            ),
            color: Binding(
                get: { [weak self] in self?.color ?? .yellow },
                set: { [weak self] newValue in self?.setColor(newValue) }
            ),
            onClose: { [weak self] in
                guard let self = self else { return }
                StickyWindowManager.shared.removeSticky(self)
            },
            onNewSticky: {
                StickyWindowManager.shared.createSticky()
            }
        )
        
        let rootView: AnyView
        if let modelContext = StickyWindowManager.shared.modelContext {
            rootView = AnyView(stickyView.modelContext(modelContext))
        } else {
            rootView = AnyView(stickyView)
        }
        
        // Wrap it in a hosting view
        hostingView = NSHostingView(rootView: rootView)
        
        // Create the floating panel
        let panel = NSPanel(
            contentRect: NSRect(
                origin: position,
                size: CGSize(width: 280, height: expandedHeight)
            ),
            styleMask: [
                .titled,
                .fullSizeContentView,
                .closable,
                .resizable,
                .miniaturizable,
                .utilityWindow
            ],
            backing: .buffered,
            defer: false
        )
        
        // Configure the panel to float like Stickies.app
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.minSize = NSSize(width: 220, height: 180)
        
        // Let SwiftUI render the visible title bar content.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor(color.opacity(0.05))
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Set the content view
        panel.contentView = hostingView
        panel.title = displayTitle
        
        // Show the panel
        panel.orderFront(nil)
        
        self.panel = panel
        updateWindowTitle()
    }
    
    // MARK: - NSWindowDelegate
    
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard !self.isClosing else { return }
            StickyWindowManager.shared.removeSticky(self)
        }
    }
    
    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let panel = self.panel else { return }
            self.position = panel.frame.origin
        }
    }
    
    nonisolated func windowDidMiniaturize(_ notification: Notification) {
        // Window was shaded (minimized to titlebar)
    }
    
    nonisolated func windowDidDeminiaturize(_ notification: Notification) {
        // Window was unshaded (restored from titlebar)
    }
    
    func close() {
        guard !isClosing else { return }
        
        isClosing = true
        panel?.close()
        panel = nil
        hostingView = nil
        isClosing = false
    }
    
    func focus() {
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    
    func setColor(_ color: Color) {
        self.color = color
    }
    
    private func updateWindowTitle() {
        panel?.title = displayTitle
    }
}
