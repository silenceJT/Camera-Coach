Summary

There is no existing official or open-source component that directly implements the iOS Camera-style “horizon + two side dashes with thirds grid.”

But Apple provides the critical low-level capability:
	•	AVCaptureDevice.RotationCoordinator gives real-time, gravity-aligned rotation angles.
	•	With this, you can implement a zero-latency, jitter-free overlay.
	•	The middle horizon line comes from RotationCoordinator, while the side dashes and thirds grid must be drawn yourself using CAShapeLayer.
	•	videoRotationAngleForHorizonLevelPreview supports main-thread KVO callbacks, and Apple explicitly recommends updating UI directly in those callbacks to avoid delay, lag, or artifacts. This matches your requirement of no delay/lag/shake.

⸻

1) Existing solutions / references
	•	Apple Official
	•	AVCaptureDevice.RotationCoordinator: tracks device orientation vs gravity and provides compensation angles for preview/capture.
	•	videoRotationAngleForHorizonLevelPreview: observable with KVO; delivered on main thread; recommended for direct UI updates.
	•	Apply to preview/capture via AVCaptureConnection.videoRotationAngle.
	•	Core Motion (fallback / compatibility)
	•	CMMotionManager / CMDeviceMotion.attitude.roll/pitch/yaw: sensor-fused attitude, hardware-dependent max update rate (often ≥100Hz). Can add custom filtering/prediction.
	•	Apple’s “Bubble Level” sample shows using attitude angles for a leveling UI.
	•	Drawing
	•	Use CAShapeLayer for high-frame-rate, GPU-accelerated vector drawing. Avoid bitmap redraws each frame.

No open-source project was found that exactly replicates iOS Camera’s “horizon + side dashes.” Existing repos are unrelated (bottom sheets, prompts, bubble level demos). You need to combine the above pieces yourself.

⸻

2) Zero-latency implementation plan

2.1 Data source (prefer RotationCoordinator)

let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
let previewLayer = AVCaptureVideoPreviewLayer(session: session)
let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer) // iOS 17+

	•	Angle updates: Observe videoRotationAngleForHorizonLevelPreview with KVO. Delivered on main thread, so you can update the overlay directly with no queue hops, avoiding jitter/delay.
	•	For older iOS or if you need prediction, fall back to CMMotionManager.deviceMotion. But prefer RotationCoordinator because it matches AVFoundation’s preview pipeline.

2.2 Geometry (final design we agreed on)
	•	Grid: vertical thirds x1=W/3, x2=2W/3; horizontal thirds y1=H/3, y2=2H/3; midline cy=(y1+y2)/2.
	•	Middle line (world horizon): passes (cx=W/2, cy+cyOffset), slope from θ: y(x) = cy + (x − cx)*tanθ.
	•	Left & right dashes: fixed at y=cy (same as middle line’s center), horizontal, with side gaps:
	•	Left: [x1−sideGap−dashLen, x1−sideGap] × {cy}
	•	Right: [x2+sideGap, x2+sideGap+dashLen] × {cy}
	•	Merged state: when |θ| ≤ mergeDegOn, animate gapX → 0 over 150–200 ms. sideGap stays. Visually appears as one line.

2.3 Drawing layers (no jitter)
	•	Pre-create 3 CAShapeLayers (left, center, right). Update only their paths on KVO or CADisplayLink.
	•	Disable implicit animations to avoid “dragging” effects:

CATransaction.begin()
CATransaction.setDisableActions(true)
leftLayer.path   = leftPath
centerLayer.path = centerPath
rightLayer.path  = rightPath
CATransaction.commit()

2.4 Timing & anti-jitter
	•	Update trigger:
	•	Preferred: directly in videoRotationAngleForHorizonLevelPreview KVO main-thread callback. Apple recommends this to avoid lag.
	•	Optional: use CADisplayLink (60Hz) to poll the angle and update in sync with screen refresh.
	•	Filtering:
	•	Goal: “zero perceptible delay.” So don’t over-filter. RotationCoordinator already fuses sensors.
	•	At most, apply a very light low-pass filter (α≈0.1–0.15) and use hysteresis thresholds (mergeDegOn/mergeDegOff) to stabilize merge/split transitions.
	•	Stay on main thread: KVO is delivered there; don’t offload to another queue or async debounce timer, which would add visible lag.

2.5 Preview alignment (optional)
	•	If you also want the preview itself to auto-level, apply:

previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview

Apple recommends this approach.

2.6 Performance monitoring
	•	Use OSSignposter to measure “angle → geometry → path update,” confirm p95 < 0.2 ms.
	•	In Instruments, check for jank or frame drops.
	•	Post-launch, monitor with MetricKit for crashes, hangs, and power.

⸻

3) Minimal code skeleton

final class HorizonOverlay: UIView {
    private let left = CAShapeLayer(), center = CAShapeLayer(), right = CAShapeLayer()
    private let coordinator: AVCaptureDevice.RotationCoordinator
    private var cx: CGFloat { bounds.width*0.5 }
    private var cy: CGFloat { bounds.height*0.5 + cyOffset }

    init(coordinator: AVCaptureDevice.RotationCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        [left, center, right].forEach { L in
            L.lineWidth = 2.5; L.lineCap = .round; L.fillColor = nil
            layer.addSublayer(L)
        }
        // KVO on main thread per Apple’s recommendation
        coordinator.addObserver(self,
            forKeyPath: #keyPath(AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelPreview),
            options: [.initial, .new], context: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func observeValue(forKeyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let deg = change?[.newKey] as? CGFloat else { return }
        layoutSegments(angleDeg: deg) // direct update on main thread, zero lag
    }

    private func layoutSegments(angleDeg: CGFloat) {
        let θ = angleDeg * .pi/180
        let t = tan(θ)
        // Compute final geometry here (middle horizon + left/right dashes with sideGap)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        left.path   = leftPath
        center.path = centerPath
        right.path  = rightPath
        CATransaction.commit()
    }
}

Here, leftPath, centerPath, rightPath are built from the confirmed final geometry. KVO triggers on the main thread, so UI responds instantly.

⸻

4) Common pitfalls
	•	Front camera mirroring: invert angle / mirror geometry for consistent behavior.
	•	Device orientation changes: RotationCoordinator accounts for gravity, but ensure overlay coordinate space updates with interface orientation.
	•	Anti-jitter: avoid timers/debounce; only use light low-pass + hysteresis.
	•	Performance: don’t enable Core Image filters or forced rasterization on layers — it hurts resolution and speed.

⸻

Takeaway
	•	There’s no plug-and-play component.
	•	But with RotationCoordinator (gravity-aligned angle, main-thread KVO), and CAShapeLayer overlay drawing, you can build exactly the iOS Camera-style horizon guide: middle line aligned to world horizon, side dashes fixed at mid height with gaps, zero delay, no jitter.

This design is already validated by Apple’s guidance: update overlay directly in KVO callbacks for lowest latency.
