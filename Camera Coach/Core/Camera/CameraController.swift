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
import Photos

public protocol CameraControllerDelegate: AnyObject {
    func cameraController(_ controller: CameraController, didUpdateFrame features: FrameFeatures)
    func cameraController(_ controller: CameraController, didEncounterError error: Error)
    func cameraControllerDidCapturePhoto(_ controller: CameraController)
    func cameraController(_ controller: CameraController, didFailWithError error: Error)
}

public final class CameraController: NSObject {
    // MARK: - Properties
    public weak var delegate: CameraControllerDelegate?
    
    private let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let frameAnalyzer = FrameAnalyzer()
    
    private let sessionQueue = DispatchQueue(label: "com.silencejt.cameracoach.session", qos: .userInitiated)
    private let videoDataQueue = DispatchQueue(label: "com.silencejt.cameracoach.videodata", qos: .userInitiated)
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionRunning = false
    private var currentDevice: AVCaptureDevice?
    private var angleProvider: LevelAngleProvider?
    
    // MARK: - Performance Monitoring
    private var frameCount = 0
    private var lastFrameTime: TimeInterval = 0
    private var thermalState: ProcessInfo.ThermalState = .nominal
    
    // MARK: - Initialization
    public override init() {
        super.init()
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
    
    public func capturePhoto() {
        guard isSessionRunning else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            
            // Enable high resolution capture
            if self.photoOutput.isHighResolutionCaptureEnabled {
                settings.isHighResolutionPhotoEnabled = true
            }
            
            // Set correct photo orientation to match device orientation
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                if photoOutputConnection.isVideoOrientationSupported {
                    // Use current device orientation for proper photo orientation
                    let deviceOrientation = UIDevice.current.orientation
                    switch deviceOrientation {
                    case .portrait:
                        photoOutputConnection.videoOrientation = .portrait
                    case .portraitUpsideDown:
                        photoOutputConnection.videoOrientation = .portraitUpsideDown
                    case .landscapeLeft:
                        photoOutputConnection.videoOrientation = .landscapeRight
                    case .landscapeRight:
                        photoOutputConnection.videoOrientation = .landscapeLeft
                    default:
                        // Default to portrait for face up/down or unknown
                        photoOutputConnection.videoOrientation = .portrait
                    }
                }
            }
            
            // Capture the photo
            self.photoOutput.capturePhoto(with: settings, delegate: self)
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
        
        // Store device reference for level indicator
        self.currentDevice = backCamera
        
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
        
        // Configure photo output for still image capture
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(photoOutput)
        
        // Lock orientation to portrait
        if let connection = videoDataOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 0
            } else {
                connection.videoOrientation = .portrait
            }
        }
        
        // Configure photo output connection orientation
        if let photoConnection = photoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                photoConnection.videoRotationAngle = 0
            } else {
                photoConnection.videoOrientation = .portrait
            }
        }
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
        // Use FrameAnalyzer for comprehensive analysis
        let features = frameAnalyzer.analyzeFrame(sampleBuffer)
        
        // Log performance metrics periodically
        if frameCount % 30 == 0 { // Every 30 frames
            Logger.shared.logFPSSample(average: features.currentFPS, p95: features.currentFPS)
        }
        
        frameCount += 1
        
        return features
    }
    
    // MARK: - Level Indicator Setup
    
    public func setupLevelIndicator(for hudView: GuidanceHUDView) {
        guard currentDevice != nil else {
            return
        }
        
        // Always use Core Motion for reliable world-relative roll angle
        // The RotationCoordinatorAngleProvider was returning preview rotation angles
        // rather than the direct world-relative roll we need for the level indicator
        let provider = MotionAngleProvider()
        provider.start()
        self.angleProvider = provider
        hudView.setAngleProvider(provider)
    }
    
    // Frame analysis is now handled by FrameAnalyzer
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

// Frame analysis is now handled by FrameAnalyzer

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

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.delegate?.cameraController(self, didFailWithError: error)
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            let error = CameraError.cannotAddOutput // Reuse existing error
            DispatchQueue.main.async {
                self.delegate?.cameraController(self, didFailWithError: error)
            }
            return
        }
        
        guard let image = UIImage(data: imageData) else {
            let error = CameraError.cannotAddOutput // Reuse existing error
            DispatchQueue.main.async {
                self.delegate?.cameraController(self, didFailWithError: error)
            }
            return
        }
        
        // Save to Photos Library
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.creationRequestForAsset(from: image)
                }) { [weak self] success, error in
                    DispatchQueue.main.async {
                        if success {
                            self?.delegate?.cameraControllerDidCapturePhoto(self!)
                            Logger.shared.logPhotoKept(kept: true)
                        } else {
                            self?.delegate?.cameraController(self!, didFailWithError: error ?? CameraError.cannotAddOutput)
                            Logger.shared.logPhotoKept(kept: false)
                        }
                    }
                }
            case .denied, .restricted, .notDetermined:
                DispatchQueue.main.async {
                    let error = CameraError.cannotAddOutput // Reuse existing error for photo permission
                    self?.delegate?.cameraController(self!, didFailWithError: error)
                    Logger.shared.logPhotoKept(kept: false)
                }
            @unknown default:
                DispatchQueue.main.async {
                    let error = CameraError.cannotAddOutput // Reuse existing error
                    self?.delegate?.cameraController(self!, didFailWithError: error)
                    Logger.shared.logPhotoKept(kept: false)
                }
            }
        }
    }
}
