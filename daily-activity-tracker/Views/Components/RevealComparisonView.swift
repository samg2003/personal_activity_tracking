import SwiftUI

/// Reusable reveal-slider comparison view with pinch-to-zoom and pan.
/// Used by both QualityComparisonView and PhotoRevealOverlay.
///
/// Layout: GeometryReader with overlaid images + slider below.
/// Gestures: pinch to zoom, drag to pan (when zoomed), double-tap to reset.
struct RevealComparisonView: View {
    let imageA: UIImage?
    let imageB: UIImage?
    let labelA: AnyView
    let labelB: AnyView
    let accentColor: Color

    @State private var revealAmount: CGFloat = 0.5
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    init(
        imageA: UIImage?,
        imageB: UIImage?,
        accentColor: Color = .blue,
        @ViewBuilder labelA: () -> some View,
        @ViewBuilder labelB: () -> some View
    ) {
        self.imageA = imageA
        self.imageB = imageB
        self.accentColor = accentColor
        self.labelA = AnyView(labelA())
        self.labelB = AnyView(labelB())
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    if let imageB {
                        Image(uiImage: imageB)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if let imageA {
                        Image(uiImage: imageA)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RevealClipShape(revealAmount: revealAmount))
                    }

                    // Divider line
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2)
                        .position(x: geo.size.width * revealAmount, y: geo.size.height / 2)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    // Labels
                    HStack {
                        labelA
                            .padding(.leading, 8)
                        Spacer()
                        labelB
                            .padding(.trailing, 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                }
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(1.0, lastZoomScale * value)
                        }
                        .onEnded { _ in
                            lastZoomScale = zoomScale
                            if zoomScale <= 1.0 {
                                withAnimation(.spring(duration: 0.3)) {
                                    panOffset = .zero
                                    lastPanOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoomScale > 1.0 else { return }
                            panOffset = CGSize(
                                width: lastPanOffset.width + value.translation.width,
                                height: lastPanOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastPanOffset = panOffset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                }
                .clipped()
            }

            // Reveal slider
            Slider(value: $revealAmount, in: 0...1)
                .tint(accentColor)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    /// Reset zoom and pan to defaults
    func resetZoom() {
        zoomScale = 1.0
        lastZoomScale = 1.0
        panOffset = .zero
        lastPanOffset = .zero
    }
}

// MARK: - Reveal Clip Shape

/// Clips a view from the left edge to a given fraction of its width.
struct RevealClipShape: Shape {
    var revealAmount: CGFloat

    var animatableData: CGFloat {
        get { revealAmount }
        set { revealAmount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0,
                            width: rect.width * revealAmount,
                            height: rect.height))
        return path
    }
}
