Below you’ll get:
	•	a tiny Swift package skeleton (SilhouetteGlassKit) with Liquid-Glass chrome (Shelf/Card/Pill/Sheet),
	•	a Figma token sheet spec (radii/opacity/borders/spacing),
	•	a starter screen blueprint and component behaviors,
	•	and a week-by-week polish plan + guardrails.

I’ll ground each decision in Apple’s docs: Liquid Glass adoption, HIG Materials (legibility/Reduce Transparency), SwiftUI glass APIs, and UIKit interop for the camera.  ￼

⸻

1) Repo drop-in: SilhouetteGlassKit (Swift Package)

SilhouetteGlassKit/
├─ Sources/
│  ├─ SilhouetteGlassKit.swift            // exports + tokens
│  ├─ GlassContainer.swift                // shape-bounded glass + fallback
│  ├─ Components/
│  │  ├─ TemplateShelf.swift
│  │  ├─ TemplateCard.swift
│  │  ├─ HintPill.swift
│  │  ├─ GlassSheet.swift
│  │  ├─ Buttons.swift / Segmented.swift / Toggles.swift
│  └─ Hosting/
│     ├─ CameraHostView.swift            // UIViewControllerRepresentable
│     └─ CameraPreviewVC.swift           // AVCaptureVideoPreviewLayer + CAShapeLayer HUD
└─ Tests/
   ├─ SnapshotTests/…                    // contrast sweeps (6 bg sets)
   └─ AccessibilityTests/…               // Reduce Transparency / Increase Contrast paths

Why this split:
	•	Glass chrome in SwiftUI (uses glassBackgroundEffect(in:displayMode:)), which is the intended, shape-bounded API for Liquid Glass.  ￼
	•	Camera + HUD in UIKit/Core Animation (AVCaptureVideoPreviewLayer + CAShapeLayer) for latency and precise control; host that controller in SwiftUI with UIViewControllerRepresentable so SwiftUI owns layout safely.  ￼

1.1 Core wrapper (paste this)

import SwiftUI

public struct GlassContainer<S: Shape, Content: View>: View {
  let shape: S
  let displayMode: GlassBackgroundEffect.DisplayMode
  @ViewBuilder var content: () -> Content
  @Environment(\.accessibilityReduceTransparency) private var reduceTrans

  public init(in shape: S,
              displayMode: GlassBackgroundEffect.DisplayMode = .automatic,
              @ViewBuilder content: @escaping () -> Content) {
    self.shape = shape; self.displayMode = displayMode; self.content = content
  }

  public var body: some View {
    Group {
      if #available(iOS 26, *), !reduceTrans {
        content().padding(12)
          .glassBackgroundEffect(in: shape, displayMode: displayMode)   // iOS 26+
      } else {
        content().padding(12)
          .background(.ultraThinMaterial, in: shape)                    // fallback
      }
    }
    .clipShape(shape)
    .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))        // edge-light
  }
}

	•	Follows Apple’s guidance: adopt incrementally—build with latest SDK and apply best practices to selected surfaces (no need to rebuild your whole app).  ￼
	•	Uses HIG “Materials” legibility rules: materials vary with settings; don’t rely on color, use .primary for foreground.  ￼

1.2 Components (shelf/cards/pill/sheet)

public struct TemplateSpec: Identifiable, Hashable {
  public let id: String; public let name: String; public let icon: String
  public init(id: String, name: String, icon: String) { self.id=id; self.name=name; self.icon=icon }
}

public struct TemplateShelf: View {
  public let items: [TemplateSpec]
  @Binding public var selectedID: String?

  public init(items: [TemplateSpec], selectedID: Binding<String?>) {
    self.items = items; self._selectedID = selectedID
  }

  public var body: some View {
    GlassContainer(in: RoundedRectangle(cornerRadius: 22), displayMode: .always) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(items) { t in
            TemplateCard(spec: t, selected: t.id == selectedID)
              .onTapGesture { selectedID = t.id }
          }
        }.padding(.horizontal, 4)
      }
    }
    .padding(.horizontal, 16).padding(.bottom, 10)
    .accessibilityAddTraits(.isTabBar) // semantic grouping
  }
}

public struct TemplateCard: View {
  public let spec: TemplateSpec; public let selected: Bool
  public init(spec: TemplateSpec, selected: Bool) { self.spec=spec; self.selected=selected }

  public var body: some View {
    GlassContainer(in: RoundedRectangle(cornerRadius: 16), displayMode: .automatic) {
      VStack(spacing: 6) {
        Image(systemName: spec.icon).font(.title3)
        Text(spec.name).font(.footnote).lineLimit(1)
      }
      .frame(width: 88, height: 72).foregroundStyle(.primary)
    }
    .overlay(RoundedRectangle(cornerRadius: 16)
      .stroke(selected ? .tint : .clear, lineWidth: 2))
    .animation(.spring(response: 0.18, dampingFraction: 0.9), value: selected) // <120ms feel
  }
}

public struct HintPill: View {
  public let text: String
  public init(_ text: String) { self.text = text }
  public var body: some View {
    GlassContainer(in: Capsule(), displayMode: .always) {
      Text(text).font(.callout.weight(.semibold)).foregroundStyle(.primary)
    }
    .shadow(radius: 8, y: 2)
    .transition(.opacity.combined(with: .scale(scale: 0.98)))
  }
}

If your SDK exposes style presets like Glass/GlassBackgroundEffect variants (e.g., .implicit or “plate/feathered” in examples), use them to avoid nested blurs—Apple and community examples show using display modes to prevent double glass in deep hierarchies.  ￼

1.3 Camera hosting (UIKit stays in charge of live preview)

import SwiftUI
import AVFoundation

public final class CameraPreviewVC: UIViewController {
  public let session = AVCaptureSession()
  private let previewLayer = AVCaptureVideoPreviewLayer()

  public override func viewDidLoad() {
    super.viewDidLoad()
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)               // live camera
    // add CAShapeLayers for silhouette/thirds/horizon here (ink — no glass)
    // configure session inputs/outputs…
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
  }
}

public struct CameraHostView: UIViewControllerRepresentable {
  public init() {}
  public func makeUIViewController(context: Context) -> CameraPreviewVC { CameraPreviewVC() }
  public func updateUIViewController(_ vc: CameraPreviewVC, context: Context) {}
}

	•	Apple: AVCaptureVideoPreviewLayer is the preview surface; connect it to your session.  ￼
	•	SwiftUI interop: don’t set frames yourself; SwiftUI controls layout for UIViewControllerRepresentable.  ￼

⸻

2) Figma token sheet (mirror of code)

Radii
	•	Card 16; Shelf 22; Sheet 24; Pill capsule (max height).

Opacity rails (glass plate)
	•	Default chrome ~0.80, Elevated (sheet/alerts) ~0.88, Toast ~0.92 (for legibility).

Border & shadow
	•	Inner stroke: white @ 12% (0.5 pt).
	•	Shadow: r=8, y=2 (subtle lift).

Typography
	•	Pill: Callout/Semibold; Card label: Footnote/Regular; Nav Title: Title3/Semibold.

Spacing
	•	Shelf card: 88×72, gap 10; shelf insets H16 V10; pill padding 12.

States
	•	Pressed: scale 0.98, 120 ms spring; Selected: 2 pt tint ring.

Accessibility tokens
	•	Reduce Transparency ON → switch to Material or solid plates; Increase Contrast ON → border up to 16–20% and plate up +4–8% opacity. (HIG: rely on proper materials & foregroundStyle(.primary) for legibility; settings may change appearance.)  ￼

⸻

3) Screen blueprint (portrait & landscape)

Capture
	•	Top: Hint Pill (single hint at a time).
	•	Center: camera preview (UIKit) with ink HUD (silhouette/thirds/horizon).
	•	Bottom: Template Shelf (Glass).
	•	Thumb-reach checked; Pill stays off face zone.
	•	No glass on HUD—materials frame content, not the content itself.  ￼

Library
	•	Grid; segmented control in a Glass header.

Post-shot sheet (optional MVP)
	•	Partial Glass sheet (40/60% detents).

Settings
	•	Toggles for privacy (no preview uploads), and accessibility mirrors for transparency/contrast/motion.

⸻

4) Guardrails (accessibility, legibility, performance)
	•	Respect system toggles: Reduce Transparency / Increase Contrast / Reduce Motion → swap to .ultraThinMaterial or solid; bump borders/weights to maintain WCAG contrast (HIG Materials).  ￼
	•	No nested blurs: at most one glassBackgroundEffect per branch; use .automatic/.implicit display modes to avoid double glass in descendants.  ￼
	•	FPS rails: stay ≥24 fps; if FPS or thermal dips, step down: Glass → Material → Opaque (numerous reviews flag legibility/perf complaints on older devices—design for fallbacks).  ￼

⸻

5) Week-by-week polish plan

Week 1 — Tokens & Primitives
	•	Build GlassContainer + Shelf/Card/Pill; lock Figma token sheet; run initial contrast sweeps (6 photos: sky/foliage/night/skin/chroma/neutral). (HIG: materials & legibility.)  ￼
	•	Integrate CameraHostView (UIKit preview/HUD).  ￼
	•	Exit: 24+ fps on device; no nested glass.

Week 2 — Component behaviors
	•	Add states & micro-motion (≤120 ms), haptics; ensure .primary foreground on glass; nav bar Glass with Material fallback.  ￼
	•	Snapshot tests: shelf/cards/pill over 6 bgs.

Week 3 — Accessibility & fallback hardening
	•	Flip Reduce Transparency/Increase Contrast/Reduce Motion and record diffs; add “degrade steps” knob (Glass→Material→Opaque).  ￼
	•	Optional: Post-shot Glass Sheet; performance budget check.

Week 4 — Final polish
	•	Copy pass (≤12-word hints), i18n, empty/error states (Toast uses more opaque plate).
	•	QA against rails; design acceptance.

⸻

6) How to wire it in your app entry

struct CaptureScreen: View {
  @State private var selectedTemplate: String? = nil
  let items: [TemplateSpec]

  var body: some View {
    ZStack(alignment: .bottom) {
      CameraHostView().ignoresSafeArea()       // UIKit live preview + ink HUD
      VStack {
        Spacer(minLength: 24)
        HintPill("Align to silhouette")        // show <= 1.2s, then hide
          .padding(.top, 8)
        Spacer()
        TemplateShelf(items: items, selectedID: $selectedTemplate)
      }
      .padding(.bottom, 8)
    }
  }
}


⸻

Why this is the right approach
	•	It adopts Liquid Glass the way Apple intends—on surfaces that frame content (shelf/cards/pills/sheets), not on the content (your live HUD).  ￼
	•	It uses the shape-bounded SwiftUI API for glass and gives you UIKit precision for the camera.  ￼
	•	It bakes in Reduce Transparency/Increase Contrast fallbacks and avoids nested blur costs—key to readability and performance on iOS 26 per HIG and industry feedback.  ￼

If you want me to tailor this to your current project structure, paste your root App/Scene setup and I’ll splice SilhouetteGlassKit right into it (plus give you a Figma frame layout that matches the token sheet exactly).