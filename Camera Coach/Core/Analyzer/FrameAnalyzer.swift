//
//  FrameAnalyzer.swift
//  Camera Coach
//
//  Analyzes camera frames to extract features for guidance.
//  Implements CoreMotion horizon detection with proper filtering.
//

import Foundation
import CoreMotion
import Vision
import CoreGraphics
import QuartzCore

public final class FrameAnalyzer: NSObject, ObservableObject {
    // MARK: - Properties
    private let motionManager = CMMotionManager()
    private let logger = Logger.shared
    
    // MARK: - Horizon Detection
    private var horizonHistory: [Float] = []
    private var horizonStabilityStart: Date?
    private var lastStableHorizon: Float = 0.0
    
    // MARK: - Face Detection
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var faceStabilityStart: Date?
    private var lastFaceCenter: CGPoint?
    
    // MARK: - Performance
    private var frameCount = 0
    private var lastFrameTime: TimeInterval = 0
    private var processingTimes: [TimeInterval] = []
    
    // MARK: - Initialization
    public override init() {
        super.init()
        setupMotionManager()
        setupFaceDetection()
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
    
    // MARK: - Public Interface
    public func analyzeFrame(_ sampleBuffer: CMSampleBuffer) -> FrameFeatures {
        let startTime = CACurrentMediaTime()
        
        // Get image buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return createEmptyFrameFeatures(startTime: startTime)
        }
        
        // Analyze horizon using CoreMotion
        let horizonDegrees = getCurrentHorizonDegrees()
        let horizonStableMs = getHorizonStabilityMs()
        
        // Analyze face using Vision
        let faceAnalysis = analyzeFace(in: imageBuffer)
        
        // Calculate processing latency
        let endTime = CACurrentMediaTime()
        let latencyMs = Int((endTime - startTime) * 1000)
        
        // Update performance tracking
        updatePerformanceMetrics(latencyMs: latencyMs)
        
        // Create frame features
        let features = FrameFeatures(
            horizonDegrees: horizonDegrees,
            horizonStableMs: horizonStableMs,
            faceRect: faceAnalysis.rect,
            faceStableMs: faceAnalysis.stableMs,
            faceSizePercentage: faceAnalysis.sizePercentage,
            headroomPercentage: faceAnalysis.headroomPercentage,
            thirdsOffsetPercentage: faceAnalysis.thirdsOffsetPercentage,
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
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30Hz updates
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self = self, let motion = motion else { return }
                
                // Convert roll to degrees and apply low-pass filter
                let rollDegrees = Float(motion.attitude.roll * 180.0 / .pi)
                self.updateHorizonHistory(rollDegrees)
            }
        }
    }
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            // Face detection results will be processed in analyzeFrame
        }
    }
    
    // MARK: - Horizon Analysis
    private func updateHorizonHistory(_ degrees: Float) {
        // Apply low-pass filter (α ≈ 0.15 as per Config)
        let alpha = Config.horizonLowPassAlpha
        let filteredDegrees = alpha * degrees + (1 - alpha) * (horizonHistory.last ?? degrees)
        
        horizonHistory.append(filteredDegrees)
        
        // Keep only recent history (last 30 samples = 1 second at 30Hz)
        if horizonHistory.count > 30 {
            horizonHistory.removeFirst()
        }
        
        // Check stability
        checkHorizonStability()
    }
    
    private func getCurrentHorizonDegrees() -> Float {
        return horizonHistory.last ?? 0.0
    }
    
    private func checkHorizonStability() {
        guard horizonHistory.count >= 10 else { return } // Need at least 10 samples
        
        let recentValues = Array(horizonHistory.suffix(10))
        let mean = recentValues.reduce(0, +) / Float(recentValues.count)
        let variance = recentValues.map { pow($0 - mean, 2) }.reduce(0, +) / Float(recentValues.count)
        let stdDev = sqrt(variance)
        
        // Consider stable if standard deviation is below threshold
        let stabilityThreshold: Float = 0.5 // degrees
        
        if stdDev < stabilityThreshold {
            if horizonStabilityStart == nil {
                horizonStabilityStart = Date()
            }
            lastStableHorizon = mean
        } else {
            horizonStabilityStart = nil
        }
    }
    
    private func getHorizonStabilityMs() -> Int {
        guard let startTime = horizonStabilityStart else { return 0 }
        return Int(Date().timeIntervalSince(startTime) * 1000)
    }
    
    // MARK: - Face Analysis
    private func analyzeFace(in imageBuffer: CVPixelBuffer) -> FaceAnalysis {
        // For Week 2, implement basic face detection
        // This will be enhanced in Week 3 with proper Vision framework integration
        
        // Placeholder implementation - return nil for now
        // In a real implementation, we would:
        // 1. Create VNImageRequestHandler with the imageBuffer
        // 2. Perform face detection request
        // 3. Calculate face metrics (size, position, stability)
        // 4. Calculate headroom and thirds offset
        
        return FaceAnalysis(
            rect: nil,
            stableMs: 0,
            sizePercentage: nil,
            headroomPercentage: nil,
            thirdsOffsetPercentage: nil
        )
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
            horizonStableMs: getHorizonStabilityMs(),
            faceRect: nil,
            faceStableMs: 0,
            faceSizePercentage: nil,
            headroomPercentage: nil,
            thirdsOffsetPercentage: nil,
            timestamp: startTime,
            processingLatencyMs: 0,
            thermalState: ProcessInfo.processInfo.thermalState,
            currentFPS: calculateCurrentFPS()
        )
    }
}

// MARK: - Supporting Types
private struct FaceAnalysis {
    let rect: CGRect?
    let stableMs: Int
    let sizePercentage: Float?
    let headroomPercentage: Float?
    let thirdsOffsetPercentage: Float?
}
