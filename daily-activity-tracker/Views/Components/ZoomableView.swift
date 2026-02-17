import SwiftUI
import UIKit

/// A Photos-like zoomable container using UIScrollView.
/// Supports pinch-to-zoom at the pinch point, smooth inertial panning,
/// bounce-back, and double-tap to zoom in/out.
struct ZoomableView<Content: View>: UIViewRepresentable {
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let doubleTapZoom: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        minZoom: CGFloat = 1.0,
        maxZoom: CGFloat = 5.0,
        doubleTapZoom: CGFloat = 3.0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.doubleTapZoom = doubleTapZoom
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(maxZoom: maxZoom, doubleTapZoom: doubleTapZoom)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hostingController.view)
        context.coordinator.hostedView = hostingController.view

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        // Double-tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var hostedView: UIView?
        weak var scrollView: UIScrollView?
        let maxZoom: CGFloat
        let doubleTapZoom: CGFloat

        init(maxZoom: CGFloat, doubleTapZoom: CGFloat) {
            self.maxZoom = maxZoom
            self.doubleTapZoom = doubleTapZoom
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostedView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        /// Keep content centered when smaller than scroll view bounds
        private func centerContent(in scrollView: UIScrollView) {
            guard let hostedView else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = hostedView.frame.size

            let xOffset = max(0, (boundsSize.width - contentSize.width) / 2)
            let yOffset = max(0, (boundsSize.height - contentSize.height) / 2)
            hostedView.center = CGPoint(
                x: contentSize.width / 2 + xOffset,
                y: contentSize.height / 2 + yOffset
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: scrollView.subviews.first)
                let zoomRect = zoomRect(for: doubleTapZoom, center: point, in: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private func zoomRect(for scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            return CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }
}
