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
    
    // MARK: - Composition
    public let headroomPercentage: Float?  // % of frame height above face (primary subject - LEGACY)
    public let thirdsOffsetPercentage: Float? // horizontal offset from rule of thirds (0 = perfect)
    
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
        headroomPercentage: Float?,
        thirdsOffsetPercentage: Float?,
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
        self.headroomPercentage = headroomPercentage
        self.thirdsOffsetPercentage = thirdsOffsetPercentage
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
        return Config.targetHeadroomPercentage.contains(headroom)
    }
    
    public var isGroupHeadroomInTarget: Bool {
        guard let groupHeadroom = groupHeadroomPercentage else { return false }
        return Config.targetHeadroomPercentage.contains(groupHeadroom)
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
        headroomPercentage: Float? = 10.0,
        thirdsOffsetPercentage: Float? = 0.0
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
            headroomPercentage: headroomPercentage,
            thirdsOffsetPercentage: thirdsOffsetPercentage,
            timestamp: Date().timeIntervalSince1970,
            processingLatencyMs: 50,
            thermalState: .nominal,
            currentFPS: 30.0
        )
    }
}
