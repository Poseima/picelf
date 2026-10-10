// IOSEditorView.swift
// PicelfIOS — Main editor view combining canvas, tool picker, and property bar
//
// Target: iOS 16+, Swift 5.9+

import SwiftUI

struct IOSEditorView: View {
    @StateObject private var document: IOSEditorDocument
    @Environment(\.dismiss) private var dismiss

    let onDone: (UIImage) -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var showDeleteConfirmation = false

    init(image: UIImage, onDone: @escaping (UIImage) -> Void) {
        _document = StateObject(wrappedValue: IOSEditorDocument(baseImage: image))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Canvas area (scrollable + zoomable)
                canvasArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .opacity(0.3)

                // Tool picker
                ToolPickerView(selectedTool: $document.selectedTool)
                    .padding(.top, IOSTheme.spacing8)

                // Property bar (when tool selected)
                if document.selectedTool != nil {
                    PropertyBarView(document: document)
                        .padding(.top, IOSTheme.spacing6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Bottom safe area spacer
                Color.clear.frame(height: IOSTheme.spacing8)
            }
            .background(Color.black.opacity(0.95).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.cancel)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityIdentifier("editor.cancel.button")
                }

                ToolbarItemGroup(placement: .principal) {
                    HStack(spacing: IOSTheme.spacing12) {
                        Button {
                            IOSHaptics.light()
                            document.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(document.canUndo ? .white : .white.opacity(0.3))
                        }
                        .disabled(!document.canUndo)
                        .accessibilityIdentifier("editor.undo.button")

                        Button {
                            IOSHaptics.light()
                            document.redo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(document.canRedo ? .white : .white.opacity(0.3))
                        }
                        .disabled(!document.canRedo)
                        .accessibilityIdentifier("editor.redo.button")

                        if !document.selectedAnnotationIDs.isEmpty {
                            Button {
                                IOSHaptics.medium()
                                document.deleteSelection()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                            .accessibilityIdentifier("editor.delete.button")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        IOSHaptics.medium()
                        let result = document.renderAnnotatedImage()
                        onDone(result)
                        dismiss()
                    } label: {
                        Text(L10n.done)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(IOSTheme.emeraldGradient)
                            )
                    }
                    .accessibilityIdentifier("editor.done.button")
                }
            }
            .animation(.spring(duration: 0.2), value: document.selectedTool != nil)
            .animation(.spring(duration: 0.2), value: document.selectedAnnotationIDs.isEmpty)
        }
    }

    // MARK: - Canvas Area

    private var canvasArea: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                IOSAnnotationCanvasView(document: document)
                    .scaleEffect(zoomScale, anchor: .topLeading)
                    .frame(
                        width: document.imageWidth * zoomScale,
                        height: document.imageHeight * zoomScale
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastZoomScale
                                lastZoomScale = value
                                zoomScale = min(max(zoomScale * delta, 0.25), 5.0)
                            }
                            .onEnded { _ in
                                lastZoomScale = 1.0
                                // Snap to 1.0 if close
                                if abs(zoomScale - 1.0) < 0.08 {
                                    withAnimation(.spring(duration: 0.2)) {
                                        zoomScale = 1.0
                                    }
                                }
                            }
                    )
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height
                    )
            }
        }
        .accessibilityIdentifier("editor.canvas.area")
    }
}
