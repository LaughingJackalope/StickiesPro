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
    
    private var title: String {
        StickyNoteTitle.make(from: content)
    }
    
    var body: some View {
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
            .ignoresSafeArea()
            .overlay {
                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.72))
                    .ignoresSafeArea()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                StickyTitleBar(
                    title: title,
                    color: color,
                    isEditing: isEditing,
                    isHovered: isHovered,
                    onClose: {
                        showsDeleteConfirmation = true
                    },
                    onNewSticky: onNewSticky,
                    onToggleEditing: {
                        isEditing.toggle()
                        isFocused = isEditing
                    },
                    windowShadeController: windowShadeController
                )
                
                if !windowShadeController.isShaded {
                    ScrollView {
                        if isEditing {
                            TextEditor(text: $content)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .focused($isFocused)
                                .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
                        } else {
                            if let attributedString = try? AttributedString(markdown: content) {
                                Text(attributedString)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
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
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.22))
        }
        .glassEffect(
            .regular
                .tint(color.opacity(0.28))
                .interactive(true),
            in: .rect(cornerRadius: 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.42 : 0.25), lineWidth: 1)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .alert("Delete this sticky?", isPresented: $showsDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onClose)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note will be permanently removed.")
        }
    }
}

private struct StickyTitleBar: View {
    let title: String
    let color: Color
    let isEditing: Bool
    let isHovered: Bool
    let onClose: () -> Void
    let onNewSticky: () -> Void
    let onToggleEditing: () -> Void
    @ObservedObject var windowShadeController: WindowShadeController
    
    var body: some View {
        ZStack {
            WindowTitleBarBridge(windowShadeController: windowShadeController)
            
            HStack(spacing: 8) {
                Button {
                    windowShadeController.toggleShade()
                } label: {
                    Image(systemName: windowShadeController.isShaded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .help(windowShadeController.isShaded ? "Expand" : "Collapse")
                
                Button {
                    windowShadeController.zoom()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(windowShadeController.isShaded)
                .help("Zoom")
                
                if windowShadeController.isShaded {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: onNewSticky) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .help("New Sticky")
                
                Button(action: onToggleEditing) {
                    Image(systemName: isEditing ? "eye.fill" : "pencil")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                        .padding(6)
                        .background {
                            Circle()
                                .fill(color.opacity(0.2))
                        }
                }
                .buttonStyle(.plain)
                .opacity(windowShadeController.isShaded ? 0 : (isHovered ? 1 : 0.65))
                .disabled(windowShadeController.isShaded)
                .help(isEditing ? "Preview" : "Edit")
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .padding(.horizontal, 12)
        }
        .frame(height: windowShadeController.titleBarHeight)
        .background {
            LinearGradient(
                colors: [
                    .white.opacity(0.18),
                    color.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 1)
        }
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
    
    func attach(to window: NSWindow?) {
        self.window = window
        
        guard let window, !isShaded else { return }
        expandedFrame = window.frame
    }
    
    func toggleShade() {
        guard let window else { return }
        
        if isShaded {
            restore(window: window)
        } else {
            shade(window: window)
        }
    }
    
    func zoom() {
        guard let window, !isShaded else { return }
        window.performZoom(nil)
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
        
        isShaded = true
        window.minSize = NSSize(width: 180, height: targetHeight)
        window.maxSize = NSSize(width: .greatestFiniteMagnitude, height: targetHeight)
        window.styleMask.remove(.resizable)
        window.animator().setFrame(shadedFrame, display: true)
    }
    
    private func restore(window: NSWindow) {
        guard let expandedFrame else { return }
        
        isShaded = false
        
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
