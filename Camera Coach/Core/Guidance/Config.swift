//
//  Config.swift
//  Camera Coach
//
//  Central configuration file with all tunable constants.
//  These values are read-only at runtime for release builds.
//

import Foundation

enum Config {
    // MARK: - Camera Settings
    static let cameraResolution = CGSize(width: 1280, height: 720)
    static let targetFPS: Int = 30
    static let fallbackFPS: Int = 24
    
    // MARK: - Performance Budgets
    static let maxFrameLoopLatencyMs: Int = 80
    static let minStableFPS: Int = 24
    static let thermalGuardThreshold: ProcessInfo.ThermalState = .fair
    
    // MARK: - Guidance Engine
    static let stabilityWindowMs: Int = 300   // 🎯 WEEK 2 SPEC: ≥300ms stability window per FSM specification
    static let ruleCooldownMs: Int = 600
    static let globalMaxPromptsPerSec: Int = 2
    static let postShutterCooldownMs: Int = 1500
    static let maxPromptsPerMinute: Int = 15  // Balanced rate - not too spammy, not too restrictive
    static let maxSameTypePromptsPer10s: Int = 3
    
    // MARK: - Horizon Detection
    static let horizonThresholdDegrees: Float = 3.0  // 🎯 WEEK 2 SPEC: |θ|>3° → emit guidance per specification
    static let horizonHysteresisDegrees: Float = 2.0  // Increased hysteresis for smoother transitions
    static let horizonLowPassAlpha: Float = 0.3  // Updated to match FrameAnalyzer
    static let horizonDeadZoneDegrees: Float = 2.0  // Adjusted to match stricter threshold
    static let horizonGoodEnoughDegrees: Float = 3.0  // Aligned with threshold for consistency
    
    // 🚀 VISUAL SMOOTHING: Reduce red line sensitivity for better UX
    static let visualHorizonLowPassAlpha: Float = 0.1  // Heavy smoothing for visual display (vs 0.3 for guidance logic)
    static let visualUpdateThresholdDegrees: Float = 0.5  // Only update visual if change > 0.5°
    
    // MARK: - Headroom Detection
    static let targetHeadroomPercentage: ClosedRange<Float> = 7.0...12.0
    static let headroomToleranceDegrees: Float = 2.0
    
    // MARK: - Rule of Thirds
    static let thirdsTolerancePercentage: Float = 15.0
    
    // MARK: - Face Detection
    static let minFaceSizePercentage: Float = 2.0
    static let faceStabilityThresholdMs: Int = 300
    
    // MARK: - HUD Animation
    static let hudFadeInDuration: TimeInterval = 0.8
    static let hudFadeOutDuration: TimeInterval = 0.4
    
    // MARK: - Guidance Content
    static let maxGuidanceWords: Int = 12
    
    // MARK: - Privacy & Data
    static let defaultPostShotCloudEnabled: Bool = false
    static let maxDailyCloudUploads: Int = 5
    static let cloudUploadWiFiOnly: Bool = true
    
    // MARK: - Success Metrics
    static let hintAdoptionWindowMs: Int = 10000 // 10 seconds
    static let targetOneShotSuccessRate: Float = 0.6 // 60% by Week 6
    static let targetUserSatisfaction: Float = 3.8 // 3.8/5 by Week 6
    static let maxCrashRate: Float = 0.01 // 1% by Week 6
}
