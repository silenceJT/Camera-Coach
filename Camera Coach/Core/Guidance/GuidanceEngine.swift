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

    // MARK: - Template System (NEW)
    private let templateEngine: TemplateEngine
    public var currentTemplate: Template? {
        didSet {
            if currentTemplate?.id != oldValue?.id {
                print("🎯 GuidanceEngine current template changed: \(currentTemplate?.id ?? "nil")")
            }
        }
    }
    
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
    
    // MARK: - Hint Adoption Tracking
    private var activeHint: ActiveHint?
    private var hintCheckTimer: Timer?
    
    // MARK: - Initialization
    public init(provider: FrameFeaturesProvider, templateEngine: TemplateEngine = TemplateEngine.shared) {
        self.provider = provider
        self.templateEngine = templateEngine
        startSession()
    }
    
    deinit {
        hintCheckTimer?.invalidate()
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
            // Extract metrics before applying guidance
            let beforeMetrics = extractMetricsFromFeatures(features)
            
            // Apply cooldowns and track usage
            applyCooldowns(for: advice)
            trackGuidanceUsage(advice)
            
            // Start hint adoption tracking
            startHintTracking(for: advice, beforeMetrics: beforeMetrics)
            
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
    

    
    // MARK: - Hint Adoption Tracking
    private func startHintTracking(for advice: GuidanceAdvice, beforeMetrics: [String: String]) {
        // Cancel any existing timer
        hintCheckTimer?.invalidate()
        
        // Create new active hint
        activeHint = ActiveHint(
            advice: advice,
            startTime: Date(),
            beforeMetrics: beforeMetrics
        )
        
        // Set timer to check adoption after 10 seconds
        hintCheckTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(Config.hintAdoptionWindowMs / 1000), repeats: false) { [weak self] _ in
            self?.checkHintAdoption()
        }
    }
    
    private func checkHintAdoption() {
        guard let hint = activeHint,
              let currentFeatures = currentFrameFeatures else {
            return
        }
        
        let afterMetrics = extractMetricsFromFeatures(currentFeatures)
        let adopted = evaluateHintAdoption(hint: hint, afterMetrics: afterMetrics)
        let latencyMs = Int(Date().timeIntervalSince(hint.startTime) * 1000)
        
        // Log the adoption result
        Logger.shared.logHintAdopted(
            type: hint.advice.type.rawValue,
            adopted: adopted,
            latencyMs: latencyMs,
            before: hint.beforeMetrics,
            after: afterMetrics
        )
        
        // Clear active hint and invalidate timer to allow new guidance
        activeHint = nil
        hintCheckTimer?.invalidate()
        hintCheckTimer = nil
    }
    
    private func extractMetricsFromFeatures(_ features: FrameFeatures) -> [String: String] {
        var metrics: [String: String] = [:]

        metrics["horizon_degrees"] = String(format: "%.1f", features.horizonDegrees)
        metrics["horizon_stable"] = String(features.hasStableHorizon)
        metrics["horizon_level"] = String(features.isHorizonLevel)

        if let headroom = features.headroomPercentage {
            metrics["headroom_percent"] = String(format: "%.1f", headroom)
        }

        if let thirdsOffset = features.thirdsOffsetPercentage {
            metrics["thirds_offset"] = String(format: "%.1f", thirdsOffset)
        }

        // 🚀 WEEK 7: Face orientation & lead space metrics
        if let orientation = features.faceOrientation {
            metrics["face_orientation"] = orientation.description
            metrics["orientation_confidence"] = String(format: "%.2f", features.orientationConfidence)
        }

        if let leadSpace = features.leadSpacePercentage {
            metrics["lead_space_percent"] = String(format: "%.1f", leadSpace)
        }

        // 🚀 WEEK 7: Edge density metrics
        if let leftEdge = features.leftEdgeDensity {
            metrics["left_edge_density"] = String(format: "%.2f", leftEdge)
        }

        if let rightEdge = features.rightEdgeDensity {
            metrics["right_edge_density"] = String(format: "%.2f", rightEdge)
        }

        metrics["has_edge_conflict"] = String(features.hasEdgeConflict)

        // 🚀 NEW: Template-related metrics
        metrics["has_active_template"] = String(features.hasActiveTemplate)
        metrics["template_aligned"] = String(features.isTemplateAligned)
        metrics["template_id"] = features.currentTemplate?.id ?? "none"

        if let alignment = features.templateAlignment {
            metrics["template_offset_x"] = String(format: "%.3f", alignment.offsetX)
            metrics["template_offset_y"] = String(format: "%.3f", alignment.offsetY)
            metrics["template_distance"] = String(format: "%.3f", alignment.distance)
            metrics["template_confidence"] = String(format: "%.2f", alignment.confidence)
        }

        metrics["face_count"] = String(features.faceCount)
        metrics["fps"] = String(format: "%.1f", features.currentFPS)

        return metrics
    }
    
    private func evaluateHintAdoption(hint: ActiveHint, afterMetrics: [String: String]) -> Bool {
        switch hint.advice.type {
        case .templateAlignment:
            return evaluateTemplateAlignmentAdoption(hint: hint, afterMetrics: afterMetrics)
        case .headroom:
            return evaluateHeadroomAdoption(hint: hint, afterMetrics: afterMetrics)
        case .thirds:
            return evaluateThirdsAdoption(hint: hint, afterMetrics: afterMetrics)
        case .leadspace:
            return evaluateLeadSpaceAdoption(hint: hint, afterMetrics: afterMetrics)
        }
    }
    
    // 🚀 NEW: Template Alignment Adoption Evaluation
    private func evaluateTemplateAlignmentAdoption(hint: ActiveHint, afterMetrics: [String: String]) -> Bool {
        guard let template = hint.advice.relatedTemplate,
              let currentFeatures = currentFrameFeatures else {
            return false
        }

        // Calculate alignment improvement
        let currentAlignment = templateEngine.calculateAlignment(faces: currentFeatures.allFaceRects, template: template)

        // Adoption criteria:
        // 1. Now within acceptable threshold
        // 2. Significant improvement in alignment distance
        // 3. Movement in correct direction

        if currentAlignment.withinThreshold {
            print("🎯 Template alignment adopted: now within threshold")
            return true
        }

        // Extract previous alignment data if available (simplified check for now)
        if currentAlignment.confidence > 0.8 && currentAlignment.distance < Config.goodAlignmentThreshold {
            print("🎯 Template alignment adopted: significant improvement")
            return true
        }

        return false
    }

    // Horizon adoption evaluation removed - no longer needed

    // 🚀 WEEK 3: Headroom Adoption Tracking Implementation
    private func evaluateHeadroomAdoption(hint: ActiveHint, afterMetrics: [String: String]) -> Bool {
        guard let beforeHeadroomStr = hint.beforeMetrics["headroom_percent"],
              let afterHeadroomStr = afterMetrics["headroom_percent"],
              let beforeHeadroom = Float(beforeHeadroomStr),
              let afterHeadroom = Float(afterHeadroomStr) else {
            // No valid headroom data available
            return false
        }
        
        let targetRange = Config.targetHeadroomPercentage
        let targetCenter = (targetRange.upperBound + targetRange.lowerBound) / 2.0
        
        // Calculate distances from target before and after
        let beforeDistance = abs(beforeHeadroom - targetCenter)
        let afterDistance = abs(afterHeadroom - targetCenter)
        
        // Adoption criteria:
        // 1. Movement towards target (distance reduced)
        // 2. Significant improvement (≥1% headroom improvement)
        // 3. Now within acceptable range or much closer
        
        let distanceImprovement = beforeDistance - afterDistance
        let improvementThreshold: Float = 1.0 // 1% headroom improvement required
        
        // Check if headroom improved significantly
        if distanceImprovement >= improvementThreshold {
            return true
        }
        
        // Check if now within target range (even with small improvement)
        if targetRange.contains(afterHeadroom) && !targetRange.contains(beforeHeadroom) {
            return true
        }
        
        // Check for substantial movement in correct direction (≥50% improvement)
        if distanceImprovement > 0 && (distanceImprovement / beforeDistance) >= 0.5 {
            return true
        }
        
        return false
    }
    
    private func evaluateThirdsAdoption(hint: ActiveHint, afterMetrics: [String: String]) -> Bool {
        // TODO: Implement thirds adoption tracking
        return false
    }

    // 🚀 WEEK 7: Lead Space Adoption Evaluation
    private func evaluateLeadSpaceAdoption(hint: ActiveHint, afterMetrics: [String: String]) -> Bool {
        guard let currentFeatures = currentFrameFeatures,
              let leadSpace = currentFeatures.leadSpacePercentage,
              let orientation = currentFeatures.faceOrientation else {
            return false
        }

        // Extract before metrics
        let beforeLeadSpaceStr = hint.beforeMetrics["lead_space_percent"]
        let beforeOrientation = hint.beforeMetrics["face_orientation"]

        // Calculate improvement
        let targetCenter = (Config.leadSpaceTargetPercentage.upperBound + Config.leadSpaceTargetPercentage.lowerBound) / 2.0

        // Check if orientation is still the same (subject hasn't turned)
        guard beforeOrientation == orientation.description else {
            // Orientation changed - can't evaluate properly
            return false
        }

        if let beforeLeadSpaceStr = beforeLeadSpaceStr,
           let beforeLeadSpace = Float(beforeLeadSpaceStr) {
            // Calculate distances from target
            let beforeDistance = abs(beforeLeadSpace - targetCenter)
            let afterDistance = abs(leadSpace - targetCenter)

            // Adoption criteria:
            // 1. Movement towards target (distance reduced)
            // 2. Significant improvement (≥5% lead space improvement)
            // 3. Now within target range

            let distanceImprovement = beforeDistance - afterDistance
            let improvementThreshold: Float = 5.0 // 5% lead space improvement

            // Check if lead space improved significantly
            if distanceImprovement >= improvementThreshold {
                print("✅ Lead space adopted: improvement=\(distanceImprovement)%")
                return true
            }

            // Check if now within target range (even with small improvement)
            if Config.leadSpaceTargetPercentage.contains(leadSpace) && !Config.leadSpaceTargetPercentage.contains(beforeLeadSpace) {
                print("✅ Lead space adopted: now in target range")
                return true
            }

            // Check for substantial movement in correct direction (≥50% improvement)
            if distanceImprovement > 0 && (distanceImprovement / beforeDistance) >= 0.5 {
                print("✅ Lead space adopted: 50%+ improvement")
                return true
            }
        }

        return false
    }

    // MARK: - Private Methods
    private func startSession() {
        sessionStartTime = Date()
        lastGuidanceTime = Date() // Initialize to current time so first guidance can be generated
        guidanceCount = 0
        typeCooldowns.removeAll()
        recentPrompts.removeAll()
        
        // Clean up any existing hint tracking
        hintCheckTimer?.invalidate()
        activeHint = nil
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
        
        // Allow more guidance in the first few minutes for immediate feedback and testing
        let maxPromptsInSession: Int
        if sessionMinutes < 1.0 {
            // First minute: allow up to 10 prompts (more responsive initial feedback)
            maxPromptsInSession = 10
        } else if sessionMinutes < 2.0 {
            // Second minute: allow up to 15 prompts
            maxPromptsInSession = 15
        } else if sessionMinutes < 3.0 {
            // Third minute: allow up to 20 prompts
            maxPromptsInSession = 20
        } else {
            // After 3 minutes: use the configured rate
            maxPromptsInSession = Int(sessionMinutes * Double(Config.maxPromptsPerMinute))
        }
        
        if guidanceCount >= maxPromptsInSession {
            return false
        }
        
        return true
    }
    
    private func analyzeFrameAndGenerateGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        // 🚀 WEEK 7 PRIORITY ORDER: Template > Headroom > Lead Space > Thirds
        // Lead space guidance added between headroom and thirds per Week 7 spec

        print("🔍 GUIDANCE CHECK: hasActiveTemplate=\(features.hasActiveTemplate), needsTemplateAlignment=\(features.needsTemplateAlignment)")

        // 1. Template alignment guidance (HIGHEST PRIORITY)
        if let templateAdvice = generateTemplateAlignmentGuidance(features) {
            print("✅ Returning TEMPLATE alignment guidance")
            return templateAdvice
        }

        // 2. Headroom guidance (only if no template alignment needed)
        if !features.needsTemplateAlignment {
            print("🔍 No template alignment needed, checking headroom...")
            if let headroomAdvice = generateHeadroomGuidance(features) {
                return headroomAdvice
            }
        } else {
            print("⏸️ Skipping headroom - template alignment needed (distance: \(features.templateAlignment?.distance ?? 0))")
        }

        // 3. Lead space guidance (Week 7 - only if headroom is good and no template issues)
        if features.isHeadroomInTarget && !features.needsTemplateAlignment {
            if let leadSpaceAdvice = generateLeadSpaceGuidance(features) {
                print("✅ Returning LEAD SPACE guidance")
                return leadSpaceAdvice
            }
        }

        // 4. Rule of thirds (only if headroom is good, no template issues, and lead space is adequate)
        if features.isHeadroomInTarget && !features.needsTemplateAlignment {
            if let thirdsAdvice = generateThirdsGuidance(features) {
                return thirdsAdvice
            }
        }

        // 🚀 WEEK 7: Check for PERFECT composition (all rules satisfied)
        if isPerfectComposition(features) {
            print("✨ PERFECT COMPOSITION DETECTED!")
            return createPerfectCompositionAdvice()
        }

        // Clear currentGuidance when no new guidance is generated
        // This prevents the guidance engine from staying "stuck" with old guidance
        // after the user corrects their position
        if currentGuidance != nil {
            currentGuidance = nil
        }

        return nil
    }

    // MARK: - Perfect Composition Detection (Week 7)

    /// Check if current composition is perfect (all rules satisfied)
    private func isPerfectComposition(_ features: FrameFeatures) -> Bool {
        // Must have a stable face
        guard features.hasStableFace else { return false }

        // Headroom must be in target range
        guard features.isHeadroomInTarget else { return false }

        // If there's an active template, alignment must be perfect
        if features.hasActiveTemplate {
            guard let alignment = features.templateAlignment,
                  alignment.distance < Config.perfectAlignmentThreshold else {
                return false
            }
        }

        // Lead space must be adequate (if facing direction detected)
        if features.hasFacingDirection,
           let leadSpace = features.leadSpacePercentage {
            let targetRange = Config.leadSpaceTargetPercentage
            let tolerance = Config.leadSpaceTolerancePercentage
            let expandedMin = targetRange.lowerBound - tolerance
            let expandedMax = targetRange.upperBound + tolerance

            guard leadSpace >= expandedMin && leadSpace <= expandedMax else {
                return false
            }
        }

        // Rule of thirds must be satisfied (face centered or on thirds line)
        if let offset = features.thirdsOffsetPercentage {
            let tolerance = Config.thirdsTolerancePercentage
            let isCentered = abs(offset) < tolerance
            let isOnThirdsLine = abs(abs(offset) - 33.33) < tolerance

            guard isCentered || isOnThirdsLine else {
                return false
            }
        }

        // All checks passed - composition is perfect!
        return true
    }

    /// Create perfect composition advice
    private func createPerfectCompositionAdvice() -> GuidanceAdvice {
        return GuidanceAdvice(
            action: .perfect,
            type: .headroom,  // Use headroom type for logging
            reason: NSLocalizedString("guidance.ready_to_shoot", comment: "Tap to shoot"),
            confidence: 0.95,  // High confidence for perfect state
            cooldownMs: 0,  // No cooldown - persist while perfect
            ruleVersion: "1.0"
        )
    }
    
    // 🚀 MULTI-FACE ENHANCEMENT: Adaptive Headroom Guidance
    private func generateHeadroomGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        // Only provide guidance if we have a stable, valid face
        guard features.hasStableFace else {
            print("⏱️ Face not stable yet (stableMs: \(features.faceStableMs)ms, needs: \(Config.faceStabilityThresholdMs)ms)")
            return nil
        }

        print("✅ Face STABLE for \(features.faceStableMs)ms - checking headroom guidance...")

        // 🚀 NEW: Multi-face adaptive strategy
        let (headroom, strategy) = selectHeadroomStrategy(features)
        
        guard let selectedHeadroom = headroom else {
            print("❌ No headroom value available")
            return nil
        }

        print("📊 Headroom: \(selectedHeadroom)%, strategy: \(strategy)")

        // Skip guidance if primary face is too small (likely false positive)
        if let faceSize = features.faceSizePercentage {
            guard faceSize >= Config.minFaceSizePercentage else {
                print("❌ Face too small: \(faceSize)% < \(Config.minFaceSizePercentage)%")
                return nil
            }
        }

        // Check type-specific cooldown to prevent spamming headroom guidance
        if let lastTime = typeCooldowns[.headroom],
           Date().timeIntervalSince(lastTime) < Double(Config.ruleCooldownMs) / 1000.0 {
            let remaining = Int(Double(Config.ruleCooldownMs) / 1000.0 - Date().timeIntervalSince(lastTime))
            print("⏳ Headroom cooldown active: \(remaining)s remaining")
            return nil
        }
        
        // 🎯 CRITICAL FIX: Use context-aware headroom target based on vertical position
        let targetRange: ClosedRange<Float>
        let verticalZone: String

        if let verticalPos = features.faceVerticalPosition {
            if verticalPos >= 66 {
                // Upper third: Face is high in frame (66-100% height)
                targetRange = Config.upperThirdsHeadroomRange  // 0-8%
                verticalZone = "upper-third"
            } else if verticalPos >= 33 {
                // Middle third: Face is centered (33-66% height)
                targetRange = Config.centeredHeadroomRange  // 7-12%
                verticalZone = "centered"
            } else {
                // Lower third: Face is low in frame (0-33% height)
                targetRange = Config.lowerThirdsHeadroomRange  // 15-25%
                verticalZone = "lower-third"
            }
            print("📍 Face vertical position: \(String(format: "%.1f", verticalPos))% → Zone: \(verticalZone), Target range: \(targetRange)")
        } else {
            // Fallback to centered range if no vertical position available
            targetRange = Config.centeredHeadroomRange
            verticalZone = "unknown (fallback)"
        }

        // Check if headroom is within target range first
        if targetRange.contains(selectedHeadroom) {
            print("✅ Headroom IN range: headroom=\(selectedHeadroom)%, target=\(targetRange), zone=\(verticalZone)")
            return nil
        }

        // Calculate how far we are OUTSIDE the target range
        let difference: Float
        if selectedHeadroom < targetRange.lowerBound {
            // Too little headroom - difference is distance below lower bound
            difference = targetRange.lowerBound - selectedHeadroom
        } else {
            // Too much headroom - difference is distance above upper bound
            difference = selectedHeadroom - targetRange.upperBound
        }

        // Apply tolerance - only trigger if significantly outside range
        guard difference > Config.headroomTolerancePercentage else {
            print("📏 Headroom outside range but within tolerance: headroom=\(selectedHeadroom)%, target=\(targetRange), diff=\(difference)%, tolerance=\(Config.headroomTolerancePercentage)%")
            return nil
        }

        print("⚠️ Headroom OUT of range: headroom=\(selectedHeadroom)%, target=\(targetRange), diff=\(difference)%, zone=\(verticalZone)")
        
        // Determine action and confidence based on how far off we are
        let action: GuidanceAction
        let reason: String
        let confidence: Float

        if selectedHeadroom < targetRange.lowerBound {
            // Not enough headroom - face(s) too low in frame, need to move camera UP
            let adjustmentAmount = naturalLanguageAmount(for: difference)
            action = .moveUp(amount: adjustmentAmount)

            // Adaptive reason based on strategy
            switch strategy {
            case .groupHeadroom:
                reason = NSLocalizedString("guidance.reason.group_headroom", comment: "Better headroom for group")
            case .primarySubject:
                reason = NSLocalizedString("guidance.reason.better_headroom", comment: "Better headroom")
            }

            // Higher confidence for larger adjustments needed
            var baseConfidence = 0.7 + Float(difference) / 10.0
            // Apply group headroom confidence boost if using group strategy
            if case .groupHeadroom = strategy {
                baseConfidence += Config.groupHeadroomConfidenceBoost
            }
            confidence = min(0.95, baseConfidence)
        } else {
            // Too much headroom - face(s) too high in frame, need to move camera DOWN
            let adjustmentAmount = naturalLanguageAmount(for: difference)
            action = .moveDown(amount: adjustmentAmount)
            
            // Adaptive reason based on strategy
            switch strategy {
            case .groupHeadroom:
                reason = NSLocalizedString("guidance.reason.group_framing", comment: "Better framing for group")
            case .primarySubject:
                reason = NSLocalizedString("guidance.reason.better_framing", comment: "Better framing")
            }

            // Slightly lower confidence for "too much headroom" cases
            var baseConfidence = 0.65 + Float(difference) / 12.0
            // Apply group headroom confidence boost if using group strategy
            if case .groupHeadroom = strategy {
                baseConfidence += Config.groupHeadroomConfidenceBoost
            }
            confidence = min(0.9, baseConfidence)
        }
        
        // 🚀 DEBUG: Log multi-face headroom guidance
        print("🎯 HEADROOM GUIDANCE (\(strategy)): \(reason) - \(action) (confidence: \(String(format: "%.2f", confidence)))")
        
        return GuidanceAdvice(
            action: action,
            type: .headroom,
            reason: reason,
            confidence: confidence,
            cooldownMs: Config.ruleCooldownMs,
            ruleVersion: "v4.0" // Multi-face enhanced headroom guidance
        )
    }
    
    // 🚀 NEW: Smart headroom strategy selection for multi-face scenarios
    private func selectHeadroomStrategy(_ features: FrameFeatures) -> (headroom: Float?, strategy: HeadroomStrategy) {
        // Check if group headroom guidance is enabled
        guard Config.enableGroupHeadroomGuidance else {
            return (features.headroomPercentage, .primarySubject)
        }
        
        // If no group headroom data, fall back to legacy behavior
        guard let groupHeadroom = features.groupHeadroomPercentage else {
            return (features.headroomPercentage, .primarySubject)
        }
        
        // Use configuration threshold to determine strategy
        if features.faceCount >= Config.groupHeadroomThreshold {
            // Multiple faces: use group headroom strategy
            // This ensures adequate space above ALL visible faces
            return (groupHeadroom, .groupHeadroom)
        } else {
            // Single face or below threshold: use primary subject headroom
            return (features.headroomPercentage, .primarySubject)
        }
    }
    
    // Supporting enum for strategy tracking
    private enum HeadroomStrategy: CustomStringConvertible {
        case primarySubject
        case groupHeadroom
        
        var description: String {
            switch self {
            case .primarySubject: return "Primary Subject"
            case .groupHeadroom: return "Group Headroom"
            }
        }
    }
    
    // Horizon guidance removed - users handle camera leveling by common sense
    
    // 🚀 WEEK 7: Lead Space Guidance
    private func generateLeadSpaceGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        // Only provide guidance if we have orientation detection
        guard features.hasFacingDirection,
              let orientation = features.faceOrientation,
              let leadSpace = features.leadSpacePercentage,
              features.hasStableFace else {
            return nil
        }

        // Check type-specific cooldown
        if let lastTime = typeCooldowns[.leadspace],
           Date().timeIntervalSince(lastTime) < Double(Config.leadSpaceCooldownMs) / 1000.0 {
            return nil
        }

        // Calculate target lead space center
        let targetCenter = (Config.leadSpaceTargetPercentage.upperBound + Config.leadSpaceTargetPercentage.lowerBound) / 2.0
        let difference = targetCenter - leadSpace

        // Only provide guidance if significantly outside target range
        guard abs(difference) > Config.leadSpaceTolerancePercentage else {
            return nil
        }

        // Determine action based on facing direction and current lead space
        let action: GuidanceAction
        let reason: String
        let confidence: Float

        switch orientation {
        case .left:
            // Facing left - needs more space on left side
            if difference > 0 {
                // Need more lead space - move right to add space on left
                action = .moveRight(amount: naturalLanguageAmount(for: abs(difference)))
                reason = NSLocalizedString("guidance.reason.lead_space", comment: "Room ahead")
                confidence = 0.75 + min(0.15, Float(abs(difference)) / 100.0)
            } else {
                // Too much lead space - move left to reduce space
                action = .moveLeft(amount: naturalLanguageAmount(for: abs(difference)))
                reason = NSLocalizedString("guidance.reason.center_subject", comment: "Center subject")
                confidence = 0.7 + min(0.15, Float(abs(difference)) / 100.0)
            }

        case .right:
            // Facing right - needs more space on right side
            if difference > 0 {
                // Need more lead space - move left to add space on right
                action = .moveLeft(amount: naturalLanguageAmount(for: abs(difference)))
                reason = NSLocalizedString("guidance.reason.lead_space", comment: "Room ahead")
                confidence = 0.75 + min(0.15, Float(abs(difference)) / 100.0)
            } else {
                // Too much lead space - move right to reduce space
                action = .moveRight(amount: naturalLanguageAmount(for: abs(difference)))
                reason = NSLocalizedString("guidance.reason.center_subject", comment: "Center subject")
                confidence = 0.7 + min(0.15, Float(abs(difference)) / 100.0)
            }

        case .center:
            // Face is centered - no lead space guidance needed
            return nil
        }

        // Boost confidence based on orientation confidence
        let finalConfidence = min(0.95, confidence * features.orientationConfidence)

        print("🎯 LEAD SPACE GUIDANCE: \(orientation.description), leadSpace=\(leadSpace)%, target=\(targetCenter)%, diff=\(difference)%")

        return GuidanceAdvice(
            action: action,
            type: .leadspace,
            reason: reason,
            confidence: finalConfidence,
            cooldownMs: Config.leadSpaceCooldownMs,
            ruleVersion: "leadspace_v1.0"
        )
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
                let adjustmentAmount = naturalLanguageAmount(for: abs(thirdsOffset))
                action = .moveLeft(amount: adjustmentAmount)
                reason = "Better composition"
            } else {
                // Subject is too far left - move right
                let adjustmentAmount = naturalLanguageAmount(for: abs(thirdsOffset))
                action = .moveRight(amount: adjustmentAmount)
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

    // 🚀 NEW: Template Alignment Guidance (HIGHEST PRIORITY)
    private func generateTemplateAlignmentGuidance(_ features: FrameFeatures) -> GuidanceAdvice? {
        // Only provide guidance if we have an active template and face detection
        guard let template = currentTemplate ?? features.currentTemplate,
              features.hasStableFace,
              !features.allFaceRects.isEmpty else { return nil }

        // Check template-specific cooldown
        if let lastTime = typeCooldowns[.templateAlignment],
           Date().timeIntervalSince(lastTime) < Double(Config.templateAlignmentCooldownMs) / 1000.0 {
            return nil
        }

        // Calculate alignment using template engine
        let alignment = templateEngine.calculateAlignment(faces: features.allFaceRects, template: template)

        // Only provide guidance if alignment is not within threshold
        guard !alignment.withinThreshold else { return nil }

        let action: GuidanceAction
        let reason: String
        let confidence: Float

        if alignment.distance > Config.goodAlignmentThreshold {
            // Significant misalignment - provide specific directional guidance
            action = .alignToTemplate(offsetX: alignment.offsetX, offsetY: alignment.offsetY)
            reason = NSLocalizedString("guidance.reason.template_alignment", comment: "Match the silhouette")
            confidence = 0.9 + Config.templateConfidenceBoost
        } else {
            // Minor adjustment needed
            let direction = determineAlignmentDirection(alignment)
            let amount = determineAlignmentAmount(alignment)
            action = .adjustForTemplate(direction: direction, amount: amount)
            reason = NSLocalizedString("guidance.reason.fine_alignment", comment: "Fine-tune position")
            confidence = 0.7 + Config.templateConfidenceBoost
        }

        print("🎯 TEMPLATE ALIGNMENT GUIDANCE: \(reason) - \(action) (confidence: \(String(format: "%.2f", confidence)))")

        return GuidanceAdvice(
            action: action,
            type: .templateAlignment,
            reason: reason,
            confidence: min(0.95, confidence),
            cooldownMs: Config.templateAlignmentCooldownMs,
            relatedTemplate: template,
            ruleVersion: "template_v1.0"
        )
    }

    private func determineAlignmentDirection(_ alignment: TemplateAlignment) -> String {
        let absOffsetX = abs(alignment.offsetX)
        let absOffsetY = abs(alignment.offsetY)

        if absOffsetY > absOffsetX {
            return alignment.offsetY > 0 ? NSLocalizedString("guidance.direction.down", comment: "down") :
                                         NSLocalizedString("guidance.direction.up", comment: "up")
        } else {
            return alignment.offsetX > 0 ? NSLocalizedString("guidance.direction.right", comment: "right") :
                                         NSLocalizedString("guidance.direction.left", comment: "left")
        }
    }

    private func determineAlignmentAmount(_ alignment: TemplateAlignment) -> String {
        let distance = alignment.distance

        if distance <= 0.02 {
            return NSLocalizedString("guidance.amount.tiny", comment: "slightly")
        } else if distance <= 0.05 {
            return NSLocalizedString("guidance.amount.little", comment: "a little")
        } else if distance <= 0.1 {
            return NSLocalizedString("guidance.amount.bit", comment: "a bit")
        } else {
            return NSLocalizedString("guidance.amount.lot", comment: "more")
        }
    }

    // MARK: - Template Management
    public func setCurrentTemplate(_ template: Template?) {
        currentTemplate = template
        templateEngine.setCurrentTemplate(template)

        if let template = template {
            print("🎯 GuidanceEngine template set: \(template.id)")
        } else {
            print("🎯 GuidanceEngine template cleared")
        }
    }

    public func recommendTemplate(for features: FrameFeatures) -> Template? {
        let orientation: CameraOrientation = features.currentTemplate?.orientation ?? .portrait
        let faceSize: TemplateCategory? = estimateTemplateCategoryFromFeatures(features)

        return templateEngine.recommendTemplate(
            faceCount: features.faceCount,
            orientation: orientation,
            faceSize: faceSize
        )
    }

    private func estimateTemplateCategoryFromFeatures(_ features: FrameFeatures) -> TemplateCategory? {
        guard let faceSize = features.faceSizePercentage else { return nil }

        // Estimate template category based on face size in frame
        if faceSize >= 15.0 {
            return .close_up
        } else if faceSize >= 8.0 {
            return .half_body
        } else {
            return .full_body
        }
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
        
        // Horizon-specific logic removed
        
        return baseCooldown
    }

    // MARK: - Natural Language Helper
    private func naturalLanguageAmount(for difference: Float) -> String {
        // Convert percentage difference to natural language
        // Based on typical headroom adjustments needed

        if difference <= 2.0 {
            return NSLocalizedString("guidance.amount.tiny", comment: "Very small adjustment")
        } else if difference <= 5.0 {
            return NSLocalizedString("guidance.amount.little", comment: "Small adjustment")
        } else if difference <= 8.0 {
            return NSLocalizedString("guidance.amount.bit", comment: "Moderate adjustment")
        } else if difference <= 12.0 {
            return NSLocalizedString("guidance.amount.lot", comment: "Large adjustment")
        } else {
            return NSLocalizedString("guidance.amount.much", comment: "Very large adjustment")
        }
    }
}

// MARK: - Supporting Data Structures
private struct ActiveHint {
    let advice: GuidanceAdvice
    let startTime: Date
    let beforeMetrics: [String: String]
}
