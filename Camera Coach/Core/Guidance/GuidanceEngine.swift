//
//  GuidanceEngine.swift
//  Camera Coach
//
//  Core guidance engine implementing the FSM for camera coaching.
//  Handles priority arbitration, cooldowns, and anti-spam logic.
//

import Foundation

public protocol FrameFeaturesProvider: AnyObject {
    func latest() -> FrameFeatures?
}

public final class GuidanceEngine: ObservableObject {
    // MARK: - Properties
    private let provider: FrameFeaturesProvider
    private let logger = Logger.shared
    
    // MARK: - State Management
    private enum State {
        case idle
        case analyzing
        case hintCooldown(Date)
        case postShutterCooldown(Date)
    }
    
    private var currentState: State = .idle
    private var lastGuidanceTime: Date = Date.distantPast
    private var lastShutterTime: Date = Date.distantPast
    
    // MARK: - Cooldown Tracking
    private var typeCooldowns: [GuidanceType: Date] = [:]
    private var recentPrompts: [GuidanceType: Date] = [:]
    
    // MARK: - Performance Monitoring
    private var guidanceCount = 0
    private var sessionStartTime = Date()
    
    // MARK: - Current State
    public private(set) var currentGuidance: GuidanceAdvice?
    
    // MARK: - Frame Features (set by CameraCoordinator)
    public var currentFrameFeatures: FrameFeatures?
    
    // MARK: - Initialization
    public init(provider: FrameFeaturesProvider) {
        self.provider = provider
        startSession()
    }
    
    // MARK: - Public Interface
    public func processFrame() -> GuidanceAdvice? {
        // Check if we can emit guidance
        guard !isInCooldown() && canEmitGuidance() else { 
            return nil 
        }
        
        // Get current frame features from the coordinator
        guard let features = currentFrameFeatures else { 
            return nil 
        }
        
        // Analyze frame and generate guidance
        if let advice = analyzeFrameAndGenerateGuidance(features) {
            // Apply cooldowns and track usage
            applyCooldowns(for: advice)
            trackGuidanceUsage(advice)
            
            // Update current guidance
            currentGuidance = advice
            
            // Log the guidance
            logger.logHintShown(
                type: advice.type.rawValue,
                confidence: advice.confidence,
                ruleVersion: advice.ruleVersion
            )
            
            return advice
        }
        
        return nil
    }
    
    public func onShutter() {
        lastShutterTime = Date()
        currentState = .postShutterCooldown(Date().addingTimeInterval(TimeInterval(Config.postShutterCooldownMs) / 1000.0))
        
        // Log shutter event
        let latencyFromFirstHint = Int((Date().timeIntervalSince(lastGuidanceTime)) * 1000)
        logger.logShutter(mode: "single", latencyFromFirstHintMs: max(0, latencyFromFirstHint))
    }
    
    public func onPhotoKept(_ kept: Bool) {
        logger.logPhotoKept(kept: kept)
    }
    
    public func update() {
        guard let features = provider.latest() else { return }
        
        // Check if we can emit guidance
        guard !isInCooldown() && canEmitGuidance() else { return }
        
        // Generate guidance based on current frame features
        if let guidance = analyzeFrameAndGenerateGuidance(features) {
            // Apply cooldowns and track usage
            applyCooldowns(for: guidance)
            trackGuidanceUsage(guidance)
            
            // Update current guidance
            currentGuidance = guidance
            
            // Log the guidance shown
            logger.logHintShown(type: guidance.type.rawValue, confidence: guidance.confidence, ruleVersion: "1.0")
        }
    }
    

    
    // MARK: - Private Methods
    private func startSession() {
        sessionStartTime = Date()
        lastGuidanceTime = Date() // Initialize to current time so first guidance can be generated
        guidanceCount = 0
        typeCooldowns.removeAll()
        recentPrompts.removeAll()
    }
    
    private func isInCooldown() -> Bool {
        switch currentState {
        case .idle, .analyzing:
            return false
        case .hintCooldown(let endTime):
            if Date() >= endTime {
                currentState = .idle
                return false
            }
            return true
        case .postShutterCooldown(let endTime):
            if Date() >= endTime {
                currentState = .idle
                return false
            }
            return true
        }
    }
    
    private func canEmitGuidance() -> Bool {
        let now = Date()
        
        // Global rate limiting: ≤2 prompts/sec
        let timeSinceLastGuidance = now.timeIntervalSince(lastGuidanceTime)
        
        if timeSinceLastGuidance < 0.5 { // 2 prompts/sec = 0.5s between prompts
            return false
        }
        
        // 🚀 CRITICAL FIX: Improved session limit logic
        // Previous logic was flawed: max(1, Int(sessionDuration / 60.0) * Config.maxPromptsPerMinute)
        // This meant: first minute = 1 prompt, after 1 minute = 20 prompts (too restrictive then too permissive)
        
        let sessionDuration = now.timeIntervalSince(sessionStartTime)
        let sessionMinutes = sessionDuration / 60.0
        
        // Allow more guidance in the first minute for immediate feedback
        let maxPromptsInSession: Int
        if sessionMinutes < 1.0 {
            // First minute: allow up to 5 prompts (more responsive initial feedback)
            maxPromptsInSession = 5
        } else if sessionMinutes < 2.0 {
            // Second minute: allow up to 8 prompts
            maxPromptsInSession = 8
        } else {
            // After 2 minutes: use the configured rate
            maxPromptsInSession = Int(sessionMinutes * Double(Config.maxPromptsPerMinute))
        }
        
        if guidanceCount >= maxPromptsInSession {
            return false
        }
        
        return true
    }
    
    private func analyzeFrameAndGenerateGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        // Priority order: headroom > horizon > thirds
        // Only emit guidance if higher priority issues are resolved
        
        // 1. Headroom guidance (highest priority)
        if let headroomAdvice = generateHeadroomGuidance(features) {
            return headroomAdvice
        }
        
        // 2. Horizon guidance (independent of headroom - can work without faces)
        if let horizonAdvice = generateHorizonGuidance(features) {
            return horizonAdvice
        }
        
        // 3. Rule of thirds (only if headroom and horizon are good)
        if features.isHeadroomInTarget && features.isHorizonLevel {
            if let thirdsAdvice = generateThirdsGuidance(features) {
                return thirdsAdvice
            }
        }
        
        // Clear currentGuidance when no new guidance is generated
        // This prevents the guidance engine from staying "stuck" with old guidance
        // after the user corrects their position
        if currentGuidance != nil {
            currentGuidance = nil
        }
        
        return nil
    }
    
    private func generateHeadroomGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        guard let headroom = features.headroomPercentage,
              features.hasStableFace else { return nil }
        
        // Check if headroom is outside target range
        if !features.isHeadroomInTarget {
            let targetCenter = (Config.targetHeadroomPercentage.upperBound + Config.targetHeadroomPercentage.lowerBound) / 2
            let difference = targetCenter - headroom
            
            if abs(difference) > Config.headroomToleranceDegrees {
                let action: GuidanceAction
                let reason: String
                
                if difference > 0 {
                    // Need more headroom - tilt up
                    let degrees = Int(round(abs(difference)))
                    action = .tiltUp(degrees: min(degrees, 10)) // Cap at 10 degrees
                    reason = "Better headroom"
                } else {
                    // Too much headroom - tilt down
                    let degrees = Int(round(abs(difference)))
                    action = .tiltDown(degrees: min(degrees, 10))
                    reason = "Better framing"
                }
                
                return GuidanceAdvice(
                    action: action,
                    type: .headroom,
                    reason: reason,
                    confidence: 0.9,
                    cooldownMs: Config.ruleCooldownMs
                )
            }
        }
        
        return nil
    }
    
    private func generateHorizonGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        // Only provide horizon guidance if horizon is stable and tilted
        guard features.hasStableHorizon,
              !features.isHorizonLevel else { 
            return nil 
        }
        
        let degrees = features.horizonDegrees
        let absDegrees = abs(degrees)
        
        // Apply dead zone to prevent guidance spam
        // Don't guide if user is already "good enough" (±2.0°)
        if absDegrees <= Config.horizonGoodEnoughDegrees {
            return nil
        }
        
        // Apply smart hysteresis to prevent oscillation
        // Only guide if significantly outside threshold + hysteresis
        let effectiveThreshold = Config.horizonThresholdDegrees + Config.horizonHysteresisDegrees
        
        if absDegrees > effectiveThreshold {
            let action: GuidanceAction
            let reason: String
            
            if degrees > 0 {
                // Tilted right - rotate left
                let roundedDegrees = Int(round(absDegrees))
                action = .rotateLeft(degrees: roundedDegrees)
                reason = "Level horizon"
            } else {
                // Tilted left - rotate right
                let roundedDegrees = Int(round(absDegrees))
                action = .rotateRight(degrees: roundedDegrees)
                reason = "Level horizon"
            }
            
            // 🚀 SMART COOLDOWN: Adaptive cooldown based on improvement
            let adaptiveCooldown = calculateAdaptiveCooldown(for: .horizon, currentAngle: degrees)
            
            return GuidanceAdvice(
                action: action,
                type: .horizon,
                reason: reason,
                confidence: 0.95,
                cooldownMs: adaptiveCooldown
            )
        } else {
            return nil
        }
        
        return nil
    }
    
    private func generateThirdsGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        guard let thirdsOffset = features.thirdsOffsetPercentage,
              features.hasStableFace else { return nil }
        
        // Only suggest thirds guidance if offset is significant
        if abs(thirdsOffset) > Config.thirdsTolerancePercentage {
            let action: GuidanceAction
            let reason: String
            
            if thirdsOffset > 0 {
                // Subject is too far right - move left
                let percentage = Int(round(abs(thirdsOffset)))
                action = .moveLeft(percentage: min(percentage, 15)) // Cap at 15%
                reason = "Better composition"
            } else {
                // Subject is too far left - move right
                let percentage = Int(round(abs(thirdsOffset)))
                action = .moveRight(percentage: min(percentage, 15))
                reason = "Better composition"
            }
            
            return GuidanceAdvice(
                action: action,
                type: .thirds,
                reason: reason,
                confidence: 0.8,
                cooldownMs: Config.ruleCooldownMs
            )
        }
        
        return nil
    }
    
    private func applyCooldowns(for advice: GuidanceAdvice) {
        let now = Date()
        
        // Type-specific cooldown
        let cooldownEnd = now.addingTimeInterval(TimeInterval(advice.cooldownMs) / 1000.0)
        typeCooldowns[advice.type] = cooldownEnd
        
        // Global guidance cooldown
        lastGuidanceTime = now
        currentState = .hintCooldown(now.addingTimeInterval(TimeInterval(Config.ruleCooldownMs) / 1000.0))
        
        // Track recent prompts for anti-spam
        recentPrompts[advice.type] = now
        
        // Clean up old entries
        let cutoffTime = now.addingTimeInterval(-10.0) // 10 seconds ago
        recentPrompts = recentPrompts.filter { $0.value > cutoffTime }
    }
    
    private func trackGuidanceUsage(_ advice: GuidanceAdvice) {
        guidanceCount += 1
    }
    
    // MARK: - Performance Monitoring
    public var currentPromptsPerMinute: Int {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        let minutes = sessionDuration / 60.0
        return minutes > 0 ? Int(Double(guidanceCount) / minutes) : 0
    }
    
    public var isInPostShutterCooldown: Bool {
        if case .postShutterCooldown = currentState {
            return true
        }
        return false
    }
    
    // MARK: - Smart Cooldown Logic
    private func calculateAdaptiveCooldown(for guidanceType: GuidanceType, currentAngle: Float) -> Int {
        let baseCooldown = Config.ruleCooldownMs
        
        // For horizon guidance, check if user is improving
        if guidanceType == .horizon {
            // If user is within "good enough" range, extend cooldown
            if abs(currentAngle) <= Config.horizonGoodEnoughDegrees {
                return baseCooldown * 3 // 3x longer cooldown when close to target
            }
            
            // If user is making small improvements, give them more time
            if abs(currentAngle) <= Config.horizonThresholdDegrees + 2.0 {
                return baseCooldown * 2 // 2x longer cooldown when improving
            }
        }
        
        return baseCooldown
    }
}
