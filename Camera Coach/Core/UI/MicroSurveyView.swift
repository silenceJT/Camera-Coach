//
//  MicroSurveyView.swift
//  Camera Coach
//
//  Post-shot micro survey for guidance effectiveness.
//  Week 2 requirement: helpful? (Y/N) + satisfaction (1-5).
//

import SwiftUI

public struct MicroSurveyView: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let onComplete: (Bool, Int) -> Void
    
    @State private var isHelpful: Bool? = nil
    @State private var satisfaction: Int = 3
    @State private var showingThankYou = false
    
    // MARK: - Body
    public var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on background tap (counts as skip)
                    dismissSurvey()
                }
            
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text(NSLocalizedString("survey.title", comment: "Micro survey title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(NSLocalizedString("survey.subtitle", comment: "Micro survey subtitle"))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // Helpful Y/N buttons
                HStack(spacing: 20) {
                    Button(action: {
                        isHelpful = false
                        submitSurvey()
                    }) {
                        VStack {
                            Image(systemName: "hand.thumbsdown")
                                .font(.title)
                                .foregroundColor(isHelpful == false ? .red : .white.opacity(0.7))
                            
                            Text(NSLocalizedString("survey.no", comment: "Survey no button"))
                                .font(.caption)
                                .foregroundColor(isHelpful == false ? .red : .white.opacity(0.7))
                        }
                        .frame(width: 80, height: 60)
                        .background(Color.white.opacity(isHelpful == false ? 0.2 : 0.1))
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        isHelpful = true
                        submitSurvey()
                    }) {
                        VStack {
                            Image(systemName: "hand.thumbsup")
                                .font(.title)
                                .foregroundColor(isHelpful == true ? .green : .white.opacity(0.7))
                            
                            Text(NSLocalizedString("survey.yes", comment: "Survey yes button"))
                                .font(.caption)
                                .foregroundColor(isHelpful == true ? .green : .white.opacity(0.7))
                        }
                        .frame(width: 80, height: 60)
                        .background(Color.white.opacity(isHelpful == true ? 0.2 : 0.1))
                        .cornerRadius(12)
                    }
                }
                
                // Satisfaction rating (1-5 stars)
                VStack(spacing: 12) {
                    Text(NSLocalizedString("survey.satisfaction", comment: "Survey satisfaction rating"))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { rating in
                            Button(action: {
                                satisfaction = rating
                            }) {
                                Image(systemName: rating <= satisfaction ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(rating <= satisfaction ? .yellow : .white.opacity(0.4))
                            }
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    Button(NSLocalizedString("survey.skip", comment: "Survey skip button")) {
                        dismissSurvey()
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .font(.subheadline)
                    
                    Spacer()
                    
                    Button(NSLocalizedString("survey.submit", comment: "Survey submit button")) {
                        submitSurvey()
                    }
                    .foregroundColor(.blue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.9))
            .cornerRadius(16)
            .padding(.horizontal, 32)
            
            // Thank you overlay
            if showingThankYou {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    
                    Text(NSLocalizedString("survey.thank_you", comment: "Survey thank you message"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.9))
                .cornerRadius(16)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingThankYou)
    }
    
    // MARK: - Private Methods
    private func submitSurvey() {
        // Show thank you briefly, then complete
        withAnimation {
            showingThankYou = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onComplete(isHelpful ?? true, satisfaction)
            isPresented = false
        }
    }
    
    private func dismissSurvey() {
        // Count skip as neutral feedback
        onComplete(true, 3)
        isPresented = false
    }
}

// MARK: - Preview
#Preview {
    MicroSurveyView(
        isPresented: .constant(true),
        onComplete: { helpful, satisfaction in
            print("Survey completed: helpful=\(helpful), satisfaction=\(satisfaction)")
        }
    )
}