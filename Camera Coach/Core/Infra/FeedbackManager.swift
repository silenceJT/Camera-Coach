//
//  FeedbackManager.swift
//  Camera Coach
//
//  Strategic feedback collection system - collects metrics silently and 
//  shows feedback at appropriate times to respect user workflow.
//

import Foundation
import UIKit
import Combine
import os.log

// MARK: - Data Models

public struct PhotoCaptureMetrics {
    let timestamp: Date
    let guidanceActive: Bool
    let lastGuidanceType: GuidanceType?
    let timeSinceLastGuidance: TimeInterval
    let deviceOrientation: UIDeviceOrientation
    let thermalState: ProcessInfo.ThermalState
    let sessionDuration: TimeInterval
    let cameraSession: String // Unique session identifier
    
    // Context information for better feedback targeting
    let consecutivePhotos: Int
    let guidanceAdopted: Bool
    let horizonAngleAtCapture: Float
}

public enum FeedbackTrigger: String, CaseIterable {
    case sessionEnd = "session_end"           // User exits camera naturally
    case appBackground = "app_background"     // App goes to background
    case settingsAccess = "settings_access"  // User opens settings
    case photoReview = "photo_review"         // User reviews photos in app
    case guidanceRequest = "guidance_request" // User explicitly asks for help
    case timedReminder = "timed_reminder"     // Background notification
}

// MARK: - FeedbackManager

public final class FeedbackManager: ObservableObject {
    // MARK: - Published Properties
    @Published var shouldShowFeedback = false
    @Published var feedbackTrigger: FeedbackTrigger?
    @Published var pendingFeedbackCount = 0
    
    // MARK: - Private Properties
    private var pendingMetrics: [PhotoCaptureMetrics] = []
    private let logger = Logger.shared
    private let maxPendingMetrics = 50 // Prevent memory issues
    
    // Timing configuration
    private let minPhotosForFeedback = 5
    private let minHoursBetweenFeedback: TimeInterval = 24
    private let maxDaysBeforeFeedback: TimeInterval = 7 * 24 * 3600 // 7 days
    
    // Persistence
    private let lastFeedbackKey = "last_feedback_timestamp"
    private let feedbackCountKey = "total_feedback_count"
    
    // MARK: - Singleton
    public static let shared = FeedbackManager()
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Interface
    
    public func collectPhotoMetrics(_ metrics: PhotoCaptureMetrics) {
        // Store metrics silently without any UI interruption
        pendingMetrics.append(metrics)
        pendingFeedbackCount = pendingMetrics.count
        
        // Prevent memory issues
        if pendingMetrics.count > maxPendingMetrics {
            pendingMetrics.removeFirst(10) // Remove oldest 10
        }
        
        // Log the collection (for analytics)
        logger.logEvent(LogEvent(
            name: "photo_metrics_collected",
            timestamp: metrics.timestamp.timeIntervalSince1970,
            parameters: [
                "session": metrics.cameraSession,
                "guidance_active": metrics.guidanceActive ? "true" : "false",
                "session_duration_s": String(format: "%.1f", metrics.sessionDuration)
            ]
        ))
        
        // Check if we should prepare for feedback
        checkFeedbackEligibility()
    }
    
    public func triggerFeedbackIfReady(_ trigger: FeedbackTrigger) {
        guard shouldShowFeedback else { return }
        
        logger.logEvent(LogEvent(
            name: "feedback_triggered",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "trigger": trigger.rawValue,
                "pending_photos": String(pendingMetrics.count)
            ]
        ))
        
        feedbackTrigger = trigger
    }
    
    public func completeFeedback(helpful: Bool, satisfaction: Int) {
        let completedMetrics = pendingMetrics
        
        // Log aggregated feedback for all pending metrics
        logger.logAggregatedFeedback(
            metrics: completedMetrics,
            helpful: helpful,
            satisfaction: satisfaction,
            trigger: feedbackTrigger?.rawValue ?? "unknown"
        )
        
        // Clear pending metrics
        clearPendingFeedback()
        
        // Update last feedback time
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastFeedbackKey)
        
        // Increment feedback count
        let currentCount = UserDefaults.standard.integer(forKey: feedbackCountKey)
        UserDefaults.standard.set(currentCount + 1, forKey: feedbackCountKey)
        
        // Reset feedback state
        shouldShowFeedback = false
        feedbackTrigger = nil
    }
    
    public func skipFeedback() {
        logger.logEvent(LogEvent(
            name: "feedback_skipped",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "trigger": feedbackTrigger?.rawValue ?? "unknown",
                "pending_photos": String(pendingMetrics.count)
            ]
        ))
        
        clearPendingFeedback()
        shouldShowFeedback = false
        feedbackTrigger = nil
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        triggerFeedbackIfReady(.appBackground)
    }
    
    private func checkFeedbackEligibility() {
        let photoCount = pendingMetrics.count
        let lastFeedbackTime = UserDefaults.standard.double(forKey: lastFeedbackKey)
        let timeSinceLastFeedback = Date().timeIntervalSince1970 - lastFeedbackTime
        
        // Eligibility criteria:
        // 1. Have enough photos to provide meaningful feedback
        // 2. Sufficient time has passed since last feedback
        // 3. Not overwhelming the user with feedback requests
        
        let hasEnoughPhotos = photoCount >= minPhotosForFeedback
        let enoughTimeHasPassed = timeSinceLastFeedback >= (minHoursBetweenFeedback * 3600)
        let hasGuidanceActivity = pendingMetrics.contains { $0.guidanceActive }
        
        // Special case: If it's been a week, show feedback regardless
        let overdue = timeSinceLastFeedback >= maxDaysBeforeFeedback
        
        shouldShowFeedback = (hasEnoughPhotos && enoughTimeHasPassed && hasGuidanceActivity) || overdue
        
        if shouldShowFeedback {
            logger.logEvent(LogEvent(
                name: "feedback_eligible",
                timestamp: Date().timeIntervalSince1970,
                parameters: [
                    "photo_count": String(photoCount),
                    "hours_since_last": String(format: "%.1f", timeSinceLastFeedback / 3600),
                    "has_guidance": hasGuidanceActivity ? "true" : "false"
                ]
            ))
        }
    }
    
    private func clearPendingFeedback() {
        pendingMetrics.removeAll()
        pendingFeedbackCount = 0
    }
    
    // MARK: - Analytics Support
    
    public func getFeedbackAnalytics() -> [String: Any] {
        return [
            "pending_photos": pendingMetrics.count,
            "sessions_with_guidance": pendingMetrics.filter { $0.guidanceActive }.count,
            "average_session_duration": pendingMetrics.map { $0.sessionDuration }.average(),
            "most_common_guidance": getMostCommonGuidanceType(),
            "total_feedback_given": UserDefaults.standard.integer(forKey: feedbackCountKey)
        ]
    }
    
    private func getMostCommonGuidanceType() -> String {
        let guidanceTypes = pendingMetrics.compactMap { $0.lastGuidanceType?.rawValue }
        let counts = Dictionary(grouping: guidanceTypes, by: { $0 })
        return counts.max(by: { $0.value.count < $1.value.count })?.key ?? "none"
    }
}

// MARK: - Extensions

extension Array where Element == TimeInterval {
    func average() -> TimeInterval {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / TimeInterval(count)
    }
}

// MARK: - Logger Extension

extension Logger {
    func logAggregatedFeedback(metrics: [PhotoCaptureMetrics], helpful: Bool, satisfaction: Int, trigger: String) {
        let event = LogEvent(
            name: "aggregated_feedback",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "helpful": helpful ? "true" : "false",
                "satisfaction": String(satisfaction),
                "trigger": trigger,
                "photo_count": String(metrics.count),
                "sessions_analyzed": String(Set(metrics.map { $0.cameraSession }).count),
                "guidance_sessions": String(metrics.filter { $0.guidanceActive }.count),
                "avg_session_duration": String(format: "%.1f", metrics.map { $0.sessionDuration }.average())
            ]
        )
        
        self.logEvent(event)
        let osLog = OSLog(subsystem: "com.silencejt.cameracoach", category: "feedback")
        os_log(.info, log: osLog, "Aggregated feedback - Helpful: %{public}@, Satisfaction: %d, Photos: %d", 
               helpful ? "true" : "false", satisfaction, metrics.count)
    }
}