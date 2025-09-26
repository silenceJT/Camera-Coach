//
//  FaceDetectionDebugView.swift
//  Camera Coach
//
//  🚀 WEEK 3: Debug overlay to visualize face detection and headroom guidance
//  Shows face boxes, headroom measurements, and guidance decisions in real-time
//

import UIKit
import CoreGraphics

public final class FaceDetectionDebugView: UIView {
    // MARK: - Properties
    private var faceRect: CGRect?
    private var headroomPercentage: Float?
    private var isHeadroomInTarget: Bool = false
    private var currentGuidance: GuidanceAdvice?
    private var debugInfo: [String] = []
    private var detectionMethod: DetectionMethod = .appleVision
    private var detectionConfidence: Float = 0.0
    private var processingTimeMs: Int = 0
    
    // MARK: - Multi-face Detection Properties
    private var allDetectedFaces: [EnhancedFaceInfo] = []
    private var faceCount: Int = 0
    private var groupHeadroomPercentage: Float?
    private var isGroupHeadroomInTarget: Bool = false
    
    // MARK: - UI Components  
    private let debugLabel = UILabel()
    private let strategyButton = UIButton()
    
    // MARK: - Detection Strategy
    public var onStrategyChanged: ((FaceDetectionStrategy) -> Void)?
    private var currentStrategy: FaceDetectionStrategy = .enhancedDistance
    
    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupDebugView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDebugView()
    }
    
    private func setupDebugView() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        
        // Setup debug label
        debugLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        debugLabel.textColor = .yellow
        debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        debugLabel.numberOfLines = 0
        debugLabel.layer.cornerRadius = 4
        debugLabel.layer.masksToBounds = true
        
        // Setup strategy button
        strategyButton.setTitle("Enhanced", for: .normal)
        strategyButton.setTitleColor(.white, for: .normal)
        strategyButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        strategyButton.layer.cornerRadius = 6
        strategyButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        strategyButton.addTarget(self, action: #selector(strategyButtonTapped), for: .touchUpInside)
        
        addSubview(debugLabel)
        addSubview(strategyButton)
        
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        strategyButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            debugLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            debugLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            
            strategyButton.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            strategyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            strategyButton.widthAnchor.constraint(equalToConstant: 80),
            strategyButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    @objc private func strategyButtonTapped() {
        let alert = UIAlertController(title: "Face Detection Strategy", message: "Choose detection method", preferredStyle: .actionSheet)
        
        let strategies: [(FaceDetectionStrategy, String)] = [
            (.appleVisionOnly, "Apple Vision"),
            (.enhancedDistance, "Enhanced"),
            (.hybridMultiScale, "Multi-Scale")
        ]
        
        for (strategy, title) in strategies {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.currentStrategy = strategy
                self.onStrategyChanged?(strategy)
                
                let buttonTitle: String
                switch strategy {
                case .appleVisionOnly: buttonTitle = "Apple"
                case .enhancedDistance: buttonTitle = "Enhanced"
                case .hybridMultiScale: buttonTitle = "Multi"
                }
                self.strategyButton.setTitle(buttonTitle, for: .normal)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let viewController = self.findViewController() {
            alert.popoverPresentationController?.sourceView = strategyButton
            alert.popoverPresentationController?.sourceRect = strategyButton.bounds
            viewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Public Interface
    public func updateFaceDetection(
        faceRect: CGRect?,
        headroomPercentage: Float?,
        isHeadroomInTarget: Bool,
        guidance: GuidanceAdvice?
    ) {
        self.faceRect = faceRect
        self.headroomPercentage = headroomPercentage
        self.isHeadroomInTarget = isHeadroomInTarget
        self.currentGuidance = guidance
        
        updateDebugInfo()
        setNeedsDisplay()
    }
    
    public func updateEnhancedFaceDetection(result: EnhancedFaceResult) {
        self.detectionMethod = result.detectionMethod
        self.detectionConfidence = result.confidence
        self.processingTimeMs = result.processingTimeMs
        self.allDetectedFaces = result.faces
        self.faceCount = result.faces.count
        
        if let firstFace = result.faces.first {
            self.faceRect = firstFace.rect
            self.headroomPercentage = firstFace.headroomPercentage
            self.isHeadroomInTarget = Config.targetHeadroomPercentage.contains(firstFace.headroomPercentage)
        } else {
            self.faceRect = nil
            self.headroomPercentage = nil
            self.isHeadroomInTarget = false
        }
        
        updateDebugInfo()
        setNeedsDisplay()
    }
    
    // 🚀 NEW: Update with comprehensive FrameFeatures data including group headroom
    public func updateFrameFeatures(_ features: FrameFeatures) {
        // Update face detection data
        self.faceRect = features.faceRect
        self.headroomPercentage = features.headroomPercentage
        self.isHeadroomInTarget = features.isHeadroomInTarget
        self.faceCount = features.faceCount
        
        // Update group headroom data
        self.groupHeadroomPercentage = features.groupHeadroomPercentage
        self.isGroupHeadroomInTarget = features.isGroupHeadroomInTarget
        
        // Convert face rects to EnhancedFaceInfo for display consistency
        self.allDetectedFaces = features.allFaceRects.enumerated().map { index, rect in
            let area = rect.width * rect.height
            let imageArea = bounds.width * bounds.height
            let sizePercentage = Float((area / imageArea) * 100.0)
            let headroomPercentage = Float((rect.minY / bounds.height) * 100.0)
            
            return EnhancedFaceInfo(
                rect: rect,
                sizePercentage: sizePercentage,
                headroomPercentage: headroomPercentage,
                confidence: index == features.primaryFaceIndex ? 0.9 : 0.7, // Higher confidence for primary
                detectionScale: 0.1
            )
        }
        
        updateDebugInfo()
        setNeedsDisplay()
    }
    
    private func updateDebugInfo() {
        debugInfo.removeAll()
        
        // Detection method indicator
        let methodEmoji: String
        switch detectionMethod {
        case .appleVision: methodEmoji = "🍎"
        case .appleVisionEnhanced: methodEmoji = "🍎+"
        case .multiScale: methodEmoji = "🔍"
        case .scaled: methodEmoji = "📏"
        case .regionOfInterest: methodEmoji = "🎯"
        }
        
        debugInfo.append("Method: \(methodEmoji) \(detectionMethod.displayName)")
        debugInfo.append("Latency: \(processingTimeMs)ms")
        
        // Multi-face detection status
        debugInfo.append("")
        if faceCount > 0 {
            let faceEmoji = faceCount == 1 ? "👤" : "👥"
            debugInfo.append("\(faceEmoji) \(faceCount) FACE\(faceCount == 1 ? "" : "S") DETECTED")
            debugInfo.append("Confidence: \(String(format: "%.2f", detectionConfidence))")
            
            // Show details for primary (first) face
            if let faceRect = faceRect {
                debugInfo.append("Primary: \(Int(faceRect.width))x\(Int(faceRect.height))")
                
                if let headroom = headroomPercentage {
                    let status = isHeadroomInTarget ? "✅ GOOD" : "❌ BAD"
                    debugInfo.append("Primary Headroom: \(String(format: "%.1f", headroom))% \(status)")
                }
                
                // Show group headroom if multiple faces
                if faceCount > 1, let groupHeadroom = groupHeadroomPercentage {
                    let groupStatus = isGroupHeadroomInTarget ? "✅ GOOD" : "❌ BAD"
                    debugInfo.append("Group Headroom: \(String(format: "%.1f", groupHeadroom))% \(groupStatus)")
                }
            }
            
            // Show size info for additional faces
            if faceCount > 1 {
                let otherFaces = Array(allDetectedFaces.dropFirst())
                for (index, face) in otherFaces.enumerated() {
                    let faceNumber = index + 2
                    debugInfo.append("Face \(faceNumber): \(Int(face.rect.width))x\(Int(face.rect.height))")
                }
            }
        } else {
            debugInfo.append("❌ NO FACES")
        }
        
        if let guidance = currentGuidance {
            debugInfo.append("")
            debugInfo.append("🎯 GUIDANCE ACTIVE")
            debugInfo.append("Type: \(guidance.type.rawValue)")
            debugInfo.append("Action: \(guidance.action.debugDescription)")
            debugInfo.append("Confidence: \(String(format: "%.2f", guidance.confidence))")
        } else {
            debugInfo.append("")
            debugInfo.append("💤 No guidance")
        }
        
        debugLabel.text = debugInfo.joined(separator: "\n")
    }
    
    // MARK: - Drawing
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Draw all detected faces with different colors and labels
        for (index, face) in allDetectedFaces.enumerated() {
            let viewFaceRect = convertToViewCoordinates(face.rect)
            
            // Choose color for each face (primary face gets special coloring)
            let faceColor: UIColor
            if index == 0 {
                // Primary face: green if headroom is good, red if bad
                faceColor = isHeadroomInTarget ? .green : .red
            } else {
                // Additional faces: cycle through colors
                let colors: [UIColor] = [.blue, .orange, .purple, .cyan, .magenta]
                faceColor = colors[index % colors.count]
            }
            
            // Draw face rectangle
            context.setStrokeColor(faceColor.cgColor)
            context.setLineWidth(index == 0 ? 3.0 : 2.0) // Primary face gets thicker border
            context.stroke(viewFaceRect)
            
            // Draw face number label
            drawFaceLabel(context: context, faceRect: viewFaceRect, faceNumber: index + 1, color: faceColor)
            
            // Draw headroom indicator only for primary face
            if index == 0, let headroom = headroomPercentage {
                drawHeadroomIndicator(context: context, faceRect: viewFaceRect, headroom: headroom)
            }
        }
        
        // Draw guidance type indicator
        if let guidance = currentGuidance {
            drawGuidanceIndicator(context: context, guidance: guidance)
        }
    }
    
    private func convertToViewCoordinates(_ imageRect: CGRect) -> CGRect {
        // This is a simplified conversion - in practice you'd need the actual
        // camera preview layer transformation
        let scaleX = bounds.width / 1280.0  // Camera resolution width
        let scaleY = bounds.height / 720.0  // Camera resolution height
        
        return CGRect(
            x: imageRect.minX * scaleX,
            y: imageRect.minY * scaleY,
            width: imageRect.width * scaleX,
            height: imageRect.height * scaleY
        )
    }
    
    private func drawHeadroomIndicator(context: CGContext, faceRect: CGRect, headroom: Float) {
        // Draw a line from top of screen to top of face to show headroom
        context.setStrokeColor(UIColor.yellow.cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [5, 5])
        
        let startPoint = CGPoint(x: faceRect.midX, y: 0)
        let endPoint = CGPoint(x: faceRect.midX, y: faceRect.minY)
        
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        
        // Reset line dash
        context.setLineDash(phase: 0, lengths: [])
        
        // Draw headroom percentage text
        let text = "\(String(format: "%.1f", headroom))%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.yellow
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: faceRect.midX - textSize.width / 2,
            y: faceRect.minY / 2 - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawFaceLabel(context: CGContext, faceRect: CGRect, faceNumber: Int, color: UIColor) {
        // Draw face number in top-left corner of face rectangle
        let labelText = "\(faceNumber)"
        let labelSize: CGFloat = 16
        let labelRect = CGRect(
            x: faceRect.minX - 2,
            y: faceRect.minY - labelSize - 4,
            width: labelSize + 4,
            height: labelSize + 4
        )
        
        // Draw background circle
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: labelRect)
        
        // Draw face number
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        
        let textSize = labelText.size(withAttributes: attributes)
        let textRect = CGRect(
            x: labelRect.midX - textSize.width / 2,
            y: labelRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        labelText.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawGuidanceIndicator(context: CGContext, guidance: GuidanceAdvice) {
        // Draw guidance type indicator in bottom right
        let indicatorSize: CGFloat = 20
        let margin: CGFloat = 16
        let indicatorRect = CGRect(
            x: bounds.width - indicatorSize - margin,
            y: bounds.height - indicatorSize - margin,
            width: indicatorSize,
            height: indicatorSize
        )
        
        let color: UIColor
        switch guidance.type {
        case .headroom:
            color = .orange
        case .horizon:
            color = .blue
        case .thirds:
            color = .purple
        case .leadspace:
            color = .cyan
        }
        
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: indicatorRect)
        
        // Draw type letter in the circle
        let letter: String
        switch guidance.type {
        case .headroom: letter = "H"
        case .horizon: letter = "L"
        case .thirds: letter = "T" 
        case .leadspace: letter = "S"
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        
        let textSize = letter.size(withAttributes: attributes)
        let textRect = CGRect(
            x: indicatorRect.midX - textSize.width / 2,
            y: indicatorRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        letter.draw(in: textRect, withAttributes: attributes)
    }
}

// MARK: - Extensions

extension DetectionMethod {
    var displayName: String {
        switch self {
        case .appleVision:
            return "Apple Vision"
        case .appleVisionEnhanced:
            return "Enhanced Vision"
        case .multiScale:
            return "Multi-Scale"
        case .scaled:
            return "Scaled"
        case .regionOfInterest:
            return "ROI"
        }
    }
}

extension GuidanceAction {
    var debugDescription: String {
        switch self {
        case .rotateLeft(let degrees):
            return "Rotate ↺ \(degrees)°"
        case .rotateRight(let degrees):
            return "Rotate ↻ \(degrees)°"
        case .tiltUp(let degrees):
            return "Tilt ↑ \(degrees)°"
        case .tiltDown(let degrees):
            return "Tilt ↓ \(degrees)°"
        case .moveLeft(let percent):
            return "Move ← \(percent)%"
        case .moveRight(let percent):
            return "Move → \(percent)%"
        }
    }
}

extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}