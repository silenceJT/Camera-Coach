# Week 7 Feature Testing Guide 🧪

**Updated:** October 4, 2025
**Status:** Ready for comprehensive testing
**New Features:** Perfect composition feedback, improved guidance language, letterbox headroom fix

---

## ✅ 0. Pre-Test Checklist (CRITICAL FIXES)

### 0A: Verify Letterbox Headroom Fix
**Context:** Headroom calculation now accounts for 4:3 capture buffer vs 9:19.5 screen letterboxing.

**Setup:** Stand close to camera, move face to TOP EDGE of visible preview
**Expected logs:**
```
🔬 PREVIEW MAPPING: Capture=1608×1206, AspectRatio=1.33
🔬 PREVIEW MAPPING: Visible height ratio=35% of capture
🔬 PREVIEW MAPPING: Visible range: 393-813px (height=420px)
🔬 PREVIEW MAPPING: Face maxY in capture=926px → visible=533px
🔬 PREVIEW MAPPING: Headroom=0-5% of VISIBLE area
📍 VERTICAL POSITION: Face midY in capture=XXXpx → visible=XXXpx (visible height=417px) → 95-100%
```

**Expected guidance:** "Tilt down, Better crop" (or no headroom guidance if perfect)
**OLD WRONG behavior:** Would show 20-23% headroom even at top edge ❌
**NEW CORRECT behavior:** Shows 0-5% headroom when at top edge ✅

### 0B: Verify New Guidance Language (Photographer-Focused)
**Context:** All guidance now uses camera operation terms for the PHOTOGRAPHER.

**Test each guidance type:**
- Too much headroom → **"Move up, Room to breathe"** (physical: raise camera)
- Too little headroom → **"Move down, Better crop"** (physical: lower camera)
- Face too far left → **"Pan left, Better balance"** (horizontal movement)
- Face too far right → **"Pan right, Better balance"** (horizontal movement)

**Chinese localization:**
- "上移相机, 留白空间" (Move camera up, Room to breathe)
- "下移相机, 构图更好" (Move camera down, Better crop)
- "左移相机, 更好平衡" (Pan camera left, Better balance)
- "右移相机, 更好平衡" (Pan camera right, Better balance)

**Verify:**
- Uses PHYSICAL camera movements (move up/down, pan left/right) ✅
- "Move" = vertical translation (raise/lower arms), NOT rotation ✅
- Clear photographer actions, NOT subject instructions ✅

### 0C: Verify Gravity-Based Horizon (Pitch-Isolated)
**Context:** Horizon uses gravity.x and gravity.z to isolate ROLL from PITCH.

**Test 1 - Roll (Left/Right Tilt):**
1. Hold device upright and level
2. Tilt device LEFT 10-15° (roll)
3. Horizon lines should appear ✅

**Test 2 - Pitch (Forward/Back Tilt) - CRITICAL:**
1. Hold device upright and level
2. Tilt device DOWN (pitch forward toward ground)
3. **Horizon lines should NOT appear** ✅

**Test 3 - Haptic Feedback (REMOVED):**
1. Tilt device to achieve level (yellow line appears)
2. **NO haptic feedback** ✅ (removed - was too aggressive)
3. Only visual feedback (yellow merged line) ✅
4. VoiceOver announces "Level" for accessibility ✅

**Why This Works:**
- Calculate `gravityYZ = sqrt(gravity.y² + gravity.z²)` (magnitude in Y-Z plane)
- Use `atan2(gravity.x, gravityYZ)` for TRUE roll angle
- **Key insight**: Normalizing Y-Z plane magnitude prevents pitch amplification
- gravity.x: roll component (what we want)
- gravityYZ: stable reference that stays constant regardless of pitch
- **NEGATE result**: Counter-rotates line to stay parallel to ground

**Expected behavior:**
- Roll left/right → Lines appear, line stays parallel to ground ✅
- Pitch forward/back → Lines stay hidden ✅
- Device tilts left → Line tilts right (counter-rotation) ✅
- Level achieved → Yellow line, NO haptic (visual only) ✅
- Matches iPhone Camera app behavior exactly ✅

**OLD WRONG behavior:** Used gravity.y, triggered on pitch changes ❌
**NEW CORRECT behavior:** Uses gravity.z, isolates roll only ✅

### 0D: Verify Context-Aware Headroom (FIXED - Correct Logic)
**Context:** Headroom targets adapt based on vertical position. **CRITICAL FIX**: Ranges now match actual positioning logic!

**Understanding Vertical Position:**
- 0% = Face at BOTTOM of visible preview (Vision Y-axis points UP from bottom)
- 100% = Face at TOP of visible preview
- Headroom = space ABOVE face

**Test Scenario 1 - Upper Third Position (Face Near TOP):**
**Setup:** Position face at upper third (66-100% from bottom = near top edge)
**Expected target:** 0-8% headroom (tight framing, face fills top)
**Expected logs:**
```
📍 VERTICAL POSITION: Face midY in capture=XXXpx → visible=XXXpx → 70-95%
📍 Face vertical position: 85.0% → Zone: upper-third, Target range: 0.0...8.0
```
**Result:** With 5% headroom → NO guidance ✅

**Test Scenario 2 - Centered Position (Face in MIDDLE):**
**Setup:** Position face at center (33-66% from bottom)
**Expected target:** 7-12% headroom (standard portrait)
**Expected logs:**
```
📍 VERTICAL POSITION: Face midY in capture=XXXpx → visible=XXXpx → 45-55%
📍 Face vertical position: 50.0% → Zone: centered, Target range: 7.0...12.0
```

**Test Scenario 3 - Lower Third Position (Face Near BOTTOM):**
**Setup:** Position face at lower third (0-33% from bottom = near bottom edge)
**Expected target:** 35-50% headroom (LOTS of space above, low-angle look)
**Expected logs:**
```
📍 VERTICAL POSITION: Face midY in capture=XXXpx → visible=XXXpx → 20-30%
📍 Face vertical position: 24.0% → Zone: lower-third, Target range: 35.0...50.0
```
**Result:** With 45% headroom → NO guidance ✅

**OLD WRONG behavior:** Lower-third expected 15-25% (backwards!) ❌
**NEW CORRECT behavior:** Lower-third expects 35-50% (face at bottom = lots of headroom) ✅

---

## ✅ 1. Face Orientation Detection (COMPLETED ✓)

**Status:** All tests passed with 100% accuracy using yaw angle.

- ✅ Left profile: Working (yaw -45° to -90°)
- ✅ Center/frontal: Working (yaw -15° to +15°)
- ✅ Right profile: Working (yaw +45° to +90°)

**Skip to next section** unless you want to revalidate.

---

## 🧪 2. Lead Space Guidance (PRIMARY TEST)

**Objective:** Verify the app guides you to leave space in the direction you're facing.

### Test 2A: Facing Left - Needs Lead Space
**Setup:** Position yourself on the RIGHT side of frame
**Face direction:** Turn your head to face LEFT (left profile visible)
**Wait:** Hold steady for face stability (300ms)

**Expected guidance:** **"Pan right, Room ahead"** (NEW LANGUAGE)
**Explanation:** Photographer pans camera RIGHT → adds space on LEFT where subject is facing

**Verify console logs:**
```
🎯 YAW ANGLE: -XX° → facing_left (conf: 0.95)
lead_space_percent: 10-15% (too little)
🎯 LEAD SPACE GUIDANCE: facing_left, leadSpace=XX%, target=30%, diff=+XX%
```

### Test 2B: Facing Right - Needs Lead Space
**Setup:** Position yourself on the LEFT side of frame
**Face direction:** Turn your head to face RIGHT (right profile visible)
**Wait:** Hold steady for face stability

**Expected guidance:** **"Pan left, Room ahead"** (NEW LANGUAGE)
**Explanation:** Photographer pans camera LEFT → adds space on RIGHT where subject is facing

**Verify telemetry:** Similar to 2A but opposite direction

### Test 2C: Lead Space Adoption
**Follow guidance from Test 2A or 2B**
Move your camera in the suggested direction
Wait 10 seconds after moving

**Expected console log:**
```
✅ Lead space adopted: improvement=XX%
```
Or:
```
✅ Lead space adopted: now in target range
```

### Test 2D: Lead Space Already Good
**Setup:** Position yourself with good lead space (20-40% in facing direction)
Face left or right with proper space already

**Expected:** NO lead space guidance (should skip to thirds or show perfect state)

---

## 🧪 3. Edge Density Detection

**Objective:** Verify the app detects when you're too close to strong background edges.

### Test 3A: High-Contrast Edge - Doorframe
**Setup:** Stand next to a doorframe
**Position:** Place your face very close to the doorframe edge (left or right)

**Expected console log:**
```
⚠️ EDGE CONFLICT: left=0.XX, right=0.XX
has_edge_conflict: true
```
One side should show >0.3 edge density

### Test 3B: Window Frame
**Setup:** Position near a window with strong vertical edges
**Get close:** Move face near the window frame edge

**Expected:** Similar edge conflict warning

### Test 3C: Plain Wall (Baseline)
**Setup:** Stand against a plain, uniform wall

**Expected console log:**
```
left_edge_density: 0.0X-0.1X (low)
right_edge_density: 0.0X-0.1X (low)
has_edge_conflict: false
```

### Test 3D: Bookshelf/Strong Vertical Lines
**Setup:** Position near bookshelf or striped background

**Expected:** Edge conflict detected on the side near vertical lines

---

## 🧪 4. Guidance Priority Chain

**Objective:** Verify guidance follows the correct order: Template > Headroom > Lead Space > Thirds > **Perfect**

### Test 4A: Poor Headroom (Should Come First)
**Setup:** Frame your face with too much headroom (>12%) or too little (<7%)
**Have:** Face off-center AND facing left/right

**Expected:** Headroom guidance appears FIRST
```
🎯 HEADROOM GUIDANCE: Tilt up/down, Better crop
```

**Expected:** NO lead space or thirds guidance yet

### Test 4B: Fix Headroom, Then Lead Space
**Fix headroom from Test 4A** (get into 7-12% range)
**Keep:** Face off-center with bad lead space

**Expected:** Now lead space guidance appears
```
✅ Returning LEAD SPACE guidance
"Pan left/right, Room ahead"
```

### Test 4C: Fix Lead Space, Then Thirds
**Fix lead space from Test 4B** (get into 20-40% range)
**Keep:** Face off-center horizontally

**Expected:** Now thirds guidance appears (if offset >15%)
```
guidance.type: thirds
"Pan left/right, Stronger shot"
```

### Test 4D: Everything Perfect → **NEW: Perfect Composition State** ✨
**Setup:** Perfect framing - Good headroom (7-12%), good lead space (20-40%), centered/on thirds

**Expected:** **Perfect composition feedback!**

**Visual indicators:**
1. 🟢 **Shutter Button:** Green ring glow appears, breathing animation (opacity 0.6 ↔ 0.9, 1.5s cycle)
2. 🟢 **GlassPill:** Changes to green tint, shows **"Perfect! Tap to shoot"** / **"完美! 轻触拍摄"**

**Haptic:** Medium tap (stronger than normal guidance)

**Persistence:** Both indicators stay visible while composition remains perfect

**Console log:**
```
✨ PERFECT COMPOSITION DETECTED!
guidance.action: perfect
```

**Test persistence:**
- Hold perfect position for 5 seconds → Glow keeps breathing ✅
- Move slightly off → Glow fades smoothly (300ms), new guidance appears ✅

---

## 🧪 5. Perfect Composition Feedback (NEW - Week 7 UX) ✨

**Objective:** Verify the dual feedback system for perfect composition.

### Test 5A: Achieve Perfect State
**Setup:**
- Headroom: 7-12% of visible preview
- Lead space: 20-40% (if facing left/right)
- Horizontal position: Centered or on thirds line (±15%)
- Face: Stable for ≥300ms

**Expected visual feedback (DUAL):**
1. **Shutter Button:**
   - Green ring glow (SF Green #34C759)
   - 3px thick ring, 4pt outside button
   - Breathing pulse: opacity 0.6 ↔ 0.9 over 1.5s
   - Subtle scale: 1.0 ↔ 1.05
   - Fade in: 200ms ease-out

2. **GlassPill (iOS 26+):**
   - Background changes to green tint
   - Text: "Perfect! Tap to shoot" (English) or "完美! 轻触拍摄" (Chinese)
   - Color transition: 200ms ease-out
   - PERSISTS (does not auto-hide)

**Expected haptic:** Single medium tap (stronger than normal guidance light tap)

### Test 5B: Perfect State Persistence
**Achieve perfect state from 5A**
**Hold position:** Keep perfect composition for 10 seconds

**Expected:**
- Green glow continues breathing animation ✅
- GlassPill stays visible in green ✅
- No auto-hide timeout ✅

### Test 5C: Exit Perfect State
**While in perfect state from 5A**
**Action:** Tilt camera slightly up (worsen headroom)

**Expected:**
- Green glow fades out smoothly (300ms ease-in) ✅
- GlassPill transitions back to white/gray ✅
- New guidance appears: "Tilt down, Better crop" ✅

### Test 5D: Perfect State Re-Entry
**From non-perfect state**
**Action:** Adjust back to perfect composition

**Expected:**
- Green glow fades IN smoothly (200ms ease-out) ✅
- GlassPill changes to green ✅
- Haptic tap triggers ✅
- Response time: < 50ms (feels instant) ✅

### Test 5E: Multiple Perfect Criteria Check
**Test perfect detection logic by satisfying criteria one-by-one:**

**Scenario 1: Only headroom perfect**
- Headroom: 7-12% ✅
- Lead space: Poor ❌
- Result: NO perfect state (shows lead space guidance)

**Scenario 2: Headroom + Lead space perfect**
- Headroom: 7-12% ✅
- Lead space: 20-40% ✅
- Thirds: Off-center >15% ❌
- Result: NO perfect state (shows thirds guidance)

**Scenario 3: All criteria perfect**
- Headroom: 7-12% ✅
- Lead space: 20-40% ✅
- Thirds: Centered OR on thirds line ✅
- Result: **PERFECT STATE** ✨

---

## 🧪 6. Telemetry Validation

**Objective:** Verify all Week 7 metrics are logged correctly.

### Test 6A: Take Photos with Different Orientations
**Left-facing photo:** Take photo while facing left
**Right-facing photo:** Take photo while facing right
**Center photo:** Take photo facing forward

**Check logs after each photo for:**
```
Logger: hint_adopted event with:
- face_orientation: "facing_left" / "facing_right" / "facing_center"
- orientation_confidence: 0.XX
- lead_space_percent: XX.X
- left_edge_density: 0.XX
- right_edge_density: 0.XX
- has_edge_conflict: true/false
```

### Test 6B: Lead Space Adoption Telemetry
**Get lead space guidance**
**Follow the guidance**
**Take photo**

**Check logs:**
```
Logger: hint_adopted
type: leadspace
adopted: true/false
before: { lead_space_percent: "XX.X", face_orientation: "..." }
after: { lead_space_percent: "XX.X", face_orientation: "..." }
```

### Test 6C: Perfect Composition Telemetry
**Achieve perfect state**
**Take photo while in perfect state**

**Check logs:**
```
Logger: hint_shown
type: headroom (used for perfect state)
guidance.action: perfect
confidence: 0.95
```

---

## 🧪 7. Performance & Stability

### Test 7A: FPS Impact
**Monitor console for FPS samples during:**
- Face orientation detection
- Perfect composition state transitions
- Shutter button glow animations

**Expected:** FPS should stay ≥24fps
**Check:** Processing latency ≤80ms (p95)

### Test 7B: Thermal Behavior
**Use for 5+ minutes continuously**
**Monitor:** thermalState in logs
**Expected:** Should handle thermal state gracefully

### Test 7C: Orientation Stability
**Slowly turn head left → center → right**

**Expected:** Orientation changes smoothly with stability gating (70% consistency over 10 frames)
**Should NOT:** Rapidly flicker between orientations

### Test 7D: Animation Performance
**Rapidly achieve and lose perfect state** (move in/out of perfect composition quickly)

**Expected:**
- Glow animations smooth (no stuttering) ✅
- Transitions clean (no visual glitches) ✅
- App remains responsive ✅

---

## 📋 Updated Quick Test Checklist

Copy this to track your testing progress:

### CRITICAL FIXES (Week 7 Latest):
- ☐ **Headroom letterbox fix:** 0-5% at top edge (not 20-23%)
- ☐ **Vertical position fix:** Uses visible preview coords (95%+ at top edge, not 54%)
- ☐ **Context-aware headroom:** FIXED zone logic (upper-third: 0-8%, centered: 7-12%, lower-third: 35-50%)
- ☐ **Gravity-based horizon:** Uses atan2(gravity.x, gravity.y) for TRUE world-relative horizon (matches iPhone Camera)
- ☐ **New guidance language:** "Move up/down" (physical movement, not "Get closer/Step back")
- ☐ **Photographer-focused:** All hints coach camera movements
- ☐ **Chinese localization:** "上抬相机" includes "相机" (camera)

### FACE ORIENTATION:
- ✅ Left profile detection (yaw -45° to -90°)
- ✅ Center/frontal detection (yaw -15° to +15°)
- ✅ Right profile detection (yaw +45° to +90°)

### LEAD SPACE GUIDANCE:
- ☐ Facing left, positioned right → "Pan right, Room ahead"
- ☐ Facing right, positioned left → "Pan left, Room ahead"
- ☐ Lead space adoption tracking works
- ☐ Good lead space → no guidance (or perfect state)

### EDGE DENSITY:
- ☐ Doorframe conflict detected (>0.3 density)
- ☐ Window frame conflict detected
- ☐ Plain wall → no conflict (<0.1 density)
- ☐ Edge density values logged

### GUIDANCE PRIORITY:
- ☐ Headroom comes before lead space
- ☐ Lead space comes before thirds
- ☐ **Perfect state after all criteria satisfied** (NEW)
- ☐ Priority chain enforced

### PERFECT COMPOSITION FEEDBACK (NEW):
- ☐ **Shutter button green ring glow** appears
- ☐ **GlassPill turns green** with "Perfect! Tap to shoot"
- ☐ **Medium haptic tap** on perfect state entry
- ☐ **Glow persists** while composition perfect
- ☐ **Smooth transitions** in/out of perfect state
- ☐ **All criteria must pass:** Headroom + Lead space + Thirds

### TELEMETRY:
- ☐ All 6 new metrics logged (orientation, lead space, edge density)
- ☐ Lead space adoption events recorded
- ☐ Orientation data in telemetry
- ☐ **Perfect composition events logged** (NEW)

### PERFORMANCE:
- ☐ FPS ≥24 maintained
- ☐ No crashes or jank
- ☐ Orientation stable (no flickering)
- ☐ **Glow animations smooth** (NEW)

---

## 📤 What to Share

For each test, please share:

1. **Test number** (e.g., "Test 5A - Perfect State")
2. **Result:** ✅ Pass / ❌ Fail / ⚠️ Partial
3. **Relevant console logs** (especially the 🎯 and ✨ lines)
4. **Screenshots/videos** (especially for perfect composition glow)
5. **Any unexpected behavior**

---

## 🎯 Week 7 Success Criteria

**Must Pass:**
- ✅ Face orientation detection: 100% accuracy
- ✅ Headroom calculation: Correct for letterboxed preview
- ✅ Guidance language: Photographer-focused camera operations
- ✅ Lead space guidance: ≥40% adoption rate
- ✅ Perfect composition: Visual + haptic feedback working
- ✅ Performance: FPS ≥24, latency ≤80ms
- ✅ No crashes or major UX issues

**Metrics to Track:**
- Lead space adoption rate: Target ≥40%
- Edge-merge reduction: Target ≥30%
- Perfect composition trigger frequency
- Time to perfect state from initial guidance
- User satisfaction with new feedback system

---

**Ready to start testing!** 🚀📸

Begin with **Section 0** (Critical Fixes) to verify the foundational improvements, then proceed through the feature tests sequentially.
