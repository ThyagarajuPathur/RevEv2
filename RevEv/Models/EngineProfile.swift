//
//  EngineProfile.swift
//  RevEv
//

import Foundation

/// Engine sound profile configuration
struct EngineProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let audioFileName: String
    let baseRPM: Int
    let minRPM: Int
    let maxRPM: Int

    /// Pitch adjustment range in cents (semitone = 100 cents)
    let pitchRange: Float

    static let v8Muscle = EngineProfile(
        id: "v8_muscle",
        name: "V8 Muscle",
        description: "Classic American muscle car rumble",
        audioFileName: "v8_idle",
        baseRPM: 0,
        minRPM: -10100,
        maxRPM: 10100,
        pitchRange: 2400
    )

    static let inline6Sport = EngineProfile(
        id: "inline6_sport",
        name: "Inline-6 Sport",
        description: "Smooth high-revving sports car",
        audioFileName: "inline6_idle",
        baseRPM: 0,
        minRPM: -10100,
        maxRPM: 10100,
        pitchRange: 2800
    )

    static let futuristic = EngineProfile(
        id: "futuristic",
        name: "Futuristic",
        description: "Electric/hybrid sci-fi sound",
        audioFileName: "futuristic_idle",
        baseRPM: 0,
        minRPM: -10100,
        maxRPM: 10100,
        pitchRange: 3600
    )

    static let allProfiles: [EngineProfile] = [
        .v8Muscle,
        .inline6Sport,
        .futuristic
    ]
}
