//
//  ReplayDataSource.swift
//  Camera Coach
//
//  🚀 WEEK 3: Data source for managing sample video clips for replay testing
//  Provides standard test clips for deterministic guidance engine validation
//

import Foundation
import AVFoundation

// MARK: - Sample Clip Models

public struct SampleClip {
    let name: String
    let url: URL
    let description: String
    let expectedScenario: ScenarioType
    let duration: TimeInterval
    let frameCount: Int?
    let tags: [String]
}

public enum ScenarioType: String, CaseIterable {
    case portrait = "portrait"
    case landscape = "landscape"
    case tilted = "tilted"
    case lowHeadroom = "low_headroom"
    case excessiveHeadroom = "excessive_headroom"
    case noFace = "no_face"
    case multipleFaces = "multiple_faces"
    case movingSubject = "moving_subject"
    case mixed = "mixed"
    
    var description: String {
        switch self {
        case .portrait: return "Portrait with single face"
        case .landscape: return "Landscape/outdoor scene"
        case .tilted: return "Tilted horizon requiring correction"
        case .lowHeadroom: return "Face too low, needs more headroom"
        case .excessiveHeadroom: return "Face too high, excessive headroom"
        case .noFace: return "No face detected, horizon guidance only"
        case .multipleFaces: return "Multiple faces, primary subject selection"
        case .movingSubject: return "Subject in motion, stability testing"
        case .mixed: return "Mixed scenario with multiple guidance types"
        }
    }
}

// MARK: - Replay Data Source

public final class ReplayDataSource {
    // MARK: - Properties
    private let samplesDirectory: URL
    private var availableClips: [SampleClip] = []
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    public init() {
        // Create samples directory in Documents/Samples
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        samplesDirectory = documentsPath.appendingPathComponent("Samples")
        
        createSamplesDirectoryIfNeeded()
        loadAvailableClips()
    }
    
    // MARK: - Public Interface
    
    /// Get all available sample clips
    public func getAllClips() -> [SampleClip] {
        return availableClips
    }
    
    /// Get clips for a specific scenario type
    public func getClips(for scenario: ScenarioType) -> [SampleClip] {
        return availableClips.filter { $0.expectedScenario == scenario }
    }
    
    /// Get clips with specific tags
    public func getClips(withTags tags: [String]) -> [SampleClip] {
        return availableClips.filter { clip in
            return tags.allSatisfy { tag in clip.tags.contains(tag) }
        }
    }
    
    /// Create a standard test suite (10 clips covering key scenarios)
    public func getStandardTestSuite() -> [SampleClip] {
        var testSuite: [SampleClip] = []
        
        // Try to get at least one clip from each important scenario
        let priorityScenarios: [ScenarioType] = [
            .portrait, .tilted, .lowHeadroom, .excessiveHeadroom, 
            .noFace, .multipleFaces, .movingSubject
        ]
        
        for scenario in priorityScenarios {
            if let clip = getClips(for: scenario).first {
                testSuite.append(clip)
                if testSuite.count >= 10 { break }
            }
        }
        
        // Fill remaining slots with any available clips
        let remainingClips = availableClips.filter { clip in
            !testSuite.contains { testClip in clip.name == testClip.name }
        }
        let slotsRemaining = 10 - testSuite.count
        testSuite.append(contentsOf: Array(remainingClips.prefix(slotsRemaining)))
        
        return testSuite
    }
    
    /// Add a new sample clip to the data source
    public func addClip(
        name: String,
        videoURL: URL,
        scenario: ScenarioType,
        description: String? = nil,
        tags: [String] = []
    ) throws {
        // Validate video file exists
        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw ReplayDataSourceError.fileNotFound
        }
        
        // Copy to samples directory if not already there
        let destinationURL = samplesDirectory.appendingPathComponent(videoURL.lastPathComponent)
        
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.copyItem(at: videoURL, to: destinationURL)
        }
        
        // Get video metadata
        let asset = AVURLAsset(url: destinationURL)
        let duration = asset.duration.seconds
        let frameCount = try? getFrameCount(for: asset)
        
        let clip = SampleClip(
            name: name,
            url: destinationURL,
            description: description ?? scenario.description,
            expectedScenario: scenario,
            duration: duration,
            frameCount: frameCount,
            tags: tags
        )
        
        availableClips.append(clip)
        saveClipMetadata()
    }
    
    /// Remove a clip from the data source
    public func removeClip(named clipName: String) throws {
        guard let clipIndex = availableClips.firstIndex(where: { $0.name == clipName }) else {
            throw ReplayDataSourceError.clipNotFound
        }
        
        let clip = availableClips[clipIndex]
        
        // Remove file
        if fileManager.fileExists(atPath: clip.url.path) {
            try fileManager.removeItem(at: clip.url)
        }
        
        // Remove from array
        availableClips.remove(at: clipIndex)
        saveClipMetadata()
    }
    
    /// Generate mock clips for development/testing when no real clips are available
    public func generateMockClips() {
        availableClips = [
            SampleClip(
                name: "portrait_centered",
                url: samplesDirectory.appendingPathComponent("portrait_centered.mp4"),
                description: "Well-composed portrait with good headroom",
                expectedScenario: .portrait,
                duration: 5.0,
                frameCount: 150,
                tags: ["stable", "good_lighting", "single_face"]
            ),
            SampleClip(
                name: "portrait_low_headroom",
                url: samplesDirectory.appendingPathComponent("portrait_low_headroom.mp4"),
                description: "Portrait with face too low in frame",
                expectedScenario: .lowHeadroom,
                duration: 8.0,
                frameCount: 240,
                tags: ["needs_improvement", "headroom", "single_face"]
            ),
            SampleClip(
                name: "landscape_tilted",
                url: samplesDirectory.appendingPathComponent("landscape_tilted.mp4"),
                description: "Outdoor landscape with tilted horizon",
                expectedScenario: .tilted,
                duration: 6.0,
                frameCount: 180,
                tags: ["horizon", "outdoor", "no_face"]
            ),
            SampleClip(
                name: "group_photo",
                url: samplesDirectory.appendingPathComponent("group_photo.mp4"),
                description: "Multiple people, primary subject selection test",
                expectedScenario: .multipleFaces,
                duration: 4.0,
                frameCount: 120,
                tags: ["multiple_faces", "subject_selection", "challenging"]
            ),
            SampleClip(
                name: "moving_portrait",
                url: samplesDirectory.appendingPathComponent("moving_portrait.mp4"),
                description: "Person moving, stability tracking test",
                expectedScenario: .movingSubject,
                duration: 10.0,
                frameCount: 300,
                tags: ["motion", "stability", "tracking"]
            )
        ]
    }
    
    // MARK: - Private Implementation
    
    private func createSamplesDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: samplesDirectory.path) {
            try? fileManager.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func loadAvailableClips() {
        // Load clip metadata from JSON file
        let metadataURL = samplesDirectory.appendingPathComponent("clips_metadata.json")
        
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let clipData = try? JSONDecoder().decode([ClipMetadata].self, from: data) else {
            // No saved metadata, scan directory for video files
            scanDirectoryForClips()
            return
        }
        
        // Convert metadata to SampleClip objects
        availableClips = clipData.compactMap { metadata in
            let clipURL = samplesDirectory.appendingPathComponent(metadata.fileName)
            guard fileManager.fileExists(atPath: clipURL.path) else { return nil }
            
            return SampleClip(
                name: metadata.name,
                url: clipURL,
                description: metadata.description,
                expectedScenario: ScenarioType(rawValue: metadata.scenario) ?? .mixed,
                duration: metadata.duration,
                frameCount: metadata.frameCount,
                tags: metadata.tags
            )
        }
    }
    
    private func scanDirectoryForClips() {
        guard let contents = try? fileManager.contentsOfDirectory(at: samplesDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        let videoExtensions = ["mp4", "mov", "m4v"]
        let videoFiles = contents.filter { url in
            videoExtensions.contains(url.pathExtension.lowercased())
        }
        
        for videoURL in videoFiles {
            let asset = AVURLAsset(url: videoURL)
            let duration = asset.duration.seconds
            let name = videoURL.deletingPathExtension().lastPathComponent

            let clip = SampleClip(
                name: name,
                url: videoURL,
                description: generateDescription(for: name),
                expectedScenario: detectScenario(from: name),
                duration: duration,
                frameCount: try? getFrameCount(for: asset),
                tags: generateTags(for: name)
            )

            availableClips.append(clip)
        }
        
        saveClipMetadata()
    }

    // MARK: - Clip Detection Helpers

    private func detectScenario(from filename: String) -> ScenarioType {
        let name = filename.lowercased()

        // Exact matches for your clip names
        if name.contains("portrait") && name.contains("good") { return .portrait }
        if name.contains("tilted") && name.contains("horizon") { return .tilted }
        if name.contains("low") && name.contains("headroom") { return .lowHeadroom }
        if name.contains("excessive") && name.contains("headroom") { return .excessiveHeadroom }
        if name.contains("no_face") { return .noFace }
        if name.contains("multiple") && name.contains("faces") { return .multipleFaces }
        if name.contains("moving") && name.contains("subject") { return .movingSubject }
        if name.contains("outdoor") && name.contains("scene") { return .landscape }
        if name.contains("thirds") && name.contains("composition") { return .mixed }  // thirds composition test
        if name.contains("mixed") && name.contains("scenario") { return .mixed }

        return .mixed
    }

    private func generateDescription(for filename: String) -> String {
        let scenario = detectScenario(from: filename)
        return scenario.description
    }

    private func generateTags(for filename: String) -> [String] {
        let name = filename.lowercased()
        var tags = ["auto_detected"]

        if name.contains("portrait") { tags.append("single_face") }
        if name.contains("good") { tags.append("reference_quality") }
        if name.contains("headroom") { tags.append("headroom_test") }
        if name.contains("horizon") { tags.append("horizon_test") }
        if name.contains("multiple") { tags.append("multi_face") }
        if name.contains("moving") { tags.append("stability_test") }
        if name.contains("outdoor") { tags.append("landscape") }
        if name.contains("thirds") { tags.append("composition_test") }
        if name.contains("tilted") { tags.append("rotation_needed") }
        if name.contains("no_face") { tags.append("no_face") }

        return tags
    }

    private func saveClipMetadata() {
        let metadata = availableClips.map { clip in
            ClipMetadata(
                name: clip.name,
                fileName: clip.url.lastPathComponent,
                description: clip.description,
                scenario: clip.expectedScenario.rawValue,
                duration: clip.duration,
                frameCount: clip.frameCount,
                tags: clip.tags
            )
        }
        
        let metadataURL = samplesDirectory.appendingPathComponent("clips_metadata.json")
        
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            print("Failed to save clip metadata: \(error)")
        }
    }
    
    private func getFrameCount(for asset: AVAsset) throws -> Int {
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ReplayDataSourceError.invalidVideo
        }
        
        let frameRate = track.nominalFrameRate
        let duration = asset.duration.seconds
        
        return Int(Float(duration) * frameRate)
    }
}

// MARK: - Supporting Types

private struct ClipMetadata: Codable {
    let name: String
    let fileName: String
    let description: String
    let scenario: String
    let duration: TimeInterval
    let frameCount: Int?
    let tags: [String]
}

// MARK: - Errors

public enum ReplayDataSourceError: Error, LocalizedError {
    case fileNotFound
    case clipNotFound
    case invalidVideo
    case directoryNotAccessible
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Video file not found"
        case .clipNotFound:
            return "Sample clip not found"
        case .invalidVideo:
            return "Invalid video format"
        case .directoryNotAccessible:
            return "Cannot access samples directory"
        }
    }
}

// Note: AVAssetTrack.nominalFrameRate is already available in iOS SDK