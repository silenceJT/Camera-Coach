//
//  Logger.swift
//  Camera Coach
//
//  Central logging and telemetry system.
//  Handles MetricKit integration and custom event logging.
//

import Foundation
import MetricKit
import os.log

public final class Logger: ObservableObject {
    // MARK: - Singleton
    public static let shared = Logger()
    
    // MARK: - Properties
    private let osLog = OSLog(subsystem: "com.silencejt.cameracoach", category: "app")
    private let queue = DispatchQueue(label: "com.silencejt.cameracoach.logger", qos: .utility)
    
    // MARK: - Session Data
    private var sessionStartTime: TimeInterval = 0
    private var sessionEvents: [LogEvent] = []
    private var performanceMetrics: [PerformanceMetric] = []
    
    // MARK: - Initialization
    private init() {
        setupMetricKit()
    }
    
    // MARK: - MetricKit Setup
    private func setupMetricKit() {
        // MetricKit will automatically collect system metrics
        // We'll add our custom metrics to the payload
    }
    
    // MARK: - Session Management
    public func startSession(build: String, deviceModel: String, osVersion: String) {
        sessionStartTime = Date().timeIntervalSince1970
        sessionEvents.removeAll()
        performanceMetrics.removeAll()
        
        let event = LogEvent(
            name: "session_start",
            timestamp: sessionStartTime,
            parameters: [
                "build": build,
                "device_model": deviceModel,
                "os_version": osVersion
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Session started - Build: %{public}@, Device: %{public}@, OS: %{public}@", build, deviceModel, osVersion)
    }
    
    public func stopSession() {
        let duration = Date().timeIntervalSince1970 - sessionStartTime
        
        let event = LogEvent(
            name: "session_stop",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "duration_s": String(format: "%.2f", duration)
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Session stopped - Duration: %.2fs", duration)
        
        // Export logs if requested
        _ = exportLogs()
    }
    
    // MARK: - Guidance Events
    public func logHintShown(type: String, confidence: Float, ruleVersion: String) {
        let event = LogEvent(
            name: "hint_shown",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "type": type,
                "confidence": String(format: "%.2f", confidence),
                "rule_version": ruleVersion
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Hint shown - Type: %{public}@, Confidence: %.2f", type, confidence)
    }
    
    public func logHintAdopted(type: String, adopted: Bool, latencyMs: Int, before: [String: String], after: [String: String]) {
        let event = LogEvent(
            name: "hint_adopted",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "type": type,
                "adopted": adopted ? "true" : "false",
                "latency_ms": String(latencyMs),
                "before": before.description,
                "after": after.description
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Hint adoption - Type: %{public}@, Adopted: %{public}@, Latency: %dms", type, adopted ? "true" : "false", latencyMs)
    }
    
    // MARK: - Photo Events
    public func logShutter(mode: String, latencyFromFirstHintMs: Int) {
        let event = LogEvent(
            name: "shutter",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "mode": mode,
                "latency_from_first_hint_ms": String(latencyFromFirstHintMs)
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Shutter - Mode: %{public}@, Latency: %dms", mode, latencyFromFirstHintMs)
    }
    
    public func logPhotoKept(kept: Bool) {
        let event = LogEvent(
            name: "photo_kept",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "kept": kept ? "true" : "false"
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Photo kept: %{public}@", kept ? "true" : "false")
    }
    
    public func logMicroSurvey(helpful: Bool, satisfaction: Int) {
        let event = LogEvent(
            name: "micro_survey",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "helpful": helpful ? "true" : "false",
                "satisfaction": String(satisfaction)
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Micro-survey - Helpful: %{public}@, Satisfaction: %d", helpful ? "true" : "false", satisfaction)
    }
    
    // 🚀 WEEK 3: Headroom-Specific Telemetry Events
    public func logFaceDetected(
        size: Float,
        headroom: Float,
        isStable: Bool,
        isPrimarySubject: Bool,
        selectionScore: Float? = nil
    ) {
        let event = LogEvent(
            name: "face_detected",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "face_size_percent": String(format: "%.1f", size),
                "headroom_percent": String(format: "%.1f", headroom),
                "is_stable": isStable ? "true" : "false",
                "is_primary": isPrimarySubject ? "true" : "false",
                "selection_score": selectionScore != nil ? String(format: "%.2f", selectionScore!) : "null"
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Face detected - Size: %.1f%%, Headroom: %.1f%%, Stable: %{public}@", 
               size, headroom, isStable ? "true" : "false")
    }
    
    public func logHeadroomGuidance(
        currentHeadroom: Float,
        targetRange: ClosedRange<Float>,
        adjustmentDegrees: Int,
        direction: String
    ) {
        let event = LogEvent(
            name: "headroom_guidance",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "current_headroom": String(format: "%.1f", currentHeadroom),
                "target_min": String(format: "%.1f", targetRange.lowerBound),
                "target_max": String(format: "%.1f", targetRange.upperBound),
                "adjustment_degrees": String(adjustmentDegrees),
                "direction": direction
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Headroom guidance - Current: %.1f%%, Target: %.1f-%.1f%%, Adjust: %{public}@ %d°", 
               currentHeadroom, targetRange.lowerBound, targetRange.upperBound, direction, adjustmentDegrees)
    }
    
    public func logHeadroomAdoption(
        beforeHeadroom: Float,
        afterHeadroom: Float,
        improvement: Float,
        adopted: Bool
    ) {
        let event = LogEvent(
            name: "headroom_adoption",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "before_headroom": String(format: "%.1f", beforeHeadroom),
                "after_headroom": String(format: "%.1f", afterHeadroom),
                "improvement": String(format: "%.1f", improvement),
                "adopted": adopted ? "true" : "false"
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Headroom adoption - Before: %.1f%%, After: %.1f%%, Improvement: %.1f%%, Adopted: %{public}@", 
               beforeHeadroom, afterHeadroom, improvement, adopted ? "true" : "false")
    }
    
    public func logSceneClassification(
        sceneType: String,
        confidence: Float,
        faceCount: Int,
        primaryFaceSize: Float?
    ) {
        let event = LogEvent(
            name: "scene_classification",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "scene_type": sceneType,
                "confidence": String(format: "%.2f", confidence),
                "face_count": String(faceCount),
                "primary_face_size": primaryFaceSize != nil ? String(format: "%.1f", primaryFaceSize!) : "null"
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Scene classification - Type: %{public}@, Confidence: %.2f, Faces: %d", 
               sceneType, confidence, faceCount)
    }
    
    // MARK: - Performance Events
    public func logFPSSample(average: Float, p95: Float) {
        let event = LogEvent(
            name: "fps_sample",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "avg": String(format: "%.1f", average),
                "p95": String(format: "%.1f", p95)
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "FPS Sample - Avg: %.1f, P95: %.1f", average, p95)
    }
    
    public func logThermalSample(state: ProcessInfo.ThermalState) {
        let stateString = thermalStateString(state)
        let event = LogEvent(
            name: "thermal_sample",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "state": stateString
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Thermal state: %{public}@", stateString)
    }
    
    // MARK: - Privacy Events
    public func logConsentChanged(postShotCloud: Bool) {
        let event = LogEvent(
            name: "consent_changed",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "postshot_cloud": postShotCloud ? "on" : "off"
            ]
        )
        
        logEvent(event)
        os_log(.info, log: osLog, "Consent changed - Post-shot cloud: %{public}@", postShotCloud ? "on" : "off")
    }
    
    // MARK: - Private Methods
    public func logEvent(_ event: LogEvent) {
        queue.async {
            self.sessionEvents.append(event)
        }
    }
    
    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
    
    // MARK: - Export
    public func exportLogs() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        let csvData = generateCSV()
        let jsonData = generateJSON()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let csvURL = documentsPath.appendingPathComponent("camera_coach_logs_\(timestamp).csv")
        let jsonURL = documentsPath.appendingPathComponent("camera_coach_logs_\(timestamp).json")
        
        do {
            try csvData.write(to: csvURL)
            try jsonData.write(to: jsonURL)
            os_log(.info, log: osLog, "Logs exported to: %{public}@", csvURL.path)
            return csvURL
        } catch {
            os_log(.error, log: osLog, "Failed to export logs: %{public}@", error.localizedDescription)
            return nil
        }
    }
    
    private func generateCSV() -> Data {
        var csv = "timestamp,event_name,parameters\n"
        
        for event in sessionEvents {
            let params = event.parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
            csv += "\(event.timestamp),\(event.name),\(params)\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
    
    private func generateJSON() -> Data {
        let logData: [String: Any] = [
            "session_start": sessionStartTime,
            "events": sessionEvents.map { event in
                [
                    "timestamp": event.timestamp,
                    "name": event.name,
                    "parameters": event.parameters
                ]
            }
        ]
        
        return try! JSONSerialization.data(withJSONObject: logData, options: .prettyPrinted)
    }
}

// MARK: - Data Models
public struct LogEvent {
    let name: String
    let timestamp: TimeInterval
    let parameters: [String: String]
    
    public init(name: String, timestamp: TimeInterval, parameters: [String: String]) {
        self.name = name
        self.timestamp = timestamp
        self.parameters = parameters
    }
}

private struct PerformanceMetric {
    let timestamp: TimeInterval
    let fps: Float
    let latencyMs: Int
    let thermalState: ProcessInfo.ThermalState
}
