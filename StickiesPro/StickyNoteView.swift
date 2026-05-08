//
//  StickyNoteView.swift
//  StickiesPro
//
//  Created by Michael Perez on 1/5/26.
//

import SwiftUI
import AppKit
import Combine

/// The individual sticky note view - this goes in each floating window
struct StickyNoteView: View {
    @Binding var content: String
    @Binding var color: Color
    let onClose: () -> Void
    let onNewSticky: () -> Void
    
    @StateObject private var windowShadeController = WindowShadeController()
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var showsDeleteConfirmation = false
    @FocusState private var isFocused: Bool
    @Namespace private var morphNamespace
    @AppStorage(StickyTextStyle.fontSizeKey) private var noteFontSize = StickyTextStyle.defaultFontSize
    @AppStorage(StickyTextStyle.designKey) private var noteFontDesign = StickyTextStyle.defaultDesign
    
    private var title: String {
        StickyNoteTitle.make(from: content)
    }
    
    private var isExpanded: Bool {
        !windowShadeController.isShaded
    }
    
    private var surfaceCornerRadius: CGFloat {
        isExpanded ? 16 : 30
    }
    
    private var noteFont: Font {
        .system(size: noteFontSize, design: StickyTextStyle.fontDesign(for: noteFontDesign))
    }
    
    var body: some View {
        Group {
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    expandedToolbar
                    
                    Divider()
                        .opacity(0.3)
                    
                    noteBody
                    
                    statusBar
                }
            } else {
                collapsedPill
            }
        }
        .matchedGeometryEffect(id: "stickySurface", in: morphNamespace)
        .background {
            surfaceBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.42 : 0.25), lineWidth: 1)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
        .onExitCommand {
            endEditing()
        }
        .overlay {
            keyboardShortcutCommands
        }
        .alert("Delete this sticky?", isPresented: $showsDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onClose)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note will be permanently removed.")
        }
    }
    
    private var surfaceBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    color.opacity(0.34),
                    .white.opacity(0.12),
                    color.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.72))
        }
    }
    
    private var expandedToolbar: some View {
        ZStack {
            WindowTitleBarBridge(windowShadeController: windowShadeController)
            
            HStack(spacing: 8) {
                Button {
                    collapse()
                } label: {
                    toolbarIcon("chevron.up", size: 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("m", modifiers: .command)
                .help("Collapse")
                
                Button {
                    windowShadeController.zoom()
                } label: {
                    toolbarIcon("arrow.up.left.and.arrow.down.right", size: 8)
                }
                .buttonStyle(.plain)
                .help("Zoom")
                
                Spacer()
                
                Button(action: onNewSticky) {
                    toolbarIcon("plus", size: 9)
                }
                .buttonStyle(.plain)
                .help("New Sticky")
                
                Button(action: toggleEditing) {
                    toolbarIcon(isEditing ? "eye" : "info.circle", size: 11)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.65)
                .help(isEditing ? "Preview" : "Edit")
                
                Button {
                    showsDeleteConfirmation = true
                } label: {
                    toolbarIcon("xmark", size: 9)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
                .help("Delete")
            }
            .padding(.horizontal, 12)
        }
        .frame(height: windowShadeController.titleBarHeight)
    }
    
    private var collapsedPill: some View {
        ZStack {
            WindowTitleBarBridge(windowShadeController: windowShadeController)
            
            HStack(spacing: 8) {
                Button {
                    expand()
                } label: {
                    toolbarIcon("chevron.down", size: 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Expand")
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                Button(action: onNewSticky) {
                    toolbarIcon("plus", size: 9)
                }
                .buttonStyle(.plain)
                .help("New Sticky")
                
                Button {
                    showsDeleteConfirmation = true
                } label: {
                    toolbarIcon("xmark", size: 9)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
                .help("Delete")
            }
            .padding(.horizontal, 12)
        }
        .frame(height: windowShadeController.titleBarHeight)
    }
    
    private var noteBody: some View {
        ScrollView {
            if isEditing {
                TextEditor(text: $content)
                    .font(noteFont)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
            } else if let attributedString = try? AttributedString(markdown: content) {
                Text(attributedString)
                    .font(noteFont)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(content)
                    .font(noteFont)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private var statusBar: some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(content.split(separator: " ").count) words")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private var keyboardShortcutCommands: some View {
        Group {
            Button(action: beginEditing) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: .command)
            
            Button(action: endEditing) {
                EmptyView()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
    
    private func toolbarIcon(_ systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.primary.opacity(0.75))
            .frame(width: 18, height: 18)
            .background(Circle().fill(.white.opacity(0.28)))
    }
    
    private func toggleEditing() {
        isEditing.toggle()
        isFocused = isEditing
    }
    
    private func beginEditing() {
        if !isExpanded {
            expand()
        }
        
        isEditing = true
        
        DispatchQueue.main.async {
            isFocused = true
        }
    }
    
    private func endEditing() {
        isFocused = false
        isEditing = false
    }
    
    private func collapse() {
        windowShadeController.collapse()
    }
    
    private func expand() {
        windowShadeController.expand()
    }
}

@MainActor
private final class WindowShadeController: ObservableObject {
    @Published private(set) var isShaded = false
    
    let titleBarHeight: CGFloat = 34
    
    weak var window: NSWindow?
    private var expandedFrame: NSRect?
    private var expandedMinSize: NSSize?
    private var expandedMaxSize: NSSize?
    private var expandedStyleMask: NSWindow.StyleMask?
    private let shadeAnimation = Animation.spring(response: 0.38, dampingFraction: 0.72)
    private var windowMutationGeneration = 0
    
    func attach(to window: NSWindow?) {
        self.window = window
        
        guard let window, !isShaded else { return }
        expandedFrame = window.frame
    }
    
    func toggleShade() {
        if isShaded {
            expand()
        } else {
            collapse()
        }
    }
    
    func collapse() {
        guard let window, !isShaded else { return }
        
        shade(window: window)
    }
    
    func expand() {
        guard let window, isShaded else { return }
        
        restore(window: window)
    }
    
    func zoom() {
        guard let window, !isShaded else { return }
        
        scheduleWindowMutation { [weak window] in
            window?.performZoom(nil)
        }
    }
    
    private func shade(window: NSWindow) {
        let currentFrame = window.frame
        expandedFrame = currentFrame
        expandedMinSize = window.minSize
        expandedMaxSize = window.maxSize
        expandedStyleMask = window.styleMask
        
        let targetHeight = titleBarHeight
        let deltaHeight = currentFrame.height - targetHeight
        
        guard deltaHeight > 0 else { return }
        
        var shadedFrame = currentFrame
        shadedFrame.origin.y += deltaHeight
        shadedFrame.size.height = targetHeight
        
        withAnimation(shadeAnimation) {
            isShaded = true
        }
        
        scheduleWindowMutation { [weak window] in
            guard let window else { return }
            window.minSize = NSSize(width: 180, height: targetHeight)
            window.maxSize = NSSize(width: .greatestFiniteMagnitude, height: targetHeight)
            window.styleMask.remove(.resizable)
            window.animator().setFrame(shadedFrame, display: true)
        }
    }
    
    private func restore(window: NSWindow) {
        guard let expandedFrame else { return }
        
        withAnimation(shadeAnimation) {
            isShaded = false
        }
        
        let expandedMinSize = expandedMinSize
        let expandedMaxSize = expandedMaxSize
        let expandedStyleMask = expandedStyleMask
        
        scheduleWindowMutation { [weak window] in
            guard let window else { return }
            
            if let expandedMinSize {
                window.minSize = expandedMinSize
            }
            
            if let expandedMaxSize {
                window.maxSize = expandedMaxSize
            }
            
            if let expandedStyleMask {
                window.styleMask = expandedStyleMask
            }
            
            window.animator().setFrame(expandedFrame, display: true)
        }
    }
    
    private func scheduleWindowMutation(_ mutation: @escaping @MainActor () -> Void) {
        windowMutationGeneration += 1
        let generation = windowMutationGeneration
        
        DispatchQueue.main.async { [weak self] in
            guard let self, self.windowMutationGeneration == generation else { return }
            mutation()
        }
    }
}

enum StickyNoteTitle {
    static func make(from content: String) -> String {
        let title = content
            .split(whereSeparator: \.isNewline)
            .map { cleanup(String($0)) }
            .first { !$0.isEmpty }
        
        return title ?? "New Sticky"
    }
    
    private static func cleanup(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        while cleaned.first == "#" || cleaned.first == "-" || cleaned.first == "*" || cleaned.first == ">" {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleaned
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WindowTitleBarBridge: NSViewRepresentable {
    @ObservedObject var windowShadeController: WindowShadeController
    
    func makeNSView(context: Context) -> TitleBarHostView {
        let view = TitleBarHostView()
        view.windowShadeController = windowShadeController
        return view
    }
    
    func updateNSView(_ nsView: TitleBarHostView, context: Context) {
        nsView.windowShadeController = windowShadeController
        
        DispatchQueue.main.async {
            windowShadeController.attach(to: nsView.window)
        }
    }
}

private final class TitleBarHostView: NSView {
    weak var windowShadeController: WindowShadeController?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            windowShadeController?.toggleShade()
            return
        }
        
        window?.performDrag(with: event)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }
}

#Preview {
    StickyNoteView(
        content: .constant("# Preview Note\n\nThis is a **preview** of the sticky note.\n\n- Item 1\n- Item 2\n\n*More pro than ever!*"),
        color: .constant(.yellow),
        onClose: {},
        onNewSticky: {}
    )
    .frame(width: 280, height: 320)
}
