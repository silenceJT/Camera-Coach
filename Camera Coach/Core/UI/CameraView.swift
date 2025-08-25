//
//  CameraView.swift
//  Camera Coach
//
//  SwiftUI wrapper for the camera view controller.
//  Bridges UIKit camera functionality to SwiftUI.
//

import SwiftUI
import UIKit

public struct CameraView: UIViewControllerRepresentable {
    // MARK: - Properties
    @ObservedObject private var logger = Logger.shared
    
    // MARK: - UIViewControllerRepresentable
    public func makeUIViewController(context: Context) -> CameraViewController {
        let cameraVC = CameraViewController()
        cameraVC.delegate = context.coordinator
        return cameraVC
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Handle any updates if needed
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    public class Coordinator: NSObject, CameraViewControllerDelegate {
        private let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        // MARK: - CameraViewControllerDelegate
        public func cameraViewControllerDidStartSession(_ viewController: CameraViewController) {
            // Log session start
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            let deviceModel = UIDevice.current.model
            let osVersion = UIDevice.current.systemVersion
            
            parent.logger.startSession(build: build, deviceModel: deviceModel, osVersion: osVersion)
        }
        
        public func cameraViewControllerDidStopSession(_ viewController: CameraViewController) {
            parent.logger.stopSession()
        }
        
        public func cameraViewController(_ viewController: CameraViewController, didUpdateFrame features: FrameFeatures) {
            // Handle frame updates - this will be connected to the guidance engine later
            // For Week 1, we just log performance metrics
        }
        
        public func cameraViewController(_ viewController: CameraViewController, didEncounterError error: Error) {
            // Handle camera errors
            print("Camera error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Camera View Controller
public final class CameraViewController: UIViewController {
    // MARK: - Properties
    public weak var delegate: CameraViewControllerDelegate?
    
    private let cameraController = CameraController()
    private let hudView = GuidanceHUDView()
    private let cameraView = UIView()
    
    private var isSessionActive = false
    
    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCameraSession()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCameraSession()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraController.updatePreviewLayerFrame(cameraView.bounds)
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
        
        // Setup constraints
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            hudView.topAnchor.constraint(equalTo: view.topAnchor),
            hudView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hudView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hudView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Hide status bar for full-screen camera experience
        setNeedsStatusBarAppearanceUpdate()
    }
    
    private func setupCamera() {
        do {
            try cameraController.setupCamera(in: cameraView)
            cameraController.delegate = self
        } catch {
            print("Failed to setup camera: \(error.localizedDescription)")
            showCameraError(error)
        }
    }
    
    // MARK: - Camera Session Management
    private func startCameraSession() {
        guard !isSessionActive else { return }
        
        cameraController.startSession()
        isSessionActive = true
        delegate?.cameraViewControllerDidStartSession(self)
    }
    
    private func stopCameraSession() {
        guard isSessionActive else { return }
        
        cameraController.stopSession()
        isSessionActive = false
        delegate?.cameraViewControllerDidStopSession(self)
    }
    
    // MARK: - Error Handling
    private func showCameraError(_ error: Error) {
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
}

// MARK: - Camera Controller Delegate
extension CameraViewController: CameraControllerDelegate {
    public func cameraController(_ controller: CameraController, didUpdateFrame features: FrameFeatures) {
        // Update HUD with frame features
        hudView.updateHorizonAngle(features.horizonDegrees)
        
        // Delegate frame update to SwiftUI coordinator
        delegate?.cameraViewController(self, didUpdateFrame: features)
    }
    
    public func cameraController(_ controller: CameraController, didEncounterError error: Error) {
        delegate?.cameraViewController(self, didEncounterError: error)
    }
}

// MARK: - Protocol
public protocol CameraViewControllerDelegate: AnyObject {
    func cameraViewControllerDidStartSession(_ viewController: CameraViewController)
    func cameraViewControllerDidStopSession(_ viewController: CameraViewController)
    func cameraViewController(_ viewController: CameraViewController, didUpdateFrame features: FrameFeatures)
    func cameraViewController(_ viewController: CameraViewController, didEncounterError error: Error)
}
