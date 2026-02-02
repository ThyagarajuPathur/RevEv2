//
//  AudioEngineService.swift
//  RevEv
//

import Foundation
import AVFoundation
import QuartzCore

/// Represents a single audio layer with its own player and varispeed
private struct AudioLayerNode {
    let layer: AudioLayer
    let playerNode: AVAudioPlayerNode
    let varispeedNode: AVAudioUnitVarispeed
    let buffer: AVAudioPCMBuffer
}

/// Audio engine service for dynamic engine sound generation with crossfading layers
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
    private var layerNodes: [AudioLayerNode] = []

    private var displayLink: CADisplayLink?
    private var targetRPM: Int = 0
    private var currentRPM: Float = 0

    // Volume scaling
    private let minVolume: Float = 0.7   // Volume at idle
    private let maxVolume: Float = 1.5   // Volume at max RPM

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    // MARK: - Public Methods

    /// Load an engine profile and prepare all layers for playback
    func loadProfile(_ profile: EngineProfile) {
        currentProfile = profile
        layerNodes = []

        // Load each layer's audio file
        for layer in profile.layers {
            guard let url = Bundle.main.url(forResource: layer.fileName, withExtension: "wav") else {
                print("Audio file not found: \(layer.fileName).wav")
                continue
            }

            do {
                let audioFile = try AVAudioFile(forReading: url)
                let frameCount = AVAudioFrameCount(audioFile.length)

                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: audioFile.processingFormat,
                    frameCapacity: frameCount
                ) else {
                    print("Failed to create buffer for: \(layer.fileName)")
                    continue
                }

                try audioFile.read(into: buffer)

                // Create nodes (will be attached when engine starts)
                let playerNode = AVAudioPlayerNode()
                let varispeedNode = AVAudioUnitVarispeed()

                let layerNode = AudioLayerNode(
                    layer: layer,
                    playerNode: playerNode,
                    varispeedNode: varispeedNode,
                    buffer: buffer
                )
                layerNodes.append(layerNode)

                print("Loaded layer: \(layer.fileName) (center: \(layer.centerRPM) RPM)")
            } catch {
                print("Failed to load audio file \(layer.fileName): \(error)")
            }
        }

        print("Loaded \(layerNodes.count) audio layers for profile: \(profile.name)")
    }

    /// Start engine sound playback
    func start() {
        guard !isPlaying else { return }
        guard !layerNodes.isEmpty else {
            print("No audio layers loaded")
            return
        }

        // Set initial idle RPM so audio is audible immediately
        if targetRPM == 0 {
            targetRPM = 800
        }

        setupAudioEngine()
        startDisplayLink()
        isPlaying = true
    }

    /// Stop engine sound playback
    func stop() {
        isPlaying = false
        stopDisplayLink()

        for layerNode in layerNodes {
            layerNode.playerNode.stop()
        }
        audioEngine?.stop()

        // Detach all nodes
        if let engine = audioEngine {
            for layerNode in layerNodes {
                engine.detach(layerNode.playerNode)
                engine.detach(layerNode.varispeedNode)
            }
        }

        audioEngine = nil
    }

    /// Update target RPM for pitch/crossfade calculation
    func updateRPM(_ rpm: Int) {
        targetRPM = rpm
    }

    /// Set playback volume (allows boost above 1.0)
    func setVolume(_ volume: Float) {
        self.volume = max(0, min(2.0, volume))
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
            try session.setPreferredIOBufferDuration(0.005)  // 5ms low latency
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else { return }

        // Attach and connect all layer nodes
        for layerNode in layerNodes {
            engine.attach(layerNode.playerNode)
            engine.attach(layerNode.varispeedNode)

            let format = layerNode.buffer.format

            // Connect: Player -> Varispeed -> MainMixer
            engine.connect(layerNode.playerNode, to: layerNode.varispeedNode, format: format)
            engine.connect(layerNode.varispeedNode, to: engine.mainMixerNode, format: format)

            // Initialize with zero volume (crossfade will set proper levels)
            layerNode.playerNode.volume = 0
            layerNode.varispeedNode.rate = 1.0
        }

        do {
            try engine.start()

            // Start all players looping
            for layerNode in layerNodes {
                layerNode.playerNode.scheduleBuffer(layerNode.buffer, at: nil, options: .loops)
                layerNode.playerNode.play()
            }
        } catch {
            print("Failed to start audio engine: \(error)")
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
        // Direct RPM update for lowest latency
        currentRPM = Float(targetRPM)
        let absRPM = abs(Int(currentRPM))

        // Calculate overall volume multiplier based on RPM
        let maxRPM = Float(currentProfile.maxRPM)
        let normalizedRPM = min(1.0, Float(absRPM) / maxRPM)
        let rpmVolumeMultiplier = minVolume + (maxVolume - minVolume) * normalizedRPM

        // Update each layer's volume and pitch
        for layerNode in layerNodes {
            // Calculate crossfade volume for this layer
            let layerVolume = layerNode.layer.volume(at: Int(currentRPM))

            // Apply: layer crossfade * RPM volume curve * user volume
            let finalVolume = layerVolume * rpmVolumeMultiplier * volume
            layerNode.playerNode.volume = finalVolume

            // Calculate pitch rate based on distance from layer's center RPM
            let rate = calculateRate(for: absRPM, layer: layerNode.layer)
            layerNode.varispeedNode.rate = rate
        }

        // Calculate average pitch for display (weighted by volume)
        var totalPitch: Float = 0
        var totalWeight: Float = 0
        for layerNode in layerNodes {
            let layerVolume = layerNode.layer.volume(at: Int(currentRPM))
            if layerVolume > 0 {
                let rate = layerNode.varispeedNode.rate
                let pitch = 1200.0 * log2(rate)
                totalPitch += pitch * layerVolume
                totalWeight += layerVolume
            }
        }
        currentPitch = totalWeight > 0 ? totalPitch / totalWeight : 0
    }

    /// Calculate playback rate for a layer based on RPM distance from center
    private func calculateRate(for rpm: Int, layer: AudioLayer) -> Float {
        // How far from the layer's recorded RPM are we?
        let rpmDiff = Float(rpm - layer.centerRPM)

        // Scale: every 1400 RPM difference = 0.5x rate change
        // This means at layer boundaries, pitch shift is ~50% (about 7 semitones)
        let ratePerRPM: Float = 0.5 / 1400.0
        let rate = 1.0 + rpmDiff * ratePerRPM

        // Clamp to reasonable range (0.5x to 2.0x)
        return max(0.5, min(2.0, rate))
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
