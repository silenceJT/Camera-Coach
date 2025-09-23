# 📱 Week 4: iPhone 17 Pro + iOS 26 Test Scenarios

**Date**: September 23, 2025
**Target Platform**: iPhone 17 Pro running iOS 26
**Focus**: Privacy settings, system consolidation, and performance validation

## 🔧 **Hardware Configuration**
- **Device**: iPhone 17 Pro
- **OS Version**: iOS 26.0
- **Xcode Version**: 17.0+
- **Build Target**: iOS 26+ minimum deployment

## 🛡️ **Privacy & Consent Testing**

### **Test Scenario 1: First-Time Privacy Setup**
**Objective**: Validate privacy disclosure and consent flow for new users

**Steps:**
1. Fresh app install on iPhone 17 Pro
2. Launch Camera Coach for first time
3. Navigate to Settings → Privacy & Data section
4. Verify face detection toggle is ON by default
5. Verify cloud features toggle is OFF by default
6. Verify analytics toggle is ON by default
7. Test toggling each setting and verify consent logging

**Expected Results:**
- Clear privacy disclosures visible in English/Chinese
- Face detection explanation: "On-device processing, no data stored"
- Cloud features explanation: "Optional, explicit consent required"
- All consent changes logged to telemetry system

### **Test Scenario 2: Privacy-Aware Face Detection**
**Objective**: Verify face detection respects privacy settings

**Steps:**
1. Enable face detection in privacy settings
2. Point camera at 2-face scenario
3. Verify multi-face headroom guidance appears
4. Navigate to Settings → Disable face detection
5. Return to camera view
6. Verify NO face detection or headroom guidance
7. Re-enable face detection
8. Verify face detection resumes immediately

**Expected Results:**
- Face detection completely disabled when consent withdrawn
- No crash or errors when toggling consent during active session
- Graceful fallback to horizon-only guidance

### **Test Scenario 3: Data Deletion & Reset**
**Objective**: Validate comprehensive data removal

**Steps:**
1. Use app for 10+ photos with various guidance types
2. Trigger feedback collection (take 5+ photos, access settings)
3. Navigate to Settings → Privacy → Data Controls
4. Tap "Delete All Data" → Confirm deletion
5. Verify confirmation dialog with proper warnings
6. Navigate to Settings → Export Logs
7. Verify logs are cleared
8. Check feedback system has reset

**Expected Results:**
- Confirmation dialog warns action cannot be undone
- All logs, feedback data, and analytics cleared
- Privacy settings reset to defaults
- No crashes or data corruption

## ⚡ **Performance & Stability Testing**

### **Test Scenario 4: Thermal Management Under Load**
**Objective**: Test sustained camera use on iPhone 17 Pro

**Steps:**
1. Ensure device is at room temperature
2. Launch Camera Coach with face detection enabled
3. Point at multi-face scenario (2-4 faces)
4. Keep camera active for 15 minutes continuously
5. Monitor performance metrics in debug mode
6. Note any thermal throttling or FPS degradation
7. Verify graceful degradation, not hard failures

**Expected Results:**
- Sustained ≥24fps for first 10 minutes
- Graceful thermal throttling when device heats up
- No crashes or hard freezes
- Proper thermal state logging

### **Test Scenario 5: Vision Framework Error Recovery**
**Objective**: Test robustness against Vision framework failures

**Steps:**
1. Enable face detection
2. Point camera at extreme conditions:
   - Very low light scenarios
   - Very bright backlit scenarios
   - Rapid movement/shaking
   - Extreme close-up faces
   - Very distant faces
3. Monitor error recovery logs
4. Simulate memory pressure (open many apps)
5. Return to Camera Coach and test recovery

**Expected Results:**
- Vision errors logged with context (thermal state, error count)
- Graceful fallback to horizon guidance on errors
- Automatic recovery after error conditions resolve
- No cascade failures or infinite error loops

### **Test Scenario 6: Multi-Face Performance on iPhone 17 Pro**
**Objective**: Validate optimized performance with multiple faces

**Steps:**
1. Test scenarios with 1, 2, 5, and 10 faces in frame
2. Measure frame processing latency in each scenario
3. Verify group headroom calculation accuracy
4. Test camera area coordinate mapping precision
5. Verify letterboxed 4:3 view performance
6. Test rapid face count changes (people entering/leaving)

**Expected Results:**
- p95 processing latency ≤80ms for all scenarios
- Group headroom calculation adds <5ms overhead
- Smooth transitions between individual/group strategies
- Accurate coordinate mapping within camera bounds

## 📊 **UI/UX Validation**

### **Test Scenario 7: Privacy Settings User Experience**
**Objective**: Validate intuitive privacy controls

**Steps:**
1. Navigate through all privacy settings sections
2. Read all privacy descriptions in both EN/CN languages
3. Test toggle responsiveness and visual feedback
4. Test delete confirmation flow
5. Verify settings persistence across app restarts
6. Test accessibility with VoiceOver (if enabled)

**Expected Results:**
- Clear, concise privacy explanations
- Immediate visual feedback on setting changes
- Proper Chinese localization for CN users
- Settings persist correctly across sessions

### **Test Scenario 8: iPhone 17 Pro Specific Features**
**Objective**: Leverage iPhone 17 Pro capabilities

**Steps:**
1. Test camera performance with 4:3 letterbox view
2. Verify proper integration with iOS 26 features
3. Test camera switching (if multiple lenses available)
4. Verify proper orientation handling
5. Test with various camera control gestures

**Expected Results:**
- Optimal camera quality on iPhone 17 Pro hardware
- Smooth integration with iOS 26 camera APIs
- Proper constraint handling for letterboxed view
- No conflicts with iOS 26 system camera controls

## 🔍 **Edge Cases & Stress Tests**

### **Test Scenario 9: Memory Pressure Testing**
**Objective**: Validate memory management under stress

**Steps:**
1. Open 10+ apps in background
2. Launch Camera Coach with face detection
3. Use app for 5+ minutes with multi-face scenarios
4. Monitor memory usage via Xcode Instruments
5. Check for memory leaks or excessive allocation
6. Test app suspension/resume cycles

**Expected Results:**
- Memory usage remains stable over time
- No significant memory leaks detected
- Graceful handling of memory warnings
- Quick recovery from suspension/resume

### **Test Scenario 10: Network & Connectivity**
**Objective**: Test offline resilience and privacy compliance

**Steps:**
1. Turn off WiFi and cellular data
2. Use Camera Coach with all privacy settings enabled
3. Verify complete offline functionality
4. Test privacy settings changes offline
5. Re-enable connectivity and verify no unexpected network calls

**Expected Results:**
- 100% functionality works offline (no cloud dependency)
- Privacy settings work completely offline
- No network requests during face detection
- No background uploads without explicit consent

## 📋 **Success Criteria**

### **Privacy & Compliance**
- ✅ Clear privacy disclosures for all data processing
- ✅ Granular consent controls for each feature
- ✅ Complete data deletion functionality
- ✅ Offline-first architecture with explicit cloud opt-in

### **Performance on iPhone 17 Pro**
- ✅ Sustained ≥24fps with thermal management
- ✅ p95 frame processing ≤80ms with multi-face detection
- ✅ Smooth 4:3 letterboxed camera experience
- ✅ Memory efficient multi-face tracking

### **System Reliability**
- ✅ Graceful Vision framework error recovery
- ✅ Proper thermal throttling without crashes
- ✅ Stable operation under memory pressure
- ✅ Quick recovery from system interruptions

### **User Experience**
- ✅ Intuitive privacy controls in English/Chinese
- ✅ Non-intrusive feedback collection system
- ✅ Responsive UI on latest iOS 26 features
- ✅ Clear visual feedback for all privacy changes

## 🎯 **Pre-Week 6 Validation Checklist**

Before external testing begins (Week 6 goal: 60% one-shot success rate):

- [ ] All 10 test scenarios pass on iPhone 17 Pro + iOS 26
- [ ] Privacy settings comply with App Store guidelines
- [ ] Performance meets all specified targets
- [ ] Error recovery handles all edge cases gracefully
- [ ] Memory and thermal management work under sustained use
- [ ] Multi-face detection provides reliable guidance
- [ ] UI/UX matches iOS platform conventions

---
*Generated on September 23, 2025*
*Camera Coach - Week 4 Testing Documentation*