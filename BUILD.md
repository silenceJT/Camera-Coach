# Camera Coach - TestFlight Build Instructions

## Prerequisites

1. **Xcode 15.0+** installed
2. **Apple Developer Account** with TestFlight access
3. **Development Team**: M6M9GH2JWC (already configured)
4. **Bundle ID**: jiatao.Camera-Coach (already configured)

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
- **Build Number**: 1
- **Deployment Target**: iOS 18.5
- **Code Signing**: Automatic
- **Team**: M6M9GH2JWC

## Pre-Release Checklist

### Week 2 Completion Requirements

- [x] **Micro-Survey Modal**: Post-shot helpful Y/N + satisfaction rating
- [x] **Localization**: EN/CN support with Localizable.strings
- [x] **Horizon Threshold**: Fixed to 3° per specification (was 5°)
- [x] **Guidance Rate**: 300ms stability + 600ms cooldown per FSM spec
- [x] **Performance**: Targeting ≥24fps with p95 latency ≤80ms
- [x] **Telemetry**: Complete event logging pipeline

### Manual Testing

```bash
# 1. Install on physical device
# 2. Run 15-minute soak test:
#    - Monitor FPS (should stay ≥24)
#    - Check guidance prompts (≤8 per minute)
#    - Test micro-survey after photo
#    - Verify horizon guidance at ±3°
# 3. Export and verify logs work
# 4. Test Chinese localization
```

## Version Management

For weekly releases, increment build number:

```bash
# Update build number for TestFlight builds
agvtool next-version -all

# Or manually update in Xcode:
# Project Settings → General → Build (increment)
```

## Release Notes Template

```
# Camera Coach - Week 2 TestFlight Build

## ✅ New Features
- Post-shot micro-survey for guidance feedback
- EN/CN localization support
- Improved horizon guidance sensitivity (3° threshold)

## 🐛 Bug Fixes  
- Fixed guidance rate timing per FSM specification
- Improved stability window to 300ms

## 📊 Telemetry
- Complete event tracking pipeline
- Micro-survey feedback logging
- Performance metrics collection

## 🧪 Testing Focus
- Horizon guidance effectiveness at ±3°
- Micro-survey UX and completion rates
- Chinese localization accuracy
- Performance stability (≥24fps target)
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

## Next Steps (Week 3)

- [ ] Integrate face detection + headroom guidance
- [ ] Implement replay harness for testing
- [ ] Add deterministic priority: headroom > horizon
- [ ] Prepare for external beta testing (≥10 users)