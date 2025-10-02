//
//  Template.swift
//  Camera Coach
//
//  Silhouette template data structures and types.
//  Based on user's innovative JSON template design for revolutionary composition guidance.
//

import Foundation
import CoreGraphics

// MARK: - Template Data Structure
/// Core template structure based on user's JSON design
public struct Template: Codable, Identifiable, Hashable {
    public let id: String
    public let category: TemplateCategory
    public let description: String
    public let orientation: CameraOrientation
    public let headAnchorRect: CGRect
    public let headroomRangePct: HeadroomRange
    public let horizonToleranceDeg: Float
    public let flipAllowed: Bool
    public let aspectVariants: [String]

    // MARK: - Computed Properties
    /// Center point of the head anchor area
    public var headCenter: CGPoint {
        return CGPoint(
            x: headAnchorRect.midX,
            y: headAnchorRect.midY
        )
    }

    /// Template suitable for current device orientation
    public var isPortrait: Bool {
        return orientation == .portrait
    }

    /// Expected headroom center value
    public var targetHeadroomPct: Float {
        return (headroomRangePct.min + headroomRangePct.max) / 2.0
    }
}

// MARK: - Supporting Types
public enum TemplateCategory: String, CaseIterable, Codable {
    case full_body = "full_body"
    case half_body = "half_body"
    case close_up = "close_up"
    case couple = "couple"

    /// Localized display name
    public var displayName: String {
        switch self {
        case .full_body:
            return NSLocalizedString("template.category.full_body", comment: "Full body template category")
        case .half_body:
            return NSLocalizedString("template.category.half_body", comment: "Half body template category")
        case .close_up:
            return NSLocalizedString("template.category.close_up", comment: "Close up template category")
        case .couple:
            return NSLocalizedString("template.category.couple", comment: "Couple template category")
        }
    }

    /// Expected number of subjects for this category
    public var expectedSubjectCount: Int {
        switch self {
        case .full_body, .half_body, .close_up:
            return 1
        case .couple:
            return 2
        }
    }
}

public enum CameraOrientation: String, Codable {
    case portrait = "portrait"
    case landscape = "landscape"
}

public struct HeadroomRange: Codable, Hashable {
    public let min: Float
    public let max: Float

    /// Check if a headroom value is within this range
    public func contains(_ value: Float) -> Bool {
        return value >= min && value <= max
    }

    /// Distance from range (0 if within range, positive if outside)
    public func distanceFrom(_ value: Float) -> Float {
        if contains(value) {
            return 0.0
        } else if value < min {
            return min - value
        } else {
            return value - max
        }
    }
}

// MARK: - Template Alignment
/// Represents how well faces align with a template
public struct TemplateAlignment {
    public let offsetX: Float          // Horizontal offset percentage (-1 to 1)
    public let offsetY: Float          // Vertical offset percentage (-1 to 1)
    public let confidence: Float       // Alignment confidence 0-1
    public let withinThreshold: Bool   // Whether alignment is acceptable
    public let distance: Float         // Overall distance from ideal position

    public init(offsetX: Float, offsetY: Float, confidence: Float, withinThreshold: Bool, distance: Float) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.confidence = confidence
        self.withinThreshold = withinThreshold
        self.distance = distance
    }

    /// Create alignment result indicating perfect match
    public static var perfect: TemplateAlignment {
        return TemplateAlignment(
            offsetX: 0.0,
            offsetY: 0.0,
            confidence: 1.0,
            withinThreshold: true,
            distance: 0.0
        )
    }

    /// Create alignment result indicating no match possible
    public static var noMatch: TemplateAlignment {
        return TemplateAlignment(
            offsetX: 0.0,
            offsetY: 0.0,
            confidence: 0.0,
            withinThreshold: false,
            distance: Float.infinity
        )
    }
}

// MARK: - Template Collection Extensions
public extension Array where Element == Template {
    /// Filter templates by orientation
    func filtered(by orientation: CameraOrientation) -> [Template] {
        return filter { $0.orientation == orientation }
    }

    /// Filter templates by category
    func filtered(by category: TemplateCategory) -> [Template] {
        return filter { $0.category == category }
    }

    /// Filter templates suitable for given number of faces
    func suitable(for faceCount: Int) -> [Template] {
        return filter { template in
            switch template.category {
            case .couple:
                return faceCount >= 2
            case .full_body, .half_body, .close_up:
                return faceCount >= 1
            }
        }
    }

    /// Find template by ID
    func template(with id: String) -> Template? {
        return first { $0.id == id }
    }
}