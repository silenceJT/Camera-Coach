//
//  TemplateEngine.swift
//  Camera Coach
//
//  Core template management system for the revolutionary silhouette guidance feature.
//  Handles JSON loading, template recommendation, and face-to-template alignment calculations.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - Template Engine Protocol
public protocol TemplateEngineProtocol: AnyObject {
    func loadTemplates() throws
    func recommendTemplate(faceCount: Int, orientation: CameraOrientation, faceSize: TemplateCategory?) -> Template?
    func availableTemplates(for orientation: CameraOrientation) -> [Template]
    func calculateAlignment(faces: [CGRect], template: Template) -> TemplateAlignment
    func allTemplates() -> [Template]
}

// MARK: - Template Engine Implementation
public final class TemplateEngine: TemplateEngineProtocol, ObservableObject {
    // MARK: - Singleton
    public static let shared = TemplateEngine()

    // MARK: - Properties
    private var templates: [Template] = []
    private let logger = Logger.shared
    private let jsonFileName = "templates"

    // MARK: - Current State
    @Published public private(set) var currentTemplate: Template?
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: Error?

    // MARK: - Initialization
    private init() {
        do {
            try loadTemplates()
            print("🎯 TemplateEngine initialized with \(templates.count) templates")
        } catch {
            print("🚨 Failed to initialize TemplateEngine: \(error.localizedDescription)")
            self.loadError = error
        }
    }

    // MARK: - Template Loading
    public func loadTemplates() throws {
        isLoading = true
        loadError = nil

        defer { isLoading = false }

        guard let url = Bundle.main.url(forResource: jsonFileName, withExtension: "json") else {
            throw TemplateEngineError.templateFileNotFound(jsonFileName)
        }

        let data = try Data(contentsOf: url)

        // Handle CGRect decoding
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Custom CGRect decoding
        decoder.dataDecodingStrategy = .deferredToData

        let templateArray = try decoder.decode([TemplateData].self, from: data)

        // Convert TemplateData to Template
        templates = templateArray.compactMap { templateData in
            return Template(
                id: templateData.id,
                category: templateData.category,
                description: templateData.description,
                iconName: templateData.iconName,
                orientation: templateData.orientation,
                headAnchorRect: CGRect(
                    x: templateData.headAnchorRect.x,
                    y: templateData.headAnchorRect.y,
                    width: templateData.headAnchorRect.width,
                    height: templateData.headAnchorRect.height
                ),
                headroomRangePct: templateData.headroomRangePct,
                horizonToleranceDeg: templateData.horizonToleranceDeg,
                flipAllowed: templateData.flipAllowed,
                aspectVariants: templateData.aspectVariants
            )
        }

        print("🎯 Loaded \(templates.count) templates successfully")

        // Log loaded template details
        for template in templates {
            print("🎯 Template loaded: \(template.id) - \(template.category.rawValue) - \(template.orientation.rawValue)")
        }
    }

    // MARK: - Template Recommendation
    public func recommendTemplate(faceCount: Int, orientation: CameraOrientation, faceSize: TemplateCategory? = nil) -> Template? {
        let availableTemplates = templates.filtered(by: orientation).suitable(for: faceCount)

        guard !availableTemplates.isEmpty else {
            print("⚠️ No suitable templates found for \(faceCount) faces, \(orientation.rawValue)")
            return nil
        }

        // Smart recommendation logic based on face count and size
        var recommendedTemplate: Template?

        if faceCount == 1 {
            // Single person - prefer based on estimated size or default to close_up
            let targetCategory = faceSize ?? .close_up
            recommendedTemplate = availableTemplates.filtered(by: targetCategory).first

            // Fallback to any single-person template if specific category not found
            if recommendedTemplate == nil {
                recommendedTemplate = availableTemplates.first { $0.category.expectedSubjectCount == 1 }
            }
        } else if faceCount >= 2 {
            // Multiple people - prefer couple or group templates
            recommendedTemplate = availableTemplates.filtered(by: .couple).first

            // Fallback to any multi-person suitable template
            if recommendedTemplate == nil {
                recommendedTemplate = availableTemplates.first { $0.category == .couple }
            }
        }

        // Ultimate fallback - first available template
        if recommendedTemplate == nil {
            recommendedTemplate = availableTemplates.first
        }

        if let template = recommendedTemplate {
            print("🎯 Recommended template: \(template.id) for \(faceCount) faces")
        } else {
            print("⚠️ No template recommendation possible")
        }

        return recommendedTemplate
    }

    // MARK: - Template Queries
    public func availableTemplates(for orientation: CameraOrientation) -> [Template] {
        return templates.filtered(by: orientation)
    }

    public func allTemplates() -> [Template] {
        return templates
    }

    public func template(with id: String) -> Template? {
        return templates.template(with: id)
    }

    public func templates(for category: TemplateCategory) -> [Template] {
        return templates.filtered(by: category)
    }

    // MARK: - Template Alignment Calculation
    public func calculateAlignment(faces: [CGRect], template: Template) -> TemplateAlignment {
        guard !faces.isEmpty else {
            return TemplateAlignment.noMatch
        }

        // Use primary face (largest) for alignment calculation
        let primaryFace = faces.max { face1, face2 in
            face1.width * face1.height < face2.width * face2.height
        } ?? faces[0]

        return calculateAlignment(face: primaryFace, template: template)
    }

    private func calculateAlignment(face: CGRect, template: Template) -> TemplateAlignment {
        let faceCenter = CGPoint(x: face.midX, y: face.midY)
        let templateCenter = template.headCenter

        // Calculate offsets (-1 to 1 scale)
        let offsetX = Float(faceCenter.x - templateCenter.x)
        let offsetY = Float(faceCenter.y - templateCenter.y)

        // Calculate distance from ideal position
        let distance = sqrt(offsetX * offsetX + offsetY * offsetY)

        // Calculate confidence based on distance (closer = higher confidence)
        let maxDistance: Float = 0.5 // Maximum meaningful distance across frame
        let confidence = max(0.0, 1.0 - (distance / maxDistance))

        // Check if within acceptable threshold
        let threshold = Config.templateAlignmentThresholdPct / 100.0 // Convert percentage to decimal
        let withinThreshold = distance <= threshold

        let alignment = TemplateAlignment(
            offsetX: offsetX,
            offsetY: offsetY,
            confidence: confidence,
            withinThreshold: withinThreshold,
            distance: distance
        )

        print("🎯 Template alignment calculated: offset(\(offsetX), \(offsetY)), distance: \(distance), within threshold: \(withinThreshold)")

        return alignment
    }

    // MARK: - Template Management
    public func setCurrentTemplate(_ template: Template?) {
        if currentTemplate?.id != template?.id {
            currentTemplate = template

            if let template = template {
                print("🎯 Current template set to: \(template.id)")
            } else {
                print("🎯 Current template cleared")
            }
        }
    }

    // MARK: - Template Flipping (for flipAllowed templates)
    public func flippedTemplate(_ template: Template) -> Template? {
        guard template.flipAllowed else { return nil }

        // Create horizontally flipped version
        let flippedRect = CGRect(
            x: 1.0 - template.headAnchorRect.maxX,
            y: template.headAnchorRect.minY,
            width: template.headAnchorRect.width,
            height: template.headAnchorRect.height
        )

        return Template(
            id: template.id + "_flipped",
            category: template.category,
            description: template.description + " (翻转)",
            iconName: template.iconName,  // Preserve icon from original template
            orientation: template.orientation,
            headAnchorRect: flippedRect,
            headroomRangePct: template.headroomRangePct,
            horizonToleranceDeg: template.horizonToleranceDeg,
            flipAllowed: template.flipAllowed,
            aspectVariants: template.aspectVariants
        )
    }
}

// MARK: - Template Data Structure for JSON Decoding
private struct TemplateData: Codable {
    let id: String
    let category: TemplateCategory
    let description: String
    let iconName: String  // SF Symbol name for UI display
    let orientation: CameraOrientation
    let headAnchorRect: RectData
    let headroomRangePct: HeadroomRange
    let horizonToleranceDeg: Float
    let flipAllowed: Bool
    let aspectVariants: [String]
}

private struct RectData: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Template Engine Errors
public enum TemplateEngineError: Error, LocalizedError {
    case templateFileNotFound(String)
    case invalidTemplateData
    case templateLoadingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .templateFileNotFound(let fileName):
            return "Template file '\(fileName).json' not found in bundle"
        case .invalidTemplateData:
            return "Template data is invalid or corrupted"
        case .templateLoadingFailed(let error):
            return "Failed to load templates: \(error.localizedDescription)"
        }
    }
}

// MARK: - Template Engine Extensions
extension TemplateEngine {
    /// Get templates suitable for current device orientation
    public var portraitTemplates: [Template] {
        return availableTemplates(for: .portrait)
    }

    public var landscapeTemplates: [Template] {
        return availableTemplates(for: .landscape)
    }

    /// Get templates grouped by category
    public var templatesByCategory: [TemplateCategory: [Template]] {
        return Dictionary(grouping: templates) { $0.category }
    }

    /// Check if templates are loaded and ready
    public var isReady: Bool {
        return !templates.isEmpty && !isLoading && loadError == nil
    }
}