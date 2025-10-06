//
//  ShutterButton.swift
//  Camera Coach
//
//  Custom shutter button with green ring glow for perfect composition feedback.
//  Follows iOS 26 design patterns with subtle success animations.
//

import UIKit

public final class ShutterButton: UIButton {
    // MARK: - Properties
    private let glowLayer = CAShapeLayer()
    private var glowAnimation: CAAnimationGroup?
    private var isGlowing = false

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    // MARK: - Setup
    private func setupButton() {
        // Button appearance (standard camera shutter)
        backgroundColor = .white
        layer.cornerRadius = 35
        layer.borderWidth = 4
        layer.borderColor = UIColor.white.cgColor

        // Setup glow layer (green ring)
        glowLayer.fillColor = UIColor.clear.cgColor
        glowLayer.strokeColor = UIColor.systemGreen.cgColor // SF Green #34C759
        glowLayer.lineWidth = 3
        glowLayer.opacity = 0 // Hidden by default
        layer.insertSublayer(glowLayer, at: 0)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateGlowPath()
    }

    private func updateGlowPath() {
        let glowRadius = bounds.width / 2 + 4 // 4pt outside the button
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: glowRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        glowLayer.path = path.cgPath
        glowLayer.frame = bounds
    }

    // MARK: - Public Interface

    /// Show green ring glow animation (perfect composition state)
    /// - Parameter withHaptic: Whether to provide haptic feedback (default: true)
    public func showPerfectGlow(withHaptic: Bool = true) {
        guard !isGlowing else { return }
        isGlowing = true

        // Fade in glow layer (smooth transition from Config)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 0.6
        fadeIn.duration = Config.glowFadeInDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false

        // Breathing pulse animation (opacity 0.6 ↔ 0.9)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.6
        pulse.toValue = 0.9
        pulse.duration = 1.5
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Scale animation (subtle grow effect)
        let scaleUp = CABasicAnimation(keyPath: "transform.scale")
        scaleUp.fromValue = 1.0
        scaleUp.toValue = 1.05
        scaleUp.duration = 1.5
        scaleUp.autoreverses = true
        scaleUp.repeatCount = .infinity
        scaleUp.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Group animations
        let group = CAAnimationGroup()
        group.animations = [pulse, scaleUp]
        group.duration = 1.5
        group.repeatCount = .infinity

        glowAnimation = group

        // Apply animations
        glowLayer.add(fadeIn, forKey: "fadeIn")
        glowLayer.add(group, forKey: "perfectGlow")

        // Provide haptic feedback (conditional)
        if withHaptic {
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
        }
    }

    /// Hide green ring glow
    public func hidePerfectGlow() {
        guard isGlowing else { return }
        isGlowing = false

        // Remove ongoing animations
        glowLayer.removeAnimation(forKey: "perfectGlow")

        // Fade out (smooth transition from Config)
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = glowLayer.presentation()?.opacity ?? 0.6
        fadeOut.toValue = 0.0
        fadeOut.duration = Config.glowFadeOutDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false

        glowLayer.add(fadeOut, forKey: "fadeOut")

        // Reset after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.glowFadeOutDuration) {
            self.glowLayer.removeAllAnimations()
            self.glowLayer.opacity = 0
        }
    }
}
