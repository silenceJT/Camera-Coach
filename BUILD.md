# Camera Coach - Week 6 TestFlight Build Instructions

## Prerequisites

1. **Xcode 17.0+** installed
2. **Apple Developer Account** with TestFlight access
3. **Development Team**: M6M9GH2JWC (already configured)
4. **Bundle ID**: jiatao.Camera-Coach (already configured)
5. **iOS 26+ Deployment Target** for latest hardware optimization

## Quick TestFlight Build

### Method 1: Xcode Archive (Recommended)

```bash
# 1. Open project
open "Camera Coach.xcodeproj"

# 2. In Xcode:
# - Select "Any iOS Device (arm64)" as destination
# - Product → Archive
# - Click "Distribute App" → "TestFlight & App Store Connect"
# - Follow upload wizard

# 3. In App Store Connect:
# - Navigate to TestFlight tab
# - Add test users
# - Submit for review if needed
```

### Method 2: Command Line Build

```bash
# 1. Clean and build for release
xcodebuild clean -project "Camera Coach.xcodeproj" -scheme "Camera Coach"

# 2. Archive the build
xcodebuild archive \
  -project "Camera Coach.xcodeproj" \
  -scheme "Camera Coach" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "build/Camera Coach.xcarchive"

# 3. Export for App Store distribution
xcodebuild -exportArchive \
  -archivePath "build/Camera Coach.xcarchive" \
  -exportPath "build/" \
  -exportOptionsPlist exportOptions.plist

# 4. Upload to TestFlight (requires exportOptions.plist)
xcrun altool --upload-app \
  --file "build/Camera Coach.ipa" \
  --type ios \
  --username "your-apple-id" \
  --password "app-specific-password"
```

## Build Configuration

**Current Settings:**
- **Marketing Version**: 1.0
- **Build Number**: 6 (Week 6 release)
- **Deployment Target**: iOS 26.0
- **Code Signing**: Automatic
- **Team**: M6M9GH2JWC
- **Configuration**: Release (optimized for performance)

## Pre-Release Checklist

### Week 6 External Testing Requirements

- [x] **Face Detection**: Multi-face detection with primary subject selection
- [x] **Headroom Guidance**: 7-12% frame height targeting with group support
- [x] **Priority System**: headroom > horizon > thirds > leadspace deterministic FSM
- [x] **Test Infrastructure**: 10 standard test clips with replay harness validation
- [x] **Privacy Controls**: Comprehensive PrivacyManager with granular consent
- [x] **Thermal Management**: Dynamic performance degradation for sustained use
- [x] **Performance**: ≥24fps sustained, p95 latency ≤80ms validated
- [x] **Strategic Feedback**: Non-intrusive micro-survey with EN/CN localization

### Week 6 Manual Testing Protocol

```bash
# 1. Install on iPhone 17 Pro (or equivalent)
# 2. Run comprehensive 15-minute soak test:
#    - Monitor sustained FPS (≥24fps target)
#    - Test face detection across all scenarios
#    - Verify headroom guidance (7-12% frame height)
#    - Check guidance priority: headroom > horizon > thirds
#    - Validate stability window (300ms) and cooldown (600ms)
#    - Test thermal throttling behavior
#    - Verify micro-survey strategic timing
# 3. Scenario coverage validation:
#    - Portrait (single face): headroom guidance
#    - Group photos (multiple faces): primary subject selection
#    - Landscape/tilted horizon: horizon guidance
#    - Mixed scenarios: priority arbitration
# 4. Privacy & localization:
#    - Test privacy settings and consent flows
#    - Verify Chinese localization accuracy
#    - Validate on-device processing (no network calls)
# 5. Performance validation:
#    - Export logs and verify telemetry pipeline
#    - Check memory usage under multi-face scenarios
#    - Validate thermal state monitoring
```

## Version Management

For weekly releases, increment build number:

```bash
# Update build number for TestFlight builds
agvtool next-version -all

# Or manually update in Xcode:
# Project Settings → General → Build (increment)
```

## Week 6 Release Notes Template

```
# Camera Coach - Week 6 External Testing Build

## 🎯 Ready for External Testing
Week 6 milestone: First external beta ready for 20-30 testers

## ✅ Major Features Complete
- **Face Detection**: Multi-face detection with primary subject selection
- **Headroom Guidance**: Intelligent 7-12% frame height targeting
- **Priority System**: headroom > horizon > thirds deterministic arbitration
- **Test Infrastructure**: 10 standardized test clips with replay harness
- **Privacy-First**: Comprehensive on-device processing with granular controls
- **Thermal Management**: Dynamic performance degradation for sustained use

## 🚀 Performance Achievements
- **Sustained FPS**: ≥24fps validated with thermal fallback from 30fps
- **Processing Speed**: p95 latency ≤80ms @ 720p resolution
- **Memory Optimization**: Pressure-aware multi-face detection (10→5→3→1)
- **Stability**: 300ms stability window + 600ms cooldown per guidance type

## 📱 User Experience
- **Single Hint Display**: One guidance hint at a time, never overwhelming
- **Strategic Feedback**: Non-intrusive micro-survey after photo sessions
- **Dual Language**: English/Chinese localization with cultural adaptation
- **Visual Polish**: Clear directional guidance with subtle haptic feedback

## 🛡️ Privacy & Security
- **On-Device First**: 100% local processing during live camera preview
- **Explicit Consent**: Cloud features require user opt-in with granular controls
- **Data Transparency**: Clear usage descriptions with easy deletion options
- **Wi-Fi Only**: Cloud uploads restricted to Wi-Fi connections only

## 🧪 External Testing Focus Areas
**SUCCESS CRITERIA:**
- One-shot success rate ≥60% (hint → photo kept ≤6s)
- User satisfaction ≥3.8/5 (micro-survey ratings)
- Crash rate <1% (TestFlight + MetricKit analytics)

**TESTING SCENARIOS:**
- Portrait photos (single person headroom guidance)
- Group photos (multi-face primary subject selection)
- Landscape/outdoor scenes (horizon guidance)
- Mixed scenarios (priority system validation)
- Extended use (thermal and performance monitoring)

## 📊 Analytics & Telemetry
- Complete event pipeline: session_start/stop, hint_shown/adopted, photo_kept
- Performance monitoring: fps_sample, thermal_sample, memory_pressure
- User feedback: micro-survey responses with privacy protection
- Crash reporting: MetricKit integration for stability tracking

## 🔧 Technical Specifications
- **iOS 26+ Required**: Optimized for iPhone 17 Pro and latest hardware
- **Swift 6.0**: Latest language features with structured concurrency
- **Architecture**: UIKit camera + SwiftUI shell, clean module separation
- **Frameworks**: AVFoundation, Vision, CoreMotion, SwiftUI + UIKit hybrid
```

## Troubleshooting

### Common Issues

1. **Code Signing Errors**
   - Verify Apple Developer account status
   - Check certificate expiration
   - Try "Clean Build Folder" in Xcode

2. **Archive Upload Fails**
   - Check bundle ID matches App Store Connect
   - Verify all required app icons are present
   - Ensure privacy usage descriptions are complete

3. **TestFlight Processing Issues**
   - Wait 10-15 minutes for processing
   - Check for missing compliance information
   - Verify no restricted APIs are used

## Week 6 External Testing Deployment

### TestFlight External Beta Setup
1. **Create External Test Group**: 20-30 beta testers
2. **Beta App Description**: Clear testing instructions and focus areas
3. **Testing Duration**: 7 days with daily analytics monitoring
4. **Success Metrics**: Track one-shot success, satisfaction, crash rates

### Post-Week 6 Next Steps
- [ ] **Week 7-8**: Advanced guidance (orientation, lead space) + threshold tuning
- [ ] **Week 9-10**: Post-shot cloud features (opt-in) + second external test (70% success)
- [ ] **Week 11-12**: App Store submission preparation + launch