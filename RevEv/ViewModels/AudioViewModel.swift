//
//  AudioViewModel.swift
//  RevEv
//

import Foundation
import Combine

/// ViewModel for audio engine control
@Observable
@MainActor
final class AudioViewModel {
    // MARK: - Services

    private let audioService: AudioEngineService

    // MARK: - State

    var isPlaying: Bool {
        audioService.isPlaying
    }

    var currentProfile: EngineProfile {
        audioService.currentProfile
    }

    var currentPitch: Float {
        audioService.currentPitch
    }

    var volume: Float {
        get { audioService.volume }
        set { audioService.setVolume(newValue) }
    }

    var availableProfiles: [EngineProfile] {
        EngineProfile.allProfiles
    }

    // MARK: - Initialization

    init() {
        self.audioService = AudioEngineService()
        // Load V8 muscle profile by default
        audioService.loadProfile(.v8Muscle)
    }

    // MARK: - Playback Control

    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    func start() {
        audioService.start()
    }

    func stop() {
        audioService.stop()
    }

    // MARK: - RPM Updates

    func updateRPM(_ rpm: Int) {
        audioService.updateRPM(rpm)
    }

    // MARK: - Profile Management

    func selectProfile(_ profile: EngineProfile) {
        audioService.changeProfile(to: profile)
    }
}
