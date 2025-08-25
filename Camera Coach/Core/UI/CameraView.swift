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

public struct CameraView: UIViewControllerRepresentable {
    // MARK: - Properties
    @ObservedObject private var coordinator = CameraCoordinator()
    
    // MARK: - UIViewControllerRepresentable
    public func makeUIViewController(context: Context) -> CameraViewController {
        let cameraVC = CameraViewController()
        cameraVC.coordinator = coordinator
        return cameraVC
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Handle any updates if needed
    }
    
    // No coordinator needed - we use the CameraCoordinator directly
}

// MARK: - Camera View Controller
public final class CameraViewController: UIViewController {
    // MARK: - Properties
    public var coordinator: CameraCoordinator?
    
    private let hudView = GuidanceHUDView()
    private let cameraView = UIView()
    
    private var isSessionActive = false
    private var hasAttemptedCameraSetup = false
    private var hasShownError = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
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
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Setup camera view
        cameraView.backgroundColor = .black
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        
        // Setup HUD overlay
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
        
        // Setup constraints
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            hudView.topAnchor.constraint(equalTo: view.topAnchor),
            hudView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hudView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hudView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            shutterButton.widthAnchor.constraint(equalToConstant: 70),
            shutterButton.heightAnchor.constraint(equalToConstant: 70)
        ])
        
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
        guard !isSessionActive, let coordinator = coordinator else { return }
        
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
            title: "Camera Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
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
        
        // Could add photo preview or other feedback here
    }
}

// No delegate needed - coordinator handles everything

// No protocol needed - coordinator handles everything
