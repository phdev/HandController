import SwiftUI
import Vision

/// Draws hand joint landmarks and connections as an overlay on the camera preview.
struct HandOverlayView: View {
    let hands: [DetectedHand]
    let viewSize: CGSize

    private let jointConnections: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
        // Thumb
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        // Index
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        // Middle
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        // Ring
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        // Little
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        // Palm connections
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP)
    ]

    var body: some View {
        Canvas { context, size in
            for hand in hands {
                drawConnections(context: &context, hand: hand, size: size)
                drawJoints(context: &context, hand: hand, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawConnections(context: inout GraphicsContext, hand: DetectedHand, size: CGSize) {
        for (from, to) in jointConnections {
            guard let fromPt = hand.joints[from],
                  let toPt = hand.joints[to] else { continue }

            let start = scaledPoint(fromPt, in: size)
            let end = scaledPoint(toPt, in: size)

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            context.stroke(path, with: .color(.green.opacity(0.8)), lineWidth: 2)
        }
    }

    private func drawJoints(context: inout GraphicsContext, hand: DetectedHand, size: CGSize) {
        for (_, point) in hand.joints {
            let scaled = scaledPoint(point, in: size)
            let rect = CGRect(x: scaled.x - 4, y: scaled.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(.yellow))
        }
    }

    private func scaledPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        // Mirror x-axis for front camera (selfie view)
        CGPoint(x: (1 - point.x) * size.width, y: point.y * size.height)
    }
}
