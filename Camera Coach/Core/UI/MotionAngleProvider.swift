import CoreMotion
import Foundation

/// Core Motion-backed provider for level angle
/// Fallback implementation using CMMotionManager
final class MotionAngleProvider: LevelAngleProvider {
    
    private let motionManager = CMMotionManager()
    private var currentRoll: Float = 0.0
    private let lowPassAlpha: Float = 0.15 // Low-pass filter for smoothing
    
    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30 Hz

        // CRITICAL: No reference frame parameter - uses default (most stable for gravity-based calculations)
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            // 🌍 GRAVITY-BASED HORIZON (matches FrameAnalyzer and iPhone Camera app):
            // Calculate roll angle independent of pitch by normalizing Y-Z plane
            let gravityYZ = sqrt(motion.gravity.y * motion.gravity.y + motion.gravity.z * motion.gravity.z)

            // atan2(x, magnitude_YZ) gives TRUE roll without pitch amplification
            // NEGATE for counter-rotation (line tilts opposite to device)
            let horizonAngleRadians = -atan2(motion.gravity.x, gravityYZ)
            let deviceRollDegrees = Float(horizonAngleRadians * 180.0 / .pi)

            // Apply low-pass filter for smooth motion
            self.currentRoll = self.lowPassAlpha * deviceRollDegrees + (1.0 - self.lowPassAlpha) * self.currentRoll
        }
    }
    
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func currentLevelAngleDeg() -> Float? {
        guard motionManager.isDeviceMotionActive else { return nil }
        
        // Return filtered roll angle
        // Positive roll means device tilted to the right (need to rotate left to level)
        return currentRoll
    }
}
