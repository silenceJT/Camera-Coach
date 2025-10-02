//
//  SilhouetteRenderer.swift
//  Camera Coach
//
//  High-performance silhouette rendering system for template-based composition guidance.
//  Creates elegant, iOS-native visual guidance overlays with smooth animations.
//

import UIKit
import CoreGraphics

// MARK: - Silhouette Renderer
public final class SilhouetteRenderer: UIView {
    // MARK: - Properties
    private var currentTemplate: Template?
    private var silhouetteLayer: CAShapeLayer?
    private var animationTimer: Timer?

    // Visual styling
    private let silhouetteColor = UIColor.white.withAlphaComponent(CGFloat(Config.silhouetteOpacity))
    private let borderColor = UIColor.white.withAlphaComponent(0.6)
    private let borderWidth: CGFloat = 1.5

    // Animation properties
    private let animationDuration = Config.templateAnimationDuration
    private var isAnimating = false

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupRenderer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRenderer()
    }

    private func setupRenderer() {
        backgroundColor = .clear
        isUserInteractionEnabled = false // Allow touch events to pass through

        // Setup for high-quality rendering
        layer.allowsGroupOpacity = false
        layer.shouldRasterize = false
    }

    // MARK: - Template Management
    public func updateTemplate(_ template: Template?, animated: Bool = true) {
        guard template?.id != currentTemplate?.id else { return }

        let previousTemplate = currentTemplate
        currentTemplate = template

        if animated && previousTemplate != nil && template != nil {
            animateTemplateTransition(from: previousTemplate!, to: template!)
        } else {
            renderCurrentTemplate(animated: animated)
        }

        print("🎯 SilhouetteRenderer updated template: \(template?.id ?? "nil")")
    }

    public func clearTemplate(animated: Bool = true) {
        currentTemplate = nil

        if animated {
            fadeOutSilhouette()
        } else {
            removeSilhouetteLayer()
        }
    }

    // MARK: - Rendering Core
    private func renderCurrentTemplate(animated: Bool = true) {
        guard let template = currentTemplate else {
            if animated {
                fadeOutSilhouette()
            } else {
                removeSilhouetteLayer()
            }
            return
        }

        let newPath = createSilhouettePath(for: template)

        if silhouetteLayer == nil {
            createSilhouetteLayer(with: newPath)
            if animated {
                fadeInSilhouette()
            }
        } else {
            updateSilhouettePath(newPath, animated: animated)
        }
    }

    private func createSilhouettePath(for template: Template) -> UIBezierPath {
        let path = UIBezierPath()

        // Convert template's normalized coordinates to view coordinates
        let rect = convertNormalizedRect(template.headAnchorRect, to: bounds)

        // Create silhouette shape based on template category
        switch template.category {
        case .full_body:
            addFullBodySilhouette(to: path, in: rect)
        case .half_body:
            addHalfBodySilhouette(to: path, in: rect)
        case .close_up:
            addCloseUpSilhouette(to: path, in: rect)
        case .couple:
            addCoupleSilhouette(to: path, in: rect)
        }

        return path
    }

    private func convertNormalizedRect(_ normalizedRect: CGRect, to bounds: CGRect) -> CGRect {
        return CGRect(
            x: bounds.width * normalizedRect.minX,
            y: bounds.height * normalizedRect.minY,
            width: bounds.width * normalizedRect.width,
            height: bounds.height * normalizedRect.height
        )
    }

    // MARK: - Silhouette Shapes
    private func addFullBodySilhouette(to path: UIBezierPath, in rect: CGRect) {
        // Head (ellipse)
        let headRect = CGRect(
            x: rect.minX + rect.width * 0.25,
            y: rect.minY,
            width: rect.width * 0.5,
            height: rect.height * 0.4
        )
        path.append(UIBezierPath(ovalIn: headRect))

        // Body (rounded rectangle)
        let bodyRect = CGRect(
            x: rect.minX + rect.width * 0.1,
            y: rect.minY + rect.height * 0.3,
            width: rect.width * 0.8,
            height: rect.height * 0.7
        )
        path.append(UIBezierPath(roundedRect: bodyRect, cornerRadius: rect.width * 0.1))
    }

    private func addHalfBodySilhouette(to path: UIBezierPath, in rect: CGRect) {
        // Head (ellipse)
        let headRect = CGRect(
            x: rect.minX + rect.width * 0.2,
            y: rect.minY,
            width: rect.width * 0.6,
            height: rect.height * 0.5
        )
        path.append(UIBezierPath(ovalIn: headRect))

        // Upper body (rounded rectangle)
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY + rect.height * 0.4,
            width: rect.width,
            height: rect.height * 0.6
        )
        path.append(UIBezierPath(roundedRect: bodyRect, cornerRadius: rect.width * 0.15))
    }

    private func addCloseUpSilhouette(to path: UIBezierPath, in rect: CGRect) {
        // Head and shoulders (oval)
        let silhouetteRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
        path.append(UIBezierPath(ovalIn: silhouetteRect))
    }

    private func addCoupleSilhouette(to path: UIBezierPath, in rect: CGRect) {
        let personWidth = rect.width * 0.45
        let spacing = rect.width * 0.1

        // First person
        let person1Rect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: personWidth,
            height: rect.height
        )
        addSinglePersonInRect(to: path, rect: person1Rect)

        // Second person
        let person2Rect = CGRect(
            x: rect.minX + personWidth + spacing,
            y: rect.minY,
            width: personWidth,
            height: rect.height
        )
        addSinglePersonInRect(to: path, rect: person2Rect)
    }

    private func addSinglePersonInRect(to path: UIBezierPath, rect: CGRect) {
        // Simplified person silhouette
        let headRect = CGRect(
            x: rect.minX + rect.width * 0.25,
            y: rect.minY,
            width: rect.width * 0.5,
            height: rect.height * 0.3
        )
        path.append(UIBezierPath(ovalIn: headRect))

        let bodyRect = CGRect(
            x: rect.minX + rect.width * 0.1,
            y: rect.minY + rect.height * 0.25,
            width: rect.width * 0.8,
            height: rect.height * 0.75
        )
        path.append(UIBezierPath(roundedRect: bodyRect, cornerRadius: rect.width * 0.1))
    }

    // MARK: - Layer Management
    private func createSilhouetteLayer(with path: UIBezierPath) {
        removeSilhouetteLayer()

        let newLayer = CAShapeLayer()
        newLayer.path = path.cgPath
        newLayer.fillColor = silhouetteColor.cgColor
        newLayer.strokeColor = borderColor.cgColor
        newLayer.lineWidth = borderWidth
        newLayer.lineDashPattern = [8, 4] // Dashed border for elegant look

        // Performance optimizations
        newLayer.shouldRasterize = true
        newLayer.rasterizationScale = UIScreen.main.scale

        layer.addSublayer(newLayer)
        silhouetteLayer = newLayer
    }

    private func updateSilhouettePath(_ path: UIBezierPath, animated: Bool) {
        guard let layer = silhouetteLayer else {
            createSilhouetteLayer(with: path)
            return
        }

        if animated {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = layer.path
            animation.toValue = path.cgPath
            animation.duration = animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            layer.add(animation, forKey: "pathTransition")
        }

        layer.path = path.cgPath
    }

    private func removeSilhouetteLayer() {
        silhouetteLayer?.removeFromSuperlayer()
        silhouetteLayer = nil
    }

    // MARK: - Animations
    private func fadeInSilhouette() {
        guard let layer = silhouetteLayer else { return }

        layer.opacity = 0.0

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.duration = animationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        layer.add(animation, forKey: "fadeIn")
        layer.opacity = 1.0
    }

    private func fadeOutSilhouette() {
        guard let layer = silhouetteLayer else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.opacity
        animation.toValue = 0.0
        animation.duration = animationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)

        animation.completion = { [weak self] _ in
            self?.removeSilhouetteLayer()
        }

        layer.add(animation, forKey: "fadeOut")
    }

    private func animateTemplateTransition(from oldTemplate: Template, to newTemplate: Template) {
        guard !isAnimating else { return }

        isAnimating = true

        // Fade out current
        fadeOutSilhouette()

        // Wait for fade out, then fade in new template
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            self?.renderCurrentTemplate(animated: true)
            self?.isAnimating = false
        }
    }

    // MARK: - Layout
    public override func layoutSubviews() {
        super.layoutSubviews()

        // Re-render template when bounds change (e.g., rotation)
        if bounds.size != .zero {
            renderCurrentTemplate(animated: false)
        }
    }

    // MARK: - Public Interface
    public var hasActiveTemplate: Bool {
        return currentTemplate != nil
    }

    public var currentTemplateId: String? {
        return currentTemplate?.id
    }

    public func setOpacity(_ opacity: Float, animated: Bool = true) {
        let newOpacity = max(0.0, min(1.0, opacity))

        if animated {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = silhouetteLayer?.opacity
            animation.toValue = newOpacity
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            silhouetteLayer?.add(animation, forKey: "opacityChange")
        }

        silhouetteLayer?.opacity = newOpacity
    }

    // MARK: - Template Validation
    public func validateTemplate(_ template: Template) -> Bool {
        // Ensure template coordinates are within valid range
        let rect = template.headAnchorRect
        return rect.minX >= 0 && rect.minY >= 0 &&
               rect.maxX <= 1.0 && rect.maxY <= 1.0 &&
               rect.width > 0 && rect.height > 0
    }
}

// MARK: - CAAnimation Extensions
extension CAAnimation {
    var completion: ((Bool) -> Void)? {
        get { return delegate as? (Bool) -> Void }
        set { delegate = newValue as? CAAnimationDelegate }
    }
}

// MARK: - Debug Utilities
#if DEBUG
extension SilhouetteRenderer {
    public func debugRenderAllTemplates(_ templates: [Template]) {
        let testTemplate = templates.first
        updateTemplate(testTemplate, animated: true)

        print("🎯 Debug: Rendering template \(testTemplate?.id ?? "none")")
    }

    public func debugToggleVisibility() {
        isHidden.toggle()
        print("🎯 SilhouetteRenderer visibility toggled: \(!isHidden)")
    }
}
#endif