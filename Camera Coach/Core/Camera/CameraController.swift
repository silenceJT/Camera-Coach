//
//  CameraController.swift
//  Camera Coach
//
//  Handles camera session setup, frame capture, and preview layer.
//  Runs on background queue for frame processing, main queue for UI updates.
//

import UIKit
import AVFoundation
import CoreMotion
import Vision

public protocol CameraControllerDelegate: AnyObject {
    func cameraController(_ controller: CameraController, didUpdateFrame features: FrameFeatures)
    func cameraController(_ controller: CameraController, didEncounterError error: Error)
}

public final class CameraController: NSObject {
    // MARK: - Properties
    public weak var delegate: CameraControllerDelegate?
    
    private let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let motionManager = CMMotionManager()
    
    private let sessionQueue = DispatchQueue(label: "com.silencejt.cameracoach.session", qos: .userInitiated)
    private let videoDataQueue = DispatchQueue(label: "com.silencejt.cameracoach.videodata", qos: .userInitiated)
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionRunning = false
    
    // MARK: - Performance Monitoring
    private var frameCount = 0
    private var lastFrameTime: TimeInterval = 0
    private var fpsCalculator = FPSCalculator()
    private var thermalState: ProcessInfo.ThermalState = .nominal
    
    // MARK: - Initialization
    public override init() {
        super.init()
        setupMotionManager()
        setupThermalMonitoring()
    }
    
    deinit {
        stopSession()
    }
    
    // MARK: - Public Interface
    public func setupCamera(in view: UIView) throws {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        
        self.previewLayer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        view.layer.addSublayer(previewLayer)
        
        try configureSession()
    }
    
    public func startSession() {
        guard !isSessionRunning else { return }
        
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = true
            }
        }
    }
    
    public func stopSession() {
        guard isSessionRunning else { return }
        
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
    
    public func updatePreviewLayerFrame(_ frame: CGRect) {
        previewLayer?.frame = frame
    }
    
    // MARK: - Private Setup
    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // Set resolution to 720p as specified
        session.sessionPreset = .hd1280x720
        
        // Get back camera
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.backCameraNotFound
        }
        
        // Create input
        let videoInput = try AVCaptureDeviceInput(device: backCamera)
        guard session.canAddInput(videoInput) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(videoInput)
        
        // Configure video data output
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        guard session.canAddOutput(videoDataOutput) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(videoDataOutput)
        
        // Lock orientation to portrait
        if let connection = videoDataOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 0
            } else {
                connection.videoOrientation = .portrait
            }
        }
    }
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30Hz updates
    }
    
    private func setupThermalMonitoring() {
        thermalState = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func thermalStateDidChange() {
        thermalState = ProcessInfo.processInfo.thermalState
        
        // Log thermal state change
        Logger.shared.logThermalSample(state: thermalState)
        
        // Adjust performance based on thermal state
        if thermalState.rawValue >= Config.thermalGuardThreshold.rawValue {
            // Reduce frame rate if needed
            if session.sessionPreset != .hd1280x720 {
                sessionQueue.async { [weak self] in
                    self?.session.sessionPreset = .hd1280x720
                }
            }
        }
    }
    
    // MARK: - Frame Analysis
    private func analyzeFrame(_ sampleBuffer: CMSampleBuffer) -> FrameFeatures {
        let startTime = CACurrentMediaTime()
        
        // Get image buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return FrameFeatures(
                horizonDegrees: 0,
                horizonStableMs: 0,
                faceRect: nil,
                faceStableMs: 0,
                faceSizePercentage: nil,
                headroomPercentage: nil,
                thirdsOffsetPercentage: nil,
                timestamp: startTime,
                processingLatencyMs: 0,
                thermalState: thermalState,
                currentFPS: fpsCalculator.currentFPS
            )
        }
        
        // Analyze horizon using CoreMotion
        let horizonDegrees = getHorizonDegrees()
        let horizonStableMs = getHorizonStabilityMs()
        
        // Analyze face using Vision
        let faceAnalysis = analyzeFace(in: imageBuffer)
        
        // Calculate processing latency
        let endTime = CACurrentMediaTime()
        let latencyMs = Int((endTime - startTime) * 1000)
        
        // Update FPS calculation
        fpsCalculator.updateFrame()
        
        // Log performance metrics periodically
        if frameCount % 30 == 0 { // Every 30 frames
            Logger.shared.logFPSSample(average: fpsCalculator.averageFPS, p95: fpsCalculator.p95FPS)
        }
        
        frameCount += 1
        
        return FrameFeatures(
            horizonDegrees: horizonDegrees,
            horizonStableMs: horizonStableMs,
            faceRect: faceAnalysis.rect,
            faceStableMs: faceAnalysis.stableMs,
            faceSizePercentage: faceAnalysis.sizePercentage,
            headroomPercentage: faceAnalysis.headroomPercentage,
            thirdsOffsetPercentage: faceAnalysis.thirdsOffsetPercentage,
            timestamp: startTime,
            processingLatencyMs: latencyMs,
            thermalState: thermalState,
            currentFPS: fpsCalculator.currentFPS
        )
    }
    
    private func getHorizonDegrees() -> Float {
        guard motionManager.isDeviceMotionAvailable else { return 0.0 }
        
        if !motionManager.isDeviceMotionActive {
            motionManager.startDeviceMotionUpdates()
        }
        
        guard let motion = motionManager.deviceMotion else { return 0.0 }
        
        // Convert roll to degrees and apply low-pass filter
        let rollDegrees = Float(motion.attitude.roll * 180.0 / .pi)
        return rollDegrees
    }
    
    private func getHorizonStabilityMs() -> Int {
        // For now, return a placeholder value
        // This will be implemented with proper stability tracking
        return 500
    }
    
    private func analyzeFace(in imageBuffer: CVPixelBuffer) -> FaceAnalysis {
        // For Week 1, return placeholder values
        // Vision framework integration will come in Week 2-3
        return FaceAnalysis(
            rect: nil,
            stableMs: 0,
            sizePercentage: nil,
            headroomPercentage: nil,
            thirdsOffsetPercentage: nil
        )
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let features = analyzeFrame(sampleBuffer)
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraController(self!, didUpdateFrame: features)
        }
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

private struct FPSCalculator {
    private var frameTimes: [TimeInterval] = []
    private let maxSamples = 60 // 2 seconds at 30fps
    
    var currentFPS: Float {
        guard frameTimes.count >= 2 else { return 0.0 }
        let recent = Array(frameTimes.suffix(2))
        let interval = recent[1] - recent[0]
        return interval > 0 ? Float(1.0 / interval) : 0.0
    }
    
    var averageFPS: Float {
        guard frameTimes.count >= 2 else { return 0.0 }
        let intervals = zip(frameTimes, frameTimes.dropFirst()).map { $1 - $0 }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        return avgInterval > 0 ? Float(1.0 / avgInterval) : 0.0
    }
    
    var p95FPS: Float {
        guard frameTimes.count >= 2 else { return 0.0 }
        let intervals = zip(frameTimes, frameTimes.dropFirst()).map { $1 - $0 }
        let sorted = intervals.sorted()
        let p95Index = Int(Double(sorted.count) * 0.95)
        let p95Interval = sorted[p95Index]
        return p95Interval > 0 ? Float(1.0 / p95Interval) : 0.0
    }
    
    mutating func updateFrame() {
        let now = CACurrentMediaTime()
        frameTimes.append(now)
        
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }
    }
}

// MARK: - Errors
public enum CameraError: LocalizedError {
    case backCameraNotFound
    case cannotAddInput
    case cannotAddOutput
    case previewLayerCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .backCameraNotFound:
            return "Back camera not found"
        case .cannotAddInput:
            return "Cannot add camera input"
        case .cannotAddOutput:
            return "Cannot add camera output"
        case .previewLayerCreationFailed:
            return "Failed to create preview layer"
        }
    }
}
