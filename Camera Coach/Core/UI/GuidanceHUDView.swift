//
//  GuidanceHUDView.swift
//  Camera Coach
//
//  HUD overlay view that displays guidance text and composition grid.
//  Uses UIKit for performance and GPU-friendly drawing.
//

import UIKit

public final class GuidanceHUDView: UIView {
    // MARK: - UI Components
    private let guidanceLabel = UILabel()
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
        
        // Setup guidance label
        guidanceLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        guidanceLabel.textColor = .white
        guidanceLabel.textAlignment = .center
        guidanceLabel.numberOfLines = 2
        guidanceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        guidanceLabel.layer.cornerRadius = 8
        guidanceLabel.layer.masksToBounds = true
        guidanceLabel.alpha = 0.0
        
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
        addSubview(guidanceLabel)
        addSubview(timestampLabel)
        
        // Setup constraints
        setupConstraints()
        
        // Start timestamp updates
        startTimestampUpdates()
    }
    
    private func setupConstraints() {
        gridView.translatesAutoresizingMaskIntoConstraints = false
        guidanceLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        levelIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Grid covers entire view
            gridView.topAnchor.constraint(equalTo: topAnchor),
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Guidance label positioned at bottom center
            guidanceLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            guidanceLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            guidanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            guidanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            guidanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            
            // Timestamp label at top right
            timestampLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            timestampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            timestampLabel.widthAnchor.constraint(equalToConstant: 80),
            timestampLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Level indicator covers entire view for positioning flexibility
            levelIndicator.topAnchor.constraint(equalTo: topAnchor),
            levelIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            levelIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            levelIndicator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Public Interface
    public func showGuidance(_ guidance: GuidanceAdvice) {
        // Cancel any existing fade animation
        fadeAnimation?.stopAnimation(true)
        
        // Update guidance text
        guidanceLabel.text = guidance.displayText
        
        // Validate guidance
        guard guidance.isValid else {
            return
        }
        
        // Store current guidance
        currentGuidance = guidance
        
        // Animate in
        fadeAnimation = UIViewPropertyAnimator(duration: Config.hudFadeInDuration, curve: .easeInOut) {
            self.guidanceLabel.alpha = 1.0
        }
        
        fadeAnimation?.addCompletion { _ in
            // Auto-hide after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.hideGuidance()
            }
        }
        
        fadeAnimation?.startAnimation()
        
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
        fadeAnimation?.stopAnimation(true)
        
        fadeAnimation = UIViewPropertyAnimator(duration: Config.hudFadeOutDuration, curve: .easeInOut) {
            self.guidanceLabel.alpha = 0.0
        }
        
        fadeAnimation?.addCompletion { _ in
            self.currentGuidance = nil
        }
        
        fadeAnimation?.startAnimation()
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
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let width = rect.width
        let height = rect.height
        
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
