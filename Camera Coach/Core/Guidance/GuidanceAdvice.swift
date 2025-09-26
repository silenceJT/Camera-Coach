//
//  GuidanceAdvice.swift
//  Camera Coach
//
//  Represents a single piece of guidance advice from the engine.
//  Immutable and contains all information needed for display.
//

import Foundation

public enum GuidanceAction {
    case moveUp(amount: String)
    case moveDown(amount: String)
    case moveLeft(amount: String)
    case moveRight(amount: String)
    
    var displayText: String {
        switch self {
        case .moveUp(let amount):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.move_up", comment: "Move up guidance"), amount)
        case .moveDown(let amount):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.move_down", comment: "Move down guidance"), amount)
        case .moveLeft(let amount):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.move_left", comment: "Move left guidance"), amount)
        case .moveRight(let amount):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.move_right", comment: "Move right guidance"), amount)
        }
    }
}

public enum GuidanceType: String, CaseIterable {
    case headroom = "headroom"
    case thirds = "thirds"
    case leadspace = "leadspace"

    var priority: Int {
        switch self {
        case .headroom: return 1      // Highest priority
        case .thirds: return 2
        case .leadspace: return 3     // Lowest priority
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
        action: GuidanceAction = .moveUp(amount: "a little"),
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
