import Vision
import CoreGraphics

/// Classifies hand gestures based on joint positions from Vision hand pose detection.
///
/// Uses geometric relationships between finger joints (distances, angles, extension states)
/// to determine which gesture is being performed.
struct GestureClassifier {

    func classify(joints: [VNHumanHandPoseObservation.JointName: CGPoint]) -> HandGesture {
        guard let wrist = joints[.wrist] else { return .unknown }

        let thumbExtended = isThumbExtended(joints: joints)
        let indexExtended = isFingerExtended(joints: joints, mcp: .indexMCP, pip: .indexPIP, dip: .indexDIP, tip: .indexTip)
        let middleExtended = isFingerExtended(joints: joints, mcp: .middleMCP, pip: .middlePIP, dip: .middleDIP, tip: .middleTip)
        let ringExtended = isFingerExtended(joints: joints, mcp: .ringMCP, pip: .ringPIP, dip: .ringDIP, tip: .ringTip)
        let littleExtended = isFingerExtended(joints: joints, mcp: .littleMCP, pip: .littlePIP, dip: .littleDIP, tip: .littleTip)

        let extendedCount = [thumbExtended, indexExtended, middleExtended, ringExtended, littleExtended]
            .filter { $0 }.count

        // Pinch: thumb tip and index tip are close together
        if let thumbTip = joints[.thumbTip], let indexTip = joints[.indexTip] {
            let pinchDistance = distance(thumbTip, indexTip)
            if pinchDistance < 0.05 && !middleExtended && !ringExtended {
                return .pinch
            }
        }

        // Thumbs up: only thumb extended, thumb pointing upward
        if thumbExtended && !indexExtended && !middleExtended && !ringExtended && !littleExtended {
            if let thumbTip = joints[.thumbTip], let thumbCMC = joints[.thumbCMC] {
                if thumbTip.y < thumbCMC.y {
                    return .thumbsUp
                } else {
                    return .thumbsDown
                }
            }
        }

        // Peace: index and middle extended, others curled
        if indexExtended && middleExtended && !ringExtended && !littleExtended {
            return .peace
        }

        // Pointing up: only index extended
        if indexExtended && !middleExtended && !ringExtended && !littleExtended && !thumbExtended {
            return .pointingUp
        }

        // Open hand: all fingers extended
        if extendedCount >= 4 {
            return .openHand
        }

        // Fist: no fingers extended
        if extendedCount <= 1 && !thumbExtended {
            return .fist
        }

        return .unknown
    }

    // MARK: - Helpers

    private func isFingerExtended(
        joints: [VNHumanHandPoseObservation.JointName: CGPoint],
        mcp: VNHumanHandPoseObservation.JointName,
        pip: VNHumanHandPoseObservation.JointName,
        dip: VNHumanHandPoseObservation.JointName,
        tip: VNHumanHandPoseObservation.JointName
    ) -> Bool {
        guard let mcpPt = joints[mcp],
              let pipPt = joints[pip],
              let tipPt = joints[tip] else {
            return false
        }

        // A finger is extended if the tip is farther from the wrist than the MCP,
        // and the tip-to-MCP distance is greater than the pip-to-MCP distance.
        let tipToMcp = distance(tipPt, mcpPt)
        let pipToMcp = distance(pipPt, mcpPt)

        return tipToMcp > pipToMcp * 1.2
    }

    private func isThumbExtended(joints: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Bool {
        guard let cmc = joints[.thumbCMC],
              let mp = joints[.thumbMP],
              let tip = joints[.thumbTip] else {
            return false
        }

        let tipToCmc = distance(tip, cmc)
        let mpToCmc = distance(mp, cmc)

        return tipToCmc > mpToCmc * 1.3
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
