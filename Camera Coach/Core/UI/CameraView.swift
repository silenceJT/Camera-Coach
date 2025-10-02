//
//  CameraView.swift
//  Camera Coach
//
//  SwiftUI wrapper for the camera view controller.
//  Bridges UIKit camera functionality to SwiftUI.
//

import SwiftUI
import UIKit
import Combine

public struct CameraView: View {
    // MARK: - Properties
    @ObservedObject private var coordinator = CameraCoordinator()
    
    // MARK: - Body
    public var body: some View {
        CameraViewControllerRepresentable(
            coordinator: coordinator,
            onPhotoTaken: {
                // Silent metric collection only - no UI interruption
            }
        )
    }
}

// MARK: - UIViewControllerRepresentable Wrapper
private struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    let coordinator: CameraCoordinator
    let onPhotoTaken: () -> Void
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let cameraVC = CameraViewController()
        cameraVC.coordinator = coordinator
        cameraVC.onPhotoTaken = onPhotoTaken
        return cameraVC
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Handle any updates if needed
    }
}

// MARK: - Camera View Controller
public final class CameraViewController: UIViewController {
    // MARK: - Properties
    public var coordinator: CameraCoordinator?
    public var onPhotoTaken: (() -> Void)?
    
    private let hudView = GuidanceHUDView()
    private let cameraView = UIView()

    // 🚀 NEW: Template System UI Components
    private let silhouetteRenderer = SilhouetteRenderer()
    private var templateSelectorHostingController: Any?  // UIHostingController<GlassShelfWrapper> for iOS 26+
    private var templateEngine: TemplateEngine?

    // Template selection state
    private var selectedTemplateID: String?
    private var selectedCategory: TemplateCategory?

    // 🚀 WEEK 3: Debug view to visualize face detection
    private let debugView = FaceDetectionDebugView()
    private var showDebugMode = false  // Set to false for production, true for debugging
    
    private var isSessionActive = false
    private var hasAttemptedCameraSetup = false
    private var hasShownError = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupTemplateEngine()
        setupUI()
        // Don't setup camera here - wait for view layout
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Don't start session here - wait for camera setup
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCameraSession()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Only setup once when bounds are valid and camera not already active
        if !isSessionActive && !hasAttemptedCameraSetup && view.bounds.width > 0 && view.bounds.height > 0 {
            hasAttemptedCameraSetup = true
            setupCamera()
        }
    }
    
    // MARK: - Template Engine Setup
    private func setupTemplateEngine() {
        templateEngine = TemplateEngine.shared
    }

    @available(iOS 26.0, *)
    private func setupGlassShelf() {
        let currentOrientation: CameraOrientation = .portrait // TODO: Get from device
        let templates = templateEngine!.availableTemplates(for: currentOrientation)

        let shelfWrapper = GlassShelfWrapper(
            templates: templates,
            onTemplateSelected: { [weak self] template in
                self?.handleTemplateSelection(template)
            },
            onCategorySelected: { [weak self] category in
                self?.handleCategorySelection(category)
            }
        )

        let hostingController = UIHostingController(rootView: shelfWrapper)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        templateSelectorHostingController = hostingController as Any
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func handleTemplateSelection(_ template: Template?) {
        guard let template = template else {
            // Deselection - clear silhouette
            silhouetteRenderer.clearTemplate(animated: true)
            coordinator?.setCurrentTemplate(nil)
            print("🎯 Template deselected in CameraView")
            return
        }

        // Update silhouette renderer
        silhouetteRenderer.updateTemplate(template, animated: true)

        // Update coordinator's guidance engine
        coordinator?.setCurrentTemplate(template)

        print("🎯 Template selected in CameraView: \(template.id)")
    }

    private func handleCategorySelection(_ category: TemplateCategory?) {
        print("🎯 Category selected in CameraView: \(category?.rawValue ?? "all")")
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .black

        // Setup camera view with letterbox (center area only, like iOS Camera)
        cameraView.backgroundColor = .black
        cameraView.layer.cornerRadius = 0
        cameraView.clipsToBounds = true
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)

        // 🚀 NEW: Setup silhouette renderer overlay
        silhouetteRenderer.backgroundColor = .clear
        silhouetteRenderer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(silhouetteRenderer)

        // Setup HUD overlay (now simplified for template system)
        hudView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hudView)

        // 🚀 CRITICAL FIX: Connect HUD to coordinator for horizon updates
        coordinator?.setHUDView(hudView)

        // Setup shutter button
        let shutterButton = UIButton(type: .system)
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 35
        shutterButton.layer.borderWidth = 4
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.addTarget(self, action: #selector(shutterButtonTapped), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        // 🚀 NEW: Setup Glass Shelf at bottom (SwiftUI with iOS 26 Liquid Glass)
        if #available(iOS 26.0, *) {
            setupGlassShelf()
        }

        // 🚀 WEEK 3: Add debug view to visualize face detection
        if showDebugMode {
            debugView.backgroundColor = .clear
            debugView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(debugView)
        }
        
        // Observe coordinator for guidance updates
        coordinator?.$currentGuidance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] guidance in
                if let guidance = guidance {
                    self?.hudView.showGuidance(guidance)
                } else {
                    self?.hudView.hideGuidance()
                }
            }
            .store(in: &cancellables)
        
        // 🚀 WEEK 3: Observe enhanced face detection for debugging
        coordinator?.$enhancedFaceResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self = self, self.showDebugMode, let result = result else { return }
                self.debugView.updateEnhancedFaceDetection(result: result)
            }
            .store(in: &cancellables)
        
        // 🚀 WEEK 3: Connect debug view strategy changes to coordinator
        if showDebugMode {
            debugView.onStrategyChanged = { [weak self] strategy in
                self?.coordinator?.setFaceDetectionStrategy(strategy)
            }
        }
        
        // Setup constraints - iOS Camera app layout (per frame_capture_portrait.svg)
        //
        // SVG-ACCURATE LAYOUT (Bottom-up):
        // 1. Shutter: At bottom (y=793 in SVG)
        // 2. Template Shelf: ABOVE shutter (y=652 in SVG)
        // 3. Camera: Fills top area (y=112-640 in SVG)

        let shutterSize: CGFloat = 70
        let shelfHeight: CGFloat = 90  // Per SVG design
        let shutterToBottomGap: CGFloat = 40  // Gap between shutter and screen bottom
        let shelfToShutterGap: CGFloat = 18   // Gap between shelf and shutter
        let cameraToShelfGap: CGFloat = 12    // Gap between camera and shelf

        var constraints: [NSLayoutConstraint] = []

        // Glass Shelf constraints (iOS 26+ only)
        if #available(iOS 26.0, *),
           let hostingController = templateSelectorHostingController as? UIViewController,
           let shelfView = hostingController.view {
            constraints += [
                // Shutter at bottom (per SVG y=793)
                shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -shutterToBottomGap),
                shutterButton.widthAnchor.constraint(equalToConstant: shutterSize),
                shutterButton.heightAnchor.constraint(equalToConstant: shutterSize),

                // Template Shelf ABOVE shutter (per SVG y=652)
                shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                shelfView.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -shelfToShutterGap),
                shelfView.heightAnchor.constraint(equalToConstant: shelfHeight),

                // Camera fills space above shelf (per SVG y=112-640)
                cameraView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                cameraView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                cameraView.bottomAnchor.constraint(equalTo: shelfView.topAnchor, constant: -cameraToShelfGap),
            ]
        } else {
            // Fallback for iOS <26: simple layout without shelf
            constraints += [
                shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -shutterToBottomGap),
                shutterButton.widthAnchor.constraint(equalToConstant: shutterSize),
                shutterButton.heightAnchor.constraint(equalToConstant: shutterSize),

                cameraView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                cameraView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                cameraView.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -cameraToShelfGap),
            ]
        }

        constraints += [

            // 🚀 NEW: Silhouette renderer overlays camera area
            silhouetteRenderer.topAnchor.constraint(equalTo: cameraView.topAnchor),
            silhouetteRenderer.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            silhouetteRenderer.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            silhouetteRenderer.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),

            // HUD overlays camera area (simplified for template system)
            hudView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            hudView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            hudView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            hudView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor)
        ]
        
        // 🚀 WEEK 3: Add debug view constraints if enabled (only over camera area)
        if showDebugMode {
            constraints.append(contentsOf: [
                debugView.topAnchor.constraint(equalTo: cameraView.topAnchor),
                debugView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
                debugView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
                debugView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor)
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        // Hide status bar for full-screen camera experience
        setNeedsStatusBarAppearanceUpdate()
    }
    
    private func setupCamera() {
        guard let coordinator = coordinator else { return }
        
        do {
            try coordinator.setupCamera(in: cameraView)
            
            // Setup level indicator after camera is configured
            if let hudView = coordinator.hudView {
                coordinator.cameraController.setupLevelIndicator(for: hudView)
            }
            
            // Start the camera session immediately after setup
            coordinator.startSession()
            isSessionActive = true
        } catch {
            showCameraError(error)
        }
    }
    
    // MARK: - Camera Session Management
    private func startCameraSession() {
        guard !isSessionActive, let coordinator = coordinator else { return }
        
        coordinator.startSession()
        isSessionActive = true
    }
    
    private func stopCameraSession() {
        guard isSessionActive, let coordinator = coordinator else { return }
        
        coordinator.stopSession()
        isSessionActive = false
    }
    
    // MARK: - Error Handling
    private func showCameraError(_ error: Error) {
        // Only show error once to prevent multiple alerts
        guard !hasShownError else {
            return
        }
        
        hasShownError = true
        
        let alert = UIAlertController(
            title: NSLocalizedString("camera.error.title", comment: "Camera error alert title"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("camera.error.ok", comment: "Camera error OK button"), style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Status Bar
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    // MARK: - Actions
    @objc private func shutterButtonTapped() {
        coordinator?.onShutter()
        
        // Show a simple photo taken feedback
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        
        // Silent metric collection handled by coordinator
        onPhotoTaken?()
    }
}

