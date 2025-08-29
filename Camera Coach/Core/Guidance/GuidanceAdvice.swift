//
//  GuidanceAdvice.swift
//  Camera Coach
//
//  Represents a single piece of guidance advice from the engine.
//  Immutable and contains all information needed for display.
//

import Foundation

public enum GuidanceAction {
    case rotateLeft(degrees: Int)
    case rotateRight(degrees: Int)
    case tiltUp(degrees: Int)
    case tiltDown(degrees: Int)
    case moveLeft(percentage: Int)
    case moveRight(percentage: Int)
    
    var displayText: String {
        switch self {
        case .rotateLeft(let degrees):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.rotate_left", comment: "Rotate left guidance"), degrees)
        case .rotateRight(let degrees):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.rotate_right", comment: "Rotate right guidance"), degrees)
        case .tiltUp(let degrees):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.tilt_up", comment: "Tilt up guidance"), degrees)
        case .tiltDown(let degrees):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.tilt_down", comment: "Tilt down guidance"), degrees)
        case .moveLeft(let percentage):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.move_left", comment: "Move left guidance"), percentage)
        case .moveRight(let percentage):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.move_right", comment: "Move right guidance"), percentage)
        }
    }
}

public enum GuidanceType: String, CaseIterable {
    case horizon = "horizon"
    case headroom = "headroom"
    case thirds = "thirds"
    case leadspace = "leadspace"
    
    var priority: Int {
        switch self {
        case .headroom: return 1      // Highest priority
        case .horizon: return 2
        case .thirds: return 3
        case .leadspace: return 4     // Lowest priority
        }
    }
}

public struct GuidanceAdvice {
    // MARK: - Core Properties
    public let action: GuidanceAction
    public let type: GuidanceType
    public let reason: String
    public let confidence: Float      // 0.0 to 1.0
    public let cooldownMs: Int       // suggested min cooldown before next hint
    
    // MARK: - Metadata
    public let timestamp: TimeInterval
    public let ruleVersion: String
    
    // MARK: - Initialization
    public init(
        action: GuidanceAction,
        type: GuidanceType,
        reason: String,
        confidence: Float,
        cooldownMs: Int,
        ruleVersion: String = "1.0"
    ) {
        self.action = action
        self.type = type
        self.reason = reason
        self.confidence = max(0.0, min(1.0, confidence)) // Clamp to 0-1
        self.cooldownMs = max(0, cooldownMs)
        self.timestamp = Date().timeIntervalSince1970
        self.ruleVersion = ruleVersion
    }
    
    // MARK: - Computed Properties
    public var displayText: String {
        // Format: "Action. Reason." (e.g., "Tilt up 5°. Better headroom.")
        return "\(action.displayText). \(reason)"
    }
    
    public var wordCount: Int {
        return displayText.components(separatedBy: .whitespaces).count
    }
    
    public var isValid: Bool {
        return wordCount <= Config.maxGuidanceWords &&
               confidence > 0.0 &&
               cooldownMs >= 0
    }
}

// MARK: - Extensions for Testing
extension GuidanceAdvice {
    /// Creates a test instance for development
    static func test(
        action: GuidanceAction = .tiltUp(degrees: 5),
        type: GuidanceType = .headroom,
        reason: String = "Better headroom",
        confidence: Float = 0.8,
        cooldownMs: Int = 600
    ) -> GuidanceAdvice {
        return GuidanceAdvice(
            action: action,
            type: type,
            reason: reason,
            confidence: confidence,
            cooldownMs: cooldownMs
        )
    }
}
