//
//  EMAFilter.swift
//  Camera Coach
//
//  Exponential Moving Average (EMA) filter for smoothing noisy sensor data.
//  Used to stabilize composition metrics and prevent UI jitter.
//
//  Week 7: Perfect composition debouncing with professional camera app smoothing.
//

import Foundation

/// Exponential Moving Average filter for smoothing time-series data
///
/// Formula: smoothed = α × current + (1-α) × previous
/// - Lower α (0.1-0.2): More smoothing, slower response
/// - Higher α (0.3-0.5): Less smoothing, faster response
///
/// Typical usage for camera metrics: α = 0.15-0.25
public final class EMAFilter {
    // MARK: - Properties

    /// Smoothing factor (alpha) - controls responsiveness vs smoothness
    /// - 0.1: Very smooth, slow response (good for UI elements)
    /// - 0.2: Balanced (recommended for composition metrics)
    /// - 0.3: Fast response, less smoothing
    private let alpha: Float

    /// Current smoothed value
    private var smoothedValue: Float?

    // MARK: - Initialization

    /// Create an EMA filter with specified smoothing factor
    /// - Parameter alpha: Smoothing factor (0.0-1.0), default 0.2
    public init(alpha: Float = 0.2) {
        // Clamp alpha to valid range
        self.alpha = max(0.0, min(1.0, alpha))
    }

    // MARK: - Public Methods

    /// Update filter with new value and return smoothed result
    /// - Parameter value: New measurement value
    /// - Returns: Smoothed value
    public func update(_ value: Float) -> Float {
        guard let previous = smoothedValue else {
            // First value - initialize with no smoothing
            smoothedValue = value
            return value
        }

        // EMA formula: smoothed = α × current + (1-α) × previous
        let smoothed = alpha * value + (1.0 - alpha) * previous
        smoothedValue = smoothed
        return smoothed
    }

    /// Reset the filter (clear history)
    public func reset() {
        smoothedValue = nil
    }

    /// Get current smoothed value without updating
    /// - Returns: Current smoothed value, or nil if no data yet
    public var current: Float? {
        return smoothedValue
    }
}

/// Dual-EMA filter for boolean state with hysteresis
///
/// Prevents rapid flickering by using different smoothing for rising vs falling edges.
/// Common in professional camera apps for "perfect composition" detection.
public final class HysteresisEMAFilter {
    // MARK: - Properties

    private let risingAlpha: Float   // Faster response when becoming true
    private let fallingAlpha: Float  // Slower response when becoming false
    private let threshold: Float     // Decision threshold (0.0-1.0)

    private var smoothedValue: Float = 0.0
    private var currentState: Bool = false

    // MARK: - Initialization

    /// Create hysteresis filter for boolean state
    /// - Parameters:
    ///   - risingAlpha: Smoothing when transitioning to true (default: 0.3, faster)
    ///   - fallingAlpha: Smoothing when transitioning to false (default: 0.1, slower)
    ///   - threshold: Decision threshold (default: 0.5)
    public init(risingAlpha: Float = 0.3, fallingAlpha: Float = 0.1, threshold: Float = 0.5) {
        self.risingAlpha = max(0.0, min(1.0, risingAlpha))
        self.fallingAlpha = max(0.0, min(1.0, fallingAlpha))
        self.threshold = max(0.0, min(1.0, threshold))
    }

    // MARK: - Public Methods

    /// Update filter with new boolean value
    /// - Parameter value: New boolean measurement
    /// - Returns: Smoothed boolean state
    public func update(_ value: Bool) -> Bool {
        let target: Float = value ? 1.0 : 0.0

        // Choose alpha based on direction
        let alpha = (target > smoothedValue) ? risingAlpha : fallingAlpha

        // Apply EMA
        smoothedValue = alpha * target + (1.0 - alpha) * smoothedValue

        // Apply threshold with hysteresis
        if smoothedValue > threshold && !currentState {
            currentState = true  // Rising edge
        } else if smoothedValue < (threshold - 0.2) && currentState {
            currentState = false  // Falling edge (with hysteresis gap)
        }

        return currentState
    }

    /// Reset filter to initial state
    public func reset() {
        smoothedValue = 0.0
        currentState = false
    }
}
