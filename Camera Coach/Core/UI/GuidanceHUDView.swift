//
//  GuidanceHUDView.swift
//  Camera Coach
//
//  HUD overlay view that displays guidance text and composition grid.
//  Uses UIKit for grid/level (crisp vectors) + SwiftUI GlassPill for guidance hints (iOS 26+ glass).
//

import UIKit
import SwiftUI

public final class GuidanceHUDView: UIView {
    // MARK: - UI Components
    private var glassPillHostingController: UIHostingController<AnyView>?
    private let gridView = CompositionGridView()
    private let levelIndicator = LevelIndicatorView()
    private let timestampLabel = UILabel()
    
    // MARK: - Properties
    private var currentGuidance: GuidanceAdvice?
    private var fadeAnimation: UIViewPropertyAnimator?
    private var angleProvider: LevelAngleProvider?
    
    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        // Setup GlassPill hosting controller (iOS 26+)
        if #available(iOS 26.0, *) {
            let pillView = GlassPill(text: "")
                .opacity(0)  // Start hidden
            let hostingController = UIHostingController(rootView: AnyView(pillView))
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            glassPillHostingController = hostingController
            addSubview(hostingController.view)
        }

        // Setup timestamp label (for performance monitoring)
        timestampLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        timestampLabel.textColor = .white
        timestampLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        timestampLabel.layer.cornerRadius = 4
        timestampLabel.layer.masksToBounds = true
        timestampLabel.textAlignment = .center

        // Setup level indicator
        levelIndicator.backgroundColor = .clear

        // Add subviews
        addSubview(gridView)
        addSubview(levelIndicator)
        addSubview(timestampLabel)

        // Setup constraints
        setupConstraints()

        // Start timestamp updates
        startTimestampUpdates()
    }
    
    private func setupConstraints() {
        gridView.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        levelIndicator.translatesAutoresizingMaskIntoConstraints = false

        var constraints: [NSLayoutConstraint] = [
            // Grid covers entire view
            gridView.topAnchor.constraint(equalTo: topAnchor),
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Timestamp label at top LEFT (moved to avoid settings button overlap)
            timestampLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            timestampLabel.widthAnchor.constraint(equalToConstant: 80),
            timestampLabel.heightAnchor.constraint(equalToConstant: 24),

            // Level indicator covers entire view for positioning flexibility
            levelIndicator.topAnchor.constraint(equalTo: topAnchor),
            levelIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            levelIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            levelIndicator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]

        // GlassPill constraints (iOS 26+ only)
        if #available(iOS 26.0, *), let pillView = glassPillHostingController?.view {
            constraints += [
                // GlassPill positioned in upper third of screen
                pillView.centerXAnchor.constraint(equalTo: centerXAnchor),
                pillView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 60),
                pillView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
                pillView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }
    
    // MARK: - Public Interface
    public func showGuidance(_ guidance: GuidanceAdvice) {
        // Validate guidance
        guard guidance.isValid else { return }

        // Store current guidance
        currentGuidance = guidance

        // Update GlassPill with new text (iOS 26+)
        if #available(iOS 26.0, *) {
            let pillView = GlassPill(text: guidance.displayText)
            glassPillHostingController?.rootView = AnyView(pillView)

            // Animate in with SwiftUI transition
            withAnimation(.easeInOut(duration: Config.hudFadeInDuration)) {
                glassPillHostingController?.rootView = AnyView(pillView.opacity(1))
            }

            // Auto-hide after 1.2s (per DoD: glass pill auto-hide ≤1.2s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.hideGuidance()
            }
        }

        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Log the guidance shown
        Logger.shared.logHintShown(
            type: guidance.type.rawValue,
            confidence: guidance.confidence,
            ruleVersion: guidance.ruleVersion
        )
    }

    public func hideGuidance() {
        if #available(iOS 26.0, *) {
            withAnimation(.easeInOut(duration: Config.hudFadeOutDuration)) {
                if let currentText = currentGuidance?.displayText {
                    glassPillHostingController?.rootView = AnyView(GlassPill(text: currentText).opacity(0))
                }
            }
        }

        currentGuidance = nil
    }
    
    public func updateHorizonAngle(_ degrees: Float) {
        // 🚀 NEW: Use proper Level Indicator instead of rotating line
        levelIndicator.update(angleDeg: degrees)
    }
    
    public func setAngleProvider(_ provider: LevelAngleProvider) {
        self.angleProvider = provider
    }
    
    public func updateLevelIndicator() {
        guard let provider = angleProvider else { return }
        let angle = provider.currentLevelAngleDeg()
        levelIndicator.update(angleDeg: angle)
    }
    

    
    public func updateTimestamp(_ timestamp: String) {
        timestampLabel.text = timestamp
    }
    
    // MARK: - Private Methods
    private func startTimestampUpdates() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = formatter.string(from: Date())
            self?.updateTimestamp(timestamp)
        }
    }
}

// MARK: - Composition Grid View
private final class CompositionGridView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true  // Ensure grid lines stay within camera view bounds
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true  // Ensure grid lines stay within camera view bounds
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Use bounds instead of rect to ensure we're drawing within the view's coordinate system
        let width = bounds.width
        let height = bounds.height
        
        // Set line properties
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1.0)
        
        // Draw rule of thirds grid
        let thirdWidth = width / 3
        let thirdHeight = height / 3
        
        // Vertical lines
        context.move(to: CGPoint(x: thirdWidth, y: 0))
        context.addLine(to: CGPoint(x: thirdWidth, y: height))
        
        context.move(to: CGPoint(x: thirdWidth * 2, y: 0))
        context.addLine(to: CGPoint(x: thirdWidth * 2, y: height))
        
        // Horizontal lines
        context.move(to: CGPoint(x: 0, y: thirdHeight))
        context.addLine(to: CGPoint(x: width, y: thirdHeight))
        
        context.move(to: CGPoint(x: 0, y: thirdHeight * 2))
        context.addLine(to: CGPoint(x: width, y: thirdHeight * 2))
        
        // Draw the lines
        context.strokePath()
    }
}
