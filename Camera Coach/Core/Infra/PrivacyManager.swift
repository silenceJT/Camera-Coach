//
//  PrivacyManager.swift
//  Camera Coach
//
//  Privacy and consent management for face detection and data handling.
//  Handles user consent, data controls, and privacy disclosures.
//

import Foundation
import Combine

public final class PrivacyManager: ObservableObject {
    public static let shared = PrivacyManager()

    // MARK: - Published Properties
    @Published public var faceDetectionConsent: Bool {
        didSet {
            UserDefaults.standard.set(faceDetectionConsent, forKey: "faceDetectionConsent")
            Logger.shared.logConsentChanged(faceDetection: faceDetectionConsent)
        }
    }

    @Published public var postShotCloudConsent: Bool {
        didSet {
            UserDefaults.standard.set(postShotCloudConsent, forKey: "postShotCloudConsent")
            Logger.shared.logConsentChanged(postShotCloud: postShotCloudConsent)
        }
    }

    @Published public var analyticsConsent: Bool {
        didSet {
            UserDefaults.standard.set(analyticsConsent, forKey: "analyticsConsent")
            Logger.shared.logConsentChanged(analytics: analyticsConsent)
        }
    }

    // MARK: - Private Properties
    private let logger = Logger.shared

    // MARK: - Initialization
    private init() {
        // Load consent states from UserDefaults
        self.faceDetectionConsent = UserDefaults.standard.object(forKey: "faceDetectionConsent") as? Bool ?? true
        self.postShotCloudConsent = UserDefaults.standard.object(forKey: "postShotCloudConsent") as? Bool ?? false
        self.analyticsConsent = UserDefaults.standard.object(forKey: "analyticsConsent") as? Bool ?? true
    }

    // MARK: - Public Methods

    /// Check if face detection is allowed
    public var canUseFaceDetection: Bool {
        return faceDetectionConsent
    }

    /// Check if cloud features are allowed
    public var canUseCloudFeatures: Bool {
        return postShotCloudConsent
    }

    /// Check if analytics are allowed
    public var canCollectAnalytics: Bool {
        return analyticsConsent
    }

    /// Reset all consent to default values
    public func resetAllConsent() {
        faceDetectionConsent = true
        postShotCloudConsent = false
        analyticsConsent = true
        logger.logConsentChanged(allReset: true)
    }

    /// Delete all cached data
    public func deleteAllData() {
        // Clear any cached face detection data
        clearFaceDetectionCache()

        // Clear feedback data
        FeedbackManager.shared.clearAllData()

        // Clear logs if requested
        logger.clearLogs()

        logger.logDataDeletion(type: "all")
    }

    /// Clear face detection related cache
    public func clearFaceDetectionCache() {
        // Clear any temporary face detection data
        // (Currently we don't store face data, but this is for future use)
        logger.logDataDeletion(type: "faceDetection")
    }

    /// Show privacy disclosure for first-time users
    public func showPrivacyDisclosureIfNeeded() -> Bool {
        let hasShownDisclosure = UserDefaults.standard.bool(forKey: "hasShownPrivacyDisclosure")
        if !hasShownDisclosure {
            UserDefaults.standard.set(true, forKey: "hasShownPrivacyDisclosure")
            return true
        }
        return false
    }

    /// Get privacy policy text for face detection
    public var faceDetectionPrivacyText: String {
        return NSLocalizedString("privacy.face_detection.description", comment: "Face detection privacy description")
    }

    /// Get data handling policy text
    public var dataHandlingPolicyText: String {
        return NSLocalizedString("privacy.data_handling.description", comment: "Data handling policy description")
    }
}

// MARK: - Extensions for Logger Integration
extension Logger {
    func logConsentChanged(faceDetection: Bool? = nil, postShotCloud: Bool? = nil, analytics: Bool? = nil, allReset: Bool = false) {
        var parameters: [String: String] = [:]

        if let faceDetection = faceDetection {
            parameters["face_detection_consent"] = faceDetection ? "true" : "false"
        }

        if let postShotCloud = postShotCloud {
            parameters["post_shot_cloud_consent"] = postShotCloud ? "true" : "false"
        }

        if let analytics = analytics {
            parameters["analytics_consent"] = analytics ? "true" : "false"
        }

        if allReset {
            parameters["all_reset"] = "true"
        }

        let event = LogEvent(
            name: "consent_changed",
            timestamp: Date().timeIntervalSince1970,
            parameters: parameters
        )
        logEvent(event)
    }

    func logDataDeletion(type: String) {
        let event = LogEvent(
            name: "data_deletion",
            timestamp: Date().timeIntervalSince1970,
            parameters: ["type": type]
        )
        logEvent(event)
    }
}