//
//  ContentView.swift
//  Camera Coach
//
//  Main SwiftUI view that hosts the camera interface.
//

import SwiftUI

struct ContentView: View {
    // MARK: - Properties
    @StateObject private var logger = Logger.shared
    @StateObject private var feedbackManager = FeedbackManager.shared
    @State private var showingSettings = false
    @State private var showSessionEndFeedback = false
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                // Camera view takes full screen
                CameraView()
                    .ignoresSafeArea()
                
                // Top toolbar
                VStack {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.top, 50)
                        .padding(.trailing, 20)
                    }
                    
                    Spacer()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSessionEndFeedback) {
            MicroSurveyView(
                isPresented: $showSessionEndFeedback,
                onComplete: { helpful, satisfaction in
                    feedbackManager.completeFeedback(helpful: helpful, satisfaction: satisfaction)
                }
            )
        }
        .onChange(of: feedbackManager.feedbackTrigger) { trigger in
            if trigger == .sessionEnd {
                showSessionEndFeedback = true
            }
        }
        .onAppear {
            // Log app launch
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            let deviceModel = UIDevice.current.model
            let osVersion = UIDevice.current.systemVersion
            
            logger.startSession(build: build, deviceModel: deviceModel, osVersion: osVersion)
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var logger = Logger.shared
    @StateObject private var feedbackManager = FeedbackManager.shared
    @State private var postShotCloudEnabled = Config.defaultPostShotCloudEnabled
    @State private var maxDailyUploads = Config.maxDailyCloudUploads
    @State private var showFeedbackModal = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("settings.privacy_data", comment: "Privacy & Data section header")) {
                    Toggle(NSLocalizedString("settings.postshot_cloud", comment: "Post-shot cloud toggle"), isOn: $postShotCloudEnabled)
                        .onChange(of: postShotCloudEnabled) { newValue in
                            logger.logConsentChanged(postShotCloud: newValue)
                        }
                    
                    if postShotCloudEnabled {
                        HStack {
                            Text(NSLocalizedString("settings.daily_upload_limit", comment: "Daily upload limit label"))
                            Spacer()
                            Text("\(maxDailyUploads)")
                        }
                        
                        Stepper("", value: $maxDailyUploads, in: 1...20)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("settings.wifi_only", comment: "Wi-Fi only label"))
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                }
                
                Section(NSLocalizedString("settings.performance", comment: "Performance section header")) {
                    HStack {
                        Text(NSLocalizedString("settings.target_fps", comment: "Target FPS label"))
                        Spacer()
                        Text("\(Config.targetFPS)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("settings.max_latency", comment: "Max latency label"))
                        Spacer()
                        Text("\(Config.maxFrameLoopLatencyMs)ms")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(NSLocalizedString("settings.export_debug", comment: "Export & Debug section header")) {
                    Button(NSLocalizedString("settings.export_logs", comment: "Export logs button")) {
                        exportLogs()
                    }
                    
                    // Strategic feedback collection section
                    if feedbackManager.pendingFeedbackCount > 0 {
                        Button("Help Improve Camera Coach (\(feedbackManager.pendingFeedbackCount) photos)") {
                            showFeedbackModal = true
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Button(NSLocalizedString("settings.reset_settings", comment: "Reset settings button")) {
                        resetSettings()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle(NSLocalizedString("settings.title", comment: "Settings screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("settings.done", comment: "Settings done button")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Strategic feedback trigger - Settings access is user-initiated
            feedbackManager.triggerFeedbackIfReady(.settingsAccess)
        }
        .onChange(of: feedbackManager.shouldShowFeedback) { shouldShow in
            if shouldShow {
                showFeedbackModal = true
            }
        }
        .sheet(isPresented: $showFeedbackModal) {
            MicroSurveyView(
                isPresented: $showFeedbackModal,
                onComplete: { helpful, satisfaction in
                    feedbackManager.completeFeedback(helpful: helpful, satisfaction: satisfaction)
                }
            )
        }
    }
    
    private func exportLogs() {
        if let url = logger.exportLogs() {
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
    
    private func resetSettings() {
        postShotCloudEnabled = Config.defaultPostShotCloudEnabled
        maxDailyUploads = Config.maxDailyCloudUploads
        logger.logConsentChanged(postShotCloud: postShotCloudEnabled)
    }
}

#Preview {
    ContentView()
}
