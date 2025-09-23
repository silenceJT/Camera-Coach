//
//  ThermalManager.swift
//  Camera Coach
//
//  Thermal management system for iPhone 17 Pro sustained camera use.
//  Monitors thermal state and implements performance optimizations.
//

import Foundation
import UIKit
import Combine

public final class ThermalManager: ObservableObject {
    public static let shared = ThermalManager()

    // MARK: - Published Properties
    @Published public var currentThermalState: ProcessInfo.ThermalState = .nominal
    @Published public var isThrottlingActive: Bool = false
    @Published public var performanceLevel: PerformanceLevel = .full

    // MARK: - Types
    public enum PerformanceLevel {
        case full       // Normal operation
        case reduced    // Fair thermal state - reduce some processing
        case minimal    // Serious/critical - minimal processing only

        var faceDetectionEnabled: Bool {
            switch self {
            case .full, .reduced: return true
            case .minimal: return false
            }
        }

        var targetFPS: Float {
            switch self {
            case .full: return 30.0
            case .reduced: return 24.0
            case .minimal: return 15.0
            }
        }

        var processingInterval: TimeInterval {
            switch self {
            case .full: return 1.0/30.0    // 30 FPS
            case .reduced: return 1.0/24.0  // 24 FPS
            case .minimal: return 1.0/15.0  // 15 FPS
            }
        }
    }

    // MARK: - Private Properties
    private let logger = Logger.shared
    private var thermalObserver: NSObjectProtocol?
    private var lastThermalCheck: Date = Date()
    private let thermalCheckInterval: TimeInterval = 5.0 // Check every 5 seconds

    // Thermal statistics
    private var thermalStateHistory: [ThermalStateRecord] = []
    private let maxHistoryRecords = 100

    private struct ThermalStateRecord {
        let timestamp: Date
        let state: ProcessInfo.ThermalState
        let performanceLevel: PerformanceLevel
    }

    // MARK: - Initialization
    private init() {
        setupThermalMonitoring()
        currentThermalState = ProcessInfo.processInfo.thermalState
        updatePerformanceLevel()
    }

    deinit {
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    /// Check if face detection should be enabled based on thermal state
    public var shouldEnableFaceDetection: Bool {
        return performanceLevel.faceDetectionEnabled
    }

    /// Get recommended processing interval based on thermal state
    public var recommendedProcessingInterval: TimeInterval {
        return performanceLevel.processingInterval
    }

    /// Get current target FPS based on thermal state
    public var targetFPS: Float {
        return performanceLevel.targetFPS
    }

    /// Force thermal check (useful for testing)
    public func forceThermalCheck() {
        updateThermalState()
    }

    /// Get thermal statistics for debugging
    public func getThermalStatistics() -> [String: Any] {
        let recentRecords = thermalStateHistory.suffix(20)
        let stateCounts = Dictionary(grouping: recentRecords) { $0.state }

        return [
            "current_state": logger.thermalStateString(currentThermalState),
            "performance_level": String(describing: performanceLevel),
            "is_throttling": isThrottlingActive,
            "history_count": thermalStateHistory.count,
            "nominal_count": stateCounts[.nominal]?.count ?? 0,
            "fair_count": stateCounts[.fair]?.count ?? 0,
            "serious_count": stateCounts[.serious]?.count ?? 0,
            "critical_count": stateCounts[.critical]?.count ?? 0
        ]
    }

    // MARK: - Private Methods

    private func setupThermalMonitoring() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThermalState()
        }

        // Initial state
        updateThermalState()
    }

    private func updateThermalState() {
        let newState = ProcessInfo.processInfo.thermalState
        let previousState = currentThermalState

        currentThermalState = newState

        // Update performance level
        let previousLevel = performanceLevel
        updatePerformanceLevel()

        // Log thermal state change
        if newState != previousState || performanceLevel != previousLevel {
            logThermalStateChange(from: previousState, to: newState)
        }

        // Record in history
        recordThermalState()

        lastThermalCheck = Date()
    }

    private func updatePerformanceLevel() {
        let previousLevel = performanceLevel

        switch currentThermalState {
        case .nominal:
            performanceLevel = .full
            isThrottlingActive = false

        case .fair:
            performanceLevel = .reduced
            isThrottlingActive = true

        case .serious:
            performanceLevel = .minimal
            isThrottlingActive = true

        case .critical:
            performanceLevel = .minimal
            isThrottlingActive = true

        @unknown default:
            performanceLevel = .reduced
            isThrottlingActive = true
        }

        if performanceLevel != previousLevel {
            logger.logThermalPerformanceChange(
                from: String(describing: previousLevel),
                to: String(describing: performanceLevel),
                thermalState: currentThermalState
            )
        }
    }

    private func recordThermalState() {
        let record = ThermalStateRecord(
            timestamp: Date(),
            state: currentThermalState,
            performanceLevel: performanceLevel
        )

        thermalStateHistory.append(record)

        // Keep history size manageable
        if thermalStateHistory.count > maxHistoryRecords {
            thermalStateHistory.removeFirst(thermalStateHistory.count - maxHistoryRecords)
        }
    }

    private func logThermalStateChange(from previousState: ProcessInfo.ThermalState, to newState: ProcessInfo.ThermalState) {
        logger.logThermalStateTransition(
            from: logger.thermalStateString(previousState),
            to: logger.thermalStateString(newState),
            performanceLevel: String(describing: performanceLevel),
            isThrottling: isThrottlingActive
        )
    }
}

// MARK: - Logger Extensions for Thermal Management
extension Logger {
    func logThermalStateTransition(from: String, to: String, performanceLevel: String, isThrottling: Bool) {
        let event = LogEvent(
            name: "thermal_state_transition",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "from_state": from,
                "to_state": to,
                "performance_level": performanceLevel,
                "is_throttling": isThrottling ? "true" : "false"
            ]
        )
        logEvent(event)
    }

    func logThermalPerformanceChange(from: String, to: String, thermalState: ProcessInfo.ThermalState) {
        let event = LogEvent(
            name: "thermal_performance_change",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "from_level": from,
                "to_level": to,
                "thermal_state": thermalStateString(thermalState)
            ]
        )
        logEvent(event)
    }

    func logThermalSustainedTest(duration: TimeInterval, averageFPS: Float, thermalEvents: Int) {
        let event = LogEvent(
            name: "thermal_sustained_test",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "duration_seconds": String(format: "%.1f", duration),
                "average_fps": String(format: "%.1f", averageFPS),
                "thermal_events": String(thermalEvents),
                "device_model": UIDevice.current.model
            ]
        )
        logEvent(event)
    }
}