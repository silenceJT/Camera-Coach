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
    private var faceDetectionRequest: VNDetectFaceLandmarksRequest?
    private var faceStabilityStart: Date?
    private var lastFaceCenter: CGPoint?

    // MARK: - Face Orientation Tracking (Week 7)
    private var facePositionHistory: [CGPoint] = []            // Track face center positions
    private var orientationHistory: [FaceOrientation] = []     // Track detected orientations
    private var lastFaceRect: CGRect?                          // Previous frame's face bbox
    
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
            faceOrientation: faceAnalysis.faceOrientation,
            orientationConfidence: faceAnalysis.orientationConfidence,
            leftEdgeDensity: faceAnalysis.leftEdgeDensity,
            rightEdgeDensity: faceAnalysis.rightEdgeDensity,
            hasEdgeConflict: faceAnalysis.hasEdgeConflict,
            headroomPercentage: faceAnalysis.headroomPercentage,
            thirdsOffsetPercentage: faceAnalysis.thirdsOffsetPercentage,
            faceVerticalPosition: faceAnalysis.faceVerticalPosition,
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

            // 🌍 GRAVITY-BASED HORIZON (CORRECT METHOD - isolates roll from pitch):
            // For portrait mode, calculate roll angle that's independent of pitch
            // Key: Normalize the reference axis (Y-Z plane magnitude) to prevent pitch amplification

            // Calculate magnitude of gravity in Y-Z plane (perpendicular to roll axis)
            let gravityYZ = sqrt(motion.gravity.y * motion.gravity.y + motion.gravity.z * motion.gravity.z)

            // Roll angle = atan2(x-component, magnitude of perpendicular plane)
            // This gives TRUE roll angle regardless of pitch
            // NEGATE for counter-rotation (line tilts opposite to device)
            let horizonAngleRadians = -atan2(motion.gravity.x, gravityYZ)
            let normalizedHorizonRoll = Float(horizonAngleRadians * 180.0 / .pi)

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
        // 🚀 WEEK 7 ENHANCEMENT: Use landmarks for accurate orientation detection
        faceDetectionRequest = VNDetectFaceLandmarksRequest()
        // Note: VNDetectFaceLandmarksRequest provides facial landmarks (eyes, nose, mouth)
        // which we use for accurate head pose/orientation detection
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
        
        // Create image request handler with CORRECT orientation
        // CRITICAL: Back camera in portrait mode outputs buffer in .right orientation
        // We must tell Vision this so coordinates are calculated correctly
        let handler = VNImageRequestHandler(
            cvPixelBuffer: imageBuffer,
            orientation: .right,  // Back camera portrait = landscape right buffer
            options: [:]
        )
        
        do {
            // Perform face detection
            try handler.perform([faceRequest])
            
            // Process results - now handling multiple faces
            guard let results = faceRequest.results, !results.isEmpty else {
                resetFaceStability()
                return createEmptyFaceAnalysis()
            }
            
            // 🚀 MULTI-FACE ENHANCEMENT: Process all detected faces
            // CRITICAL: When using .right orientation, Vision returns normalized coordinates
            // in the ROTATED coordinate system, not the buffer coordinate system!
            // Buffer: 1608×1206 (landscape) → Rotated: 1206×1608 (portrait)
            let bufferWidth = CVPixelBufferGetWidth(imageBuffer)   // 1608
            let bufferHeight = CVPixelBufferGetHeight(imageBuffer) // 1206

            // Vision coordinates are in ROTATED space (after .right orientation applied)
            let rotatedWidth = bufferHeight   // 1206 (portrait width)
            let rotatedHeight = bufferWidth   // 1608 (portrait height)

            let imageSize = CGSize(width: rotatedWidth, height: rotatedHeight)

            // Convert all faces to image coordinates and filter by size
            // Use ROTATED dimensions for VNImageRectForNormalizedRect
            let allFaceRects = results.compactMap { face -> CGRect? in
                let rect = VNImageRectForNormalizedRect(face.boundingBox, Int(rotatedWidth), Int(rotatedHeight))
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

            // 🎯 CRITICAL: Calculate headroom based on VISIBLE camera preview area only
            // User sees rotated portrait content (1206×1608) letterboxed on iPhone screen (1290×2796)
            // Black bars appear top/bottom, we must exclude them from headroom calculation

            // Step 1: Calculate how much of the buffer is actually visible (accounting for letterbox)
            // Portrait content aspect ratio
            let contentAspect = imageSize.width / imageSize.height  // 1206/1608 = 0.75

            // iPhone 17 Pro screen aspect ratio (excluding safe areas)
            let screenWidth: CGFloat = 1290
            let screenHeight: CGFloat = 2796
            let screenAspect = screenWidth / screenHeight  // ~0.461

            // With .resizeAspect, content fills screen width, letterbox bars on top/bottom
            // Scale factor: screen width / content width
            let scaleFactor = screenWidth / imageSize.width  // 1290/1206 = 1.07

            // Scaled content height on screen
            let scaledContentHeight = imageSize.height * scaleFactor  // 1608 × 1.07 = 1720px

            // Visible ratio: what portion of screen shows actual camera content
            let visibleScreenRatio = scaledContentHeight / screenHeight  // 1720/2796 = 61.5%

            // Calculate letterbox bars (in screen pixels)
            let totalBlackBarHeight = screenHeight - scaledContentHeight  // 1076px
            let blackBarTop = totalBlackBarHeight / 2.0  // 538px
            let blackBarBottom = totalBlackBarHeight / 2.0  // 538px

            // Step 2: Convert face position from buffer coordinates to screen coordinates
            // Map face maxY from buffer space to screen space
            let faceTopInScreenSpace = (primaryFaceRect.maxY / imageSize.height) * scaledContentHeight

            // Step 3: Calculate headroom in SCREEN space (excluding black bars)
            // Space from face top to content edge (not including black bar above)
            let headroomInContentSpace = scaledContentHeight - faceTopInScreenSpace

            // Headroom as percentage of VISIBLE content height
            let headroomPercentage = Float((headroomInContentSpace / scaledContentHeight) * 100.0)

            // 🎯 WEEK 7 ENHANCEMENT: Calculate "EYEROOM" (space above eyes) - More accurate than headroom!
            // Professional photographers follow "rule of thirds" for EYES, not head
            // Eyes at 1/3 from top (33% eyeroom) is the professional standard
            let eyeroomPercentage: Float?
            let eyePositionY: CGFloat?

            if let landmarks = primaryFace.landmarks,
               let leftEye = landmarks.leftEye,
               let rightEye = landmarks.rightEye {

                // Get eye centers in normalized face-relative coordinates [0,1]
                let leftEyePoints = leftEye.normalizedPoints
                let rightEyePoints = rightEye.normalizedPoints

                if leftEyePoints.isEmpty || rightEyePoints.isEmpty {
                    eyeroomPercentage = nil
                    eyePositionY = nil
                    print("⚠️ EYEROOM: No eye landmarks available, falling back to headroom")
                } else {

                // Calculate average Y position of both eyes (in face-relative space)
                let leftEyeAvgY = leftEyePoints.map { $0.y }.reduce(0, +) / CGFloat(leftEyePoints.count)
                let rightEyeAvgY = rightEyePoints.map { $0.y }.reduce(0, +) / CGFloat(rightEyePoints.count)
                let eyeCenterY_faceRelative = (leftEyeAvgY + rightEyeAvgY) / 2.0

                // Convert from face-relative [0,1] to image coordinates
                // Landmarks are relative to face bbox, not image!
                let eyeCenterY_image = primaryFaceRect.minY + (eyeCenterY_faceRelative * primaryFaceRect.height)
                eyePositionY = eyeCenterY_image

                // Map to screen space
                let eyeCenterY_screen = (eyeCenterY_image / imageSize.height) * scaledContentHeight

                // Calculate space ABOVE eyes (this is what photographers care about!)
                let eyeroomInContentSpace = scaledContentHeight - eyeCenterY_screen
                eyeroomPercentage = Float((eyeroomInContentSpace / scaledContentHeight) * 100.0)

                print("👁️ EYEROOM: Eye center Y=\(Int(eyeCenterY_image))px buffer → \(Int(eyeCenterY_screen))px screen")
                print("👁️ EYEROOM: Space above eyes=\(Int(eyeroomInContentSpace))px / \(Int(scaledContentHeight))px = \(String(format: "%.1f", eyeroomPercentage!))%")
                print("📸 RULE OF THIRDS: Target eyeroom ~30-35% (eyes at 1/3 from top)")
                }
            } else {
                eyeroomPercentage = nil
                eyePositionY = nil
                print("⚠️ EYEROOM: Landmarks not available, using headroom fallback")
            }

            // 🐛 DEBUG: Log headroom calculation with letterbox info
            print("🔬 LETTERBOX: Buffer \(bufferWidth)×\(bufferHeight) → Rotated \(Int(imageSize.width))×\(Int(imageSize.height))")
            print("🔬 LETTERBOX: Screen \(Int(screenWidth))×\(Int(screenHeight)), Content scaled to \(Int(imageSize.width*scaleFactor))×\(Int(scaledContentHeight))")
            print("🔬 LETTERBOX: Black bars: \(Int(blackBarTop))px top + \(Int(blackBarBottom))px bottom = \(Int(totalBlackBarHeight))px total")
            print("🔬 HEADROOM: Face top (maxY)=\(Int(primaryFaceRect.maxY))px buffer → \(Int(faceTopInScreenSpace))px screen")
            print("🔬 HEADROOM: Space above HEAD=\(Int(headroomInContentSpace))px / \(Int(scaledContentHeight))px = \(String(format: "%.1f", headroomPercentage))%")
            
            // 🚀 GROUP EYEROOM CALCULATION: Find highest eyes in group for accurate framing
            // For group photos, find topmost person's eyes (professional multi-person composition)
            let groupEyeroomPercentage: Float?

            if results.count > 1 {
                // Multi-person scenario - find highest eye position
                var topmostEyeY: CGFloat = eyePositionY ?? primaryFaceRect.maxY // Fallback to face top

                for (index, face) in results.enumerated() {
                    guard let landmarks = face.landmarks,
                          let leftEye = landmarks.leftEye,
                          let rightEye = landmarks.rightEye else { continue }

                    let leftEyePoints = leftEye.normalizedPoints
                    let rightEyePoints = rightEye.normalizedPoints
                    guard !leftEyePoints.isEmpty && !rightEyePoints.isEmpty else { continue }

                    // Get face rect for this person
                    let faceRect = VNImageRectForNormalizedRect(face.boundingBox, Int(rotatedWidth), Int(rotatedHeight))

                    // Calculate eye center Y
                    let leftEyeAvgY = leftEyePoints.map { $0.y }.reduce(0, +) / CGFloat(leftEyePoints.count)
                    let rightEyeAvgY = rightEyePoints.map { $0.y }.reduce(0, +) / CGFloat(rightEyePoints.count)
                    let eyeCenterY_faceRelative = (leftEyeAvgY + rightEyeAvgY) / 2.0
                    let eyeCenterY_image = faceRect.minY + (eyeCenterY_faceRelative * faceRect.height)

                    // Track highest (topmost) eye position
                    topmostEyeY = max(topmostEyeY, eyeCenterY_image)
                }

                // Calculate group eyeroom based on topmost eyes
                let groupEyeY_screen = (topmostEyeY / imageSize.height) * scaledContentHeight
                let groupEyeroomInContentSpace = scaledContentHeight - groupEyeY_screen
                groupEyeroomPercentage = Float((groupEyeroomInContentSpace / scaledContentHeight) * 100.0)

                print("👥 GROUP EYEROOM: Topmost eyes at \(Int(topmostEyeY))px → \(String(format: "%.1f", groupEyeroomPercentage!))% eyeroom")
            } else {
                // Single person - group eyeroom same as primary
                groupEyeroomPercentage = eyeroomPercentage
            }

            // 🚀 GROUP HEADROOM CALCULATION (Legacy): Find topmost face for group headroom (memory-limited)
            // Topmost face = highest maxY value (remember: origin at bottom-left)
            let topmostMaxY = memoryLimitedFaceRects.map { $0.maxY }.max() ?? primaryFaceRect.maxY

            // Calculate group headroom using same letterbox logic
            let groupTopInScreenSpace = (topmostMaxY / imageSize.height) * scaledContentHeight
            let groupHeadroomInContentSpace = scaledContentHeight - groupTopInScreenSpace
            let groupHeadroomPercentage = Float((groupHeadroomInContentSpace / scaledContentHeight) * 100.0)

            // 🚀 DEBUG: Log multi-face detection (memory-aware)
            print("🔍 FACES DETECTED: Total=\(allFaceRects.count), Limited=\(memoryLimitedFaceRects.count)")
            print("📊 PRIMARY: Headroom=\(String(format: "%.1f", headroomPercentage))%, Eyeroom=\(eyeroomPercentage.map { String(format: "%.1f", $0) + "%" } ?? "N/A")")
            print("📊 GROUP: Headroom=\(String(format: "%.1f", groupHeadroomPercentage))%, Eyeroom=\(groupEyeroomPercentage.map { String(format: "%.1f", $0) + "%" } ?? "N/A")")
            
            // Calculate thirds offset (based on primary face)
            let faceCenterX = primaryFaceRect.midX
            let imageCenterX = imageSize.width / 2
            let offset = (faceCenterX - imageCenterX) / imageSize.width
            let thirdsOffsetPercentage = Float(offset * 100.0)
            
            // Check face stability with enhanced tracking (based on primary face)
            // IMPORTANT: Normalize face center to 0-1 coordinates for stability check
            let normalizedFaceCenter = CGPoint(
                x: primaryFaceRect.midX / imageSize.width,
                y: primaryFaceRect.midY / imageSize.height
            )
            let stableMs = checkFaceStability(faceCenter: normalizedFaceCenter)

            // 🚀 WEEK 7: Detect face orientation using yaw angle
            let (orientation, confidence) = detectFaceOrientation(
                faceObservation: primaryFace,
                currentRect: primaryFaceRect,
                normalizedCenter: normalizedFaceCenter,
                imageSize: imageSize
            )

            // 🚀 WEEK 7: Calculate edge density near face bbox
            let (leftEdge, rightEdge, edgeConflict) = calculateEdgeDensity(
                faceRect: primaryFaceRect,
                imageBuffer: imageBuffer,
                imageSize: imageSize
            )

            // 🎯 Calculate vertical position of face center
            // Percentage is same in buffer space and screen space (scales proportionally)
            let faceVerticalPosition = Float((primaryFaceRect.midY / imageSize.height) * 100.0)
            let faceMidYInScreenSpace = (primaryFaceRect.midY / imageSize.height) * scaledContentHeight

            print("📍 VERTICAL POSITION: Face midY=\(Int(primaryFaceRect.midY))px buffer → \(Int(faceMidYInScreenSpace))px screen = \(String(format: "%.1f", faceVerticalPosition))%")

            return FaceAnalysis(
                rect: primaryFaceRect,
                stableMs: stableMs,
                sizePercentage: sizePercentage,
                headroomPercentage: headroomPercentage,
                thirdsOffsetPercentage: thirdsOffsetPercentage,
                faceVerticalPosition: faceVerticalPosition,
                allFaceRects: memoryLimitedFaceRects,
                faceCount: memoryLimitedFaceRects.count,
                groupHeadroomPercentage: groupHeadroomPercentage,
                primaryFaceIndex: primaryFaceIndex,
                faceOrientation: orientation,
                orientationConfidence: confidence,
                leftEdgeDensity: leftEdge,
                rightEdgeDensity: rightEdge,
                hasEdgeConflict: edgeConflict
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
            faceVerticalPosition: nil,
            allFaceRects: [],
            faceCount: 0,
            groupHeadroomPercentage: nil,
            primaryFaceIndex: nil,
            faceOrientation: nil,
            orientationConfidence: 0.0,
            leftEdgeDensity: nil,
            rightEdgeDensity: nil,
            hasEdgeConflict: false
        )
    }
    
    private func resetFaceStability() {
        faceStabilityStart = nil
        lastFaceCenter = nil
        // Also reset orientation tracking
        facePositionHistory.removeAll()
        orientationHistory.removeAll()
        lastFaceRect = nil
    }
    
    // 🚀 WEEK 3: Enhanced Face Stability Tracking
    private func checkFaceStability(faceCenter: CGPoint) -> Int {
        let currentCenter = faceCenter
        
        if let lastCenter = lastFaceCenter {
            let distance = sqrt(pow(currentCenter.x - lastCenter.x, 2) + pow(currentCenter.y - lastCenter.y, 2))
            
            // 🚀 Dynamic stability threshold based on face size and movement patterns
            // Larger faces can tolerate more movement, smaller faces need to be more stable
            // NOTE: Coordinates are NORMALIZED (0-1), so 0.02 = 2% of screen width/height
            let baseThreshold: CGFloat = 0.02 // 2% of screen dimension (was incorrectly 15.0!)
            let dynamicThreshold = baseThreshold // Could adjust based on face size in future

            print("🔍 Face stability: distance=\(String(format: "%.4f", distance)), threshold=\(dynamicThreshold), stable=\(distance < dynamicThreshold)")

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
    
    // MARK: - Face Orientation Detection (Week 7 - Enhanced with Landmarks)
    /// Detects face orientation using Vision landmarks (nose, eyes) for accurate head pose
    /// Returns tuple of (orientation, confidence)
    private func detectFaceOrientation(
        faceObservation: VNFaceObservation,
        currentRect: CGRect,
        normalizedCenter: CGPoint,
        imageSize: CGSize
    ) -> (FaceOrientation?, Float) {
        // Update position history
        facePositionHistory.append(normalizedCenter)
        if facePositionHistory.count > Config.orientationHistorySize {
            facePositionHistory.removeFirst()
        }

        var finalOrientation: FaceOrientation?
        var finalConfidence: Float = 0.0

        // 🚀 PRIMARY METHOD: Use Vision's yaw angle for true head pose
        if let landmarks = faceObservation.landmarks {
            let (landmarkOrientation, landmarkConfidence) = detectOrientationFromLandmarks(
                faceObservation: faceObservation,
                landmarks: landmarks,
                faceRect: currentRect,
                imageSize: imageSize
            )

            if let orientation = landmarkOrientation, landmarkConfidence >= 0.5 {
                finalOrientation = orientation
                finalConfidence = landmarkConfidence
            }
        }

        // 🚀 FALLBACK METHOD: Position-based heuristic (only if landmarks fail)
        if finalOrientation == nil {
            let faceCenterX = currentRect.midX
            let imageCenterX = imageSize.width / 2
            let offsetFromCenter = faceCenterX - imageCenterX
            let offsetPercentage = abs(offsetFromCenter / imageSize.width)

            if offsetPercentage > 0.15 { // Face is >15% off-center
                if offsetFromCenter < 0 {
                    // Face on left - assume facing right (toward center)
                    finalOrientation = .right
                    finalConfidence = min(0.6, Float(offsetPercentage) * 2.5)
                } else {
                    // Face on right - assume facing left (toward center)
                    finalOrientation = .left
                    finalConfidence = min(0.6, Float(offsetPercentage) * 2.5)
                }
                print("📍 Position-based fallback: \(finalOrientation?.description ?? "nil"), confidence: \(String(format: "%.2f", finalConfidence))")
            } else {
                finalOrientation = .center
                finalConfidence = 0.5
            }
        }

        // Update orientation history for stability gating
        if let orientation = finalOrientation {
            orientationHistory.append(orientation)
            if orientationHistory.count > Config.orientationHistorySize {
                orientationHistory.removeFirst()
            }

            // Calculate stability-adjusted confidence
            let consistentOrientations = orientationHistory.filter { $0 == orientation }.count
            let stabilityRatio = Float(consistentOrientations) / Float(orientationHistory.count)

            // Only return high confidence if orientation is stable over time
            let adjustedConfidence = finalConfidence * stabilityRatio

            if stabilityRatio >= Config.orientationStabilityThreshold {
                lastFaceRect = currentRect
                print("🎯 Face orientation: \(orientation.description), confidence: \(String(format: "%.2f", adjustedConfidence)) (stability: \(String(format: "%.2f", stabilityRatio)))")
                return (orientation, adjustedConfidence)
            }
        }

        // Not stable enough yet
        lastFaceRect = currentRect
        return (finalOrientation, finalConfidence * 0.5) // Reduce confidence if unstable
    }

    /// Detect orientation using Vision's built-in head pose (yaw angle)
    /// This is the industry-standard approach used by professional face tracking
    private func detectOrientationFromLandmarks(
        faceObservation: VNFaceObservation,
        landmarks: VNFaceLandmarks2D,
        faceRect: CGRect,
        imageSize: CGSize
    ) -> (FaceOrientation?, Float) {

        // 🚀 PRIMARY METHOD: Use Vision's yaw angle (most accurate)
        // Yaw = horizontal head rotation angle
        // Negative yaw = facing left, Positive yaw = facing right
        if let yaw = faceObservation.yaw {
            let yawDegrees = yaw.floatValue * 180.0 / .pi  // Convert radians to degrees

            let orientation: FaceOrientation
            let confidence: Float

            // Yaw angle thresholds (industry standard)
            if abs(yawDegrees) < 15 {
                // Face nearly frontal (±15°)
                orientation = .center
                confidence = 0.90 - abs(yawDegrees) / 100.0  // Higher confidence when more centered
            } else if yawDegrees < -15 {
                // Face rotated left (yaw negative)
                orientation = .left
                confidence = min(0.95, 0.75 + abs(yawDegrees + 15) / 100.0)
            } else {
                // Face rotated right (yaw positive)
                orientation = .right
                confidence = min(0.95, 0.75 + abs(yawDegrees - 15) / 100.0)
            }

            print("🎯 YAW ANGLE: \(String(format: "%.1f", yawDegrees))° → \(orientation.description) (conf: \(String(format: "%.2f", confidence)))")

            return (orientation, confidence)
        }

        // 🚀 FALLBACK: Use landmark-based detection if yaw unavailable
        return detectOrientationFromLandmarksFallback(landmarks: landmarks)
    }

    /// Fallback landmark-based detection (only when yaw unavailable)
    private func detectOrientationFromLandmarksFallback(landmarks: VNFaceLandmarks2D) -> (FaceOrientation?, Float) {
        // Use nose position as simple fallback
        guard let nose = landmarks.nose else { return (nil, 0.0) }
        let nosePoints = nose.normalizedPoints
        guard !nosePoints.isEmpty else { return (nil, 0.0) }

        var avgNoseX: CGFloat = 0
        for point in nosePoints {
            avgNoseX += point.x
        }
        avgNoseX /= CGFloat(nosePoints.count)

        let normalizedNoseX = 1.0 - avgNoseX  // Flip for correct orientation
        let offset = Float(normalizedNoseX - 0.5)

        let orientation: FaceOrientation
        let confidence: Float = 0.6  // Lower confidence for fallback

        if abs(offset) < 0.10 {
            orientation = .center
        } else if offset < -0.10 {
            orientation = .left
        } else {
            orientation = .right
        }

        print("📍 FALLBACK (nose): offset=\(String(format: "%.3f", offset)) → \(orientation.description) (conf: 0.60)")

        return (orientation, confidence)
    }

    /// Detect orientation from nose position (most reliable single feature)
    private func detectOrientationFromNose(landmarks: VNFaceLandmarks2D) -> (FaceOrientation, Float)? {
        guard let nose = landmarks.nose else { return nil }
        let nosePoints = nose.normalizedPoints
        guard !nosePoints.isEmpty else { return nil }

        // Calculate average nose position in face-relative coordinates
        var avgNoseX: CGFloat = 0
        for point in nosePoints {
            avgNoseX += point.x
        }
        avgNoseX /= CGFloat(nosePoints.count)

        // 🚀 UNIFIED COORDINATE SYSTEM:
        // Vision landmarks are in normalized face-relative space [0,1]
        // BUT the coordinate system origin is bottom-left with mirrored X for back camera
        // Convert to intuitive coordinates: 0=left, 0.5=center, 1=right
        let normalizedNoseX = 1.0 - avgNoseX

        // Calculate offset from center
        let offset = Float(normalizedNoseX - 0.5)

        // Stricter thresholds for better accuracy
        let orientation: FaceOrientation
        let baseConfidence: Float

        if abs(offset) < 0.08 {
            // Very centered (within 8%) - facing forward
            orientation = .center
            baseConfidence = 0.85
        } else if offset < -0.08 {
            // Nose significantly left - facing left
            orientation = .left
            // Higher offset = more confident (profile view)
            baseConfidence = min(0.92, 0.75 + abs(offset) * 1.5)
        } else {
            // Nose significantly right - facing right
            orientation = .right
            baseConfidence = min(0.92, 0.75 + abs(offset) * 1.5)
        }

        print("🔬 NOSE: pos=\(String(format: "%.3f", normalizedNoseX)), offset=\(String(format: "%.3f", offset)) → \(orientation.description) (conf: \(String(format: "%.2f", baseConfidence)))")

        return (orientation, baseConfidence)
    }

    /// Detect orientation from eye position and visibility
    private func detectOrientationFromEyes(landmarks: VNFaceLandmarks2D) -> (FaceOrientation, Float)? {
        guard let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye else {
            return nil
        }

        // Calculate eye sizes (profile view = one eye much smaller/occluded)
        let leftEyePoints = leftEye.normalizedPoints
        let rightEyePoints = rightEye.normalizedPoints

        guard !leftEyePoints.isEmpty && !rightEyePoints.isEmpty else {
            return nil
        }

        // Calculate eye widths as proxy for visibility
        let leftEyeMinX = leftEyePoints.map { $0.x }.min() ?? 0
        let leftEyeMaxX = leftEyePoints.map { $0.x }.max() ?? 0
        let leftEyeWidth = leftEyeMaxX - leftEyeMinX

        let rightEyeMinX = rightEyePoints.map { $0.x }.min() ?? 0
        let rightEyeMaxX = rightEyePoints.map { $0.x }.max() ?? 0
        let rightEyeWidth = rightEyeMaxX - rightEyeMinX

        // Calculate asymmetry ratio
        let eyeSizeRatio = Float(max(leftEyeWidth, rightEyeWidth) / max(min(leftEyeWidth, rightEyeWidth), 0.001))

        let orientation: FaceOrientation
        let confidence: Float

        // If eyes are very similar in size, likely frontal
        if eyeSizeRatio < 1.3 {
            orientation = .center
            confidence = 0.65
        } else if leftEyeWidth > rightEyeWidth * 1.3 {
            // Left eye significantly larger - right eye occluded - facing LEFT ←
            // (We see left eye, right eye hidden behind nose)
            orientation = .left
            confidence = min(0.85, 0.70 + Float((eyeSizeRatio - 1.3) * 0.5))
        } else {
            // Right eye significantly larger - left eye occluded - facing RIGHT →
            // (We see right eye, left eye hidden behind nose)
            orientation = .right
            confidence = min(0.85, 0.70 + Float((eyeSizeRatio - 1.3) * 0.5))
        }

        print("🔬 EYES: L_width=\(String(format: "%.3f", leftEyeWidth)), R_width=\(String(format: "%.3f", rightEyeWidth)), ratio=\(String(format: "%.2f", eyeSizeRatio)) → \(orientation.description) (conf: \(String(format: "%.2f", confidence)))")

        return (orientation, confidence)
    }

    /// Detect orientation from face contour asymmetry
    private func detectOrientationFromContour(landmarks: VNFaceLandmarks2D) -> (FaceOrientation, Float)? {
        guard let faceContour = landmarks.faceContour else { return nil }
        let points = faceContour.normalizedPoints
        guard points.count > 10 else { return nil }

        // Calculate contour centroid
        var centroidX: CGFloat = 0
        for point in points {
            centroidX += point.x
        }
        centroidX /= CGFloat(points.count)

        // Convert to unified coordinates
        let normalizedCentroidX = 1.0 - centroidX
        let offset = Float(normalizedCentroidX - 0.5)

        // Contour shift indicates head rotation
        let orientation: FaceOrientation
        let confidence: Float

        if abs(offset) < 0.06 {
            orientation = .center
            confidence = 0.65
        } else if offset < -0.06 {
            orientation = .left
            confidence = min(0.75, 0.60 + abs(offset) * 1.2)
        } else {
            orientation = .right
            confidence = min(0.75, 0.60 + abs(offset) * 1.2)
        }

        print("🔬 CONTOUR: centroid=\(String(format: "%.3f", normalizedCentroidX)), offset=\(String(format: "%.3f", offset)) → \(orientation.description) (conf: \(String(format: "%.2f", confidence)))")

        return (orientation, confidence)
    }

    /// Combine multiple orientation signals using weighted voting
    /// Nose signal is weighted 2x higher as it's most reliable
    private func combineOrientationSignals(_ signals: [(FaceOrientation, Float)]) -> (FaceOrientation?, Float) {
        guard !signals.isEmpty else { return (nil, 0.0) }

        // Group by orientation and sum confidence-weighted votes
        // NOSE signal (first) gets 2x weight as it's most reliable
        var votes: [FaceOrientation: Float] = [:]
        for (index, (orientation, confidence)) in signals.enumerated() {
            let weight: Float = index == 0 ? 2.0 : 1.0  // First signal (nose) gets 2x weight
            votes[orientation, default: 0.0] += confidence * weight
        }

        // Find orientation with highest total confidence
        guard let winner = votes.max(by: { $0.value < $1.value }) else {
            return (nil, 0.0)
        }

        // Calculate final confidence (normalized by total possible votes)
        let totalConfidence = votes.values.reduce(0, +)
        let normalizedConfidence = winner.value / totalConfidence
        let finalConfidence = min(0.95, winner.value * normalizedConfidence / Float(signals.count))

        print("🎯 COMBINED: \(winner.key.description) with confidence \(String(format: "%.2f", finalConfidence)) (votes: \(votes.mapValues { String(format: "%.2f", $0) }))")

        return (winner.key, finalConfidence)
    }

    // MARK: - Edge Density Detection (Week 7)
    /// Calculates edge density on left and right sides of face bbox using Sobel edge detection
    /// Returns tuple of (leftDensity, rightDensity, hasConflict)
    private func calculateEdgeDensity(
        faceRect: CGRect,
        imageBuffer: CVPixelBuffer,
        imageSize: CGSize
    ) -> (Float?, Float?, Bool) {
        guard Config.edgeGuidanceEnabled else {
            return (nil, nil, false)
        }

        // Lock pixel buffer for reading
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
            return (nil, nil, false)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        // Define sampling regions on left and right of face
        let sampleWidth = Int(Config.edgeDensitySampleWidth)

        // Left region (just left of face bbox)
        let leftX = max(0, Int(faceRect.minX) - sampleWidth)
        let leftWidth = min(sampleWidth, Int(faceRect.minX))

        // Right region (just right of face bbox)
        let rightX = Int(faceRect.maxX)
        let rightWidth = min(sampleWidth, width - rightX)

        let sampleY = Int(faceRect.minY)
        let sampleHeight = Int(faceRect.height)

        // Calculate edge density using simple gradient detection
        let leftDensity = calculateRegionEdgeDensity(
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            x: leftX,
            y: sampleY,
            width: leftWidth,
            height: sampleHeight
        )

        let rightDensity = calculateRegionEdgeDensity(
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            x: rightX,
            y: sampleY,
            width: rightWidth,
            height: sampleHeight
        )

        // Determine if there's an edge conflict
        let hasConflict = (leftDensity > Config.edgeDensityThreshold) ||
                         (rightDensity > Config.edgeDensityThreshold)

        if hasConflict {
            print("⚠️ EDGE CONFLICT: left=\(String(format: "%.2f", leftDensity)), right=\(String(format: "%.2f", rightDensity))")
        }

        return (leftDensity, rightDensity, hasConflict)
    }

    /// Calculate edge density in a specific region using horizontal Sobel operator
    private func calculateRegionEdgeDensity(
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> Float {
        guard width > 2 && height > 2 else { return 0.0 }

        var edgePixelCount = 0
        let totalPixels = width * height

        // Sobel horizontal kernel for edge detection: [-1, 0, 1]
        let maxRow = y + height - 1
        let maxCol = x + width - 1

        for row in y..<maxRow {
            for col in x..<maxCol {
                // Get pixel luminance values (BGRA format)
                let offset = row * bytesPerRow + col * 4
                let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)

                // Simple horizontal gradient (Sobel-like)
                if col + 1 < maxCol {
                    let nextOffset = row * bytesPerRow + (col + 1) * 4
                    let nextPtr = baseAddress.advanced(by: nextOffset).assumingMemoryBound(to: UInt8.self)

                    // Calculate luminance gradient
                    let lum1 = (Int(ptr[2]) + Int(ptr[1]) + Int(ptr[0])) / 3  // RGB average
                    let lum2 = (Int(nextPtr[2]) + Int(nextPtr[1]) + Int(nextPtr[0])) / 3

                    let gradient = abs(lum2 - lum1)

                    // Threshold for considering it an edge pixel
                    if gradient > 30 {  // Tunable threshold
                        edgePixelCount += 1
                    }
                }
            }
        }

        return Float(edgePixelCount) / Float(totalPixels)
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
            faceOrientation: nil,
            orientationConfidence: 0.0,
            leftEdgeDensity: nil,
            rightEdgeDensity: nil,
            hasEdgeConflict: false,
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
    let faceVerticalPosition: Float?     // vertical center position (0=bottom, 100=top)

    // Multi-face support
    let allFaceRects: [CGRect]           // all detected faces
    let faceCount: Int                   // total face count
    let groupHeadroomPercentage: Float?  // topmost face headroom
    let primaryFaceIndex: Int?           // index of primary face in allFaceRects

    // Face Orientation (Week 7)
    let faceOrientation: FaceOrientation?
    let orientationConfidence: Float

    // Edge Density (Week 7)
    let leftEdgeDensity: Float?
    let rightEdgeDensity: Float?
    let hasEdgeConflict: Bool
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
