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

public final class CameraCoordinator: NSObject, FrameFeaturesProvider, ObservableObject {
    // MARK: - Properties
    public let cameraController = CameraController()
    private let frameAnalyzer = FrameAnalyzer()
    private var guidanceEngine: GuidanceEngine!
    public private(set) weak var hudView: GuidanceHUDView?
    
    // MARK: - Published Properties
    @Published var currentGuidance: GuidanceAdvice?
    @Published var isGuidanceActive = false
    @Published var currentFrameFeatures: FrameFeatures?
    
    // MARK: - Performance Monitoring
    private var lastGuidanceTime: Date = Date.distantPast
    private var guidanceCount = 0
    
    // MARK: - Initialization
    public override init() {
        super.init()
        
        // Initialize guidance engine after super.init
        self.guidanceEngine = GuidanceEngine(provider: self)
        
        // Set up camera controller delegate
        cameraController.delegate = self
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
    }
    
    public func stopSession() {
        cameraController.stopSession()
    }
    
    public func onShutter() {
        guidanceEngine.onShutter()
        isGuidanceActive = false
        currentGuidance = nil
        
        // Trigger photo capture
        cameraController.capturePhoto()
    }
    
    public func onPhotoKept(_ kept: Bool) {
        guidanceEngine.onPhotoKept(kept)
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
