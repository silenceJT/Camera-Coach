//
//  EnhancedFaceDetector.swift
//  Camera Coach
//
//  🚀 WEEK 3: Enhanced face detection system with multiple fallback options
//  Combines Apple Vision with alternative detection methods for better distance coverage
//

import Foundation
import Vision
import CoreImage
import QuartzCore

// MARK: - Enhanced Face Detection Strategy

public enum FaceDetectionStrategy {
    case appleVisionOnly          // Default Apple Vision framework
    case enhancedDistance         // Apple Vision with relaxed thresholds  
    case hybridMultiScale         // Multiple detection scales
    case externalMLKit            // Fall back to Google ML Kit (if available)
}

public final class EnhancedFaceDetector {
    // MARK: - Properties
    private let strategy: FaceDetectionStrategy
    private let appleDetector = FrameAnalyzer()
    private let mlKitDetector = MLKitFaceDetector()
    
    // MARK: - Initialization
    public init(strategy: FaceDetectionStrategy = .enhancedDistance) {
        self.strategy = strategy
    }
    
    // MARK: - Public Interface
    
    /// Enhanced face detection with multiple strategies for better distance coverage
    public func detectFaces(in pixelBuffer: CVPixelBuffer) -> EnhancedFaceResult {
        switch strategy {
        case .appleVisionOnly:
            return detectWithAppleVision(pixelBuffer)
            
        case .enhancedDistance:
            return detectWithEnhancedDistance(pixelBuffer)
            
        case .hybridMultiScale:
            return detectWithMultiScale(pixelBuffer)
            
        case .externalMLKit:
            return detectWithMLKitFallback(pixelBuffer)
        }
    }
    
    // MARK: - Detection Strategies
    
    private func detectWithAppleVision(_ pixelBuffer: CVPixelBuffer) -> EnhancedFaceResult {
        let features = appleDetector.analyzeFrame(createSampleBuffer(from: pixelBuffer))
        
        return EnhancedFaceResult(
            faces: features.faceRect != nil ? [createFaceInfo(from: features)] : [],
            detectionMethod: .appleVision,
            confidence: features.faceRect != nil ? 0.8 : 0.0,
            processingTimeMs: 10 // Estimated
        )
    }
    
    private func detectWithEnhancedDistance(_ pixelBuffer: CVPixelBuffer) -> EnhancedFaceResult {
        // 🚀 Use multiple Vision requests with different configurations for better coverage
        let results = performMultiScaleDetection(pixelBuffer)
        
        return EnhancedFaceResult(
            faces: results.faces,
            detectionMethod: .appleVisionEnhanced,
            confidence: results.maxConfidence,
            processingTimeMs: results.processingTime
        )
    }
    
    private func detectWithMultiScale(_ pixelBuffer: CVPixelBuffer) -> EnhancedFaceResult {
        var allFaces: [EnhancedFaceInfo] = []
        var processingTime = 0
        let startTime = CACurrentMediaTime()
        
        // Strategy 1: Standard detection
        let standardResult = detectWithEnhancedDistance(pixelBuffer)
        allFaces.append(contentsOf: standardResult.faces)
        
        // Strategy 2: Scaled-up detection for far faces
        if allFaces.isEmpty {
            let scaledResult = detectOnScaledImage(pixelBuffer, scale: 2.0)
            allFaces.append(contentsOf: scaledResult.faces)
        }
        
        // Strategy 3: Region-of-interest detection
        if allFaces.isEmpty {
            let roiResult = detectInRegionsOfInterest(pixelBuffer)
            allFaces.append(contentsOf: roiResult.faces)
        }
        
        processingTime = Int((CACurrentMediaTime() - startTime) * 1000)
        
        return EnhancedFaceResult(
            faces: allFaces,
            detectionMethod: .multiScale,
            confidence: allFaces.isEmpty ? 0.0 : allFaces.max(by: { $0.confidence < $1.confidence })?.confidence ?? 0.0,
            processingTimeMs: processingTime
        )
    }
    
    private func detectWithMLKitFallback(_ pixelBuffer: CVPixelBuffer) -> EnhancedFaceResult {
        // First try Apple Vision
        let appleResult = detectWithEnhancedDistance(pixelBuffer)
        
        if !appleResult.faces.isEmpty {
            return appleResult
        }
        
        // Fall back to ML Kit for better distance detection
        let mlKitResult = mlKitDetector.detectFaces(in: pixelBuffer)
        
        if let error = mlKitResult.error {
            print("⚠️ ML Kit detection failed: \(error.localizedDescription)")
            return appleResult.withMethod(.mlKitFallback)
        }
        
        // Convert ML Kit results to our format
        let enhancedFaces = mlKitResult.faces.map { $0.toEnhancedFaceInfo() }
        
        return EnhancedFaceResult(
            faces: enhancedFaces,
            detectionMethod: .mlKitFallback,
            confidence: mlKitResult.confidence,
            processingTimeMs: mlKitResult.processingTimeMs
        )
    }
    
    // MARK: - Multi-Scale Detection Helpers
    
    private func performMultiScaleDetection(_ pixelBuffer: CVPixelBuffer) -> (faces: [EnhancedFaceInfo], maxConfidence: Float, processingTime: Int) {
        let startTime = CACurrentMediaTime()
        var detectedFaces: [EnhancedFaceInfo] = []
        
        // Create multiple Vision requests with different configurations
        let configurations = [
            VNDetectFaceRectanglesRequestConfig(minFaceSize: 0.01, maxFaceCount: 10), // Very small faces
            VNDetectFaceRectanglesRequestConfig(minFaceSize: 0.05, maxFaceCount: 5),  // Medium faces  
            VNDetectFaceRectanglesRequestConfig(minFaceSize: 0.1, maxFaceCount: 3)   // Large faces
        ]
        
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        
        for config in configurations {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            do {
                try handler.perform([request])
                
                if let results = request.results, !results.isEmpty {
                    for face in results {
                        let faceRect = VNImageRectForNormalizedRect(face.boundingBox, Int(imageSize.width), Int(imageSize.height))
                        let faceArea = faceRect.width * faceRect.height
                        let imageArea = imageSize.width * imageSize.height
                        let sizePercentage = Float((faceArea / imageArea) * 100.0)
                        
                        // Apply the configuration's minimum size filter
                        let minSizePixels = imageArea * CGFloat(config.minFaceSize)
                        if faceArea >= minSizePixels {
                            let faceInfo = EnhancedFaceInfo(
                                rect: faceRect,
                                sizePercentage: sizePercentage,
                                headroomPercentage: Float((faceRect.minY / imageSize.height) * 100.0),
                                confidence: face.confidence,
                                detectionScale: config.minFaceSize
                            )
                            detectedFaces.append(faceInfo)
                        }
                    }
                    break // Stop at first successful detection
                }
            } catch {
                continue // Try next configuration
            }
        }
        
        let processingTime = Int((CACurrentMediaTime() - startTime) * 1000)
        let maxConfidence = detectedFaces.max(by: { $0.confidence < $1.confidence })?.confidence ?? 0.0
        
        return (faces: detectedFaces, maxConfidence: maxConfidence, processingTime: processingTime)
    }
    
    private func detectOnScaledImage(_ pixelBuffer: CVPixelBuffer, scale: CGFloat) -> EnhancedFaceResult {
        // TODO: Implement image scaling for better far-distance detection
        // This would involve:
        // 1. Creating a scaled version of the pixel buffer
        // 2. Running detection on the scaled image
        // 3. Scaling the results back to original coordinates
        
        return EnhancedFaceResult(faces: [], detectionMethod: .scaled, confidence: 0.0, processingTimeMs: 0)
    }
    
    private func detectInRegionsOfInterest(_ pixelBuffer: CVPixelBuffer) -> EnhancedFaceResult {
        // TODO: Implement ROI-based detection
        // Focus detection on likely face regions (upper 2/3 of frame, center areas)
        
        return EnhancedFaceResult(faces: [], detectionMethod: .regionOfInterest, confidence: 0.0, processingTimeMs: 0)
    }
    
    // MARK: - Helper Methods
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer {
        // Simplified sample buffer creation for existing FrameAnalyzer compatibility
        var sampleBuffer: CMSampleBuffer!
        var formatDescription: CMVideoFormatDescription!
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        
        let now = CMTime.init(seconds: CACurrentMediaTime(), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: now, decodeTimeStamp: CMTime.invalid)
        
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
        
        return sampleBuffer
    }
    
    private func createFaceInfo(from features: FrameFeatures) -> EnhancedFaceInfo {
        return EnhancedFaceInfo(
            rect: features.faceRect ?? CGRect.zero,
            sizePercentage: features.faceSizePercentage ?? 0.0,
            headroomPercentage: features.headroomPercentage ?? 0.0,
            confidence: 0.8, // Estimated confidence for Apple Vision
            detectionScale: 0.02 // Standard Apple Vision scale
        )
    }
}

// MARK: - Supporting Types

public struct EnhancedFaceInfo {
    let rect: CGRect
    let sizePercentage: Float
    let headroomPercentage: Float
    let confidence: Float
    let detectionScale: Float
}

public struct EnhancedFaceResult {
    let faces: [EnhancedFaceInfo]
    let detectionMethod: DetectionMethod
    let confidence: Float
    let processingTimeMs: Int
    
    func withMethod(_ method: DetectionMethod) -> EnhancedFaceResult {
        return EnhancedFaceResult(faces: faces, detectionMethod: method, confidence: confidence, processingTimeMs: processingTimeMs)
    }
}

public enum DetectionMethod {
    case appleVision
    case appleVisionEnhanced
    case multiScale
    case scaled
    case regionOfInterest
    case mlKitFallback
}

private struct VNDetectFaceRectanglesRequestConfig {
    let minFaceSize: Float      // Minimum face size as fraction of image
    let maxFaceCount: Int       // Maximum faces to detect
}