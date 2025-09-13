//
//  MLKitFaceDetector.swift
//  Camera Coach
//
//  🚀 WEEK 3: Google ML Kit face detection wrapper
//  Provides enhanced face detection capabilities with better distance coverage
//

import Foundation
import CoreMedia
import CoreImage
import UIKit

#if canImport(MLKitVision)
import MLKitVision
#endif

#if canImport(MLKitFaceDetection)
import MLKitFaceDetection
#endif

// MARK: - ML Kit Integration (will be implemented after adding dependency)

public final class MLKitFaceDetector {
    // MARK: - Properties
    private var isMLKitAvailable: Bool = false
    
    // MARK: - Initialization
    public init() {
        checkMLKitAvailability()
    }
    
    // MARK: - Public Interface
    
    /// Detect faces using Google ML Kit
    public func detectFaces(in pixelBuffer: CVPixelBuffer) -> MLKitFaceResult {
        guard isMLKitAvailable else {
            return MLKitFaceResult(
                faces: [],
                confidence: 0.0,
                processingTimeMs: 0,
                error: .mlKitNotAvailable
            )
        }
        
        #if canImport(MLKitVision) && canImport(MLKitFaceDetection)
        return performMLKitDetection(pixelBuffer)
        #else
        return MLKitFaceResult(
            faces: [],
            confidence: 0.0,
            processingTimeMs: 0,
            error: .mlKitNotAvailable
        )
        #endif
    }
    
    // MARK: - Private Methods
    
    private func checkMLKitAvailability() {
        #if canImport(MLKitVision) && canImport(MLKitFaceDetection)
        isMLKitAvailable = true
        print("📱 ML Kit face detection is available")
        #else
        isMLKitAvailable = false
        print("⚠️ ML Kit face detection not available - dependencies missing")
        #endif
    }
    
    #if canImport(MLKitVision) && canImport(MLKitFaceDetection)
    private func performMLKitDetection(_ pixelBuffer: CVPixelBuffer) -> MLKitFaceResult {
        let startTime = CACurrentMediaTime()
        var detectedFaces: [MLKitFaceInfo] = []
        
        do {
            // Configure face detector with enhanced options for distance detection
            let options = FaceDetectorOptions()
            options.performanceMode = .accurate        // Better for distance detection
            options.landmarkMode = .all               // Get landmarks for better analysis
            options.contourMode = .all               // Get face contours
            options.classificationMode = .all        // Get smile, eyes open probability
            options.minFaceSize = CGFloat(0.1)       // Smaller minimum face size than Apple Vision
            options.isTrackingEnabled = true         // Enable face tracking
            
            let faceDetector = FaceDetector.faceDetector(options: options)
            
            // Convert CVPixelBuffer to MLImage
            guard let image = createMLImage(from: pixelBuffer) else {
                return MLKitFaceResult(
                    faces: [],
                    confidence: 0.0,
                    processingTimeMs: 0,
                    error: .imageConversionFailed
                )
            }
            
            // Perform face detection
            let faces = try faceDetector.results(in: image)
            
            // Convert results to our format
            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
            
            for face in faces {
                let mlKitFace = convertToMLKitFaceInfo(face: face, imageSize: imageSize)
                detectedFaces.append(mlKitFace)
            }
            
            let processingTime = Int((CACurrentMediaTime() - startTime) * 1000)
            
            return MLKitFaceResult(
                faces: detectedFaces,
                confidence: detectedFaces.isEmpty ? 0.0 : detectedFaces.max(by: { $0.confidence < $1.confidence })?.confidence ?? 0.0,
                processingTimeMs: processingTime,
                error: nil
            )
            
        } catch {
            let processingTime = Int((CACurrentMediaTime() - startTime) * 1000)
            return MLKitFaceResult(
                faces: [],
                confidence: 0.0,
                processingTimeMs: processingTime,
                error: .detectionFailed(error.localizedDescription)
            )
        }
    }
    
    private func createMLImage(from pixelBuffer: CVPixelBuffer) -> MLImage? {
        // Convert CVPixelBuffer to UIImage first, then to MLImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        return MLImage(image: uiImage)
    }
    
    private func convertToMLKitFaceInfo(face: Face, imageSize: CGSize) -> MLKitFaceInfo {
        let rect = face.frame
        let area = rect.width * rect.height
        let imageArea = imageSize.width * imageSize.height
        let sizePercentage = Float((area / imageArea) * 100.0)
        
        // Calculate headroom percentage
        let headroomPercentage = Float((rect.minY / imageSize.height) * 100.0)
        
        // Extract landmarks
        var landmarks: MLKitFaceLandmarks? = nil
        if let leftEye = face.landmark(ofType: .leftEye),
           let rightEye = face.landmark(ofType: .rightEye),
           let nose = face.landmark(ofType: .noseBase),
           let mouth = face.landmark(ofType: .mouthBottom) {
            landmarks = MLKitFaceLandmarks(
                leftEye: CGPoint(x: leftEye.position.x, y: leftEye.position.y),
                rightEye: CGPoint(x: rightEye.position.x, y: rightEye.position.y),
                nose: CGPoint(x: nose.position.x, y: nose.position.y),
                mouth: CGPoint(x: mouth.position.x, y: mouth.position.y)
            )
        }
        
        return MLKitFaceInfo(
            rect: rect,
            sizePercentage: sizePercentage,
            headroomPercentage: headroomPercentage,
            confidence: 0.95, // ML Kit doesn't provide confidence, use high default
            trackingID: face.hasTrackingID ? Int(face.trackingID) : nil,
            landmarks: landmarks
        )
    }
    #endif
}

// MARK: - Supporting Types

public struct MLKitFaceInfo {
    let rect: CGRect
    let sizePercentage: Float
    let headroomPercentage: Float
    let confidence: Float
    let trackingID: Int?
    let landmarks: MLKitFaceLandmarks?
    
    // Convert to EnhancedFaceInfo for compatibility
    func toEnhancedFaceInfo() -> EnhancedFaceInfo {
        return EnhancedFaceInfo(
            rect: rect,
            sizePercentage: sizePercentage,
            headroomPercentage: headroomPercentage,
            confidence: confidence,
            detectionScale: 0.01 // ML Kit default scale
        )
    }
}

public struct MLKitFaceLandmarks {
    let leftEye: CGPoint?
    let rightEye: CGPoint?
    let nose: CGPoint?
    let mouth: CGPoint?
}

public struct MLKitFaceResult {
    let faces: [MLKitFaceInfo]
    let confidence: Float
    let processingTimeMs: Int
    let error: MLKitError?
}

public enum MLKitError: Error, LocalizedError {
    case mlKitNotAvailable
    case imageConversionFailed
    case detectionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .mlKitNotAvailable:
            return "Google ML Kit is not available. Add ML Kit dependencies to use this feature."
        case .imageConversionFailed:
            return "Failed to convert image for ML Kit processing"
        case .detectionFailed(let message):
            return "ML Kit face detection failed: \(message)"
        }
    }
}