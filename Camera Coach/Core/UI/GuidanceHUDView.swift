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
    private var glassPillHostingController: Any? // Will be UIHostingController<GlassPillWrapper> on iOS 26+
    private let gridView = CompositionGridView()
    private let levelIndicator = LevelIndicatorView()
    private let timestampLabel = UILabel()

    // MARK: - Properties
    private var currentGuidance: GuidanceAdvice?
    private var fadeAnimation: UIViewPropertyAnimator?
    private var angleProvider: LevelAngleProvider?
    private weak var parentViewController: UIViewController? // NEEDED for hosting controller lifecycle

    // MARK: - GlassPill State
    private var pillState: Any? // Will be GlassPillState on iOS 26+
    
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
        // NOTE: Full setup requires parent view controller - call setupGlassPillHosting() after adding to view hierarchy
        if #available(iOS 26.0, *) {
            let state = GlassPillState()
            pillState = state
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

        let constraints: [NSLayoutConstraint] = [
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

        // GlassPill constraints set up separately in setupGlassPillHosting() after view controller is available

        NSLayoutConstraint.activate(constraints)
    }
    
    // MARK: - Public Setup
    public func setupGlassPillHosting(parentViewController: UIViewController) {
        self.parentViewController = parentViewController

        if #available(iOS 26.0, *), let state = pillState as? GlassPillState {
            let wrapper = GlassPillView(state: state)
            let hostingController = UIHostingController(rootView: wrapper)
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false

            // CRITICAL: Proper UIHostingController lifecycle management
            parentViewController.addChild(hostingController)
            addSubview(hostingController.view)
            hostingController.didMove(toParent: parentViewController)

            glassPillHostingController = hostingController

            // Setup constraints
            NSLayoutConstraint.activate([
                hostingController.view.centerXAnchor.constraint(equalTo: centerXAnchor),
                hostingController.view.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 60),
                hostingController.view.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
                hostingController.view.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
            ])

        }
    }

    // MARK: - Public Interface
    public func showGuidance(_ guidance: GuidanceAdvice) {
        // Validate guidance
        guard guidance.isValid else { return }

        // Store current guidance
        currentGuidance = guidance

        // Check if this is perfect composition
        let isPerfect = guidance.action.isPerfect

        // Update GlassPill with new text (iOS 26+)
        if #available(iOS 26.0, *), let state = pillState as? GlassPillState {
            state.updateText(guidance.displayText, show: true, perfect: isPerfect)

            // Perfect state persists (no auto-hide), others auto-hide after 1.2s
            if !isPerfect {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.hideGuidance()
                }
            }
        }

        // Provide haptic feedback (stronger for perfect state)
        let impactFeedback = UIImpactFeedbackGenerator(style: isPerfect ? .medium : .light)
        impactFeedback.impactOccurred()

        // Log the guidance shown
        Logger.shared.logHintShown(
            type: guidance.type.rawValue,
            confidence: guidance.confidence,
            ruleVersion: guidance.ruleVersion
        )
    }

    public func hideGuidance() {
        if #available(iOS 26.0, *), let state = pillState as? GlassPillState {
            state.hide()
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

// MARK: - GlassPill State Management

@available(iOS 26.0, *)
@MainActor
class GlassPillState: ObservableObject {
    @Published var text: String = ""
    @Published var isVisible: Bool = false
    @Published var isPerfect: Bool = false  // NEW: Green success state

    func updateText(_ newText: String, show: Bool, perfect: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.text = newText
            self.isVisible = show
            self.isPerfect = perfect
        }
    }

    func hide() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isVisible = false
            self.isPerfect = false
        }
    }
}

@available(iOS 26.0, *)
struct GlassPillView: View {
    @ObservedObject var state: GlassPillState

    var body: some View {
        GlassPill(text: state.text)
            .tint(state.isPerfect ? .green : .primary)  // Green when perfect
            .opacity(state.isVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: state.isPerfect)
    }
}
