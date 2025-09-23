//
//  ThermalTestRunner.swift
//  Camera Coach
//
//  Thermal endurance testing specifically for iPhone 17 Pro + iOS 26.
//  Tests sustained camera use and thermal management effectiveness.
//

import Foundation
import UIKit
import AVFoundation

public final class ThermalTestRunner: ObservableObject {
    public static let shared = ThermalTestRunner()

    // MARK: - Published Properties
    @Published public var isTestRunning = false
    @Published public var testDuration: TimeInterval = 0
    @Published public var currentFPS: Float = 0
    @Published public var thermalState: String = "nominal"
    @Published public var performanceLevel: String = "full"

    // MARK: - Private Properties
    private let frameAnalyzer = FrameAnalyzer()
    private let thermalManager = ThermalManager.shared
    private let logger = Logger.shared

    private var testTimer: Timer?
    private var testStartTime: Date?
    private var fpsHistory: [Float] = []
    private var thermalEventHistory: [ThermalEvent] = []

    public struct ThermalEvent {
        let timestamp: Date
        let thermalState: ProcessInfo.ThermalState
        let fps: Float
        let performanceLevel: String
    }

    private init() {}

    // MARK: - Public Methods

    /// Start comprehensive thermal endurance test
    public func startThermalEnduranceTest(duration: TimeInterval = 900) { // 15 minutes default
        guard !isTestRunning else { return }

        isTestRunning = true
        testStartTime = Date()
        fpsHistory.removeAll()
        thermalEventHistory.removeAll()

        // Start frame analyzer thermal test
        frameAnalyzer.startThermalTest()

        // Log test start
        logger.logEvent(LogEvent(
            name: "thermal_endurance_test_start",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "target_duration": String(format: "%.0f", duration),
                "device_model": UIDevice.current.model,
                "ios_version": UIDevice.current.systemVersion,
                "app_version": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            ]
        ))

        // Start monitoring timer (update every second)
        testTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTestMetrics()
        }

        // Auto-stop after target duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.isTestRunning == true {
                self?.stopThermalEnduranceTest()
            }
        }
    }

    /// Stop thermal endurance test and generate report
    public func stopThermalEnduranceTest() -> ThermalTestReport {
        guard isTestRunning else {
            return ThermalTestReport(error: "No active test")
        }

        isTestRunning = false
        testTimer?.invalidate()
        testTimer = nil

        let finalResults = frameAnalyzer.stopThermalTest()
        let testReport = generateTestReport(frameAnalyzerResults: finalResults)

        logger.logEvent(LogEvent(
            name: "thermal_endurance_test_complete",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "actual_duration": String(format: "%.1f", testReport.actualDuration),
                "average_fps": String(format: "%.1f", testReport.averageFPS),
                "min_fps": String(format: "%.1f", testReport.minimumFPS),
                "thermal_events": String(testReport.thermalEvents.count),
                "final_thermal_state": testReport.finalThermalState,
                "performance_degradation": String(format: "%.1f", testReport.performanceDegradationPercent)
            ]
        ))

        return testReport
    }

    /// Get current test status
    public func getCurrentTestStatus() -> [String: Any] {
        return frameAnalyzer.getThermalTestStatus()
    }

    // MARK: - Private Methods

    private func updateTestMetrics() {
        guard let startTime = testStartTime else { return }

        testDuration = Date().timeIntervalSince(startTime)

        // Update published properties for UI
        let status = frameAnalyzer.getThermalTestStatus()
        currentFPS = status["current_fps"] as? Float ?? 0
        thermalState = status["thermal_state"] as? String ?? "unknown"
        performanceLevel = status["performance_level"] as? String ?? "unknown"

        // Record FPS history
        fpsHistory.append(currentFPS)

        // Record thermal events if state changed
        let currentThermalState = thermalManager.currentThermalState
        if thermalEventHistory.isEmpty || thermalEventHistory.last?.thermalState != currentThermalState {
            thermalEventHistory.append(ThermalEvent(
                timestamp: Date(),
                thermalState: currentThermalState,
                fps: currentFPS,
                performanceLevel: String(describing: thermalManager.performanceLevel)
            ))
        }

        // Log periodic status (every 30 seconds)
        if Int(testDuration) % 30 == 0 {
            logger.logEvent(LogEvent(
                name: "thermal_test_status",
                timestamp: Date().timeIntervalSince1970,
                parameters: [
                    "duration": String(format: "%.0f", testDuration),
                    "current_fps": String(format: "%.1f", currentFPS),
                    "thermal_state": thermalState,
                    "performance_level": performanceLevel
                ]
            ))
        }
    }

    private func generateTestReport(frameAnalyzerResults: [String: Any]) -> ThermalTestReport {
        guard let startTime = testStartTime else {
            return ThermalTestReport(error: "Invalid test state")
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let averageFPS = fpsHistory.isEmpty ? 0 : fpsHistory.reduce(0, +) / Float(fpsHistory.count)
        let minimumFPS = fpsHistory.min() ?? 0
        let maximumFPS = fpsHistory.max() ?? 0

        // Calculate performance degradation
        let initialFPS = fpsHistory.prefix(10).reduce(0, +) / Float(min(10, fpsHistory.count))
        let finalFPS = fpsHistory.suffix(10).reduce(0, +) / Float(min(10, fpsHistory.count))
        let performanceDegradation = initialFPS > 0 ? ((initialFPS - finalFPS) / initialFPS) * 100 : 0

        return ThermalTestReport.success(
            actualDuration: actualDuration,
            averageFPS: averageFPS,
            minimumFPS: minimumFPS,
            maximumFPS: maximumFPS,
            initialFPS: initialFPS,
            finalFPS: finalFPS,
            performanceDegradationPercent: performanceDegradation,
            thermalEvents: thermalEventHistory,
            fpsHistory: fpsHistory,
            finalThermalState: thermalState,
            frameAnalyzerResults: frameAnalyzerResults
        )
    }
}

// MARK: - Test Report
public struct ThermalTestReport {
    public let actualDuration: TimeInterval
    public let averageFPS: Float
    public let minimumFPS: Float
    public let maximumFPS: Float
    public let initialFPS: Float
    public let finalFPS: Float
    public let performanceDegradationPercent: Float
    public let thermalEvents: [ThermalTestRunner.ThermalEvent]
    public let fpsHistory: [Float]
    public let finalThermalState: String
    public let frameAnalyzerResults: [String: Any]
    public let error: String?

    init(error: String) {
        self.error = error
        self.actualDuration = 0
        self.averageFPS = 0
        self.minimumFPS = 0
        self.maximumFPS = 0
        self.initialFPS = 0
        self.finalFPS = 0
        self.performanceDegradationPercent = 0
        self.thermalEvents = []
        self.fpsHistory = []
        self.finalThermalState = "unknown"
        self.frameAnalyzerResults = [:]
    }

    init(actualDuration: TimeInterval,
         averageFPS: Float,
         minimumFPS: Float,
         maximumFPS: Float,
         initialFPS: Float,
         finalFPS: Float,
         performanceDegradationPercent: Float,
         thermalEvents: [ThermalTestRunner.ThermalEvent],
         fpsHistory: [Float],
         finalThermalState: String,
         frameAnalyzerResults: [String: Any]) {
        self.error = nil
        self.actualDuration = actualDuration
        self.averageFPS = averageFPS
        self.minimumFPS = minimumFPS
        self.maximumFPS = maximumFPS
        self.initialFPS = initialFPS
        self.finalFPS = finalFPS
        self.performanceDegradationPercent = performanceDegradationPercent
        self.thermalEvents = thermalEvents
        self.fpsHistory = fpsHistory
        self.finalThermalState = finalThermalState
        self.frameAnalyzerResults = frameAnalyzerResults
    }

    static func success(actualDuration: TimeInterval,
                       averageFPS: Float,
                       minimumFPS: Float,
                       maximumFPS: Float,
                       initialFPS: Float,
                       finalFPS: Float,
                       performanceDegradationPercent: Float,
                       thermalEvents: [ThermalTestRunner.ThermalEvent],
                       fpsHistory: [Float],
                       finalThermalState: String,
                       frameAnalyzerResults: [String: Any]) -> ThermalTestReport {
        return ThermalTestReport(
            actualDuration: actualDuration,
            averageFPS: averageFPS,
            minimumFPS: minimumFPS,
            maximumFPS: maximumFPS,
            initialFPS: initialFPS,
            finalFPS: finalFPS,
            performanceDegradationPercent: performanceDegradationPercent,
            thermalEvents: thermalEvents,
            fpsHistory: fpsHistory,
            finalThermalState: finalThermalState,
            frameAnalyzerResults: frameAnalyzerResults
        )
    }

    public var summary: String {
        if let error = error {
            return "Test Error: \(error)"
        }

        return """
        📊 Thermal Endurance Test Results

        Duration: \(String(format: "%.1f", actualDuration))s
        Average FPS: \(String(format: "%.1f", averageFPS))
        FPS Range: \(String(format: "%.1f", minimumFPS)) - \(String(format: "%.1f", maximumFPS))
        Performance Degradation: \(String(format: "%.1f", performanceDegradationPercent))%
        Thermal Events: \(thermalEvents.count)
        Final Thermal State: \(finalThermalState)

        ✅ Test completed successfully
        """
    }

    public var passedCriteria: Bool {
        guard error == nil else { return false }

        // Success criteria for iPhone 17 Pro
        return averageFPS >= 24.0 &&  // Sustained ≥24fps
               performanceDegradationPercent < 50.0 &&  // <50% degradation
               finalThermalState != "critical"  // No critical thermal state
    }
}

// MARK: - Extensions
extension ThermalTestRunner.ThermalEvent {
    public var description: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "\(formatter.string(from: timestamp)): \(thermalState.rawValue) - \(String(format: "%.1f", fps))fps (\(performanceLevel))"
    }
}