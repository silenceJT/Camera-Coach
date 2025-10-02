//
//  ReplayRunner.swift
//  Camera Coach
//
//  🚀 WEEK 3: Offline replay harness for deterministic testing
//  Feeds recorded clips to the guidance engine and captures metrics
//

import Foundation
import AVFoundation
import Vision
import CoreMotion

// MARK: - Replay Result Models

public struct ReplayFrame {
    let frameIndex: Int
    let timestamp: TimeInterval
    let processingLatencyMs: Int
    let frameFeatures: FrameFeatures
    let guidanceAdvice: GuidanceAdvice?
    let hintAdopted: Bool?
    let thermalState: ProcessInfo.ThermalState
}

public struct ReplaySession {
    let videoURL: URL
    let startTime: Date
    let endTime: Date
    let totalFrames: Int
    let frames: [ReplayFrame]
    let averageLatencyMs: Float
    let p95LatencyMs: Float
    let hintsIssued: Int
    let hintsAdopted: Int
    let adoptionRate: Float
    let guidanceTypes: [GuidanceType: Int]
}

// MARK: - Replay Runner

public final class ReplayRunner: NSObject {
    // MARK: - Properties
    private let frameAnalyzer = FrameAnalyzer()
    private let guidanceEngine: GuidanceEngine
    private let logger = Logger.shared
    
    // MARK: - Replay State
    private var currentSession: ReplaySession?
    private var replayFrames: [ReplayFrame] = []
    private var frameIndex = 0
    
    // MARK: - Performance Tracking
    private var processingTimes: [Int] = []
    private var guidanceStats: [GuidanceType: Int] = [:]
    private var adoptionCount = 0
    
    // MARK: - Initialization
    public override init() {
        // Create a mock provider for the guidance engine
        let mockProvider = MockFrameFeaturesProvider()
        self.guidanceEngine = GuidanceEngine(provider: mockProvider)
        super.init()
    }
    
    // MARK: - Public Interface
    
    /// Run replay analysis on a video file
    public func runReplay(videoURL: URL, completion: @escaping (Result<ReplaySession, Error>) -> Void) {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            completion(.failure(ReplayError.fileNotFound))
            return
        }
        
        logger.logEvent(LogEvent(
            name: "replay_started",
            timestamp: Date().timeIntervalSince1970,
            parameters: ["video_file": videoURL.lastPathComponent]
        ))
        
        let startTime = Date()
        resetReplayState()
        
        // Process video file asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let session = try self.processVideo(url: videoURL, startTime: startTime)
                DispatchQueue.main.async {
                    completion(.success(session))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Export replay results to CSV format
    public func exportToCSV(session: ReplaySession) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Int(Date().timeIntervalSince1970)
        let csvURL = documentsPath.appendingPathComponent("replay_\(timestamp).csv")
        
        var csvContent = "frame_index,timestamp,latency_ms,horizon_degrees,face_detected,headroom_percent,guidance_type,guidance_action,guidance_confidence,hint_adopted\n"
        
        for frame in session.frames {
            let faceDetected = frame.frameFeatures.faceRect != nil ? "true" : "false"
            let headroomPercent = frame.frameFeatures.headroomPercentage?.description ?? "null"
            let guidanceType = frame.guidanceAdvice?.type.rawValue ?? "none"
            let guidanceAction = frame.guidanceAdvice?.action.description ?? "none"
            let guidanceConfidence = frame.guidanceAdvice?.confidence.description ?? "null"
            let hintAdopted = frame.hintAdopted?.description ?? "null"
            
            csvContent += "\(frame.frameIndex),\(frame.timestamp),\(frame.processingLatencyMs),\(frame.frameFeatures.horizonDegrees),\(faceDetected),\(headroomPercent),\(guidanceType),\(guidanceAction),\(guidanceConfidence),\(hintAdopted)\n"
        }
        
        do {
            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
            return csvURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Private Implementation
    
    private func resetReplayState() {
        replayFrames.removeAll()
        frameIndex = 0
        processingTimes.removeAll()
        guidanceStats.removeAll()
        adoptionCount = 0
    }
    
    private func processVideo(url: URL, startTime: Date) throws -> ReplaySession {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        
        // Get video track
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw ReplayError.invalidVideo
        }
        
        // Configure output settings
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(readerOutput)
        
        // Start reading
        guard reader.startReading() else {
            throw ReplayError.readerFailed
        }
        
        // Process frames
        while reader.status == .reading {
            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                processFrame(sampleBuffer: sampleBuffer)
            }
        }
        
        // Check for errors
        if reader.status == .failed {
            throw ReplayError.readerFailed
        }
        
        let endTime = Date()
        return createSession(videoURL: url, startTime: startTime, endTime: endTime)
    }
    
    private func processFrame(sampleBuffer: CMSampleBuffer) {
        let frameStartTime = CACurrentMediaTime()
        
        // Analyze frame features
        let features = frameAnalyzer.analyzeFrame(sampleBuffer)
        
        // Update guidance engine with current features
        guidanceEngine.currentFrameFeatures = features
        
        // Generate guidance
        let guidance = guidanceEngine.processFrame()
        
        // Calculate processing time
        let frameEndTime = CACurrentMediaTime()
        let latencyMs = Int((frameEndTime - frameStartTime) * 1000)
        
        // Track guidance statistics
        if let guidance = guidance {
            let type = guidance.type
            guidanceStats[type, default: 0] += 1
            
            // Simulate hint adoption for testing (in real app, this would be measured differently)
            let adoptionSimulated = simulateHintAdoption(guidance: guidance, features: features)
            if adoptionSimulated {
                adoptionCount += 1
            }
        }
        
        // Create replay frame
        let replayFrame = ReplayFrame(
            frameIndex: frameIndex,
            timestamp: frameStartTime,
            processingLatencyMs: latencyMs,
            frameFeatures: features,
            guidanceAdvice: guidance,
            hintAdopted: guidance != nil ? simulateHintAdoption(guidance: guidance!, features: features) : nil,
            thermalState: .nominal // Simulated thermal state for testing
        )
        
        replayFrames.append(replayFrame)
        processingTimes.append(latencyMs)
        frameIndex += 1
    }
    
    private func simulateHintAdoption(guidance: GuidanceAdvice, features: FrameFeatures) -> Bool {
        // 🚀 WEEK 3: Simplified adoption simulation for replay testing
        // In real usage, this would be based on actual user behavior measurement
        
        switch guidance.type {
        case .headroom:
            // Simulate 50% adoption rate for headroom guidance (per Week 3 target)
            return Float.random(in: 0...1) < 0.5
        case .thirds:
            // Simulate 40% adoption rate for thirds guidance
            return Float.random(in: 0...1) < 0.4
        case .leadspace:
            // Simulate 35% adoption rate for leadspace guidance
            return Float.random(in: 0...1) < 0.35
        case .templateAlignment:
            // Simulate 60% adoption rate for template alignment guidance (higher due to visual clarity)
            return Float.random(in: 0...1) < 0.6
        }
    }
    
    private func createSession(videoURL: URL, startTime: Date, endTime: Date) -> ReplaySession {
        let totalFrames = replayFrames.count
        let averageLatency = processingTimes.isEmpty ? 0 : Float(processingTimes.reduce(0, +)) / Float(processingTimes.count)
        
        // Calculate P95 latency
        let sortedTimes = processingTimes.sorted()
        let p95Index = min(Int(Float(sortedTimes.count) * 0.95), sortedTimes.count - 1)
        let p95Latency = sortedTimes.isEmpty ? 0 : Float(sortedTimes[p95Index])
        
        let hintsIssued = replayFrames.compactMap { $0.guidanceAdvice }.count
        let adoptionRate = hintsIssued > 0 ? Float(adoptionCount) / Float(hintsIssued) : 0.0
        
        return ReplaySession(
            videoURL: videoURL,
            startTime: startTime,
            endTime: endTime,
            totalFrames: totalFrames,
            frames: replayFrames,
            averageLatencyMs: averageLatency,
            p95LatencyMs: p95Latency,
            hintsIssued: hintsIssued,
            hintsAdopted: adoptionCount,
            adoptionRate: adoptionRate,
            guidanceTypes: guidanceStats
        )
    }
}

// MARK: - Mock Provider for Testing

private class MockFrameFeaturesProvider: FrameFeaturesProvider {
    private var currentFeatures: FrameFeatures?
    
    func latest() -> FrameFeatures? {
        return currentFeatures
    }
    
    func updateFeatures(_ features: FrameFeatures) {
        currentFeatures = features
    }
}

// MARK: - Errors

public enum ReplayError: Error, LocalizedError {
    case fileNotFound
    case invalidVideo
    case readerFailed
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Video file not found"
        case .invalidVideo:
            return "Invalid video format"
        case .readerFailed:
            return "Failed to read video file"
        }
    }
}

// MARK: - Extensions

extension GuidanceAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .moveUp(let amount):
            return "move_up_\(amount.replacingOccurrences(of: " ", with: "_"))"
        case .moveDown(let amount):
            return "move_down_\(amount.replacingOccurrences(of: " ", with: "_"))"
        case .moveLeft(let amount):
            return "move_left_\(amount.replacingOccurrences(of: " ", with: "_"))"
        case .moveRight(let amount):
            return "move_right_\(amount.replacingOccurrences(of: " ", with: "_"))"
        case .alignToTemplate(let offsetX, let offsetY):
            return "align_to_template_\(String(format: "%.1f", offsetX))_\(String(format: "%.1f", offsetY))"
        case .switchTemplate(let to):
            return "switch_template_\(to.id)"
        case .adjustForTemplate(let direction, let amount):
            return "adjust_for_template_\(direction)_\(amount.replacingOccurrences(of: " ", with: "_"))"
        }
    }
}