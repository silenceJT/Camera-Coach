//
//  MemoryProfiler.swift
//  Camera Coach
//
//  Memory profiling and optimization for multi-face detection.
//  Monitors memory usage and implements memory pressure responses.
//

import Foundation
import UIKit

public final class MemoryProfiler: ObservableObject {
    public static let shared = MemoryProfiler()

    // MARK: - Published Properties
    @Published public var currentMemoryUsage: Int64 = 0  // in bytes
    @Published public var memoryPressureLevel: MemoryPressureLevel = .normal
    @Published public var isOptimizing: Bool = false

    // MARK: - Types
    public enum MemoryPressureLevel {
        case normal      // <100MB
        case elevated    // 100-200MB
        case high        // 200-300MB
        case critical    // >300MB

        var description: String {
            switch self {
            case .normal: return "normal"
            case .elevated: return "elevated"
            case .high: return "high"
            case .critical: return "critical"
            }
        }

        var shouldOptimize: Bool {
            switch self {
            case .normal: return false
            case .elevated: return true
            case .high: return true
            case .critical: return true
            }
        }

        var maxFaceCount: Int {
            switch self {
            case .normal: return 10      // Full multi-face detection
            case .elevated: return 5     // Reduced face count
            case .high: return 3         // Limited face count
            case .critical: return 1     // Single face only
            }
        }
    }

    // MARK: - Private Properties
    private let logger = Logger.shared
    private var memoryObserver: NSObjectProtocol?
    private var memoryMonitorTimer: Timer?
    private let memoryCheckInterval: TimeInterval = 2.0  // Check every 2 seconds

    // Memory tracking
    private var memoryHistory: [MemoryReading] = []
    private let maxHistoryCount = 50
    private var lastOptimizationTime: Date?

    private struct MemoryReading {
        let timestamp: Date
        let memoryUsage: Int64
        let pressureLevel: MemoryPressureLevel
    }

    // MARK: - Initialization
    private init() {
        setupMemoryMonitoring()
        updateMemoryUsage()
    }

    deinit {
        if let observer = memoryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        memoryMonitorTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Get recommended maximum face count based on memory pressure
    public var recommendedMaxFaceCount: Int {
        return memoryPressureLevel.maxFaceCount
    }

    /// Check if memory optimization should be triggered
    public var shouldOptimizeMemory: Bool {
        return memoryPressureLevel.shouldOptimize
    }

    /// Get memory statistics for debugging
    public func getMemoryStatistics() -> [String: Any] {
        let recentReadings = memoryHistory.suffix(10)
        let avgMemory = recentReadings.isEmpty ? 0 : recentReadings.map { $0.memoryUsage }.reduce(0, +) / Int64(recentReadings.count)
        let maxMemory = recentReadings.map { $0.memoryUsage }.max() ?? 0

        return [
            "current_memory_mb": currentMemoryUsage / (1024 * 1024),
            "average_memory_mb": avgMemory / (1024 * 1024),
            "peak_memory_mb": maxMemory / (1024 * 1024),
            "pressure_level": memoryPressureLevel.description,
            "recommended_max_faces": recommendedMaxFaceCount,
            "is_optimizing": isOptimizing,
            "readings_count": memoryHistory.count
        ]
    }

    /// Trigger memory optimization (reduce cache, clear buffers)
    public func optimizeMemory() {
        guard !isOptimizing else { return }

        isOptimizing = true
        lastOptimizationTime = Date()

        logger.logMemoryOptimization(
            beforeMemory: currentMemoryUsage,
            pressureLevel: memoryPressureLevel.description
        )

        // Perform memory optimization steps
        performMemoryOptimization()

        // Re-check memory after optimization
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateMemoryUsage()
            self?.isOptimizing = false

            if let afterMemory = self?.currentMemoryUsage {
                self?.logger.logMemoryOptimizationResult(
                    afterMemory: afterMemory,
                    memoryReduced: (self?.currentMemoryUsage ?? 0) < (afterMemory)
                )
            }
        }
    }

    /// Force memory usage update (useful for testing)
    public func updateMemoryUsage() {
        currentMemoryUsage = getCurrentMemoryUsage()
        let previousLevel = memoryPressureLevel
        memoryPressureLevel = calculateMemoryPressureLevel()

        // Record reading
        recordMemoryReading()

        // Log pressure level changes
        if memoryPressureLevel != previousLevel {
            logger.logMemoryPressureChange(
                from: previousLevel.description,
                to: memoryPressureLevel.description,
                memoryUsage: currentMemoryUsage
            )

            // Trigger optimization if pressure increased
            if memoryPressureLevel.shouldOptimize && !isOptimizing {
                optimizeMemory()
            }
        }
    }

    // MARK: - Private Methods

    private func setupMemoryMonitoring() {
        // Monitor memory warnings
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }

        // Start periodic memory monitoring
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: memoryCheckInterval, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
        }
    }

    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func calculateMemoryPressureLevel() -> MemoryPressureLevel {
        let memoryMB = currentMemoryUsage / (1024 * 1024)

        switch memoryMB {
        case 0..<100:
            return .normal
        case 100..<200:
            return .elevated
        case 200..<300:
            return .high
        default:
            return .critical
        }
    }

    private func recordMemoryReading() {
        let reading = MemoryReading(
            timestamp: Date(),
            memoryUsage: currentMemoryUsage,
            pressureLevel: memoryPressureLevel
        )

        memoryHistory.append(reading)

        // Keep history size manageable
        if memoryHistory.count > maxHistoryCount {
            memoryHistory.removeFirst(memoryHistory.count - maxHistoryCount)
        }
    }

    private func handleMemoryWarning() {
        logger.logMemoryWarning(memoryUsage: currentMemoryUsage)

        // Force optimization on memory warning
        if !isOptimizing {
            optimizeMemory()
        }
    }

    private func performMemoryOptimization() {
        // Clear any cached face detection results
        clearFaceDetectionCache()

        // Trigger garbage collection
        autoreleasepool {
            // Force autorelease pool drain
        }

        // Clear image processing buffers (implementation would depend on specific buffers used)
        clearImageProcessingBuffers()
    }

    private func clearFaceDetectionCache() {
        // This would clear any cached face detection results
        // Implementation depends on what caching is done in FrameAnalyzer
        logger.logEvent(LogEvent(
            name: "memory_cache_cleared",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "cache_type": "face_detection",
                "pressure_level": memoryPressureLevel.description
            ]
        ))
    }

    private func clearImageProcessingBuffers() {
        // Clear any temporary image processing buffers
        logger.logEvent(LogEvent(
            name: "memory_buffers_cleared",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "buffer_type": "image_processing",
                "pressure_level": memoryPressureLevel.description
            ]
        ))
    }
}

// MARK: - Logger Extensions for Memory Management
extension Logger {
    func logMemoryPressureChange(from: String, to: String, memoryUsage: Int64) {
        let event = LogEvent(
            name: "memory_pressure_change",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "from_level": from,
                "to_level": to,
                "memory_usage_mb": String(memoryUsage / (1024 * 1024))
            ]
        )
        logEvent(event)
    }

    func logMemoryOptimization(beforeMemory: Int64, pressureLevel: String) {
        let event = LogEvent(
            name: "memory_optimization_start",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "before_memory_mb": String(beforeMemory / (1024 * 1024)),
                "pressure_level": pressureLevel
            ]
        )
        logEvent(event)
    }

    func logMemoryOptimizationResult(afterMemory: Int64, memoryReduced: Bool) {
        let event = LogEvent(
            name: "memory_optimization_complete",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "after_memory_mb": String(afterMemory / (1024 * 1024)),
                "memory_reduced": memoryReduced ? "true" : "false"
            ]
        )
        logEvent(event)
    }

    func logMemoryWarning(memoryUsage: Int64) {
        let event = LogEvent(
            name: "memory_warning",
            timestamp: Date().timeIntervalSince1970,
            parameters: [
                "memory_usage_mb": String(memoryUsage / (1024 * 1024)),
                "device_model": UIDevice.current.model
            ]
        )
        logEvent(event)
    }
}