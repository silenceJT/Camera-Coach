# Camera Coach 📸

An intelligent iOS camera app that provides real-time guidance to help you take better photos through AI-powered composition coaching.

## 🎯 What is Camera Coach?

Camera Coach is an iOS app that analyzes your camera feed in real-time and provides actionable, one-sentence guidance to improve your photography composition. Whether you're trying to capture the perfect moment or just want to improve your photo skills, Camera Coach gives you instant feedback on:

- **Horizon alignment** - Keep your photos straight
- **Headroom balance** - Perfect framing for portraits
- **Rule of thirds** - Professional composition
- **Subject positioning** - Better framing and balance

## ✨ Key Features

- **Real-time guidance** - Get instant feedback as you frame your shot
- **On-device AI** - All analysis happens locally for privacy and speed
- **One-sentence coaching** - Clear, actionable advice without overwhelming you
- **Smart timing** - Guidance appears when you need it, not when you don't
- **Privacy-first** - No cloud uploads unless you explicitly opt-in
- **Performance optimized** - Smooth 30fps operation with thermal awareness

## 🚀 Getting Started

### Prerequisites

- iOS 17.0 or later
- iPhone 12 Pro or newer
- Camera permission

### Installation

1. Clone the repository:
   ```bash
   git clone git@github.com:silenceJT/Camera-Coach.git
   cd Camera-Coach
   ```

2. Open `Camera Coach.xcodeproj` in Xcode 15.0 or later

3. Build and run on your device (simulator won't have camera access)

## 🏗️ Architecture

The app follows a clean, modular architecture:

```
UIKit Camera VC → Analyzer (Vision + CoreMotion) → GuidanceEngine (FSM) → HUD Overlay
                                               ↘ Logger (events/metrics)
SwiftUI screens ⇄ Camera VC via UIViewControllerRepresentable
```

### Core Components

- **CameraController** - Handles camera session and frame capture
- **FrameAnalyzer** - Processes frames using Vision and CoreMotion
- **GuidanceEngine** - State machine that determines when and what guidance to show
- **HUDOverlay** - Displays guidance text with smooth animations
- **Logger** - Tracks performance metrics and user interactions

## 📱 How It Works

1. **Frame Analysis**: The app continuously analyzes your camera feed using Apple's Vision framework and CoreMotion
2. **Guidance Decision**: A deterministic state machine decides when to show guidance based on priority rules
3. **Smart Timing**: Guidance only appears when stable conditions are detected (≥300ms) with appropriate cooldowns
4. **Actionable Advice**: You receive one-sentence suggestions like "Tilt up 5° for better headroom" or "Rotate left 3° to level the horizon"

## 🎨 Guidance Priority System

The app follows a strict priority order to avoid overwhelming you:

1. **Headroom** (portrait framing) - Most important for people photos
2. **Horizon** (level alignment) - Critical for landscape and general photos  
3. **Rule of Thirds** (composition) - Professional framing guidance
4. **Lead Space** (subject positioning) - Advanced composition rules

## 🔒 Privacy & Data

- **Live preview**: All analysis happens locally on your device
- **Post-shot cloud**: Optional, opt-in only, with explicit consent
- **No tracking**: We don't collect personal data or analytics
- **Wi-Fi only**: Cloud features only work on Wi-Fi connections
- **Daily limits**: Configurable caps on cloud uploads
- **Delete all**: Easy way to remove all your data

## 🚧 Development Status

This is an MVP (Minimum Viable Product) currently in active development. The project follows a 12-week roadmap with weekly TestFlight releases.

### Current Phase: Week 1
- ✅ Project setup and basic camera functionality
- 🔄 Core architecture implementation
- 📋 FSM guidance engine development

## 🛠️ Technical Details

- **Language**: Swift 5.9+
- **Framework**: iOS 17+ with AVFoundation, Vision, CoreMotion
- **UI**: SwiftUI + UIKit hybrid approach
- **Performance**: Target 30fps with 24fps fallback for thermal management
- **Latency**: p95 frame processing ≤80ms

## 📊 Success Metrics

The app is designed to achieve:
- **One-shot success**: First hint → shutter ≤6s with photo kept
- **User satisfaction**: Target 4.0/5 rating by Week 10
- **Stability**: <0.5% crash rate by Week 10

## 🤝 Contributing

This is currently a solo MVP project, but contributions are welcome! Please see the engineering rules and architecture documentation in the project for development guidelines.

## 📄 License

This project is proprietary and confidential. All rights reserved.

## 📞 Support

For questions or support, please open an issue in this repository.

---

**Built with ❤️ for better photography**
