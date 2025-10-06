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
    
    // MARK: - Headroom Detection (Context-aware for composition position)
    // 🎯 CONTEXT-AWARE HEADROOM: Targets based on vertical position in VISIBLE preview
    // IMPORTANT: Vertical position 0%=bottom, 100%=top (Vision Y-axis points UP)
    //
    // 📸 PHOTOGRAPHER-FRIENDLY RANGES (Week 7 Update):
    // Based on professional portrait standards and rule of thirds (eyes at 1/3 from top)
    // Research: Standard portraits have 15-30% headroom, tight headshots 5-15%, half-length 20-35%

    // Upper third position (face at 66-100% from bottom = near TOP): Tight headshot style
    // Minimal breathing room - common for close-up portraits
    static let upperThirdsHeadroomRange: ClosedRange<Float> = 5.0...20.0  // Was 0-8, now more flexible

    // Centered position (face at 33-66% from bottom = MIDDLE): Standard portrait framing
    // Follows rule of thirds - eyes at ~1/3 from top creates natural headroom
    static let centeredHeadroomRange: ClosedRange<Float> = 15.0...35.0  // Was 7-12, now matches pro standards

    // Lower third position (face at 0-33% from bottom = near BOTTOM): Environmental/full-length
    // Lots of space above - common for showing environment or full body
    static let lowerThirdsHeadroomRange: ClosedRange<Float> = 35.0...55.0  // Was 35-50, expanded upper bound

    // Legacy (for backward compatibility - use centered range)
    static let targetHeadroomPercentage: ClosedRange<Float> = 7.0...12.0
    static let headroomTolerancePercentage: Float = 3.0  // Increased tolerance for better UX
    
    // 🚀 WEEK 3: Enhanced Headroom Configuration
    static let maxHeadroomAdjustmentDegrees: Int = 8  // Cap tilt adjustments
    static let maxHeadroomPromptsPerSession: Int = 2  // Prevent headroom spam per Week 3 spec
    
    // MARK: - Rule of Thirds
    static let thirdsTolerancePercentage: Float = 15.0

    // MARK: - Face Orientation & Lead Space (Week 7)
    static let minOrientationConfidence: Float = 0.6           // Min confidence to trust orientation
    static let orientationHistorySize: Int = 10                // Frames to track for orientation detection
    static let orientationStabilityThreshold: Float = 0.7      // Ratio of consistent frames needed
    static let leadSpaceTargetPercentage: ClosedRange<Float> = 20.0...40.0  // Ideal lead space range
    static let leadSpaceTolerancePercentage: Float = 10.0      // Tolerance before triggering guidance
    static let leadSpaceCooldownMs: Int = 800                  // Cooldown for lead space guidance

    // MARK: - Composition Smoothing & Debouncing (Week 7 - Professional Camera App Behavior)

    // EMA Smoothing Factors (α values for exponential moving average)
    // Formula: smoothed = α × current + (1-α) × previous
    // Lower α = more smoothing, slower response (good for UI stability)
    // Higher α = less smoothing, faster response (good for user control)
    static let headroomSmoothingAlpha: Float = 0.2            // Headroom smoothing (balanced)
    static let leadSpaceSmoothingAlpha: Float = 0.2           // Lead space smoothing (balanced)
    static let thirdsOffsetSmoothingAlpha: Float = 0.15       // Thirds offset (more smoothing for visual stability)
    static let eyeroomSmoothingAlpha: Float = 0.18            // Eyeroom smoothing (slightly more responsive)

    // Hysteresis Ranges for Perfect Composition (Schmitt Trigger Pattern)
    // ENTER perfect: Strict thresholds (narrow band)
    // EXIT perfect: Looser thresholds (wider band - prevents flickering)

    // Headroom hysteresis (by vertical position)
    static let upperThirdsHeadroomExitRange: ClosedRange<Float> = 2.0...25.0    // Entry: 5-20, Exit: 2-25
    static let centeredHeadroomExitRange: ClosedRange<Float> = 12.0...40.0      // Entry: 15-35, Exit: 12-40
    static let lowerThirdsHeadroomExitRange: ClosedRange<Float> = 32.0...60.0   // Entry: 35-55, Exit: 32-60

    // Lead space hysteresis
    static let leadSpaceExitRange: ClosedRange<Float> = 15.0...45.0             // Entry: 20-40, Exit: 15-45

    // Rule of thirds hysteresis (horizontal centering)
    static let thirdsExitTolerancePercentage: Float = 20.0                      // Entry: 15%, Exit: 20%

    // Time-based persistence gates (prevent rapid state flickering)
    static let perfectCompositionMinDurationMs: Int = 150     // Must be perfect for 150ms before showing
    static let imperfectMinDurationMs: Int = 200              // Must be imperfect for 200ms before hiding

    // Green ring glow animation parameters
    static let glowFadeInDuration: TimeInterval = 0.2         // Fast fade-in when entering perfect
    static let glowFadeOutDuration: TimeInterval = 0.3        // Slightly slower fade-out

    // MARK: - Edge Density Detection (Week 7)
    static let edgeDensitySampleWidth: CGFloat = 30            // Width of edge sampling region (pixels)
    static let edgeDensityThreshold: Float = 0.3               // Edge density threshold for conflict (0-1)
    static let edgeGuidanceEnabled: Bool = true                // Enable edge-aware guidance
    static let edgeAvoidanceBoost: Float = 0.1                 // Confidence boost when avoiding edges
    
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

    // Card Dimensions (EXACT SVG SPEC: board_glass_primitives.svg)
    static let glassCardWidth: CGFloat = 88                // 88pt width per SVG spec
    static let glassCardHeight: CGFloat = 72               // 72pt height per SVG spec

    // Spacing (EXACT SVG SPEC)
    static let glassCardSpacing: CGFloat = 10              // 10pt spacing per SVG spec

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
