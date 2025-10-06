//
//  FrameFeatures.swift
//  Camera Coach
//
//  Immutable data structure representing analyzed features from a camera frame.
//  Used by the GuidanceEngine to make decisions.
//

import Foundation
import CoreGraphics
import CoreMotion

public struct FrameFeatures {
    // MARK: - Horizon & Orientation
    public let horizonDegrees: Float   // +right / -left (positive = tilted right) - FILTERED for guidance logic
    public let rawHorizonDegrees: Float // +right / -left - RAW device tilt for visual display
    public let horizonStableMs: Int    // milliseconds horizon has been stable
    
    // MARK: - Face Detection
    public let faceRect: CGRect?       // normalized [0,1] coordinates, nil if no face (primary subject)
    public let faceStableMs: Int       // milliseconds face center variance below threshold
    public let faceSizePercentage: Float? // % of frame height
    
    // MARK: - Multi-Face Detection (NEW)
    public let allFaceRects: [CGRect]  // all detected faces in normalized coordinates
    public let faceCount: Int          // total number of detected faces
    public let groupHeadroomPercentage: Float? // % of frame height above topmost face
    public let primaryFaceIndex: Int?  // index of primary subject in allFaceRects (nil if no faces)

    // MARK: - Face Orientation (Week 7)
    public let faceOrientation: FaceOrientation? // detected orientation from bbox motion
    public let orientationConfidence: Float      // 0.0-1.0 confidence in orientation detection

    // MARK: - Edge Density Analysis (Week 7)
    public let leftEdgeDensity: Float?    // Edge density on left side of face bbox (0-1)
    public let rightEdgeDensity: Float?   // Edge density on right side of face bbox (0-1)
    public let hasEdgeConflict: Bool      // True if face is too close to strong edges
    
    // MARK: - Composition
    public let headroomPercentage: Float?  // % of frame height above face (primary subject - LEGACY)
    public let thirdsOffsetPercentage: Float? // horizontal offset from rule of thirds (0 = perfect)
    public let faceVerticalPosition: Float? // vertical center of face as % of frame height (0=bottom, 100=top)

    // MARK: - Template System (NEW)
    public let currentTemplate: Template?           // Currently active template
    public let templateAlignment: TemplateAlignment?   // Face-to-template alignment data
    public let recommendedTemplate: Template?       // Auto-recommended template based on scene
    public let templateSwitchStableMs: Int          // Ms since last template switch
    
    // MARK: - Performance
    public let timestamp: TimeInterval // when this frame was captured
    public let processingLatencyMs: Int // time to process this frame
    
    // MARK: - System State
    public let thermalState: ProcessInfo.ThermalState
    public let currentFPS: Float
    
    // MARK: - Initialization
    public init(
        horizonDegrees: Float,
        rawHorizonDegrees: Float,
        horizonStableMs: Int,
        faceRect: CGRect?,
        faceStableMs: Int,
        faceSizePercentage: Float?,
        allFaceRects: [CGRect] = [],
        faceCount: Int = 0,
        groupHeadroomPercentage: Float? = nil,
        primaryFaceIndex: Int? = nil,
        faceOrientation: FaceOrientation? = nil,
        orientationConfidence: Float = 0.0,
        leftEdgeDensity: Float? = nil,
        rightEdgeDensity: Float? = nil,
        hasEdgeConflict: Bool = false,
        headroomPercentage: Float?,
        thirdsOffsetPercentage: Float?,
        faceVerticalPosition: Float? = nil,
        currentTemplate: Template? = nil,
        templateAlignment: TemplateAlignment? = nil,
        recommendedTemplate: Template? = nil,
        templateSwitchStableMs: Int = 0,
        timestamp: TimeInterval,
        processingLatencyMs: Int,
        thermalState: ProcessInfo.ThermalState,
        currentFPS: Float
    ) {
        self.horizonDegrees = horizonDegrees
        self.rawHorizonDegrees = rawHorizonDegrees
        self.horizonStableMs = horizonStableMs
        self.faceRect = faceRect
        self.faceStableMs = faceStableMs
        self.faceSizePercentage = faceSizePercentage
        self.allFaceRects = allFaceRects
        self.faceCount = faceCount
        self.groupHeadroomPercentage = groupHeadroomPercentage
        self.primaryFaceIndex = primaryFaceIndex
        self.faceOrientation = faceOrientation
        self.orientationConfidence = orientationConfidence
        self.leftEdgeDensity = leftEdgeDensity
        self.rightEdgeDensity = rightEdgeDensity
        self.hasEdgeConflict = hasEdgeConflict
        self.headroomPercentage = headroomPercentage
        self.thirdsOffsetPercentage = thirdsOffsetPercentage
        self.faceVerticalPosition = faceVerticalPosition
        self.currentTemplate = currentTemplate
        self.templateAlignment = templateAlignment
        self.recommendedTemplate = recommendedTemplate
        self.templateSwitchStableMs = templateSwitchStableMs
        self.timestamp = timestamp
        self.processingLatencyMs = processingLatencyMs
        self.thermalState = thermalState
        self.currentFPS = currentFPS
    }
    
    // MARK: - Computed Properties
    public var hasStableFace: Bool {
        guard let _ = faceRect else { return false }
        return faceStableMs >= Config.faceStabilityThresholdMs
    }
    
    public var hasStableHorizon: Bool {
        return horizonStableMs >= Config.stabilityWindowMs
    }
    
    public var isHorizonLevel: Bool {
        return abs(horizonDegrees) <= Config.horizonThresholdDegrees
    }
    
    public var isHeadroomInTarget: Bool {
        guard let headroom = headroomPercentage else { return false }

        // 🎯 CRITICAL FIX: Use context-aware target based on vertical position
        let targetRange: ClosedRange<Float>
        if let verticalPos = faceVerticalPosition {
            if verticalPos >= 66 {
                targetRange = Config.upperThirdsHeadroomRange  // 0-8% for upper third
            } else if verticalPos >= 33 {
                targetRange = Config.centeredHeadroomRange  // 7-12% for centered
            } else {
                targetRange = Config.lowerThirdsHeadroomRange  // 15-25% for lower third
            }
        } else {
            targetRange = Config.targetHeadroomPercentage  // Fallback
        }

        return targetRange.contains(headroom)
    }

    public var isGroupHeadroomInTarget: Bool {
        guard let groupHeadroom = groupHeadroomPercentage else { return false }

        // Group headroom uses same context-aware logic
        let targetRange: ClosedRange<Float>
        if let verticalPos = faceVerticalPosition {
            if verticalPos >= 66 {
                targetRange = Config.upperThirdsHeadroomRange
            } else if verticalPos >= 33 {
                targetRange = Config.centeredHeadroomRange
            } else {
                targetRange = Config.lowerThirdsHeadroomRange
            }
        } else {
            targetRange = Config.targetHeadroomPercentage
        }

        return targetRange.contains(groupHeadroom)
    }
    
    public var hasMultipleFaces: Bool {
        return faceCount > 1
    }
    
    public var primaryFaceRect: CGRect? {
        guard let index = primaryFaceIndex, index < allFaceRects.count else { return faceRect }
        return allFaceRects[index]
    }
    
    public var isThirdsAligned: Bool {
        guard let offset = thirdsOffsetPercentage else { return false }
        return abs(offset) <= Config.thirdsTolerancePercentage
    }
    
    public var isPerformanceAcceptable: Bool {
        return processingLatencyMs <= Config.maxFrameLoopLatencyMs &&
               currentFPS >= Float(Config.minStableFPS)
    }

    // MARK: - Template System Computed Properties
    public var hasActiveTemplate: Bool {
        return currentTemplate != nil
    }

    public var isTemplateAligned: Bool {
        return templateAlignment?.withinThreshold == true
    }

    public var hasTemplateRecommendation: Bool {
        return recommendedTemplate != nil
    }

    public var templateSwitchStable: Bool {
        return templateSwitchStableMs >= Config.templateSwitchCooldownMs
    }

    public var needsTemplateAlignment: Bool {
        guard hasActiveTemplate, let alignment = templateAlignment else { return false }
        return !alignment.withinThreshold && alignment.distance > Config.templateAlignmentThresholdPct
    }

    // MARK: - Additional Computed Properties
    public var calculatedHeadroomPercentage: Float? {
        guard let faceSize = faceSizePercentage else { return nil }
        return 100.0 - faceSize
    }

    public var calculatedThirdsOffset: Float? {
        guard let faceRect = faceRect else { return nil }
        let faceCenterX = faceRect.midX
        let offset = (faceCenterX - 0.5) * 100 // Convert to percentage
        return Float(offset)
    }

    // MARK: - Face Orientation Computed Properties (Week 7)
    public var hasFacingDirection: Bool {
        return faceOrientation != nil && orientationConfidence >= Config.minOrientationConfidence
    }

    public var leadSpacePercentage: Float? {
        guard let orientation = faceOrientation,
              let rect = faceRect,
              orientationConfidence >= Config.minOrientationConfidence else {
            return nil
        }

        // Calculate space in the facing direction
        switch orientation {
        case .left:
            // Facing left - measure space to the left of face
            return Float(rect.minX * 100.0)
        case .right:
            // Facing right - measure space to the right of face
            return Float((1.0 - rect.maxX) * 100.0)
        case .center:
            // Facing center - no clear lead space preference
            return nil
        }
    }
}

// MARK: - Face Orientation Enum (Week 7)
public enum FaceOrientation: String, Codable {
    case left      // Face is oriented/looking left
    case right     // Face is oriented/looking right
    case center    // Face is centered/forward (ambiguous)

    public var description: String {
        switch self {
        case .left: return "facing_left"
        case .right: return "facing_right"
        case .center: return "facing_center"
        }
    }
}

// MARK: - Extensions for Testing
extension FrameFeatures {
    /// Creates a FrameFeatures instance for testing with default values
    static func test(
        horizonDegrees: Float = 0.0,
        rawHorizonDegrees: Float = 0.0,
        horizonStableMs: Int = 500,
        faceRect: CGRect? = CGRect(x: 0.5, y: 0.4, width: 0.2, height: 0.3),
        faceStableMs: Int = 500,
        faceSizePercentage: Float? = 8.0,
        allFaceRects: [CGRect] = [CGRect(x: 0.5, y: 0.4, width: 0.2, height: 0.3)],
        faceCount: Int = 1,
        groupHeadroomPercentage: Float? = 10.0,
        primaryFaceIndex: Int? = 0,
        faceOrientation: FaceOrientation? = nil,
        orientationConfidence: Float = 0.0,
        leftEdgeDensity: Float? = nil,
        rightEdgeDensity: Float? = nil,
        hasEdgeConflict: Bool = false,
        headroomPercentage: Float? = 10.0,
        thirdsOffsetPercentage: Float? = 0.0,
        currentTemplate: Template? = nil,
        templateAlignment: TemplateAlignment? = nil,
        recommendedTemplate: Template? = nil,
        templateSwitchStableMs: Int = 500
    ) -> FrameFeatures {
        return FrameFeatures(
            horizonDegrees: horizonDegrees,
            rawHorizonDegrees: rawHorizonDegrees,
            horizonStableMs: horizonStableMs,
            faceRect: faceRect,
            faceStableMs: faceStableMs,
            faceSizePercentage: faceSizePercentage,
            allFaceRects: allFaceRects,
            faceCount: faceCount,
            groupHeadroomPercentage: groupHeadroomPercentage,
            primaryFaceIndex: primaryFaceIndex,
            faceOrientation: faceOrientation,
            orientationConfidence: orientationConfidence,
            leftEdgeDensity: leftEdgeDensity,
            rightEdgeDensity: rightEdgeDensity,
            hasEdgeConflict: hasEdgeConflict,
            headroomPercentage: headroomPercentage,
            thirdsOffsetPercentage: thirdsOffsetPercentage,
            currentTemplate: currentTemplate,
            templateAlignment: templateAlignment,
            recommendedTemplate: recommendedTemplate,
            templateSwitchStableMs: templateSwitchStableMs,
            timestamp: Date().timeIntervalSince1970,
            processingLatencyMs: 50,
            thermalState: .nominal,
            currentFPS: 30.0
        )
    }
}
