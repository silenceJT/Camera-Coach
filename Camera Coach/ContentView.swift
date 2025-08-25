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
    @State private var showingSettings = false
    
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
    @State private var postShotCloudEnabled = Config.defaultPostShotCloudEnabled
    @State private var maxDailyUploads = Config.maxDailyCloudUploads
    
    var body: some View {
        NavigationView {
            Form {
                Section("Privacy & Data") {
                    Toggle("Post-shot Cloud Analysis", isOn: $postShotCloudEnabled)
                        .onChange(of: postShotCloudEnabled) { newValue in
                            logger.logConsentChanged(postShotCloud: newValue)
                        }
                    
                    if postShotCloudEnabled {
                        HStack {
                            Text("Daily Upload Limit")
                            Spacer()
                            Text("\(maxDailyUploads)")
                        }
                        
                        Stepper("", value: $maxDailyUploads, in: 1...20)
                    }
                    
                    HStack {
                        Text("Wi-Fi Only")
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                }
                
                Section("Performance") {
                    HStack {
                        Text("Target FPS")
                        Spacer()
                        Text("\(Config.targetFPS)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Max Latency")
                        Spacer()
                        Text("\(Config.maxFrameLoopLatencyMs)ms")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Export & Debug") {
                    Button("Export Logs") {
                        exportLogs()
                    }
                    
                    Button("Reset Settings") {
                        resetSettings()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
