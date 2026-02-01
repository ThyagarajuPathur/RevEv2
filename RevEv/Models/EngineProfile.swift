//
//  EngineProfile.swift
//  RevEv
//

import Foundation

/// Represents a single audio layer for crossfading
struct AudioLayer: Hashable, Sendable {
    let fileName: String      // Without extension
    let centerRPM: Int        // RPM at which this layer is recorded
    let minRPM: Int           // Fade in starts here
    let maxRPM: Int           // Fade out ends here

    /// Calculate volume (0-1) for this layer at given RPM
    func volume(at rpm: Int) -> Float {
        let absRPM = abs(rpm)

        // Outside range = silent
        if absRPM < minRPM || absRPM > maxRPM {
            return 0.0
        }

        // Fade in: minRPM -> centerRPM
        if absRPM < centerRPM {
            let fadeRange = Float(centerRPM - minRPM)
            if fadeRange <= 0 { return 1.0 }
            return Float(absRPM - minRPM) / fadeRange
        }

        // Fade out: centerRPM -> maxRPM
        if absRPM > centerRPM {
            let fadeRange = Float(maxRPM - centerRPM)
            if fadeRange <= 0 { return 1.0 }
            return 1.0 - Float(absRPM - centerRPM) / fadeRange
        }

        // At center = full volume
        return 1.0
    }
}

/// Engine sound profile configuration with multiple crossfade layers
struct EngineProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let layers: [AudioLayer]
    let minRPM: Int
    let maxRPM: Int

    // MARK: - Predefined Profiles

    static let v8Muscle = EngineProfile(
        id: "v8_muscle",
        name: "V8 Muscle",
        description: "Classic American muscle car rumble",
        layers: [
            AudioLayer(fileName: "v8_2000", centerRPM: 2000, minRPM: 0,    maxRPM: 2700),
            AudioLayer(fileName: "v8_3400", centerRPM: 3400, minRPM: 2000, maxRPM: 4100),
            AudioLayer(fileName: "v8_4800", centerRPM: 4800, minRPM: 3400, maxRPM: 5500),
            AudioLayer(fileName: "v8_6200", centerRPM: 6200, minRPM: 4800, maxRPM: 6900),
            AudioLayer(fileName: "v8_7600", centerRPM: 7600, minRPM: 6200, maxRPM: 8300),
            AudioLayer(fileName: "v8_9000", centerRPM: 9000, minRPM: 7600, maxRPM: 10100)
        ],
        minRPM: -10100,
        maxRPM: 10100
    )

    static let inline6Sport = EngineProfile(
        id: "inline6_sport",
        name: "Inline-6 Sport",
        description: "Smooth high-revving sports car",
        layers: [
            AudioLayer(fileName: "inline6_2000", centerRPM: 2000, minRPM: 0,    maxRPM: 2700),
            AudioLayer(fileName: "inline6_3400", centerRPM: 3400, minRPM: 2000, maxRPM: 4100),
            AudioLayer(fileName: "inline6_4800", centerRPM: 4800, minRPM: 3400, maxRPM: 5500),
            AudioLayer(fileName: "inline6_6200", centerRPM: 6200, minRPM: 4800, maxRPM: 6900),
            AudioLayer(fileName: "inline6_7600", centerRPM: 7600, minRPM: 6200, maxRPM: 8300),
            AudioLayer(fileName: "inline6_9000", centerRPM: 9000, minRPM: 7600, maxRPM: 10100)
        ],
        minRPM: -10100,
        maxRPM: 10100
    )

    static let futuristic = EngineProfile(
        id: "futuristic",
        name: "Futuristic",
        description: "Electric/hybrid sci-fi sound",
        layers: [
            AudioLayer(fileName: "futuristic_2000", centerRPM: 2000, minRPM: 0,    maxRPM: 2700),
            AudioLayer(fileName: "futuristic_3400", centerRPM: 3400, minRPM: 2000, maxRPM: 4100),
            AudioLayer(fileName: "futuristic_4800", centerRPM: 4800, minRPM: 3400, maxRPM: 5500),
            AudioLayer(fileName: "futuristic_6200", centerRPM: 6200, minRPM: 4800, maxRPM: 6900),
            AudioLayer(fileName: "futuristic_7600", centerRPM: 7600, minRPM: 6200, maxRPM: 8300),
            AudioLayer(fileName: "futuristic_9000", centerRPM: 9000, minRPM: 7600, maxRPM: 10100)
        ],
        minRPM: -10100,
        maxRPM: 10100
    )

    static let allProfiles: [EngineProfile] = [
        .v8Muscle,
        .inline6Sport,
        .futuristic
    ]
}
