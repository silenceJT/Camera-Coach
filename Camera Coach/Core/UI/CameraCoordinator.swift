//
//  CameraCoordinator.swift
//  Camera Coach
//
//  Coordinates between camera, analyzer, guidance engine, and HUD.
//  Implements FrameFeaturesProvider for the guidance engine.
//

import Foundation
import AVFoundation
import UIKit
import Combine

public final class CameraCoordinator: NSObject, FrameFeaturesProvider, ObservableObject {
    // MARK: - Properties
    public let cameraController = CameraController()
    private let frameAnalyzer = FrameAnalyzer()
    private var guidanceEngine: GuidanceEngine!
    public private(set) weak var hudView: GuidanceHUDView?
    private let feedbackManager = FeedbackManager.shared
    
    // MARK: - Published Properties
    @Published var currentGuidance: GuidanceAdvice?
    @Published var isGuidanceActive = false
    @Published var currentFrameFeatures: FrameFeatures?
    @Published var enhancedFaceResult: EnhancedFaceResult?

    // MARK: - Perfect Composition State (Week 7 - green ring sync)
    @Published var isPerfectComposition: Bool = false
    
    // MARK: - Performance Monitoring
    private var lastGuidanceTime: Date = Date.distantPast
    private var guidanceCount = 0

    // MARK: - Glass Performance Monitoring (Week 7)
    private var glassRenderingEnabled = true
    private var fpsBeforeGlass: Float = 0
    private var glassEnabledTime: Date?
    private var lastFPSCheckTime: Date = Date()

    // MARK: - Session Tracking
    private var sessionStartTime: Date = Date()
    private var sessionId: String = UUID().uuidString
    private var consecutivePhotos: Int = 0

    // MARK: - Combine Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    public override init() {
        super.init()

        // Initialize guidance engine after super.init
        self.guidanceEngine = GuidanceEngine(provider: self)

        // Set up camera controller delegate
        cameraController.delegate = self

        // 🚀 WEEK 7: Subscribe to perfect composition state from guidance engine
        guidanceEngine.$isPerfectCompositionActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPerfectComposition)
    }
    
    // MARK: - Public Interface
    public func setHUDView(_ hud: GuidanceHUDView) {
        self.hudView = hud
    }
    
    public func setupCamera(in view: UIView) throws {
        try cameraController.setupCamera(in: view)
    }
    
    public func startSession() {
        cameraController.startSession()

        // Initialize session tracking
        sessionStartTime = Date()
        sessionId = UUID().uuidString
        consecutivePhotos = 0

        // 🚀 WEEK 7: Enable glass rendering at session start
        enableGlassRendering()
    }
    
    public func stopSession() {
        cameraController.stopSession()
        
        // Trigger feedback collection at session end (strategic timing)
        feedbackManager.triggerFeedbackIfReady(.sessionEnd)
    }
    
    public func onShutter() {
        guidanceEngine.onShutter()
        isGuidanceActive = false
        
        // Collect silent metrics before capture
        collectPhotoMetrics()
        
        currentGuidance = nil
        consecutivePhotos += 1
        
        // Trigger photo capture
        cameraController.capturePhoto()
    }
    
    public func onPhotoKept(_ kept: Bool) {
        guidanceEngine.onPhotoKept(kept)
    }
    
    // MARK: - Enhanced Face Detection Control
    public func setFaceDetectionStrategy(_ strategy: FaceDetectionStrategy) {
        cameraController.setFaceDetectionStrategy(strategy)
    }

    // MARK: - Template System Control (NEW)
    public func setCurrentTemplate(_ template: Template?) {
        guidanceEngine.setCurrentTemplate(template)
        frameAnalyzer.setCurrentTemplate(template)

        if let template = template {
            print("🎯 CameraCoordinator template set: \(template.id)")
            // Log template selection
            Logger.shared.logTemplateSelected(
                id: template.id,
                category: template.category.rawValue,
                autoRecommended: false
            )
        } else {
            print("🎯 CameraCoordinator template cleared")
        }
    }

    // MARK: - Glass Performance Monitoring (Week 7)

    /// Monitor glass rendering performance and auto-disable if fps drops
    private func monitorGlassPerformance() {
        guard glassRenderingEnabled else { return }

        let currentTime = Date()
        guard currentTime.timeIntervalSince(lastFPSCheckTime) >= 1.0 else { return }
        lastFPSCheckTime = currentTime

        // Get current fps from frame analyzer
        guard let currentFPS = currentFrameFeatures?.currentFPS else { return }

        // Check thermal state
        let thermalState = ProcessInfo.processInfo.thermalState

        // Auto-disable glass if performance degrades
        if currentFPS < 24 || (Config.glassDisableOnThermalFair && thermalState.rawValue >= ProcessInfo.ThermalState.fair.rawValue) {
            disableGlassRendering(reason: currentFPS < 24 ? "fps" : "thermal")

            // Log performance impact
            Logger.shared.logGlassPerfImpact(
                fpsBefore: fpsBeforeGlass > 0 ? fpsBeforeGlass : currentFPS,
                fpsAfter: currentFPS,
                thermalState: thermalState
            )
        }
    }

    /// Disable glass rendering and fall back to Material
    private func disableGlassRendering(reason: String) {
        guard glassRenderingEnabled else { return }

        glassRenderingEnabled = false

        // Log degradation event
        Logger.shared.logGlassDegradation(reason: reason, componentType: "shelf")

        print("🎯 Glass rendering disabled: \(reason)")

        // TODO: Notify SwiftUI components to switch to Material fallback
        // This could be done via a Published property or NotificationCenter
    }

    /// Enable glass rendering (called at session start)
    private func enableGlassRendering() {
        glassRenderingEnabled = true
        glassEnabledTime = Date()
        fpsBeforeGlass = currentFrameFeatures?.currentFPS ?? 30.0

        // Log component rendered
        Logger.shared.logGlassComponentRendered(
            type: "shelf",
            fallbackMode: "glass"
        )

        print("🎯 Glass rendering enabled")
    }

    /// Check if glass rendering is currently active
    public func isGlassRenderingActive() -> Bool {
        return glassRenderingEnabled
    }

    // MARK: - Private Methods - Metrics Collection
    private func collectPhotoMetrics() {
        let currentTime = Date()
        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let timeSinceLastGuidance = currentTime.timeIntervalSince(lastGuidanceTime)
        
        let metrics = PhotoCaptureMetrics(
            timestamp: currentTime,
            guidanceActive: isGuidanceActive,
            lastGuidanceType: currentGuidance?.type,
            timeSinceLastGuidance: timeSinceLastGuidance,
            deviceOrientation: UIDevice.current.orientation,
            thermalState: ProcessInfo.processInfo.thermalState,
            sessionDuration: sessionDuration,
            cameraSession: sessionId,
            consecutivePhotos: consecutivePhotos,
            guidanceAdopted: false, // TODO: Implement proper guidance adoption tracking
            horizonAngleAtCapture: currentFrameFeatures?.horizonDegrees ?? 0.0
        )
        
        // Silent collection - no UI interruption
        feedbackManager.collectPhotoMetrics(metrics)
    }
    
    // MARK: - FrameFeaturesProvider
    public func latest() -> FrameFeatures? {
        return currentFrameFeatures
    }
    
    // MARK: - Private Methods
    private func processGuidance(_ advice: GuidanceAdvice) {
        // Check if we should show this guidance
        let now = Date()
        let timeSinceLastGuidance = now.timeIntervalSince(lastGuidanceTime)
        
        // Ensure minimum time between guidance (anti-spam)
        if timeSinceLastGuidance < 0.5 { // 2 prompts/sec max
            return
        }
        
        // Update guidance state on main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            self?.currentGuidance = advice
            self?.isGuidanceActive = true
        }
        
        lastGuidanceTime = now
        guidanceCount += 1
        
        // Auto-hide guidance after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hideGuidance()
        }
    }
    
    private func hideGuidance() {
        DispatchQueue.main.async { [weak self] in
            self?.isGuidanceActive = false
            self?.currentGuidance = nil
        }
    }
    
    private func shouldShowGuidance() -> Bool {
        // Don't show guidance if we're in post-shutter cooldown
        if guidanceEngine.isInPostShutterCooldown {
            return false
        }
        
        // Don't show guidance if we're already showing one
        if isGuidanceActive {
            return false
        }
        
        return true
    }
}

// MARK: - CameraControllerDelegate
extension CameraCoordinator: CameraControllerDelegate {
    public func cameraController(_ controller: CameraController, didUpdateFrame features: FrameFeatures) {
        // Update current frame features
        currentFrameFeatures = features

        // Update guidance engine with current frame features
        guidanceEngine.currentFrameFeatures = features

        // 🚀 WEEK 7: Monitor glass performance
        monitorGlassPerformance()

        // 🚀 NEW: Update level indicator using proper angle provider
        DispatchQueue.main.async { [weak self] in
            self?.hudView?.updateLevelIndicator()
        }

        // Debug: Log frame features to see what we're working with
        // Check if we should process guidance
        guard shouldShowGuidance() else {
            return
        }

        // Process frame through guidance engine
        if let advice = guidanceEngine.processFrame() {
            // Show guidance on main thread
            DispatchQueue.main.async { [weak self] in
                self?.processGuidance(advice)
            }
        }
    }
    
    public func cameraController(_ controller: CameraController, didUpdateEnhancedFaceDetection result: EnhancedFaceResult) {
        // Update enhanced face detection results
        enhancedFaceResult = result
    }
    
    public func cameraController(_ controller: CameraController, didEncounterError error: Error) {
        // Handle camera errors
        
        // Could show user-facing error message here
    }
    
    public func cameraControllerDidCapturePhoto(_ controller: CameraController) {
        // Photo captured successfully
        // Could add visual feedback here (flash effect, success animation)
        
        // For now, we assume photo is kept (user could be asked in micro-survey)
        onPhotoKept(true)
    }
    
    public func cameraController(_ controller: CameraController, didFailWithError error: Error) {
        // Photo capture failed
        
        // Could show user-facing error message here
        onPhotoKept(false)
    }
}
