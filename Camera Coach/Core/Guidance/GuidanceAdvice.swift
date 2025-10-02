//
//  GuidanceAdvice.swift
//  Camera Coach
//
//  Represents a single piece of guidance advice from the engine.
//  Immutable and contains all information needed for display.
//

import Foundation

public enum GuidanceAction {
    // Legacy actions (preserved)
    case moveUp(amount: String)
    case moveDown(amount: String)
    case moveLeft(amount: String)
    case moveRight(amount: String)

    // Template-specific actions (NEW)
    case alignToTemplate(offsetX: Float, offsetY: Float)       // Precise template alignment
    case switchTemplate(to: Template)                          // Recommend different template
    case adjustForTemplate(direction: String, amount: String)  // "Move up 2cm to match silhouette"

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
        case .alignToTemplate(let offsetX, let offsetY):
            // Generate natural language based on offset direction
            let horizontalDirection = offsetX > 0.02 ? "right" : (offsetX < -0.02 ? "left" : "")
            let verticalDirection = offsetY > 0.02 ? "down" : (offsetY < -0.02 ? "up" : "")

            if !horizontalDirection.isEmpty && !verticalDirection.isEmpty {
                return NSLocalizedString("guidance.align_diagonal", comment: "Move \(verticalDirection) and \(horizontalDirection) to match template")
            } else if !horizontalDirection.isEmpty {
                return NSLocalizedString("guidance.align_horizontal", comment: "Move \(horizontalDirection) to match template")
            } else if !verticalDirection.isEmpty {
                return NSLocalizedString("guidance.align_vertical", comment: "Move \(verticalDirection) to match template")
            } else {
                return NSLocalizedString("guidance.perfect_alignment", comment: "Perfect alignment!")
            }
        case .switchTemplate(let template):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.switch_template", comment: "Try template: %@"), template.description)
        case .adjustForTemplate(let direction, let amount):
            return String.localizedStringWithFormat(NSLocalizedString("guidance.adjust_for_template", comment: "Move %@ %@ to match silhouette"), direction, amount)
        }
    }
}

public enum GuidanceType: String, CaseIterable {
    case templateAlignment = "template_alignment"  // NEW: Highest priority
    case headroom = "headroom"
    case thirds = "thirds"
    case leadspace = "leadspace"

    var priority: Int {
        switch self {
        case .templateAlignment: return 0   // NEW: Highest priority
        case .headroom: return 1
        case .thirds: return 2
        case .leadspace: return 3           // Lowest priority
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

    // MARK: - Template System Properties (NEW)
    public let relatedTemplate: Template?  // Associated template if applicable

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
        relatedTemplate: Template? = nil,
        ruleVersion: String = "1.0"
    ) {
        self.action = action
        self.type = type
        self.reason = reason
        self.confidence = max(0.0, min(1.0, confidence)) // Clamp to 0-1
        self.cooldownMs = max(0, cooldownMs)
        self.relatedTemplate = relatedTemplate
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

    // MARK: - Template System Computed Properties (NEW)
    public var isTemplateRelated: Bool {
        return type == .templateAlignment || relatedTemplate != nil
    }

    public var templateId: String? {
        return relatedTemplate?.id
    }

    public var adjustedConfidence: Float {
        // Boost confidence for template-based guidance
        if isTemplateRelated {
            return min(1.0, confidence + Config.templateConfidenceBoost)
        }
        return confidence
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
        cooldownMs: Int = 600,
        relatedTemplate: Template? = nil
    ) -> GuidanceAdvice {
        return GuidanceAdvice(
            action: action,
            type: type,
            reason: reason,
            confidence: confidence,
            cooldownMs: cooldownMs,
            relatedTemplate: relatedTemplate
        )
    }

    /// Creates a template alignment guidance for testing
    static func templateAlignmentTest(
        offsetX: Float = 0.1,
        offsetY: Float = -0.05,
        template: Template? = nil
    ) -> GuidanceAdvice {
        return GuidanceAdvice(
            action: .alignToTemplate(offsetX: offsetX, offsetY: offsetY),
            type: .templateAlignment,
            reason: "Match the silhouette",
            confidence: 0.9,
            cooldownMs: Config.templateAlignmentCooldownMs,
            relatedTemplate: template,
            ruleVersion: "template_v1.0"
        )
    }
}
