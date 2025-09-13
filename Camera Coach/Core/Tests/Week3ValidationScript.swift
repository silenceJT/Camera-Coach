//
//  Week3ValidationScript.swift
//  Camera Coach
//
//  🚀 WEEK 3: Standalone validation script for Week 3 completion testing
//  Run this to validate all Week 3 requirements are met
//

import Foundation

// MARK: - Week 3 Validation Script

public final class Week3ValidationScript {
    private let testRunner = ReplayTestRunner()
    
    /// Run complete Week 3 validation and print results
    public func runValidation() {
        print("🚀 Starting Week 3 Validation Suite...")
        print("=====================================")
        
        testRunner.runWeek3ValidationSuite { result in
            switch result {
            case .success(let testResult):
                let report = self.testRunner.generateTestReport(result: testResult)
                print(report)
                
                // Save report to file
                self.saveReportToFile(report: report)
                
                // Exit with appropriate code
                exit(testResult.passRate >= 0.8 ? 0 : 1)
                
            case .failure(let error):
                print("❌ Validation failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        
        // Keep the script running
        RunLoop.main.run()
    }
    
    private func saveReportToFile(report: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Int(Date().timeIntervalSince1970)
        let reportURL = documentsPath.appendingPathComponent("week3_validation_\(timestamp).txt")
        
        do {
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            print("\n📄 Report saved to: \(reportURL.path)")
        } catch {
            print("\n⚠️ Failed to save report: \(error.localizedDescription)")
        }
    }
}

// MARK: - Main Execution

func runWeek3Validation() {
    let validator = Week3ValidationScript()
    validator.runValidation()
}

// Uncomment to run validation
// runWeek3Validation()