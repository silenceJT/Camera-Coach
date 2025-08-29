# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

**Building:**
```bash
# Build project
xcodebuild -scheme "Camera Coach" -configuration Debug build

# Build for device (requires signing)
xcodebuild -scheme "Camera Coach" -configuration Release -destination "generic/platform=iOS" build

# Run tests
xcodebuild -scheme "Camera Coach" test -destination "platform=iOS Simulator,name=iPhone 15 Pro"

# Clean build folder
xcodebuild -scheme "Camera Coach" clean
```

**TestFlight Deployment:**
```bash
# Archive for TestFlight (Xcode GUI recommended)
xcodebuild archive \
  -project "Camera Coach.xcodeproj" \
  -scheme "Camera Coach" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "build/Camera Coach.xcarchive"
```

**Development Workflow:**
- Open `Camera Coach.xcodeproj` in Xcode 15.0+
- Build and run on physical device (camera required)
- Use Swift Package Manager for dependencies (no CocoaPods/Carthage)
- Weekly TestFlight releases following MVPWeekly cadence
- See `BUILD.md` for detailed TestFlight instructions

## Core Architecture

This is a real-time camera coaching iOS app following a strict clean architecture:

```
UIKit Camera VC → Analyzer (Vision+CoreMotion) → GuidanceEngine (FSM) → HUD Overlay
                                              ↘ Logger/Telemetry
SwiftUI screens ⇄ Camera VC via UIViewControllerRepresentable
```

### Key Components

**CameraController (`Camera Coach/Core/Camera/CameraController.swift`):**
- UIKit-based `AVCaptureSession` at 720p (`.hd1280x720`)
- Uses `AVCaptureVideoDataOutput` with BGRA format
- Background queue processing with main thread HUD updates
- Portrait orientation locked, back camera only

**FrameAnalyzer (`Camera Coach/Core/Analyzer/`):**
- Vision framework for face detection and composition analysis  
- CoreMotion for horizon/level detection
- Runs off main thread with p95 processing ≤80ms budget
- Outputs structured `FrameFeatures` data

**GuidanceEngine (`Camera Coach/Core/Guidance/GuidanceEngine.swift`):**
- Finite State Machine: `idle → analyzing → hint_cooldown`
- Strict priority: `headroom > horizon > thirds > leadspace`
- Single hint at a time with stability ≥300ms, cooldown ≥600ms
- Outputs `GuidanceAdvice` structs (never direct UI)

**HUD/UI Components (`Camera Coach/Core/UI/`):**
- `GuidanceHUDView.swift` - Main guidance overlay
- `LevelIndicatorView.swift` - Horizon level indicator  
- `CameraView.swift` - SwiftUI wrapper for UIKit camera
- `MicroSurveyView.swift` - Strategic feedback collection modal
- Light haptics on advice changes

### Module Boundaries
- Strict separation: Camera ⟂ Analyzer ⟂ Guidance ⟂ HUD ⟂ Telemetry
- No cross-imports between Core modules except via protocols
- Dependency inversion: GuidanceEngine depends on `FrameFeaturesProvider` protocol

## Performance Requirements

**Hard Limits:**
- p95 frame processing ≤80ms @ 720p
- Sustained ≥24fps (thermal fallback from 30fps)
- Global rate limit ≤2 prompts/second
- Same advice type ≤3 times per 10 seconds

**Thermal Management:**
- Monitor `ProcessInfo.thermalState`
- When ≥`.fair`: reduce prompt frequency, lighter analysis
- Graceful degradation, never hard crashes

## Privacy & Data Handling

**Live Preview (Default):**
- 100% on-device processing
- No network calls during camera preview
- No face data storage
- No cloud uploads

**Post-Shot Cloud (Opt-in Only):**
- Explicit user consent required
- Wi-Fi only connections
- Daily upload caps
- Easy delete-all functionality

## Configuration & Feature Flags

**Config System (`Camera Coach/Core/Guidance/Config.swift`):**
- Centralized tunables for thresholds and parameters
- Read-only at runtime for release builds
- No remote config changes

**Key Settings:**
- Stability window: 300ms minimum
- Cooldown periods: 600ms per rule type  
- Thermal thresholds and fallback behaviors
- Guidance priority weights and thresholds

## Testing & Quality Gates

**Pre-Release Requirements:**
- 15-minute manual soak test (fps/thermal/jank monitoring)
- Replay harness must pass on 10-20 recorded clips
- All builds must meet performance budgets

**Success Gates:**
- **Week 6:** One-shot success ≥60%, satisfaction ≥3.8/5, crash rate <1%
- **Week 10:** One-shot success ≥70%, satisfaction ≥4.0/5, crash rate <0.5%

**Performance Metrics:**
- One-shot success rate (hint → photo kept ≤6s)
- Frame processing latency (p95 ≤80ms)
- Prompt frequency (≤8 per minute average)
- Sustained fps ≥24 (thermal-aware fallback from 30fps)

**Telemetry Events (Exact Names):**
```
session_start/stop, hint_shown, hint_adopted, shutter, photo_kept, 
fps_sample, thermal_sample, consent_changed
```

## Code Style & Standards

**Language & Frameworks:**
- Swift 5.9+, iOS 17+ minimum
- AVFoundation, Vision, CoreMotion, SwiftUI + UIKit hybrid
- Structured Concurrency + GCD for threading
- No force unwrapping (`!`) in production code

**Architecture Patterns:**
- Immutable data structures where possible
- `final` classes by default, `struct` for models
- Error handling via `Result`/`throws`, never silent failures
- No business logic in views - views render engine state

**Dependencies:**
- Swift Package Manager only
- Zero runtime 3rd-party dependencies for MVP
- SwiftFormat & SwiftLint via SPM plugins allowed

## Project Structure

```
Camera Coach/
├── Camera_CoachApp.swift          # App entry point
├── ContentView.swift              # Main SwiftUI shell
└── Core/
    ├── Camera/                    # UIKit camera session
    │   └── CameraController.swift
    ├── Analyzer/                  # Vision + CoreMotion
    │   ├── FrameAnalyzer.swift
    │   └── FrameFeatures.swift
    ├── Guidance/                  # FSM decision engine
    │   ├── GuidanceEngine.swift
    │   ├── GuidanceAdvice.swift
    │   └── Config.swift
    ├── UI/                        # HUD overlays & SwiftUI bridge
    │   ├── CameraView.swift
    │   ├── CameraCoordinator.swift
    │   ├── GuidanceHUDView.swift
    │   ├── LevelIndicatorView.swift
    │   └── MicroSurveyView.swift
    └── Infra/                     # Logging & telemetry
        ├── Logger.swift
        └── FeedbackManager.swift
```

## Current Development Phase

**Status:** Week 2 ACTUALLY Complete - Ready for Week 3
- ✅ **Week 1:** Core camera architecture, telemetry, and HUD foundation established  
- ✅ **Week 2:** All requirements completed - TRUE completion achieved
- 🔄 **Week 3 (Next):** Face detection + headroom guidance, replay harness implementation

**Week 2 Final Completion Status (100%):**
- ✅ **Strategic Feedback System**: Post-shot feedback with iOS-compliant UX (replaces immediate survey disaster)
- ✅ **EN/CN Localization**: Complete Localizable.strings support for all user-facing text
- ✅ **Horizon Threshold**: Fixed to 3° per specification (was incorrectly 5°)  
- ✅ **Guidance Rate**: 300ms stability + 600ms cooldown per FSM specification
- ✅ **TestFlight Ready**: Build configuration and deployment instructions complete

**Critical UX Transformation:**
- **UX Disaster Fix**: Eliminated immediate post-shutter survey interruption
- **Strategic Timing**: Feedback collection at natural breakpoints (session end, settings, app background)
- **Silent Metrics**: Rich context collection without workflow interruption
- **iOS Compliance**: Respects platform UX patterns and user expectations

**Upcoming Week 3 Priorities:**
- Integrate Vision framework face detection (`VNDetectFaceRectangles`)
- Implement headroom calculation targeting 7-12% frame height
- Build offline replay harness for deterministic testing with 10 standard clips
- Establish priority arbitration: headroom > horizon guidance

## Development Rules

**Non-Negotiables:**
1. Live camera preview stays 100% on-device
2. UIKit for camera + SwiftUI for shell architecture
3. One guidance hint at a time with deterministic priority
4. Real-time budget: p95 ≤80ms, ≥24fps sustained
5. Privacy-first defaults with explicit consent for cloud features

**12-Week MVP Timeline:**
- **Weeks 1-2:** ✅ Foundation + horizon guidance
- **Weeks 3-4:** Face detection + headroom + privacy settings
- **Weeks 5-6:** Performance optimization + first external testing (60% one-shot success)
- **Weeks 7-8:** Advanced guidance (orientation, thirds) + threshold tuning
- **Weeks 9-10:** Post-shot cloud (opt-in) + second external test (70% one-shot success)
- **Weeks 11-12:** Submission preparation + launch

**Weekly Release Cycle:**
- Each week produces TestFlight-ready build
- Feature flags for all new functionality
- Conventional commit messages (feat:, fix:, perf:)
- Release notes with KPI deltas

**Debugging:**
- Hidden debug overlay (long-press) shows fps, thermal, hints
- Structured logging with PII redaction
- MetricKit integration for crash/performance data
- Export logs via share sheet from Settings

## Strategic Feedback System

### **User Experience Flow**
The app uses a sophisticated **non-intrusive feedback system** that respects user workflow while collecting meaningful data.

**Silent Metrics Collection (Every Photo):**
```swift
// Triggered on shutter tap - NO UI interruption
PhotoCaptureMetrics {
    timestamp, guidanceActive, lastGuidanceType,
    deviceOrientation, thermalState, sessionDuration,
    consecutivePhotos, horizonAngleAtCapture
}
```

**Feedback Modal Triggers (Strategic Timing):**
1. **Session End** (Most Common): Natural breakpoint when exiting camera
2. **Settings Access** (User-Initiated): When opening settings screen  
3. **App Background** (Gentle): When app goes inactive/background

**Eligibility Criteria:**
- User has taken ≥5 photos in session
- ≥24 hours since last feedback request
- At least some photos had active guidance
- Manual override always available in Settings

**Key Components:**
- `FeedbackManager.swift` - Strategic timing and eligibility logic
- `MicroSurveyView.swift` - Localized feedback modal (EN/CN)
- `PhotoCaptureMetrics` - Rich context without workflow interruption

**Why This Approach:**
- **iOS UX Compliance**: Follows platform conventions
- **Quality Data**: Users provide feedback after seeing photo results
- **Workflow Respect**: Never interrupts active photo-taking
- **Higher Completion**: Strategic timing increases response rates

### **Feedback Collection Points**
```
Photo Session (5+ photos) → Silent Collection → Exit Camera → 
Strategic Eligibility Check → Feedback Modal (if due) → Analytics
```

**Settings Integration:**
- "Help Improve Camera Coach (X photos)" button for manual feedback
- Shows pending photo count when feedback is available
- Always respectful and optional

## Documentation References

- `docs/ARCHITECTURE.md` - Detailed technical architecture
- `docs/ENGINEERING-RULES.md` - Complete development constraints
- `docs/ANALYTICS.md` - Telemetry event specifications
- `docs/ROADMAP.md` - 12-week MVP development plan
- `docs/PRIVACY.md` - Data handling and privacy policies
- `BUILD.md` - TestFlight deployment instructions