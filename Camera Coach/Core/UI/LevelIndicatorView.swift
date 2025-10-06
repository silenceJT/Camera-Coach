import UIKit
import CoreGraphics

// MARK: - Level Angle Provider Protocol

public protocol LevelAngleProvider {
    /// Degrees needed to reach horizon level; + means rotate left to level.
    func currentLevelAngleDeg() -> Float?
}

// MARK: - Level State

public enum LevelState: Equatable {
    case hidden
    case offLevel(angleDeg: Float)
    case levelMerged
    case levelStable  // New state: device is level and stable, indicator disappears
    
    public static func == (lhs: LevelState, rhs: LevelState) -> Bool {
        switch (lhs, rhs) {
        case (.hidden, .hidden), (.levelMerged, .levelMerged), (.levelStable, .levelStable):
            return true
        case (.offLevel(let angle1), .offLevel(let angle2)):
            return abs(angle1 - angle2) < 0.1 // Small tolerance for floating point comparison
        default:
            return false
        }
    }
}

// MARK: - Level Indicator View

/// Camera Level Indicator that mirrors the native iPhone Camera experience
/// Shows broken white line when off-level, solid yellow when level
/// Only visible when device is near horizontal (±10°)
public final class LevelIndicatorView: UIView {
    
    // MARK: - Properties
    
    public var yOffset: CGFloat = 0
    public private(set) var state: LevelState = .hidden {
        didSet {
            guard state != oldValue else { return }
            handleStateChange(from: oldValue, to: state)
        }
    }
    
    private var levelStartTime: Date?
    private var offLevelStartTime: Date?
    private var levelStableStartTime: Date?  // Track when we first showed yellow line
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    // Configuration
    private let visibilityThreshold: Float = 20.0  // Show when |roll| ≤ 20° (matches iPhone Camera)
    private let levelThreshold: Float = 1.0        // Level when |roll| ≤ 1°
    private let hysteresisThreshold: Float = 1.6   // Revert when |roll| > 1.6°
    private let stableDeadZone: Float = 2.5        // Must exceed 2.5° to exit stable state
    private let stabilityWindow: TimeInterval = 0.2  // 200ms
    private let hysteresisWindow: TimeInterval = 0.15 // 150ms
    
    // Visual properties - Three-segment approach: short-long-short
    private let lineWidth: CGFloat = 2.0
    private let shortSegmentLength: CGFloat = 22.5   // Left and right short segments (0.75x shorter)
    private let longSegmentLength: CGFloat = 135.0   // Middle long segment (1.5x longer)
    private let segmentGap: CGFloat = 10.0           // Gap between segments
    private let totalIndicatorWidth: CGFloat = 200.0 // Total width when merged (adjusted for new lengths)
    
    // Three shape layers for the segments
    private var leftShortSegment: CAShapeLayer!     // Always horizontal
    private var middleLongSegment: CAShapeLayer!    // Tilts with device
    private var rightShortSegment: CAShapeLayer!    // Always horizontal
    private var mergedLevelLine: CAShapeLayer!      // Solid yellow when level
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        // Prepare haptic generator
        hapticGenerator.prepare()
        
        // Create three-segment layers (short-long-short pattern)
        setupThreeSegmentLayers()
        setupMergedLevelLayer()
        
        // Initially hidden
        updateVisibility(for: .hidden)
    }
    
    private func setupThreeSegmentLayers() {
        // Left short segment (always horizontal, aligned with grid)
        leftShortSegment = CAShapeLayer()
        leftShortSegment.strokeColor = UIColor.white.cgColor
        leftShortSegment.fillColor = UIColor.clear.cgColor
        leftShortSegment.lineWidth = lineWidth
        leftShortSegment.lineCap = .round
        layer.addSublayer(leftShortSegment)
        
        // Middle long segment (tilts with device roll)
        middleLongSegment = CAShapeLayer()
        middleLongSegment.strokeColor = UIColor.white.cgColor
        middleLongSegment.fillColor = UIColor.clear.cgColor
        middleLongSegment.lineWidth = lineWidth
        middleLongSegment.lineCap = .round
        layer.addSublayer(middleLongSegment)
        
        // Right short segment (always horizontal, aligned with grid)
        rightShortSegment = CAShapeLayer()
        rightShortSegment.strokeColor = UIColor.white.cgColor
        rightShortSegment.fillColor = UIColor.clear.cgColor
        rightShortSegment.lineWidth = lineWidth
        rightShortSegment.lineCap = .round
        layer.addSublayer(rightShortSegment)
    }
    
    private func setupMergedLevelLayer() {
        // Solid yellow line when level (merges all three segments)
        mergedLevelLine = CAShapeLayer()
        mergedLevelLine.strokeColor = UIColor.systemYellow.cgColor
        mergedLevelLine.fillColor = UIColor.clear.cgColor
        mergedLevelLine.lineWidth = lineWidth
        mergedLevelLine.lineCap = .round
        layer.addSublayer(mergedLevelLine)
    }
    
    // MARK: - Public API
    
    /// Update the level indicator with current angle
    /// - Parameters:
    ///   - angleDeg: Roll angle in degrees (+ means rotate left to level)
    ///   - now: Current timestamp for stability calculations
    public func update(angleDeg: Float?, now: Date = Date()) {
        guard let angle = angleDeg else {
            state = .hidden
            return
        }
        
        let absAngle = abs(angle)
        
        // Check visibility window
        guard absAngle <= visibilityThreshold else {
            state = .hidden
            levelStartTime = nil
            offLevelStartTime = nil
            return
        }
        
        // Determine target state based on angle and current state
        // .levelStable is not a direct target - it's reached through time progression from .levelMerged
        let targetState: LevelState
        if absAngle <= levelThreshold {
            targetState = .levelMerged
        } else if state == .levelStable && absAngle <= stableDeadZone {
            // Stay in stable state if within dead zone
            targetState = .levelStable
        } else {
            targetState = .offLevel(angleDeg: angle)
        }
        
        // New improved state machine logic
        switch (state, targetState) {
        case (.hidden, .levelMerged), (.offLevel, .levelMerged):
            // Immediate transition to level merged - no stability window required

            state = .levelMerged
            levelStableStartTime = now  // Start tracking stability for disappearance
            levelStartTime = nil
            offLevelStartTime = nil
            
        case (.levelMerged, .levelMerged):
            // Check if we should transition to stable (disappear)
            if let stableStart = levelStableStartTime {
                if now.timeIntervalSince(stableStart) >= stabilityWindow {

                    state = .levelStable
                    levelStableStartTime = nil
                    levelStartTime = nil
                    offLevelStartTime = nil
                }
            }
            
        case (.levelMerged, .offLevel):
            // Leaving level state from levelMerged - apply hysteresis
            if absAngle > hysteresisThreshold {
                if offLevelStartTime == nil {
                    offLevelStartTime = now

                } else if now.timeIntervalSince(offLevelStartTime!) >= hysteresisWindow {

                    state = .offLevel(angleDeg: angle)
                    levelStartTime = nil
                    offLevelStartTime = nil
                    levelStableStartTime = nil
                }
            }
            
        case (.levelStable, .offLevel):
            // Leaving stable state - use larger dead zone to prevent oscillation
            if absAngle > stableDeadZone {
                state = .offLevel(angleDeg: angle)
                levelStartTime = nil
                offLevelStartTime = nil
                levelStableStartTime = nil
            }
            
        case (.levelStable, .levelMerged):
            // This should rarely happen since we prefer staying in stable state
            // Only transition back to merged if device becomes very precisely level again
            if absAngle <= (levelThreshold * 0.5) {  // Very strict: ≤0.5°

                state = .levelMerged
                levelStableStartTime = now  // Restart stability timer
                levelStartTime = nil
                offLevelStartTime = nil
            }
            
        case (.hidden, .offLevel), (.offLevel, .offLevel):
            // Direct transition to off-level
            state = .offLevel(angleDeg: angle)
            levelStartTime = nil
            offLevelStartTime = nil
            levelStableStartTime = nil
            
        case (.levelStable, .levelStable):
            // Stay in stable state (all indicators hidden)
            break
            
        case (.hidden, .hidden):
            // Stay hidden
            break
            
        case (.levelMerged, .hidden), (.offLevel, .hidden), (.levelStable, .hidden):
            // Going to hidden state
            state = .hidden
            levelStartTime = nil
            offLevelStartTime = nil
            levelStableStartTime = nil
            
        // These cases should never occur since .levelStable is not a target state
        // but we need them for exhaustiveness
        case (.hidden, .levelStable), (.offLevel, .levelStable), (.levelMerged, .levelStable):
            // Treat as levelMerged since that's what it effectively is
            state = .levelMerged
            levelStableStartTime = now
            levelStartTime = nil
            offLevelStartTime = nil
        }
    }
    
    // MARK: - State Handling
    
    private func handleStateChange(from oldState: LevelState, to newState: LevelState) {
        // Update visual appearance
        updateVisibility(for: newState)
        updateGeometry(for: newState)
        
        // Handle VoiceOver announcements only (haptic removed - too aggressive)
        if case .levelMerged = newState {
            // VoiceOver announcement for accessibility
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Level")
            }
        } else if case .levelStable = newState {
            // VoiceOver announcement for stability
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Stable")
            }
        }
    }
    
    private func updateVisibility(for state: LevelState) {
        switch state {
        case .hidden:
            leftShortSegment.isHidden = true
            middleLongSegment.isHidden = true
            rightShortSegment.isHidden = true
            mergedLevelLine.isHidden = true
            
        case .offLevel:
            leftShortSegment.isHidden = false
            middleLongSegment.isHidden = false
            rightShortSegment.isHidden = false
            mergedLevelLine.isHidden = true
            
        case .levelMerged:
            leftShortSegment.isHidden = true
            middleLongSegment.isHidden = true
            rightShortSegment.isHidden = true
            mergedLevelLine.isHidden = false
            
        case .levelStable:
            leftShortSegment.isHidden = true
            middleLongSegment.isHidden = true
            rightShortSegment.isHidden = true
            mergedLevelLine.isHidden = true
        }
    }
    
    private func updateGeometry(for state: LevelState) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY + yOffset)
        
        // Check if bounds are zero (not yet laid out)
        if bounds.width == 0 || bounds.height == 0 {
            return
        }
        
        switch state {
        case .hidden, .levelStable:
            break
            
        case .offLevel(let angleDeg):
            updateThreeSegmentGeometry(center: center, angleDeg: angleDeg)
            
        case .levelMerged:
            updateMergedLevelGeometry(center: center)
        }
    }
    
    private func updateThreeSegmentGeometry(center: CGPoint, angleDeg: Float) {
        // Native iOS Camera pattern: "-- ----- --" (short-long-short)
        // Left and right segments are ALWAYS horizontal and aligned with grid
        // Only the middle segment rotates with device tilt
        
        let angleRadians = CGFloat(angleDeg * .pi / 180.0)
        
        // Left short segment (always horizontal)
        let leftStart = CGPoint(
            x: center.x - totalIndicatorWidth/2,
            y: center.y
        )
        let leftEnd = CGPoint(
            x: leftStart.x + shortSegmentLength,
            y: center.y
        )
        
        let leftPath = UIBezierPath()
        leftPath.move(to: leftStart)
        leftPath.addLine(to: leftEnd)
        leftShortSegment.path = leftPath.cgPath
        
        // Right short segment (always horizontal)
        let rightEnd = CGPoint(
            x: center.x + totalIndicatorWidth/2,
            y: center.y
        )
        let rightStart = CGPoint(
            x: rightEnd.x - shortSegmentLength,
            y: center.y
        )
        
        let rightPath = UIBezierPath()
        rightPath.move(to: rightStart)
        rightPath.addLine(to: rightEnd)
        rightShortSegment.path = rightPath.cgPath
        
        // Middle long segment (directly uses gravity-based horizon angle)
        // IMPORTANT: The angle is now calculated from gravity vector (atan2)
        // This gives us the TRUE world-relative horizon angle - use it directly
        let middleHalfLength = longSegmentLength / 2
        let middleStart = CGPoint(
            x: center.x - middleHalfLength * cos(angleRadians),
            y: center.y - middleHalfLength * sin(angleRadians)
        )
        let middleEnd = CGPoint(
            x: center.x + middleHalfLength * cos(angleRadians),
            y: center.y + middleHalfLength * sin(angleRadians)
        )
        
        let middlePath = UIBezierPath()
        middlePath.move(to: middleStart)
        middlePath.addLine(to: middleEnd)
        middleLongSegment.path = middlePath.cgPath
    }
    
    private func updateMergedLevelGeometry(center: CGPoint) {
        // Solid yellow line across the full indicator width (merged state)
        let startPoint = CGPoint(
            x: center.x - totalIndicatorWidth/2,
            y: center.y
        )
        let endPoint = CGPoint(
            x: center.x + totalIndicatorWidth/2,
            y: center.y
        )
        
        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        mergedLevelLine.path = path.cgPath
    }
    
    // MARK: - Layout
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // Update geometry when bounds change
        updateGeometry(for: state)
    }
}
