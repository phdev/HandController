import SwiftUI
import Vision

/// Draws hand skeleton overlays (joints + bone connections) for detected hands.
struct HandOverlayView: View {
    let hands: [DetectedHand]

    private let leftHandColor = Color.cyan
    private let rightHandColor = Color.orange
    private let jointRadius: CGFloat = 5
    private let boneWidth: CGFloat = 2.5

    var body: some View {
        Canvas { context, size in
            for hand in hands {
                let color = hand.chirality == .left ? leftHandColor : rightHandColor
                drawBones(context: &context, hand: hand, size: size, color: color)
                drawJoints(context: &context, hand: hand, size: size, color: color)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawBones(context: inout GraphicsContext, hand: DetectedHand, size: CGSize, color: Color) {
        for (from, to) in HandSkeleton.boneConnections {
            guard let fromPt = hand.joints[from],
                  let toPt = hand.joints[to] else { continue }

            let start = scaled(fromPt, in: size)
            let end = scaled(toPt, in: size)

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: boneWidth)
        }
    }

    private func drawJoints(context: inout GraphicsContext, hand: DetectedHand, size: CGSize, color: Color) {
        for (jointName, point) in hand.joints {
            let pos = scaled(point, in: size)

            // Larger dots for fingertips
            let isTip = [
                VNHumanHandPoseObservation.JointName.thumbTip,
                .indexTip, .middleTip, .ringTip, .littleTip
            ].contains(jointName)

            let radius = isTip ? jointRadius * 1.4 : jointRadius
            let rect = CGRect(
                x: pos.x - radius,
                y: pos.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            // White fill with colored border
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
        }
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}
