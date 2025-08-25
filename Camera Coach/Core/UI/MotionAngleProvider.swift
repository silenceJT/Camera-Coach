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
        
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            let deviceRollRadians = motion.attitude.roll
            let deviceRollDegrees = Float(deviceRollRadians * 180.0 / .pi)
            
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
