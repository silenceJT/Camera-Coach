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
    static let cameraResolution = CGSize(width: 1280, height: 960)  // 4:3 aspect ratio like iPhone camera
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
    
    // MARK: - Headroom Detection (Relaxed for letterbox camera view)
    static let targetHeadroomPercentage: ClosedRange<Float> = 5.0...20.0  // Much wider range for easier positioning
    static let headroomToleranceDegrees: Float = 3.0  // More tolerance before triggering guidance
    
    // 🚀 WEEK 3: Enhanced Headroom Configuration
    static let maxHeadroomAdjustmentDegrees: Int = 8  // Cap tilt adjustments
    static let maxHeadroomPromptsPerSession: Int = 2  // Prevent headroom spam per Week 3 spec
    
    // MARK: - Rule of Thirds
    static let thirdsTolerancePercentage: Float = 15.0
    
    // MARK: - Face Detection
    static let minFaceSizePercentage: Float = 1.0  // 🚀 Reduced from 2% to 1% for far-distance detection
    static let faceStabilityThresholdMs: Int = 300
    
    // 🚀 WEEK 3: Enhanced distance detection settings
    static let enableFarDistanceDetection: Bool = true
    static let farDistanceMinFaceSizePercentage: Float = 0.5  // Even smaller faces for far shots
    
    // 🚀 MULTI-FACE ENHANCEMENT: Group headroom configuration
    static let enableGroupHeadroomGuidance: Bool = true          // Enable multi-face headroom strategy
    static let groupHeadroomThreshold: Int = 2                   // Switch to group strategy at 2+ faces
    static let groupHeadroomConfidenceBoost: Float = 0.1         // Increase confidence for group guidance
    static let maxTrackedFaces: Int = 10                         // Limit face tracking for performance
    
    // MARK: - HUD Animation
    static let hudFadeInDuration: TimeInterval = 0.8
    static let hudFadeOutDuration: TimeInterval = 0.4
    
    // MARK: - Guidance Content
    static let maxGuidanceWords: Int = 12
    
    // MARK: - Privacy & Data
    static let defaultPostShotCloudEnabled: Bool = false
    static let maxDailyCloudUploads: Int = 5
    static let cloudUploadWiFiOnly: Bool = true
    
    // MARK: - Template System Configuration (NEW)
    static let templateAlignmentThresholdPct: Float = 5.0  // When to trigger template alignment guidance
    static let silhouetteOpacity: Float = 0.3              // 30% opacity for silhouette overlay
    static let templateAnimationDuration: TimeInterval = 0.4
    static let autoTemplateRecommendation: Bool = true     // Auto-recommend templates based on face count

    // Template-specific cooldowns
    static let templateSwitchCooldownMs: Int = 1000             // Prevent rapid template switching
    static let templateAlignmentCooldownMs: Int = 500           // Template alignment guidance cooldown

    // Template alignment thresholds
    static let perfectAlignmentThreshold: Float = 0.02         // 2% threshold for "perfect" alignment
    static let goodAlignmentThreshold: Float = 0.05           // 5% threshold for "good" alignment
    static let templateConfidenceBoost: Float = 0.15          // Confidence boost for template-based guidance

    // MARK: - Success Metrics (UPDATED FOR TEMPLATE SYSTEM)
    static let hintAdoptionWindowMs: Int = 10000 // 10 seconds
    static let targetOneShotSuccessRate: Float = 0.75 // 75% by Week 10 (improved with silhouette guidance)
    static let targetUserSatisfaction: Float = 4.3 // 4.3/5 by Week 10 (significantly improved UX)
    static let maxCrashRate: Float = 0.01 // 1% by Week 6

    // MARK: - Liquid Glass Design Tokens (Week 7)
    // Corner Radii
    static let glassShelfCornerRadius: CGFloat = 22        // Shelf container radius
    static let glassCardCornerRadius: CGFloat = 16         // Individual card radius
    static let glassPillCornerRadius: CGFloat = 999        // Capsule (max radius)

    // Opacities
    static let glassShelfOpacity: Float = 0.85             // 85% opacity for shelf
    static let glassCardOpacity: Float = 0.90              // 90% opacity for cards (higher legibility)
    static let glassPillOpacity: Float = 0.92              // 92% opacity for hint pill (highest legibility)
    static let glassBorderOpacity: Float = 0.12            // White border at 12% opacity
    static let glassBorderWidth: CGFloat = 0.5             // Thin border stroke

    // Shadows
    static let glassShadowRadius: CGFloat = 8              // Subtle shadow
    static let glassShadowOffsetY: CGFloat = 2             // Shadow y-offset

    // Animation
    static let glassAnimationDuration: TimeInterval = 0.12 // 120ms spring animation
    static let glassSpringResponse: Double = 0.18          // Spring response
    static let glassSpringDamping: Double = 0.9            // Spring damping fraction

    // Glass performance & degradation
    static let glassMaxFPSImpact: Float = 2.0              // Max fps drop allowed with glass
    static let glassDisableOnThermalFair: Bool = true      // Auto-disable at thermal .fair
    static let glassMaxNestingDepth: Int = 1               // Never nest glass >1 level
}
