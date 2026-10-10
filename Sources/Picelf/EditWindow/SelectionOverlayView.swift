import SwiftUI

struct SelectionOverlayView: View {
    let selectionRect: CGRect?
    let showsResizeHandle: Bool
    var showsRotationHandle: Bool = false
    var endpointHandles: (CGPoint, CGPoint)? = nil

    var body: some View {
        Canvas { context, _ in
            guard let rect = selectionRect else { return }
            context.stroke(Path(rect), with: .color(EditorTheme.selectionStroke), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

            if let (startPt, endPt) = endpointHandles {
                // Draw 2 circle handles at arrow/line endpoints
                let handleSize: CGFloat = 10
                for ep in [startPt, endPt] {
                    let handleRect = CGRect(
                        x: ep.x - handleSize / 2,
                        y: ep.y - handleSize / 2,
                        width: handleSize,
                        height: handleSize
                    )
                    context.fill(Path(ellipseIn: handleRect), with: .color(EditorTheme.handleFill))
                    context.stroke(Path(ellipseIn: handleRect), with: .color(EditorTheme.selectionStroke), lineWidth: 1)
                }
            } else if showsResizeHandle {
                let handleSize: CGFloat = 10
                let corners = [
                    CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                ]
                for corner in corners {
                    let handleRect = CGRect(
                        x: corner.x - handleSize / 2,
                        y: corner.y - handleSize / 2,
                        width: handleSize,
                        height: handleSize
                    )
                    context.fill(Path(roundedRect: handleRect, cornerRadius: 2), with: .color(EditorTheme.handleFill))
                    context.stroke(Path(roundedRect: handleRect, cornerRadius: 2), with: .color(EditorTheme.selectionStroke), lineWidth: 1)
                }
            }

            if showsRotationHandle {
                let topCenter = CGPoint(x: rect.midX, y: rect.minY)
                let rotationPoint = CGPoint(x: topCenter.x, y: topCenter.y - 24)

                var linePath = Path()
                linePath.move(to: topCenter)
                linePath.addLine(to: rotationPoint)
                context.stroke(linePath, with: .color(EditorTheme.selectionStroke), style: StrokeStyle(lineWidth: 1))

                let circleSize: CGFloat = 10
                let circleRect = CGRect(
                    x: rotationPoint.x - circleSize / 2,
                    y: rotationPoint.y - circleSize / 2,
                    width: circleSize,
                    height: circleSize
                )
                context.fill(Path(ellipseIn: circleRect), with: .color(EditorTheme.handleFill))
                context.stroke(Path(ellipseIn: circleRect), with: .color(EditorTheme.selectionStroke), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
