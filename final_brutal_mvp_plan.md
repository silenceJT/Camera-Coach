# MVP Camera Coach — Final Brutal MVP Plan (Consolidated)
**Date:** 2025-08-25 • **Last Updated:** 2025-10-02 (Post-Design Audit - CRITICAL FIXES REQUIRED)
**Owner:** JT • **Scope:** 12-week solo MVP (iOS 26+, iPhone 12 Pro+)

## 🚨 CRITICAL ISSUES IDENTIFIED (2025-10-02 Design Review)

### **Architectural Debt Before Launch**
1. **DUPLICATE UI CODE**: Both UIKit `TemplateSelector.swift` (631 lines) AND SwiftUI `GlassComponents.swift` (317 lines) exist
   - **Week 7 Day 1 BLOCKER**: DELETE UIKit version entirely
   - **Code Reduction**: 948 lines → 317 lines (66% reduction)

2. **DESIGN TOKEN MISMATCH**: Code doesn't match SVG specifications
   | Component | Design Spec | UIKit Reality | SwiftUI Reality | Status |
   |-----------|-------------|---------------|-----------------|--------|
   | Shelf radius | 22pt | 28pt ❌ | 22pt ✅ | SPLIT |
   | Card size | **88×72pt** | 85×85pt ❌ | 56×56pt ❌ | **BOTH WRONG** |
   | Card radius | **16pt** | 12pt ❌ | 12pt ❌ | **BOTH WRONG** |
   | Card spacing | **10pt** | 16pt ❌ | 12pt ❌ | **BOTH WRONG** |

3. **FAKE LIQUID GLASS API**: Using `.ultraThinMaterial` (iOS 15 API), NOT real `glassBackgroundEffect` (iOS 26 API)
   - Current `GlassComponents.swift:35` uses old Material API
   - **Required**: Implement actual `glassBackgroundEffect(in:displayMode:)` iOS 26+ API

4. **MISSING VALIDATION**: No automated tests proving silhouette renders at correct position
   - Templates define precise `headAnchorRect` coordinates
   - **Zero evidence** these produce correct visual output
   - **Risk**: Silhouettes may be misaligned on device

5. **INCOMPLETE JSON SCHEMA**: `templates.json` missing `iconName` field
   - Code expects `template.category.iconName` but JSON doesn't define it
   - Will cause icon lookup failures

---

This is the **final, modified** version of the MVP plan incorporating:

### **Core System Upgrades**
1) Deterministic hint arbitration (FSM): **templateAlignment > headroom > thirds**, stability **≥300ms**, cooldown per rule **≥600ms**
2) KPI events and gates: **hint_shown → hint_adopted(≤10s) → shutter → kept**; weekly releases gated on one-shot success & stability
3) **Replay harness by Week 3**; tune thresholds offline on every commit
4) **Hard-ban digital zoom**; only suggest movement (10–20 cm) or **1×/2×** lens switch
5) **Privacy UX now**: post-shot cloud **opt-in**, default OFF, Wi-Fi-only, daily cap, delete-all button
6) **Thermal-aware behavior**: when thermal ≥ fair or fps <24, drop heavy analyses & reduce prompts/min, **auto-disable glass**

### **🚀 NEW: Liquid Glass Design Integration (Week 7)**
7) **Glass-only on chrome**: Template shelf, cards, and hint pills use iOS 26+ `glassBackgroundEffect` with graceful fallback to `.ultraThinMaterial` (iOS 25) or opaque fills (`Reduce Transparency`)
8) **Crisp content preservation**: Silhouette outlines, HUD grid, and level indicators remain crisp vector strokes (NO glass blur)
9) **Performance-gated**: Glass rendering capped at 2fps impact; auto-disable when `fps <24` or `thermalState ≥ .fair`
10) **Accessibility-first**: Respects system settings; opaque mode with elevated borders for users with `Reduce Transparency` enabled

---

## 1) Background & Problem
- Typical users (esp. “boyfriend photographer” scenarios) struggle with **horizon tilt**, **headroom**, **subject proportion**, and **composition**.
- Pro camera apps overload users with manual controls; **AI coach** should be **one actionable sentence** at a time, not a lecture.
- MVP focuses on **real-time guidance** (not post-processing) with **on-device** inference for privacy, cost, and latency.

### North Star - **REVOLUTIONARY SILHOUETTE GUIDANCE**
- **Intuitive Success**: template selection → silhouette alignment → shutter ≤ **4s** and the photo is **kept** (revolutionary reduction in learning curve)
- **Differentiation**: World's first silhouette-guided camera app with template-based composition assistance

### Success Metrics (Week Gates) - **UPDATED FOR SILHOUETTE SYSTEM**
- Week 6 gate: **Template system functional**, basic silhouette rendering working
- Week 10 gate: one-shot **≥75%**, Sat **≥4.3/5**, 7-day crash **<1%** (significant improvement expected from intuitive silhouette guidance)
- Week 12 launch: Market-ready revolutionary silhouette guidance system

---

## 2) Constraints & Non-Goals
**Hard constraints**
- Devices: iPhone 12 Pro+; iOS 17+; preview **720p** at 30fps (24fps fallback).  
- Live loop latency **p95 ≤ 80ms**; prompts/min ≤ 8.  
- On-device analysis only in preview path; post-shot cloud optional.

**Non-goals (MVP)**
- No beauty filters/skin retouch; no portrait blur; no AR overlays; no digital zoom hints; no third-party analytics or camera SDKs.

---

## 3) Tech Stack & Dependencies
- **Language:** Swift 6.0+; iOS 26+ (iOS 25 fallback support)
- **UI:** SwiftUI (shell + **Liquid Glass chrome**) + **UIKit** (camera VC & HUD overlay)
- **Liquid Glass:** `glassBackgroundEffect` (iOS 26+), `.ultraThinMaterial` fallback (iOS <26)
- **Camera:** AVFoundation (`AVCaptureSession(.hd1280x720)`, BGRA)
- **Analysis:** Vision (face rects), CoreMotion (roll/pitch), simple image ops (edge density)
- **Haptics:** `UIImpactFeedbackGenerator(.light)`
- **Telemetry:** MetricKit + structured CSV/JSON logs (no third-party SDK)
- **CI/CD:** Fastlane or Xcode Cloud → weekly TestFlight
- **PM:** SPM only; SwiftFormat/SwiftLint via SPM plugin (no runtime deps)

---

## 4) Architecture (Clean & Deterministic) - **ENHANCED FOR LIQUID GLASS + TEMPLATES**
```
UIKit Camera VC → Analyzer (Vision + CoreMotion) → GuidanceEngine (FSM) → Silhouette + HUD (crisp)
                                               ↗ TemplateEngine (JSON templates)        ↘
                                               ↘ Logger (events/metrics)                 GlassUI (iOS 26+)
                                                                                        └─ GlassShelf/Cards/Pill
SwiftUI screens ⇄ Camera VC via UIViewControllerRepresentable
```

**Modules - UPDATED FOR LIQUID GLASS**
- **CameraController (UIKit):** session, preview layer, video data output (background queue)
- **FrameAnalyzer:** face rects (Vision), horizon angle (CoreMotion), headroom %, face-to-template alignment
- **TemplateEngine:** JSON template parsing, silhouette rendering, auto-recommendation based on face count/orientation
- **GuidanceEngine (FSM):** priority **TemplateAlignment > headroom > horizon > thirds**; stability **≥300ms**; template-aware cooldowns
- **SilhouetteOverlay:** Real-time silhouette rendering with 30% opacity (crisp, NO glass)
- **HUDOverlay:** Grid/lines/indicators (crisp vector strokes, NO glass)
- **GlassUI Components (NEW - Week 7):**
  - **GlassShelf:** Horizontal template carousel with `glassBackgroundEffect` (iOS 26+) or `.ultraThinMaterial` (fallback)
  - **GlassCard:** Individual template buttons, 16px radius, 80-90% opacity, ≤120ms spring animations
  - **GlassPill:** Transient guidance hints, capsule shape, 90% opacity, auto-hide ≤1.2s
  - **Accessibility:** Respects `Reduce Transparency` → opaque fills
- **Logger & PerformanceMonitor:** Enhanced with template metrics + glass performance tracking

**Realtime budget**
- p95 frame loop ≤ **80ms**; sustained fps **≥24**; zero main-thread stalls in analyzer

---

## 5) Core Algorithms (MVP)
### 5.1 Horizon (CoreMotion)
- `roll` low-pass (α≈0.1–0.2); trigger `rotate_left/right` if |θ|>3°; round to nearest 1–2°; hysteresis 0.5–1°.

### 5.2 Face & Headroom (Vision)
- Primary face = largest/nearest to center; ignore very small boxes (<2% screen height).  
- Headroom target: **7–12%** frame height → `tilt_up/down` with bounded magnitude.

### 5.3 Thirds (Geometric)
- Compute subject bbox center vs thirds intersections. Fire only when face **stable ≥300ms**, horizon within ±3°, headroom in target. Output `move_left/right` nudge.

### 5.4 Orientation & Lead Space (Week 7+)
- Approximate facing side from bbox motion / landmarks; prefer leaving space on the facing side.

### 5.5 Edge Merge Avoidance (Week 7+)
- Simple Sobel/Canny edge density near bbox borders; if high on one side → nudge away to avoid “merging with strong line”.

---

## 6) Guidance FSM (Deterministic Arbitration)
**States:** `idle → analyzing → hint_cooldown`  
**Guards:** stability ≥300ms; **priority:** headroom > horizon > thirds; cooldown per rule ≥600ms; global ≤2 prompts/sec; post-shutter global cooldown 1.5s.  
**Output:** `GuidanceAdvice {{ action, amount, reason, confidence, cooldownMs }}` — **single** advice at a time.  
**Success window:** hint considered **adopted** if target metric reached within 10s.

---

## 7) UX Copy & Behavior - **LIQUID GLASS INTERACTION MODEL**

### **Guidance Text (GlassPill)**
- **Tone:** *Affirm → Suggest → Reason* (e.g., "Looks steady. Tilt up 5° for better headroom.")
- Max ~12 words; one sentence; fade in/out ≤1.2s; light haptic on change
- **Never** show two hints simultaneously
- Global spam control: ≤2 prompts/sec; same-type ≤3/10s; prompts/min ≤8

**Examples**
- "Horizon leans right. Rotate left 3°. Nice—hold that."
- "Face is low. Raise the phone a little."
- "Shift right slightly to balance the frame."

### **Liquid Glass Motion Specs (Week 7+)**
- **Template Selection:** ≤120ms spring animation (`response: 0.18, dampingFraction: 0.9`)
- **Glass Opacity:** Shelf/cards 80-90%, hint pill 90% (higher for legibility over varied backgrounds)
- **Haptic Feedback:** Light impact on template switch, medium impact on alignment achievement
- **Glass Layering:** Never nest glass >1 level deep (performance constraint)
- **Thermal/FPS Degradation:** Auto-disable glass when `thermalState ≥ .fair` OR `fps < 24`
- **Accessibility:** Respect `Reduce Transparency` → switch to opaque fills with elevated borders

---

## 8) Privacy & Data
- **Live preview**: local-only; no uploads.  
- **Post-shot cloud (optional)**: default OFF; Wi-Fi-only; daily cap (e.g., 5/day); visible queue; **Delete All** action.  
- **App Privacy labels**: camera access; diagnostics only; no tracking. Strip EXIF location from analysis artifacts.

---

## 9) Performance, Thermal & Power - **LIQUID GLASS AWARE**
- When `thermalState ≥ .fair` or fps <24: drop heavy analyses (edge density), clamp prompts/min ≤6, switch 30→24fps, **disable glass rendering**
- Pre-allocate buffers; reuse `VNSequenceRequestHandler`; avoid allocations in hot path
- **Glass Performance Budget:** Glass rendering must NOT cause fps drop >2fps; monitor with `fps_sample` events
- **Glass Layer Optimization:** Pre-render glass layers at session start; never re-composite during frame processing

---

## 10) Analytics & KPIs (Exact Events) - **GLASS PERFORMANCE TRACKING**
```
session_start {build, device_model, os_version, glass_available: bool}
session_stop {duration_s}
hint_shown {type: horizon|headroom|thirds|leadspace|template_alignment, confidence, rule_version}
hint_adopted {type, adopted: true/false, latency_ms, before:{metric}, after:{metric}}
shutter {mode: single|burst, latency_from_first_hint_ms}
photo_kept {kept: true/false}
fps_sample {avg, p95}
thermal_sample {state: nominal|fair|serious|critical}
consent_changed {postshot_cloud: on/off}

# NEW: Liquid Glass Telemetry (Week 7+)
glass_component_rendered {type: shelf|card|pill, fallback_mode: glass|material|opaque}
glass_perf_impact {fps_before, fps_after, thermal_state, render_mode}
glass_degradation {reason: thermal|fps|accessibility, component_type}
template_selected {id, category, auto_recommended: bool}
template_alignment_achieved {template_id, time_to_align_ms}
```
**Gates by week** are enforced via dashboards to mark a release "Go" or "No-Go".

---

## 11) Roadmap (12 Weeks Overview) - **UPDATED FOR SILHOUETTE TEMPLATE SYSTEM**

### **Weeks 1-5: Foundation (COMPLETED)**
- **W1**: Camera + HUD + telemetry + FSM skeleton + internal TF
- **W2**: Horizon guidance + one-sentence coach + TF#1
- **W3**: Face + headroom + **replay harness** + TF#2
- **W4**: Thirds + **Privacy settings** (post-shot consent OFF) + TF#3
- **W5**: Thermal guard + fps fallback + stability/perf polish

### **Weeks 6-12: REVOLUTIONARY SILHOUETTE + LIQUID GLASS SYSTEM**
- **W6**: **SILHOUETTE TEMPLATE FOUNDATION** ✅ COMPLETE
  - Template engine + JSON parsing + basic rendering + GuidanceEngine refactor for template priority

- **W7**: **LIQUID GLASS UI POLISH** 🚨 CRITICAL REFACTOR (5-7 days)
  - **Day 1 BLOCKER:** 🔥 **DELETE `TemplateSelector.swift` (631 lines)** - complete SwiftUI migration
    - Migrate all `CameraCoordinator` integration to SwiftUI `GlassShelf`
    - Update `CameraView.swift` to embed `GlassShelf` via `UIHostingController`
    - **DoD**: Zero references to `TemplateSelector`, app compiles and runs
  - **Day 2:** Fix design token mismatches to match SVG spec EXACTLY
    - Card size: 56×56pt → **88×72pt** (per `board_glass_primitives.svg`)
    - Card radius: 12pt → **16pt**
    - Card spacing: 12pt → **10pt**
    - **DoD**: Screenshot comparison vs SVG shows pixel-perfect match
  - **Day 3:** Implement **REAL** `glassBackgroundEffect` API (iOS 26+)
    - Replace `.ultraThinMaterial` with `glassBackgroundEffect(in:displayMode:)`
    - Proper fallback: `glassBackgroundEffect` (iOS 26) → `.ultraThinMaterial` (iOS 25) → opaque (accessibility)
    - **DoD**: Glass uses real iOS 26 API on compatible devices
  - **Day 4:** Fix template JSON schema
    - Add `iconName` field to all 8 templates in `templates.json`
    - Update `Template.swift` Codable struct to include `iconName: String`
    - Add JSON schema validation test
    - **DoD**: Icons load from JSON, validation passes
  - **Day 5 CRITICAL:** Silhouette positioning validation
    - Create automated screenshot test suite for all 8 templates
    - Validate `headAnchorRect` coordinates produce correct silhouette position
    - Test on multiple screen sizes (iPhone 12 Pro, 14 Pro, 15 Pro Max)
    - **DoD**: Visual regression tests prove correct alignment
  - **Day 6:** Refactor `GuidanceHUDView` → `GlassPill`
    - Replace UIKit label with SwiftUI `GlassPill` via `UIHostingController`
    - Auto-hide ≤1.2s, iOS 26+ glass API
    - **DoD**: Guidance hints use glass capsule, accessibility tested
  - **Day 7:** Performance & accessibility validation
    - Contrast sweeps over 6 varied backgrounds
    - FPS validation (glass must NOT cause >2fps drop)
    - Thermal testing (auto-disable at `.fair`)
    - Accessibility modes (`Reduce Transparency`, `Increase Contrast`)
    - **DoD**: All budgets met, accessibility works
  - **Week 7 DoD (ALL MUST PASS):**
    - ✅ Zero UIKit template code (pure SwiftUI)
    - ✅ Design tokens match SVG exactly (88×72pt, 16pt radius, 10pt spacing)
    - ✅ Real iOS 26+ `glassBackgroundEffect` API used
    - ✅ Template JSON complete with `iconName`
    - ✅ All 8 templates have positioning validation tests
    - ✅ Glass respects accessibility, fps ≥24, auto-disable on thermal ≥.fair

- **W8**: **ADVANCED MATCHING & OPTIMIZATION** - Aspect ratio adaptation + flip support + glass performance tuning
- **W9**: **COMPLETE TEMPLATE LIBRARY** - All 8 JSON templates + scene-aware recommendation + internal testing (10 users)
- **W10**: **EXTERNAL A/B TESTING** - Silhouette vs traditional guidance + 20+ users: **one-shot ≥75%, sat ≥4.3, crash <1%**
- **W11**: **POLISH & FINAL OPTIMIZATION** - Data-driven parameter tuning + glass contrast sweeps + UX refinements
- **W12**: **REVOLUTIONARY LAUNCH** - First silhouette + Liquid Glass camera app + App Store marketing + KPI monitoring

> **MAJOR PIVOT**: From traditional text-based guidance to revolutionary silhouette template system based on user's innovative JSON template design. This transforms Camera Coach from a "photography suggestion app" to an "intuitive composition guidance app" with expected 60%→75%+ success rate improvement.

> Full weekly breakdown with DoD is available in `docs/weeks/week-01.md` … `week-12.md` (generated already).

---

## 12) Repo Layout (Cursor-friendly)
```
App/
  Application/
  Core/
    Camera/            // CameraController.swift, PreviewLayer, session
    Analyzer/          // FrameAnalyzer.swift (Vision, CoreMotion), FrameFeatures.swift
    Guidance/          // GuidanceEngine.swift (FSM, rules), Config.swift
    UI/                // GuidanceHUDView.swift (UIKit view), SwiftUI wrapper
    Infra/             // Logger.swift, PerformanceMonitor.swift
  Resources/
    Prompts/           // CoachPrompts.json (copy library)
docs/
  ENGINEERING-RULES.md
  ANALYTICS.md
  PRIVACY.md
  ARCHITECTURE.md
  REPLAY-HARNESS.md
  ROADMAP.md
  weeks/week-01.md … week-12.md
```

---

## 13) Interfaces & Stubs (for Cursor to generate code)

### 13.1 `FrameFeatures.swift` - **ENHANCED FOR TEMPLATES**
```swift
public struct FrameFeatures {
    // Legacy features (preserved)
    public var horizonDegrees: Float   // +right / -left
    public var faceRect: CGRect?       // normalized [0,1] coords, primary face
    public var faceStableMs: Int       // ms face center variance below threshold
    public var headroomPct: Float?     // % of frame height
    public var edgeMergeScore: Float?  // 0..1 near face borders (optional)

    // Template system features (NEW)
    public var faceRects: [CGRect]     // All detected faces for multi-person templates
    public var faceCount: Int          // Total number of detected faces
    public var currentTemplate: Template?  // Currently active template
    public var templateAlignment: TemplateAlignment?  // Face-to-template alignment data
    public var recommendedTemplate: Template?  // Auto-recommended template based on scene
}

public struct TemplateAlignment {
    public var offsetX: Float          // Horizontal offset percentage
    public var offsetY: Float          // Vertical offset percentage
    public var confidence: Float       // Alignment confidence 0-1
    public var withinThreshold: Bool   // Whether alignment is acceptable
}
```

### 13.2 `GuidanceAdvice.swift` - **ENHANCED FOR TEMPLATES**
```swift
public enum GuidanceAction {
    // Legacy actions (preserved)
    case rotateLeft(deg: Int), rotateRight(deg: Int),
         tiltUp(deg: Int), tiltDown(deg: Int),
         moveLeft(pct: Int), moveRight(pct: Int)

    // Template-specific actions (NEW)
    case alignToTemplate(offsetX: Float, offsetY: Float)  // Precise template alignment
    case switchTemplate(to: Template)                      // Recommend different template
    case adjustForTemplate(direction: String, amount: Float)  // "Move up 2cm to match silhouette"
}

public struct GuidanceAdvice {
    public var action: GuidanceAction
    public var reason: String      // short phrase
    public var confidence: Float   // 0..1
    public var cooldownMs: Int     // suggested min cooldown before next hint
    public var type: GuidanceType  // template_alignment, headroom, horizon, thirds
    public var relatedTemplate: Template?  // Associated template if applicable
}

public enum GuidanceType: String, CaseIterable {
    case templateAlignment = "template_alignment"  // NEW: Highest priority
    case headroom = "headroom"
    case horizon = "horizon"
    case thirds = "thirds"
    case leadspace = "leadspace"
}
```

### 13.3 `GuidanceEngine.swift` (contract)
```swift
protocol FrameFeaturesProvider {
    func latest() -> FrameFeatures?
}

final class GuidanceEngine {
    // Tunables (see Config.swift)
    private let stabilityMs = 300
    private let ruleCooldownMs = 600
    private let globalMaxPromptsPerSec = 2

    enum State { case idle, analyzing, hintCooldown(Date) }
    private var state: State = .idle

    func nextAdvice(from f: FrameFeatures) -> GuidanceAdvice? {
        // 1) Stability check (≥300ms)
        // 2) Priority: headroom > horizon > thirds
        // 3) Emit at most one advice, then enter cooldown
        // 4) Global post-shutter cooldown handled externally
        return nil // implement
    }

    func onShutter() { /* enter 1.5s global cooldown */ }
}
```

### 13.4 `Config.swift` (central tunables) - **ENHANCED FOR LIQUID GLASS + TEMPLATES**
```swift
enum Config {
    // Legacy guidance (still used as fallback)
    static let targetHeadroomPct: ClosedRange<Float> = 7.0...12.0
    static let horizonThresholdDeg: Float = 3.0

    // Template system configuration
    static let templateAlignmentThresholdPct: Float = 5.0  // When to trigger template alignment guidance
    static let silhouetteOpacity: Float = 0.3              // 30% opacity for silhouette overlay
    static let templateAnimationDuration: TimeInterval = 0.4
    static let autoTemplateRecommendation: Bool = true     // Auto-recommend templates based on face count

    // FSM timing (unchanged)
    static let stabilityMs = 300
    static let ruleCooldownMs = 600
    static let globalMaxPromptsPerSec = 2
    static let postShutterCooldownMs = 1500
    static let promptsPerMinuteCap = 8

    // Template-specific cooldowns
    static let templateSwitchCooldownMs = 1000             // Prevent rapid template switching
    static let templateAlignmentCooldownMs = 500           // Template alignment guidance cooldown

    // 🚀 LIQUID GLASS DESIGN TOKENS (Week 7 Day 2 - CORRECTED TO MATCH SVG)
    // Source: board_glass_primitives.svg + frame_capture_portrait.svg

    // Corner Radii (CORRECTED)
    static let glassShelfCornerRadius: CGFloat = 22        // ✅ Shelf radius (matches SVG)
    static let glassCardCornerRadius: CGFloat = 16         // ✅ CORRECTED from 12pt → 16pt per SVG
    static let glassPillCornerRadius: CGFloat = 999        // Capsule (max radius)

    // Card Dimensions (NEW - were missing, causing wrong sizes)
    static let glassCardWidth: CGFloat = 88                // ✅ NEW: 88pt width per SVG spec
    static let glassCardHeight: CGFloat = 72               // ✅ NEW: 72pt height per SVG spec

    // Spacing (CORRECTED)
    static let glassCardSpacing: CGFloat = 10              // ✅ CORRECTED from 12pt/16pt → 10pt per SVG

    // Opacities (UNCHANGED - correct)
    static let glassShelfOpacity: Float = 0.85             // 85% opacity for shelf
    static let glassCardOpacity: Float = 0.90              // 90% opacity for cards (higher legibility)
    static let glassPillOpacity: Float = 0.92              // 92% opacity for hint pill (highest legibility)
    static let glassBorderOpacity: Float = 0.12            // White border at 12% opacity
    static let glassBorderWidth: CGFloat = 0.5             // Thin border stroke

    // Shadows (UNCHANGED)
    static let glassShadowRadius: CGFloat = 8              // Subtle shadow
    static let glassShadowOffsetY: CGFloat = 2             // Shadow y-offset

    // Animation (UNCHANGED)
    static let glassAnimationDuration: TimeInterval = 0.12 // 120ms spring animation
    static let glassSpringResponse: Double = 0.18          // Spring response
    static let glassSpringDamping: Double = 0.9            // Spring damping fraction

    // Performance (UNCHANGED)
    static let glassMaxFPSImpact: Float = 2.0              // Max fps drop allowed with glass
    static let glassDisableOnThermalFair: Bool = true      // Auto-disable at thermal .fair
    static let glassMaxNestingDepth: Int = 1               // Never nest glass >1 level
}
```

### 13.5 `Logger.swift` (event names)
- Use the **exact** event names from §10.

### 13.6 `CameraController.swift` (essentials)
- `AVCaptureSession(.hd1280x720)` + `AVCaptureVideoDataOutput` (BGRA), background queue
- `AVCaptureVideoPreviewLayer` `.resizeAspectFill`
- Deliver frames to `FrameAnalyzer` off-main; update HUD on main

### 13.7 `Template.swift` + `TemplateEngine.swift` - **CORRECTED WITH iconName (Week 7 Day 4)**

**BEFORE (CURRENT - INCOMPLETE):**
```swift
public struct Template: Codable, Identifiable {
    public let id: String
    public let category: TemplateCategory
    public let description: String
    // ❌ Missing iconName field - causes icon lookup failures
    public let orientation: CameraOrientation
    public let headAnchorRect: CGRect
    public let headroomRangePct: HeadroomRange
    public let horizonToleranceDeg: Float
    public let flipAllowed: Bool
    public let aspectVariants: [String]
}
```

**AFTER (WEEK 7 DAY 4 - COMPLETE):**
```swift
// Template data structure with complete schema
public struct Template: Codable, Identifiable {
    public let id: String
    public let category: TemplateCategory
    public let description: String
    public let iconName: String  // ✅ NEW: Icon name loaded from JSON (not hardcoded)
    public let orientation: CameraOrientation
    public let headAnchorRect: CGRect  // Normalized 0-1 coordinates
    public let headroomRangePct: HeadroomRange
    public let horizonToleranceDeg: Float
    public let flipAllowed: Bool
    public let aspectVariants: [String]  // ["9:16", "3:4"]
}

public enum TemplateCategory: String, CaseIterable, Codable {
    case full_body, half_body, close_up, couple
}

public struct HeadroomRange: Codable {
    public let min: Float, max: Float
}

// Template Engine - Core template management system
public protocol TemplateEngineProtocol {
    func loadTemplates() throws
    func recommendTemplate(faceCount: Int, orientation: CameraOrientation, faceSize: TemplateCategory?) -> Template?
    func availableTemplates(for orientation: CameraOrientation) -> [Template]
    func renderSilhouette(for template: Template, in frame: CGRect) -> CAShapeLayer
    func calculateAlignment(faces: [CGRect], template: Template) -> TemplateAlignment
}

final class TemplateEngine: TemplateEngineProtocol {
    private var allTemplates: [Template] = []
    private let jsonFileName = "templates.json"  // User's JSON template file

    func loadTemplates() throws { /* Load from JSON */ }
    func recommendTemplate(faceCount: Int, orientation: CameraOrientation, faceSize: TemplateCategory?) -> Template? { /* Auto-recommendation logic */ }
    // ... implement other methods
}
```

**CORRECTED templates.json Schema (Week 7 Day 4):**

**BEFORE (CURRENT - INCOMPLETE):**
```json
{
  "id": "portrait_full_left_thirds",
  "category": "full_body",
  "description": "全身，主体位于左三分之一",
  // ❌ Missing iconName field
  "orientation": "portrait",
  "headAnchorRect": { "x": 0.15, "y": 0.2, "width": 0.15, "height": 0.25 },
  ...
}
```

**AFTER (WEEK 7 DAY 4 - COMPLETE):**
```json
{
  "id": "portrait_full_left_thirds",
  "category": "full_body",
  "description": "全身，主体位于左三分之一",
  "iconName": "person.fill",  // ✅ NEW: Icon name for UI display
  "orientation": "portrait",
  "headAnchorRect": { "x": 0.15, "y": 0.2, "width": 0.15, "height": 0.25 },
  "headroomRangePct": { "min": 0.07, "max": 0.12 },
  "horizonToleranceDeg": 3,
  "flipAllowed": true,
  "aspectVariants": ["9:16", "3:4"]
}
```

**Template JSON Validation Test (Week 7 Day 4):**
```swift
// TemplateSchemaTests.swift - NEW FILE
import XCTest
@testable import Camera_Coach

final class TemplateSchemaTests: XCTestCase {
    func testTemplateJSONSchemaComplete() throws {
        let engine = TemplateEngine()
        try engine.loadTemplates()

        let templates = try engine.availableTemplates(for: .portrait)

        for template in templates {
            // Validate all required fields present
            XCTAssertFalse(template.id.isEmpty, "\(template.id): id must not be empty")
            XCTAssertFalse(template.description.isEmpty, "\(template.id): description must not be empty")
            XCTAssertFalse(template.iconName.isEmpty, "\(template.id): iconName must not be empty")  // ✅ NEW

            // Validate iconName is valid SF Symbol
            XCTAssertNotNil(UIImage(systemName: template.iconName),
                           "\(template.id): iconName '\(template.iconName)' is not a valid SF Symbol")

            // Validate headAnchorRect within bounds
            XCTAssertGreaterThanOrEqual(template.headAnchorRect.minX, 0.0)
            XCTAssertLessThanOrEqual(template.headAnchorRect.maxX, 1.0)
            XCTAssertGreaterThanOrEqual(template.headAnchorRect.minY, 0.0)
            XCTAssertLessThanOrEqual(template.headAnchorRect.maxY, 1.0)
        }
    }
}
```


### 13.8 `GlassContainer.swift` - **CORRECTED LIQUID GLASS IMPLEMENTATION (Week 7 Day 3)**

**BEFORE (CURRENT - WRONG):**
```swift
// Line 35 in GlassComponents.swift - FAKE LIQUID GLASS
shape.fill(.ultraThinMaterial)  // ❌ This is iOS 15 Material API, NOT Liquid Glass
```

**AFTER (WEEK 7 DAY 3 - CORRECT):**
```swift
import SwiftUI

// Reusable glass wrapper with REAL iOS 26+ Liquid Glass API
struct GlassContainer<S: Shape, Content: View>: View {
    let shape: S
    let displayMode: GlassBackgroundEffect.DisplayMode
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTrans
    @Environment(\.colorScheme) private var scheme

    init(in shape: S,
         displayMode: GlassBackgroundEffect.DisplayMode = .automatic,
         @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.displayMode = displayMode
        self.content = content
    }

    var body: some View {
        Group {
            if #available(iOS 26, *), !reduceTrans {
                // ✅ REAL Liquid Glass API (iOS 26+)
                content()
                    .padding(12)
                    .glassBackgroundEffect(in: shape, displayMode: displayMode)
            } else if #available(iOS 15, *), !reduceTrans {
                // iOS 25 fallback - Material API
                content()
                    .padding(12)
                    .background(.ultraThinMaterial, in: shape)
            } else {
                // Accessibility fallback - opaque with elevated border
                content()
                    .padding(12)
                    .background(Color(uiColor: .systemBackground).opacity(0.95), in: shape)
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                Color.white.opacity(reduceTrans ? 0.2 : Config.glassBorderOpacity),
                lineWidth: reduceTrans ? 1.0 : Config.glassBorderWidth
            )
        )
    }
}

// Glass Shelf - horizontal template carousel (Week 7 refactor)
struct GlassShelf: View {
    let templates: [Template]
    @Binding var selectedID: String?

    var body: some View {
        GlassContainer(in: RoundedRectangle(cornerRadius: Config.glassShelfCornerRadius), displayMode: .always) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(templates) { t in
                        GlassCard(template: t, isSelected: t.id == selectedID)
                            .onTapGesture { selectedID = t.id }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// Glass Card - individual template button (Week 7 Day 2 - CORRECTED DIMENSIONS)
struct GlassCard: View {
    let template: Template
    let isSelected: Bool

    var body: some View {
        GlassContainer(in: RoundedRectangle(cornerRadius: Config.glassCardCornerRadius), displayMode: .automatic) {
            VStack(spacing: 6) {
                Image(systemName: template.iconName).font(.title3)
                Text(template.shortName).font(.footnote).lineLimit(1)
            }
            .frame(width: Config.glassCardWidth, height: Config.glassCardHeight)  // ✅ 88×72pt per SVG spec
            .foregroundStyle(.primary)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Config.glassCardCornerRadius)  // ✅ 16pt radius
                .stroke(isSelected ? .tint : .clear, lineWidth: 2)
        )
        .animation(.spring(response: Config.glassSpringResponse, dampingFraction: Config.glassSpringDamping), value: isSelected)
    }
}

// Glass Pill - transient guidance hint (Week 7 refactor)
struct GlassPill: View {
    let text: String

    var body: some View {
        GlassContainer(in: Capsule(), displayMode: .always) {
            Text(text)
                .font(.callout.weight(.semibold))
        }
        .shadow(radius: Config.glassShadowRadius, y: Config.glassShadowOffsetY)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
```

### 13.9 `SilhouetteRenderer.swift` - **SILHOUETTE (NO GLASS, KEEP CRISP)**
```swift
// High-performance silhouette rendering - NO GLASS EFFECT (must stay crisp)
final class SilhouetteRenderer: UIView {
    private var currentTemplate: Template?
    private var silhouetteLayer: CAShapeLayer?

    func updateTemplate(_ template: Template, animated: Bool = true) {
        // Smooth template switching with animations
        // 30% opacity, crisp vector strokes (NO blur)
    }

    func renderSilhouette(for template: Template) -> CAShapeLayer {
        // Create silhouette shape based on template.headAnchorRect
        // 30% opacity, smooth animations
    }
}
```

**Silhouette Positioning Validation (Week 7 Day 5 - CRITICAL):**
```swift
// SilhouettePositioningTests.swift - NEW FILE
import XCTest
import SnapshotTesting
@testable import Camera_Coach

final class SilhouettePositioningTests: XCTestCase {
    var templateEngine: TemplateEngine!
    var renderer: SilhouetteRenderer!

    override func setUp() {
        super.setUp()
        templateEngine = TemplateEngine()
        try! templateEngine.loadTemplates()

        // Test on iPhone 14 Pro screen size (393×852)
        renderer = SilhouetteRenderer(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    }

    func testAllTemplatePositions() throws {
        let templates = try templateEngine.availableTemplates(for: .portrait)

        for template in templates {
            // Render silhouette for template
            renderer.updateTemplate(template, animated: false)

            // Take snapshot for visual regression
            assertSnapshot(matching: renderer, as: .image, named: template.id)

            // Validate headAnchorRect is within frame bounds
            let anchorRect = template.headAnchorRect
            XCTAssertGreaterThanOrEqual(anchorRect.minX, 0.0, "\(template.id): x out of bounds")
            XCTAssertLessThanOrEqual(anchorRect.maxX, 1.0, "\(template.id): x+width out of bounds")
            XCTAssertGreaterThanOrEqual(anchorRect.minY, 0.0, "\(template.id): y out of bounds")
            XCTAssertLessThanOrEqual(anchorRect.maxY, 1.0, "\(template.id): y+height out of bounds")
        }
    }

    func testSilhouetteVisualAlignment() throws {
        // Test that silhouette matches design spec positions from frame_capture_portrait.svg
        let fullBodyTemplate = try templateEngine.template(id: "portrait_full_left_thirds")
        renderer.updateTemplate(fullBodyTemplate!, animated: false)

        // Validate visual position matches SVG spec
        // Expected: head at left third (x:0.15), top 20% of frame (y:0.2)
        let actualCenter = renderer.silhouetteLayer?.position
        let expectedX = 393 * 0.225  // x:0.15 + width:0.15/2 = center at 0.225
        let expectedY = 852 * 0.325  // y:0.2 + height:0.25/2 = center at 0.325

        XCTAssertEqual(actualCenter?.x ?? 0, expectedX, accuracy: 10, "Horizontal position mismatch")
        XCTAssertEqual(actualCenter?.y ?? 0, expectedY, accuracy: 10, "Vertical position mismatch")
    }

    func testMultipleScreenSizes() throws {
        let screenSizes: [(String, CGSize)] = [
            ("iPhone 12 Pro", CGSize(width: 390, height: 844)),
            ("iPhone 14 Pro", CGSize(width: 393, height: 852)),
            ("iPhone 15 Pro Max", CGSize(width: 430, height: 932))
        ]

        let template = try templateEngine.template(id: "portrait_full_left_thirds")!

        for (deviceName, size) in screenSizes {
            let testRenderer = SilhouetteRenderer(frame: CGRect(origin: .zero, size: size))
            testRenderer.updateTemplate(template, animated: false)

            // Snapshot for each device
            assertSnapshot(matching: testRenderer, as: .image, named: "\(template.id)_\(deviceName)")
        }
    }
}
```


### 13.10 `GuidanceHUDView.swift` - **REFACTOR TO USE GLASSPILL (Week 7)**
- **BEFORE (Week 6):** UILabel with black background, basic fade animation
- **AFTER (Week 7):** Embed SwiftUI `GlassPill` component via `UIHostingController`
- Auto-hide ≤1.2s, capsule shape, 92% opacity for legibility
- Respect `Reduce Transparency` → opaque pill with elevated border
- Grid/lines/horizon indicators remain UIKit vector strokes (NO glass)

---

## 14) Replay Harness (Week 3+)
- Provide 10–20 short clips (screen recordings).  
- CLI or test target that feeds frames into Analyzer+Guidance, dumps CSV (`frame_idx, hint, latency_ms`).  
- **DoD:** two consecutive runs produce identical decisions; perf within previous commit bounds.

---

## 15) Feature Flags & Config
- Flags for thirds/orientation/edge rules; quick rollback.  
- Tunables exposed only in debug builds; release builds use constants in `Config.swift`.

---

## 16) CI/CD & Release
- Weekly TF build tagged `mvp-w##` with KPI deltas and release notes.  
- 15-min soak test before each build; replay suite green.

---

## 17) Risks & Mitigations - **LIQUID GLASS RISKS ADDED**
- **Prompt flapping**: FSM with stability/cooldowns; suppress conflicting hints
- **Thermal & battery**: fps fallback; reduce analysis; lower prompt rate; **auto-disable glass rendering**
- **Low-light/backlit**: fall back to horizon + symmetric framing
- **App Review/privacy**: post-shot cloud OFF by default; explicit consent; delete-all; privacy answers aligned with actual flows

### **NEW: Liquid Glass Risks (Week 7)**
- **Risk:** Glass rendering causes fps drop >2fps → **Mitigation:** Real-time fps monitoring, auto-disable glass when fps <24, pre-render layers at session start
- **Risk:** Glass unreadable over high-chroma backgrounds → **Mitigation:** Elevated pill opacity (92%), contrast sweeps with 6+ backgrounds, force opaque mode if contrast fails WCAG
- **Risk:** Glass breaks on iOS 25 or with Reduce Transparency → **Mitigation:** Graceful fallback to `.ultraThinMaterial` (iOS 25) or opaque fills (accessibility), tested in CI
- **Risk:** Glass nesting depth causes GPU overload → **Mitigation:** Hard limit of 1 glass layer depth, static analysis check in code review

---

## 18) First 72 Hours (Command-level)
**Day 1**
- Scaffold modules & SPM; `AVCaptureSession` + preview layer; HUD grid/horizon; MetricKit + CSV logger.
**Day 2**
- CoreMotion roll → horizon advice; one-sentence prompt; haptic; anti-spam throttling.
**Day 3**
- Vision face rect + headroom calc; FSM arbitration (headroom > horizon); internal TF build.

---

## 19) Hand-off to Cursor — Task List
1. Create project (`iOS 17`, Swift 5.9), add **SPM**: SwiftFormat/SwiftLint (plugins).  
2. Add targets/folders per **Repo Layout**.  
3. Implement `CameraController` + preview; frame delivery to `FrameAnalyzer`.  
4. Implement `FrameAnalyzer` (Vision face, CoreMotion horizon, headroom %).  
5. Implement `GuidanceEngine` skeleton + FSM rules, `Config.swift` tunables.  
6. Implement `GuidanceHUDView` with one-sentence prompt + haptic.  
7. Implement `Logger` with exact events; add CSV export.  
8. Add micro-survey modal (helpful? Y/N + satisfaction 1–5).  
9. Add **Privacy Settings** screen (post-shot consent, Wi-Fi-only, daily cap, delete-all).  
10. Build **replay harness** (test target or CLI).  
11. Add **thermal guard** (reduce analyses, clamp prompts, 30→24fps fallback).  
12. Add feature flags; prepare TestFlight config & release notes template.

---

## 20) References
- See `docs/ENGINEERING-RULES.md` (non-negotiables), `docs/ANALYTICS.md` (events), `docs/PRIVACY.md`, `docs/REPLAY-HARNESS.md`, and weekly plans in `docs/weeks/`.

---

## 21) Week 7 Critical Action Summary (Post-Design Audit)

### **🚨 BLOCKING ISSUES TO FIX:**

**Day 1 (DELETE DUPLICATE CODE):**
- 🔥 DELETE `TemplateSelector.swift` (631 lines)
- Migrate `CameraCoordinator` to use SwiftUI `GlassShelf`
- **Impact**: -66% UI code, pure SwiftUI architecture

**Day 2 (FIX DESIGN TOKENS):**
- Card size: 56×56pt → **88×72pt** ✅
- Card radius: 12pt → **16pt** ✅
- Card spacing: 12/16pt → **10pt** ✅
- Add `Config.glassCardWidth` and `Config.glassCardHeight` constants
- **Impact**: Pixel-perfect match with SVG spec

**Day 3 (REAL LIQUID GLASS API):**
- Replace `.ultraThinMaterial` with `glassBackgroundEffect(in:displayMode:)` ✅
- Implement proper fallback chain: iOS 26 glass → iOS 25 material → accessibility opaque
- **Impact**: Real iOS 26+ Liquid Glass (not fake Material API)

**Day 4 (COMPLETE JSON SCHEMA):**
- Add `iconName: String` field to all 8 templates in `templates.json` ✅
- Update `Template.swift` Codable struct with `iconName` field ✅
- Create `TemplateSchemaTests.swift` validation suite ✅
- **Impact**: Icons load correctly, schema validated

**Day 5 (CRITICAL VALIDATION):**
- Create `SilhouettePositioningTests.swift` with visual regression tests ✅
- Validate all 8 templates render at correct `headAnchorRect` positions ✅
- Test on 3 device sizes (iPhone 12 Pro, 14 Pro, 15 Pro Max) ✅
- **Impact**: Proof that silhouettes align correctly

**Day 6 (GLASSPILL REFACTOR):**
- Replace UIKit `GuidanceHUDView` label with SwiftUI `GlassPill` ✅
- Use iOS 26+ glass API, proper accessibility fallback ✅
- **Impact**: Consistent glass design, proper API usage

**Day 7 (VALIDATION & TESTING):**
- Contrast sweeps (6 backgrounds) ✅
- FPS impact testing (must be <2fps drop) ✅
- Thermal auto-disable testing ✅
- Accessibility mode testing ✅
- **Impact**: Production-ready glass system

### **Expected Outcomes:**
- **Code Reduction**: 948 lines → 317 lines (66% reduction)
- **Design Fidelity**: 100% match with SVG specifications
- **API Correctness**: Real iOS 26+ Liquid Glass (not Material fake)
- **Validation Coverage**: Automated tests prove silhouette positioning
- **Schema Completeness**: All template fields properly defined

### **Risk Mitigation:**
- Visual regression tests catch silhouette misalignment
- JSON schema validation prevents icon lookup failures
- Design token constants prevent pixel drift
- Accessibility fallbacks tested for all modes
- Performance budgets enforced (fps ≥24, thermal auto-disable)
