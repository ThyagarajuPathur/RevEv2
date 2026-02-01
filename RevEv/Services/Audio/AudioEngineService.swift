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
    private(set) var volume: Float = 1.5  // Base volume boost

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?

    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?

    private var displayLink: CADisplayLink?
    private var targetRPM: Int = 0
    private var currentRPM: Float = 0
    private var currentPitchSmooth: Float = 0

    // RPM change rate (units per frame at 60fps) - higher = faster response
    private let rpmChangeRate: Float = 800

    // Pitch smoothing for silky transitions
    private let pitchSmoothingFactor: Float = 0.3

    // Volume scaling - louder overall
    private let minVolume: Float = 0.7   // Volume at idle
    private let maxVolume: Float = 1.5   // Volume at max RPM (boost above 1.0)

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

    /// Set playback volume (allows boost above 1.0)
    func setVolume(_ volume: Float) {
        self.volume = max(0, min(2.0, volume))
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
            // Set low latency buffer for responsive audio (0.005 = 5ms)
            try session.setPreferredIOBufferDuration(0.005)
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
        // Linear interpolation for RPM (responsive but not jumpy)
        let targetFloat = Float(targetRPM)
        let rpmDiff = targetFloat - currentRPM

        if abs(rpmDiff) < rpmChangeRate {
            currentRPM = targetFloat
        } else {
            currentRPM += rpmDiff > 0 ? rpmChangeRate : -rpmChangeRate
        }

        // Calculate target pitch
        let targetPitch = calculatePitch(for: currentRPM)

        // Smooth pitch transitions (prevents audible stepping)
        currentPitchSmooth += (targetPitch - currentPitchSmooth) * pitchSmoothingFactor
        currentPitch = currentPitchSmooth
        timePitchNode?.pitch = currentPitchSmooth

        // Smooth volume changes
        let targetVolume = calculateVolume(for: currentRPM) * volume
        let currentVol = playerNode?.volume ?? targetVolume
        playerNode?.volume = currentVol + (targetVolume - currentVol) * pitchSmoothingFactor
    }

    /// Calculate volume based on RPM - louder at higher RPM
    private func calculateVolume(for rpm: Float) -> Float {
        let maxRPM = Float(currentProfile.maxRPM)
        let absRPM = abs(rpm)

        // Normalize RPM (0 to 1)
        let normalizedRPM = min(1.0, absRPM / maxRPM)

        // Linear interpolation from minVolume to maxVolume
        return minVolume + (maxVolume - minVolume) * normalizedRPM
    }

    /// Calculate pitch shift in cents based on RPM
    private func calculatePitch(for rpm: Float) -> Float {
        let profile = currentProfile
        let maxRPM = Float(profile.maxRPM)

        // For EV: use absolute RPM (motor speed regardless of direction)
        // Negative RPM = regen braking, Positive RPM = driving
        // Both should increase pitch based on motor speed
        let absRPM = abs(rpm)

        // Normalize RPM (0 to 1)
        let normalizedRPM = min(1.0, absRPM / maxRPM)

        // Logarithmic pitch scaling for natural engine sound
        // 1200 cents = 1 octave
        // Range: 0 RPM = base pitch, max RPM = +1.5 octaves
        let pitchMultiplier = 1.0 + Double(normalizedRPM) * 1.5
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
