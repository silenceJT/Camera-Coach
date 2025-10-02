//
//  SilhouettePositioningTests.swift
//  Camera Coach Tests
//
//  Validation tests for silhouette positioning accuracy across all templates.
//  Ensures headAnchorRect coordinates produce correct visual output on multiple device sizes.
//

import XCTest
@testable import Camera_Coach

final class SilhouettePositioningTests: XCTestCase {
    var templateEngine: TemplateEngine!
    var renderer: SilhouetteRenderer!

    // Test device screen sizes (iPhone 12 Pro, 14 Pro, 15 Pro Max)
    let testDevices: [(name: String, size: CGSize)] = [
        ("iPhone 12 Pro", CGSize(width: 390, height: 844)),
        ("iPhone 14 Pro", CGSize(width: 393, height: 852)),
        ("iPhone 15 Pro Max", CGSize(width: 430, height: 932)),
        ("iPhone 17 Pro", CGSize(width: 402, height: 874))
    ]

    override func setUp() {
        super.setUp()
        templateEngine = TemplateEngine.shared

        // Verify templates loaded successfully
        XCTAssertTrue(templateEngine.isReady, "TemplateEngine should be ready with loaded templates")
    }

    override func tearDown() {
        renderer = nil
        super.tearDown()
    }

    // MARK: - Template Loading Validation

    func testTemplatesLoadedSuccessfully() {
        let allTemplates = templateEngine.allTemplates()

        XCTAssertEqual(allTemplates.count, 8, "Should have exactly 8 templates (4 portrait + 4 landscape)")

        // Verify all templates have required fields
        for template in allTemplates {
            XCTAssertFalse(template.id.isEmpty, "Template \(template.id): id must not be empty")
            XCTAssertFalse(template.description.isEmpty, "Template \(template.id): description must not be empty")
            XCTAssertFalse(template.iconName.isEmpty, "Template \(template.id): iconName must not be empty")
        }
    }

    func testTemplateIconNamesValid() {
        let allTemplates = templateEngine.allTemplates()

        for template in allTemplates {
            // Verify iconName is a valid SF Symbol
            let image = UIImage(systemName: template.iconName)
            XCTAssertNotNil(image, "Template \(template.id): iconName '\(template.iconName)' must be a valid SF Symbol")
        }
    }

    // MARK: - HeadAnchorRect Bounds Validation

    func testHeadAnchorRectWithinBounds() {
        let allTemplates = templateEngine.allTemplates()

        for template in allTemplates {
            let rect = template.headAnchorRect

            // Validate normalized coordinates (0-1 range)
            XCTAssertGreaterThanOrEqual(rect.minX, 0.0,
                "Template \(template.id): headAnchorRect.minX must be >= 0")
            XCTAssertLessThanOrEqual(rect.maxX, 1.0,
                "Template \(template.id): headAnchorRect.maxX must be <= 1")
            XCTAssertGreaterThanOrEqual(rect.minY, 0.0,
                "Template \(template.id): headAnchorRect.minY must be >= 0")
            XCTAssertLessThanOrEqual(rect.maxY, 1.0,
                "Template \(template.id): headAnchorRect.maxY must be <= 1")

            // Validate rect has positive dimensions
            XCTAssertGreaterThan(rect.width, 0.0,
                "Template \(template.id): headAnchorRect.width must be > 0")
            XCTAssertGreaterThan(rect.height, 0.0,
                "Template \(template.id): headAnchorRect.height must be > 0")
        }
    }

    // MARK: - Silhouette Rendering Validation

    func testSilhouetteRenderingForAllTemplates() {
        let portraitTemplates = templateEngine.availableTemplates(for: .portrait)

        // Test on primary device size (iPhone 14 Pro)
        let primaryDevice = testDevices[1] // iPhone 14 Pro
        renderer = SilhouetteRenderer(frame: CGRect(origin: .zero, size: primaryDevice.size))

        for template in portraitTemplates {
            renderer.updateTemplate(template, animated: false)

            // Verify silhouette was created
            XCTAssertNotNil(renderer.layer.sublayers,
                "Template \(template.id): Silhouette layer should be created")

            // Verify layer is visible
            let hasVisibleSublayer = renderer.layer.sublayers?.contains { layer in
                layer.opacity > 0 && !layer.isHidden
            } ?? false

            XCTAssertTrue(hasVisibleSublayer,
                "Template \(template.id): Should have visible silhouette layer")
        }
    }

    func testSilhouettePositionAccuracy() {
        // Test specific template with known coordinates
        guard let fullBodyTemplate = templateEngine.template(with: "portrait_full_left_thirds") else {
            XCTFail("portrait_full_left_thirds template not found")
            return
        }

        let deviceSize = CGSize(width: 393, height: 852) // iPhone 14 Pro
        renderer = SilhouetteRenderer(frame: CGRect(origin: .zero, size: deviceSize))
        renderer.updateTemplate(fullBodyTemplate, animated: false)

        // Expected position based on template coordinates
        // headAnchorRect: x: 0.15, y: 0.2, width: 0.15, height: 0.25
        let expectedCenterX = deviceSize.width * (0.15 + 0.15/2) // x + width/2
        let expectedCenterY = deviceSize.height * (0.2 + 0.25/2) // y + height/2

        // Validate silhouette exists and has correct bounds
        if let silhouetteLayer = renderer.layer.sublayers?.first(where: { $0 is CAShapeLayer }) as? CAShapeLayer {
            let actualBounds = silhouetteLayer.frame

            // Allow 10pt tolerance for rendering precision
            let tolerance: CGFloat = 10.0

            XCTAssertEqual(actualBounds.midX, expectedCenterX, accuracy: tolerance,
                "Silhouette horizontal center should match template specification")
            XCTAssertEqual(actualBounds.midY, expectedCenterY, accuracy: tolerance,
                "Silhouette vertical center should match template specification")
        } else {
            XCTFail("Silhouette CAShapeLayer not found")
        }
    }

    // MARK: - Multi-Device Size Validation

    func testSilhouetteScalingAcrossDevices() {
        guard let template = templateEngine.template(with: "portrait_full_left_thirds") else {
            XCTFail("Template not found")
            return
        }

        for device in testDevices {
            renderer = SilhouetteRenderer(frame: CGRect(origin: .zero, size: device.size))
            renderer.updateTemplate(template, animated: false)

            // Verify silhouette scales proportionally to device size
            let expectedWidth = device.size.width * CGFloat(template.headAnchorRect.width)
            let expectedHeight = device.size.height * CGFloat(template.headAnchorRect.height)

            if let silhouetteLayer = renderer.layer.sublayers?.first(where: { $0 is CAShapeLayer }) as? CAShapeLayer {
                let actualBounds = silhouetteLayer.frame

                let tolerance: CGFloat = 15.0 // Allow 15pt tolerance for different screen sizes

                XCTAssertEqual(actualBounds.width, expectedWidth, accuracy: tolerance,
                    "Device \(device.name): Silhouette width should scale correctly")
                XCTAssertEqual(actualBounds.height, expectedHeight, accuracy: tolerance,
                    "Device \(device.name): Silhouette height should scale correctly")
            }
        }
    }

    // MARK: - Template Category Validation

    func testTemplateCategoriesDistribution() {
        let allTemplates = templateEngine.allTemplates()
        let categoryCounts = Dictionary(grouping: allTemplates) { $0.category }
            .mapValues { $0.count }

        // Verify we have templates for each category
        XCTAssertEqual(categoryCounts[.full_body], 2, "Should have 2 full_body templates (portrait + landscape)")
        XCTAssertEqual(categoryCounts[.half_body], 2, "Should have 2 half_body templates (portrait + landscape)")
        XCTAssertEqual(categoryCounts[.close_up], 2, "Should have 2 close_up templates (portrait + landscape)")
        XCTAssertEqual(categoryCounts[.couple], 2, "Should have 2 couple templates (portrait + landscape)")
    }

    func testTemplateOrientationSplit() {
        let allTemplates = templateEngine.allTemplates()
        let orientationCounts = Dictionary(grouping: allTemplates) { $0.orientation }
            .mapValues { $0.count }

        XCTAssertEqual(orientationCounts[.portrait], 4, "Should have 4 portrait templates")
        XCTAssertEqual(orientationCounts[.landscape], 4, "Should have 4 landscape templates")
    }

    // MARK: - Template Flipping Validation

    func testTemplateFlippingPreservesProperties() {
        guard let originalTemplate = templateEngine.template(with: "portrait_full_left_thirds") else {
            XCTFail("Template not found")
            return
        }

        guard let flippedTemplate = templateEngine.flippedTemplate(originalTemplate) else {
            XCTFail("Template should allow flipping")
            return
        }

        // Verify flipped template preserves essential properties
        XCTAssertEqual(flippedTemplate.category, originalTemplate.category, "Category should be preserved")
        XCTAssertEqual(flippedTemplate.iconName, originalTemplate.iconName, "Icon should be preserved")
        XCTAssertEqual(flippedTemplate.orientation, originalTemplate.orientation, "Orientation should be preserved")

        // Verify flipped rect is horizontally mirrored
        let originalX = originalTemplate.headAnchorRect.minX
        let flippedX = flippedTemplate.headAnchorRect.minX
        let expectedFlippedX = 1.0 - originalTemplate.headAnchorRect.maxX

        XCTAssertEqual(flippedX, expectedFlippedX, accuracy: 0.001,
            "Flipped template should be horizontally mirrored")
    }

    // MARK: - Headroom Range Validation

    func testHeadroomRangesValid() {
        let allTemplates = templateEngine.allTemplates()

        for template in allTemplates {
            let range = template.headroomRangePct

            // Validate range is positive and reasonable
            XCTAssertGreaterThan(range.min, 0.0,
                "Template \(template.id): headroom min must be > 0")
            XCTAssertLessThan(range.max, 1.0,
                "Template \(template.id): headroom max must be < 1 (100%)")
            XCTAssertLessThan(range.min, range.max,
                "Template \(template.id): headroom min must be < max")

            // Validate range is within reasonable composition bounds (5-20%)
            XCTAssertGreaterThanOrEqual(range.min, 0.05,
                "Template \(template.id): headroom min should be >= 5%")
            XCTAssertLessThanOrEqual(range.max, 0.20,
                "Template \(template.id): headroom max should be <= 20%")
        }
    }

    // MARK: - Performance Validation

    func testTemplateLoadingPerformance() {
        measure {
            // Measure template loading performance
            _ = templateEngine.allTemplates()
        }
    }

    func testSilhouetteRenderingPerformance() {
        guard let template = templateEngine.template(with: "portrait_full_left_thirds") else {
            XCTFail("Template not found")
            return
        }

        let deviceSize = CGSize(width: 393, height: 852)
        renderer = SilhouetteRenderer(frame: CGRect(origin: .zero, size: deviceSize))

        measure {
            // Measure silhouette rendering performance
            renderer.updateTemplate(template, animated: false)
        }
    }
}
