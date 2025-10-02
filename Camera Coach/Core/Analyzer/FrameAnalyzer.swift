//
//  FrameAnalyzer.swift
//  Camera Coach
//
//  Analyzes camera frames to extract features for guidance.
//  Implements CoreMotion horizon detection with proper filtering.
//

import Foundation
import UIKit
import AVFoundation
import CoreMotion
import Vision
import CoreGraphics
import QuartzCore

public final class FrameAnalyzer: NSObject, ObservableObject {
    // MARK: - Properties
    private let motionManager = CMMotionManager()
    private let logger = Logger.shared
    private let thermalManager = ThermalManager.shared
    private let memoryProfiler = MemoryProfiler.shared

    // MARK: - Template System (NEW)
    private var templateEngine: TemplateEngine?
    private var currentTemplate: Template?
    private var templateSwitchTime: Date?
    
    // MARK: - Horizon Detection
    private var horizonHistory: [Float] = []
    private var horizonStabilityStart: Date?
    private var lastStableHorizon: Float = 0.0
    private var currentRawHorizonDegrees: Float = 0.0  // 🚀 Store raw device tilt for visual display
    
    // MARK: - Face Detection
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var faceStabilityStart: Date?
    private var lastFaceCenter: CGPoint?
    
    // MARK: - Performance
    private var frameCount = 0
    private var lastFrameTime: TimeInterval = 0
    private var processingTimes: [TimeInterval] = []
    private var lastProcessingTime: TimeInterval = 0

    // MARK: - Thermal Management
    private var thermalTestStartTime: Date?
    private var thermalEventCount = 0
    
    // MARK: - Initialization
    public override init() {
        super.init()
        setupMotionManager()
        setupFaceDetection()
        setupTemplateSystem()
    }

    private func setupTemplateSystem() {
        templateEngine = TemplateEngine.shared
        print("🎯 FrameAnalyzer template system initialized")
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Template System Control (NEW)
    public func setCurrentTemplate(_ template: Template?) {
        if currentTemplate?.id != template?.id {
            currentTemplate = template
            templateSwitchTime = Date()

            if let template = template {
                print("🎯 FrameAnalyzer template set: \(template.id)")
            } else {
                print("🎯 FrameAnalyzer template cleared")
            }
        }
    }
    
    // MARK: - Public Interface
    public func analyzeFrame(_ sampleBuffer: CMSampleBuffer) -> FrameFeatures {
        let startTime = CACurrentMediaTime()

        // Thermal-aware processing throttling
        let recommendedInterval = thermalManager.recommendedProcessingInterval
        if startTime - lastProcessingTime < recommendedInterval {
            // Skip this frame due to thermal throttling
            return createEmptyFrameFeatures(startTime: startTime)
        }
        lastProcessingTime = startTime

        // Get image buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return createEmptyFrameFeatures(startTime: startTime)
        }

        // Analyze horizon using CoreMotion
        let horizonDegrees = getCurrentHorizonDegrees()
        let horizonStableMs = getHorizonStabilityMs()

        // Thermal-aware face detection (privacy consent + thermal state)
        let shouldRunFaceDetection = PrivacyManager.shared.canUseFaceDetection && thermalManager.shouldEnableFaceDetection
        let faceAnalysis = shouldRunFaceDetection ? analyzeFace(in: imageBuffer) : createEmptyFaceAnalysis()
        
        // Calculate processing latency
        let endTime = CACurrentMediaTime()
        let latencyMs = Int((endTime - startTime) * 1000)
        
        // Update performance tracking
        updatePerformanceMetrics(latencyMs: latencyMs)
        
        // 🚀 NEW: Calculate template alignment if template is active
        let templateAlignment = calculateTemplateAlignment(faceAnalysis: faceAnalysis)
        let recommendedTemplate = calculateRecommendedTemplate(faceAnalysis: faceAnalysis)
        let templateSwitchStableMs = calculateTemplateSwitchStability()

        // Create frame features
        let features = FrameFeatures(
            horizonDegrees: horizonDegrees,
            rawHorizonDegrees: currentRawHorizonDegrees,  // 🚀 Pass raw device tilt for visual display
            horizonStableMs: horizonStableMs,
            faceRect: faceAnalysis.rect,
            faceStableMs: faceAnalysis.stableMs,
            faceSizePercentage: faceAnalysis.sizePercentage,
            allFaceRects: faceAnalysis.allFaceRects,
            faceCount: faceAnalysis.faceCount,
            groupHeadroomPercentage: faceAnalysis.groupHeadroomPercentage,
            primaryFaceIndex: faceAnalysis.primaryFaceIndex,
            headroomPercentage: faceAnalysis.headroomPercentage,
            thirdsOffsetPercentage: faceAnalysis.thirdsOffsetPercentage,
            currentTemplate: currentTemplate,
            templateAlignment: templateAlignment,
            recommendedTemplate: recommendedTemplate,
            templateSwitchStableMs: templateSwitchStableMs,
            timestamp: startTime,
            processingLatencyMs: latencyMs,
            thermalState: ProcessInfo.processInfo.thermalState,
            currentFPS: calculateCurrentFPS()
        )
        
        frameCount += 1
        return features
    }
    
    // MARK: - Setup
    private func setupMotionManager() {

        
        // Check if we have motion permissions
        if !motionManager.isDeviceMotionAvailable {
            return
        }
        
        // Set update interval
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0 // 20Hz updates (more appropriate for guidance)
        
        // Start motion updates with retry logic
        startMotionUpdates()
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {

            return
        }
        
        // Stop any existing updates first
        if motionManager.isDeviceMotionActive {

            motionManager.stopDeviceMotionUpdates()
        }
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            
            if let error = error {
                // Try to restart motion updates after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startMotionUpdates()
                }
                return
            }
            
            guard let motion = motion else { 
                return 
            }
            
            // 🚀 WORLD-RELATIVE HORIZON: Use gravity vector for proper world-relative roll calculation
            // This approach correctly isolates the horizon roll from pitch and yaw movements
            
            let pitchDegrees = Float(motion.attitude.pitch * 180.0 / .pi)
            
            // 🚀 CORRECT HORIZON CALCULATION: Use device roll for horizon leveling
            // The key insight: for horizon leveling, we want the roll angle relative to gravity
            // Use the attitude.roll which gives us the rotation around the Z-axis (camera direction)
            let deviceRollRadians = motion.attitude.roll
            let deviceRollDegrees = Float(deviceRollRadians * 180.0 / .pi)
            
            // 🚀 CRITICAL FIX: Prevent discontinuities at ±180° boundary
            // Normalize to [-90, 90] range for horizon display to avoid 360° jumps
            let normalizedHorizonRoll: Float
            if deviceRollDegrees > 90.0 {
                normalizedHorizonRoll = deviceRollDegrees - 180.0
            } else if deviceRollDegrees < -90.0 {
                normalizedHorizonRoll = deviceRollDegrees + 180.0
            } else {
                normalizedHorizonRoll = deviceRollDegrees
            }
            

            
            // Always update the raw value for visual display
            self.currentRawHorizonDegrees = normalizedHorizonRoll
            
            // Update horizon history with confidence levels based on device orientation
            if abs(pitchDegrees) < 80.0 {
                // High confidence: device is reasonably upright, horizon is meaningful
                self.updateHorizonHistory(normalizedHorizonRoll)
            } else if abs(pitchDegrees) < 85.0 {
                // Medium confidence: device is tilted but horizon still somewhat meaningful
                self.updateHorizonHistory(normalizedHorizonRoll)
            } else {
                // Low confidence: device is nearly vertical, but still update to avoid stuck line
                self.updateHorizonHistory(normalizedHorizonRoll)
            }
        }
        
        // Verify motion updates started successfully
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if self.motionManager.isDeviceMotionActive {
                // Motion manager started successfully
            } else {
                // Motion manager failed to start - retrying
                self.startMotionUpdates()
            }
        }
    }
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
        // Note: VNDetectFaceRectanglesRequest doesn't have maximumObservations
        // It will detect all faces, we'll use the first one in analyzeFace
    }
    
    // MARK: - Horizon Analysis
    private func updateHorizonHistory(_ degrees: Float) {

        
        // 🚀 CRITICAL FIX: Improved low-pass filter for smoother horizon
        // Previous α=0.15 was too aggressive, causing jerky guidance
        // New α=0.3 provides better balance between responsiveness and stability
        let alpha: Float = 0.3
        let filteredDegrees: Float
        
        if horizonHistory.isEmpty {
            filteredDegrees = degrees
        } else {
            let lastValue = horizonHistory.last!
            filteredDegrees = lastValue + alpha * (degrees - lastValue)
        }
        
        horizonHistory.append(filteredDegrees)
        
        // Keep only recent history (last 20 samples for 20Hz updates)
        if horizonHistory.count > 20 {
            horizonHistory.removeFirst()
        }

        
        // Check stability
        checkHorizonStability(filteredDegrees)
    }
    
    private func checkHorizonStability(_ degrees: Float) {
        // 🚀 CRITICAL FIX: Simplified horizon stability logic
        // Previous logic was overly complex and could interfere with guidance generation
        
        let threshold = Config.horizonThresholdDegrees
        let absDegrees = abs(degrees)
        
        if absDegrees <= threshold {
            // Horizon is level - start counting stability
            if horizonStabilityStart == nil {
                horizonStabilityStart = Date()
                // Horizon level - starting stability timer
            }
        } else {
            // Horizon is tilted - start counting stability for tilted position
            if horizonStabilityStart == nil {
                horizonStabilityStart = Date()
                // Horizon tilted - starting stability timer for tilted position
            }
        }
        
        // Note: We don't reset stability for tilted horizons anymore
        // This allows guidance to trigger once the tilted position is stable
        // This matches iOS Camera app behavior - it guides you to level, not to random positions
    }
    
    private func getCurrentHorizonDegrees() -> Float {
        return horizonHistory.last ?? 0.0
    }
    
    private func getHorizonStabilityMs() -> Int {
        guard let startTime = horizonStabilityStart else { return 0 }
        return Int(Date().timeIntervalSince(startTime) * 1000)
    }
    
    // MARK: - Face Analysis
    private func analyzeFace(in imageBuffer: CVPixelBuffer) -> FaceAnalysis {
        guard let faceRequest = faceDetectionRequest else {
            return createEmptyFaceAnalysis()
        }
        
        // Create image request handler
        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, options: [:])
        
        do {
            // Perform face detection
            try handler.perform([faceRequest])
            
            // Process results - now handling multiple faces
            guard let results = faceRequest.results, !results.isEmpty else {
                resetFaceStability()
                return createEmptyFaceAnalysis()
            }
            
            // 🚀 MULTI-FACE ENHANCEMENT: Process all detected faces
            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            )
            
            // Convert all faces to image coordinates and filter by size
            let allFaceRects = results.compactMap { face -> CGRect? in
                let rect = VNImageRectForNormalizedRect(face.boundingBox, Int(imageSize.width), Int(imageSize.height))
                let area = rect.width * rect.height
                let imageArea = imageSize.width * imageSize.height
                let sizePercentage = Float((area / imageArea) * 100.0)
                
                let minSizeThreshold = Config.enableFarDistanceDetection ? Config.farDistanceMinFaceSizePercentage : Config.minFaceSizePercentage
                return sizePercentage >= minSizeThreshold ? rect : nil
            }
            
            // If no faces meet size requirements, return empty
            guard !allFaceRects.isEmpty else {
                resetFaceStability()
                return createEmptyFaceAnalysis()
            }

            // Memory-aware face count limiting
            let maxFaceCount = memoryProfiler.recommendedMaxFaceCount
            let memoryLimitedFaceRects = Array(allFaceRects.prefix(maxFaceCount))

            // Log if we had to limit faces due to memory pressure
            if allFaceRects.count > maxFaceCount {
                logger.logMemoryFaceLimiting(
                    detectedFaces: allFaceRects.count,
                    limitedTo: maxFaceCount,
                    memoryPressure: memoryProfiler.memoryPressureLevel.description
                )
            }
            
            // Select primary subject from memory-limited valid faces
            let validFaces = results.filter { face in
                let rect = VNImageRectForNormalizedRect(face.boundingBox, Int(imageSize.width), Int(imageSize.height))
                return memoryLimitedFaceRects.contains(rect)
            }
            
            guard let primaryFace = selectPrimarySubject(from: validFaces, imageSize: imageSize),
                  let primaryFaceIndex = validFaces.firstIndex(of: primaryFace) else {
                resetFaceStability()
                return createEmptyFaceAnalysis()
            }
            
            let primaryFaceRect = memoryLimitedFaceRects[primaryFaceIndex]
            
            // Calculate primary face metrics (for legacy compatibility)
            let faceArea = primaryFaceRect.width * primaryFaceRect.height
            let imageArea = imageSize.width * imageSize.height
            let sizePercentage = Float((faceArea / imageArea) * 100.0)
            let headroomPercentage = Float((primaryFaceRect.minY / imageSize.height) * 100.0)
            
            // 🚀 GROUP HEADROOM CALCULATION: Find topmost face for group headroom (memory-limited)
            let topmostY = memoryLimitedFaceRects.map { $0.minY }.min() ?? primaryFaceRect.minY
            let groupHeadroomPercentage = Float((topmostY / imageSize.height) * 100.0)

            // 🚀 DEBUG: Log multi-face detection (memory-aware)
            print("🔍 FACES DETECTED: Total=\(allFaceRects.count), Limited=\(memoryLimitedFaceRects.count), Primary Headroom=\(String(format: "%.1f", headroomPercentage))%, Group Headroom=\(String(format: "%.1f", groupHeadroomPercentage))%")
            
            // Calculate thirds offset (based on primary face)
            let faceCenterX = primaryFaceRect.midX
            let imageCenterX = imageSize.width / 2
            let offset = (faceCenterX - imageCenterX) / imageSize.width
            let thirdsOffsetPercentage = Float(offset * 100.0)
            
            // Check face stability with enhanced tracking (based on primary face)
            let stableMs = checkFaceStability(faceCenter: CGPoint(x: primaryFaceRect.midX, y: primaryFaceRect.midY))
            
            return FaceAnalysis(
                rect: primaryFaceRect,
                stableMs: stableMs,
                sizePercentage: sizePercentage,
                headroomPercentage: headroomPercentage,
                thirdsOffsetPercentage: thirdsOffsetPercentage,
                allFaceRects: memoryLimitedFaceRects,
                faceCount: memoryLimitedFaceRects.count,
                groupHeadroomPercentage: groupHeadroomPercentage,
                primaryFaceIndex: primaryFaceIndex
            )
        } catch {
            // Enhanced error recovery for Vision framework failures
            handleVisionFrameworkError(error)
            resetFaceStability()
            return createEmptyFaceAnalysis()
        }
    }
    
    // 🚀 WEEK 3: Primary Subject Selection Algorithm
    private func selectPrimarySubject(from faces: [VNFaceObservation], imageSize: CGSize) -> VNFaceObservation? {
        guard !faces.isEmpty else { return nil }
        
        // Convert all faces to image coordinates for analysis
        let faceRects = faces.map { face -> (face: VNFaceObservation, rect: CGRect, area: CGFloat) in
            let rect = VNImageRectForNormalizedRect(face.boundingBox, Int(imageSize.width), Int(imageSize.height))
            let area = rect.width * rect.height
            return (face: face, rect: rect, area: area)
        }
        
        // Filter faces that meet minimum size requirement
        let minArea = imageSize.width * imageSize.height * CGFloat(Config.minFaceSizePercentage / 100.0)
        let validFaces = faceRects.filter { $0.area >= minArea }
        
        guard !validFaces.isEmpty else { return nil }
        
        // Primary subject selection criteria:
        // 1. Largest face (most prominent subject)
        // 2. Most central face (better composition)
        // 3. Prefer faces in upper 2/3 of frame (portrait convention)
        
        let scoredFaces = validFaces.map { faceData -> (face: VNFaceObservation, score: Float) in
            let rect = faceData.rect
            let area = faceData.area
            
            // Size score: larger faces score higher (40% weight)
            let maxArea = validFaces.max(by: { $0.area < $1.area })?.area ?? 1.0
            let sizeScore = Float(area / maxArea) * 0.4
            
            // Centrality score: faces closer to center score higher (30% weight)
            let centerX = imageSize.width / 2
            let faceDistance = abs(rect.midX - centerX)
            let maxDistance = imageSize.width / 2
            let centralityScore = (1.0 - Float(faceDistance / maxDistance)) * 0.3
            
            // Vertical position score: faces in upper 2/3 score higher (30% weight)
            let upperThird = imageSize.height / 3
            let verticalScore: Float
            if rect.midY <= upperThird {
                verticalScore = 0.3  // Upper third: full score
            } else if rect.midY <= (2 * upperThird) {
                verticalScore = 0.2  // Middle third: partial score
            } else {
                verticalScore = 0.1  // Lower third: minimal score
            }
            
            let totalScore = sizeScore + centralityScore + verticalScore
            return (face: faceData.face, score: totalScore)
        }
        
        // Return the highest scoring face
        return scoredFaces.max(by: { $0.score < $1.score })?.face
    }
    
    private func createEmptyFaceAnalysis() -> FaceAnalysis {
        return FaceAnalysis(
            rect: nil,
            stableMs: 0,
            sizePercentage: nil,
            headroomPercentage: nil,
            thirdsOffsetPercentage: nil,
            allFaceRects: [],
            faceCount: 0,
            groupHeadroomPercentage: nil,
            primaryFaceIndex: nil
        )
    }
    
    private func resetFaceStability() {
        faceStabilityStart = nil
        lastFaceCenter = nil
    }
    
    // 🚀 WEEK 3: Enhanced Face Stability Tracking
    private func checkFaceStability(faceCenter: CGPoint) -> Int {
        let currentCenter = faceCenter
        
        if let lastCenter = lastFaceCenter {
            let distance = sqrt(pow(currentCenter.x - lastCenter.x, 2) + pow(currentCenter.y - lastCenter.y, 2))
            
            // 🚀 Dynamic stability threshold based on face size and movement patterns
            // Larger faces can tolerate more movement, smaller faces need to be more stable
            let baseThreshold: CGFloat = 15.0 // base threshold in pixels
            let dynamicThreshold = baseThreshold // Could adjust based on face size in future
            
            if distance < dynamicThreshold {
                // Face is stable - start or continue counting
                if faceStabilityStart == nil {
                    faceStabilityStart = Date()
                }
            } else {
                // Face moved too much - reset stability
                faceStabilityStart = nil
            }
        } else {
            // First face detection - start stability tracking
            faceStabilityStart = Date()
        }
        
        lastFaceCenter = currentCenter
        
        guard let startTime = faceStabilityStart else { return 0 }
        let stabilityDuration = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Cap stability time at reasonable maximum to prevent overflow
        return min(stabilityDuration, 30000) // Max 30 seconds
    }
    
    // MARK: - Performance Monitoring
    private func updatePerformanceMetrics(latencyMs: Int) {
        let latencySeconds = TimeInterval(latencyMs) / 1000.0
        processingTimes.append(latencySeconds)
        
        // Keep only recent processing times
        if processingTimes.count > 60 { // Last 60 frames
            processingTimes.removeFirst()
        }
        
        // Log performance metrics periodically
        if frameCount % 30 == 0 { // Every 30 frames
            let sortedTimes = processingTimes.sorted()
            let p95Index = Int(Double(sortedTimes.count) * 0.95)
            let p95Latency = sortedTimes[p95Index]
            
            logger.logFPSSample(
                average: calculateCurrentFPS(),
                p95: Float(1.0 / p95Latency)
            )
        }
    }
    
    private func calculateCurrentFPS() -> Float {
        guard processingTimes.count >= 2 else { return 0.0 }
        
        let recentTimes = Array(processingTimes.suffix(10))
        let avgInterval = recentTimes.reduce(0, +) / Double(recentTimes.count)
        
        return avgInterval > 0 ? Float(1.0 / avgInterval) : 0.0
    }
    
    // MARK: - Helper Methods
    private func createEmptyFrameFeatures(startTime: TimeInterval) -> FrameFeatures {
        return FrameFeatures(
            horizonDegrees: getCurrentHorizonDegrees(),
            rawHorizonDegrees: currentRawHorizonDegrees,  // 🚀 Pass raw device tilt for visual display
            horizonStableMs: getHorizonStabilityMs(),
            faceRect: nil,
            faceStableMs: 0,
            faceSizePercentage: nil,
            allFaceRects: [],
            faceCount: 0,
            groupHeadroomPercentage: nil,
            primaryFaceIndex: nil,
            headroomPercentage: nil,
            thirdsOffsetPercentage: nil,
            currentTemplate: currentTemplate,
            templateAlignment: nil,
            recommendedTemplate: nil,
            templateSwitchStableMs: calculateTemplateSwitchStability(),
            timestamp: startTime,
            processingLatencyMs: 0,
            thermalState: ProcessInfo.processInfo.thermalState,
            currentFPS: calculateCurrentFPS()
        )
    }

    // MARK: - Error Recovery
    private var visionErrorCount = 0
    private var lastVisionErrorTime: Date?
    private let maxVisionErrors = 5
    private let visionErrorResetInterval: TimeInterval = 30.0

    private func handleVisionFrameworkError(_ error: Error) {
        let currentTime = Date()

        // Reset error count if enough time has passed
        if let lastErrorTime = lastVisionErrorTime,
           currentTime.timeIntervalSince(lastErrorTime) > visionErrorResetInterval {
            visionErrorCount = 0
        }

        visionErrorCount += 1
        lastVisionErrorTime = currentTime

        // Log error with context
        logger.logVisionFrameworkError(
            error: error,
            errorCount: visionErrorCount,
            thermalState: ProcessInfo.processInfo.thermalState
        )

        // Implement progressive fallback strategy
        if visionErrorCount >= maxVisionErrors {
            logger.logVisionFrameworkFallback(errorCount: visionErrorCount)

            // Temporarily disable face detection to prevent cascade failures
            // Face detection will be re-enabled after the reset interval
            temporarilyDisableFaceDetection()
        }

        // Trigger thermal throttling if errors correlate with high thermal state
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.fair.rawValue {
            logger.logThermalThrottling(action: "reduce_vision_processing")
        }
    }

    private func temporarilyDisableFaceDetection() {
        // Set a flag or modify request to reduce processing load
        // This is a failsafe mechanism to prevent system overload
        DispatchQueue.main.asyncAfter(deadline: .now() + visionErrorResetInterval) { [weak self] in
            self?.visionErrorCount = 0
            self?.logger.logVisionFrameworkRecovery()
        }
    }

    // MARK: - Thermal Testing

    /// Start thermal endurance testing
    public func startThermalTest() {
        thermalTestStartTime = Date()
        thermalEventCount = 0
        logger.logEvent(LogEvent(
            name: "thermal_test_start",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "device_model": UIDevice.current.model,
                "initial_thermal_state": thermalManager.currentThermalState.rawValue.description
            ]
        ))
    }

    /// Stop thermal endurance testing and log results
    public func stopThermalTest() -> [String: Any] {
        guard let startTime = thermalTestStartTime else {
            return ["error": "No active thermal test"]
        }

        let duration = Date().timeIntervalSince(startTime)
        let averageFPS = calculateCurrentFPS()
        let thermalStats = thermalManager.getThermalStatistics()

        logger.logThermalSustainedTest(
            duration: duration,
            averageFPS: averageFPS,
            thermalEvents: thermalEventCount
        )

        thermalTestStartTime = nil

        return [
            "duration_seconds": duration,
            "average_fps": averageFPS,
            "thermal_events": thermalEventCount,
            "thermal_stats": thermalStats,
            "final_thermal_state": thermalManager.currentThermalState.rawValue.description,
            "performance_level": String(describing: thermalManager.performanceLevel)
        ]
    }

    /// Get current thermal testing status
    public func getThermalTestStatus() -> [String: Any] {
        guard let startTime = thermalTestStartTime else {
            return ["active": false]
        }

        let duration = Date().timeIntervalSince(startTime)
        return [
            "active": true,
            "duration_seconds": duration,
            "thermal_events": thermalEventCount,
            "current_fps": calculateCurrentFPS(),
            "thermal_state": thermalManager.currentThermalState.rawValue.description,
            "performance_level": String(describing: thermalManager.performanceLevel)
        ]
    }
}

// MARK: - Supporting Types
private struct FaceAnalysis {
    let rect: CGRect?                    // primary face rect (legacy)
    let stableMs: Int
    let sizePercentage: Float?
    let headroomPercentage: Float?       // primary face headroom (legacy)
    let thirdsOffsetPercentage: Float?

    // Multi-face support
    let allFaceRects: [CGRect]           // all detected faces
    let faceCount: Int                   // total face count
    let groupHeadroomPercentage: Float?  // topmost face headroom
    let primaryFaceIndex: Int?           // index of primary face in allFaceRects
}

// MARK: - Template Alignment Calculations (NEW)
extension FrameAnalyzer {
    private func calculateTemplateAlignment(faceAnalysis: FaceAnalysis) -> TemplateAlignment? {
        guard let template = currentTemplate,
              !faceAnalysis.allFaceRects.isEmpty,
              let templateEngine = templateEngine else {
            return nil
        }

        // Calculate alignment using template engine
        let alignment = templateEngine.calculateAlignment(faces: faceAnalysis.allFaceRects, template: template)

        print("🎯 Template alignment calculated: distance=\(String(format: "%.3f", alignment.distance)), confidence=\(String(format: "%.2f", alignment.confidence))")

        return alignment
    }

    private func calculateRecommendedTemplate(faceAnalysis: FaceAnalysis) -> Template? {
        guard let templateEngine = templateEngine,
              Config.autoTemplateRecommendation,
              faceAnalysis.faceCount > 0 else {
            return nil
        }

        // Don't recommend if template was just changed recently
        if let switchTime = templateSwitchTime,
           Date().timeIntervalSince(switchTime) < 2.0 {
            return nil
        }

        let currentOrientation: CameraOrientation = .portrait // TODO: Get from device
        let estimatedCategory = estimateTemplateCategoryFromFaceAnalysis(faceAnalysis)

        let recommendation = templateEngine.recommendTemplate(
            faceCount: faceAnalysis.faceCount,
            orientation: currentOrientation,
            faceSize: estimatedCategory
        )

        if let recommendation = recommendation,
           recommendation.id != currentTemplate?.id {
            print("🎯 Template recommendation: \(recommendation.id)")
        }

        return recommendation
    }

    private func calculateTemplateSwitchStability() -> Int {
        guard let switchTime = templateSwitchTime else { return 0 }
        return Int(Date().timeIntervalSince(switchTime) * 1000) // Convert to milliseconds
    }

    private func estimateTemplateCategoryFromFaceAnalysis(_ faceAnalysis: FaceAnalysis) -> TemplateCategory? {
        guard let faceSize = faceAnalysis.sizePercentage else { return nil }

        // Estimate template category based on face size in frame
        if faceSize >= 15.0 {
            return .close_up
        } else if faceSize >= 8.0 {
            return .half_body
        } else {
            return .full_body
        }
    }
}
