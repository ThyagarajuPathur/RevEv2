//
//  AudioEngineService.swift
//  RevEv
//

import Foundation
import AVFoundation
import QuartzCore

/// Audio engine service for dynamic engine sound generation
@Observable
@MainActor
final class AudioEngineService {
    // MARK: - Published State

    private(set) var isPlaying = false
    private(set) var currentProfile: EngineProfile = .v8Muscle
    private(set) var currentPitch: Float = 0
    private(set) var volume: Float = 1.0

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?

    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?

    private var displayLink: CADisplayLink?
    private var targetRPM: Int = 0
    private var currentRPM: Float = 0
    private let smoothingFactor: Float = 0.12

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    // MARK: - Public Methods

    /// Load an engine profile and prepare for playback
    func loadProfile(_ profile: EngineProfile) {
        currentProfile = profile

        // Try to load the audio file
        guard let url = Bundle.main.url(forResource: profile.audioFileName, withExtension: "wav") else {
            print("Audio file not found: \(profile.audioFileName).wav")
            return
        }

        do {
            audioFile = try AVAudioFile(forReading: url)
            prepareBuffer()
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }

    /// Start engine sound playback
    func start() {
        guard !isPlaying else { return }

        setupAudioEngine()
        startDisplayLink()
        isPlaying = true
    }

    /// Stop engine sound playback
    func stop() {
        isPlaying = false
        stopDisplayLink()

        playerNode?.stop()
        audioEngine?.stop()

        playerNode = nil
        timePitchNode = nil
        audioEngine = nil
    }

    /// Update target RPM for pitch calculation
    func updateRPM(_ rpm: Int) {
        targetRPM = rpm
    }

    /// Set playback volume
    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
        playerNode?.volume = self.volume
    }

    /// Change engine profile
    func changeProfile(to profile: EngineProfile) {
        let wasPlaying = isPlaying

        if isPlaying {
            stop()
        }

        loadProfile(profile)

        if wasPlaying {
            start()
        }
    }

    // MARK: - Private Methods

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitchNode = AVAudioUnitTimePitch()

        guard let engine = audioEngine,
              let player = playerNode,
              let pitch = timePitchNode,
              let buffer = audioBuffer else {
            return
        }

        // Attach nodes
        engine.attach(player)
        engine.attach(pitch)

        // Connect nodes: Player -> TimePitch -> MainMixer -> Output
        let format = buffer.format
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)

        // Configure
        player.volume = volume
        pitch.pitch = 0

        do {
            try engine.start()

            // Schedule looped playback
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func prepareBuffer() {
        guard let file = audioFile else { return }

        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return
        }

        do {
            try file.read(into: buffer)
            audioBuffer = buffer
        } catch {
            print("Failed to read audio file into buffer: \(error)")
        }
    }

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: DisplayLinkTarget(handler: { [weak self] in
            self?.tick()
        }), selector: #selector(DisplayLinkTarget.handleDisplayLink))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        // Exponential smoothing for RPM
        let targetFloat = Float(targetRPM)
        currentRPM += (targetFloat - currentRPM) * smoothingFactor

        // Calculate pitch in cents
        let pitch = calculatePitch(for: currentRPM)
        currentPitch = pitch

        timePitchNode?.pitch = pitch
    }

    /// Calculate pitch shift in cents based on RPM
    private func calculatePitch(for rpm: Float) -> Float {
        let profile = currentProfile
        let baseRPM = Float(max(profile.baseRPM, 1))
        let minRPM = Float(profile.minRPM)
        let maxRPM = Float(profile.maxRPM)

        // Clamp RPM to valid range
        let clampedRPM = max(minRPM, min(maxRPM, rpm))

        // Normalize RPM (0 to 1)
        let normalizedRPM = (clampedRPM - baseRPM) / (maxRPM - baseRPM)
        let clampedNormalized = max(0, min(1, normalizedRPM))

        // Logarithmic pitch scaling
        // 1200 cents = 1 octave
        // Using log2 for musical pitch relationship
        let pitchMultiplier = 1.0 + clampedNormalized * 1.5
        let pitchCents = 1200.0 * log2(pitchMultiplier)

        return Float(pitchCents)
    }
}

/// Helper class for CADisplayLink target
private class DisplayLinkTarget {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func handleDisplayLink() {
        handler()
    }
}
