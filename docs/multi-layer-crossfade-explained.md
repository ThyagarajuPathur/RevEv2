# Building Realistic Engine Sounds with Multi-Layer Audio Crossfading

*How RevEv creates smooth, dynamic engine audio that responds to real-time RPM data*

---

## The Problem

If you've ever tried to simulate engine sounds in an app, you've probably hit this wall: a single audio loop sounds fake. Speed it up for high RPM and it sounds like a chipmunk. Slow it down for idle and it's a muddy mess.

Real engines don't just change pitch—they change *character*. The rumble at idle is fundamentally different from the scream at redline. Different harmonics, different textures, different everything.

So how do we solve this?

---

## The Solution: Multi-Layer Crossfading

Instead of one audio file, we use **seven**. Each recorded at a different RPM:

| Layer | Recorded At | Active Range |
|-------|-------------|--------------|
| `v8_idle` | 800 RPM | 0 - 1,500 RPM |
| `v8_2000` | 2,000 RPM | 800 - 2,700 RPM |
| `v8_3400` | 3,400 RPM | 2,000 - 4,100 RPM |
| `v8_4800` | 4,800 RPM | 3,400 - 5,500 RPM |
| `v8_6200` | 6,200 RPM | 4,800 - 6,900 RPM |
| `v8_7600` | 7,600 RPM | 6,200 - 8,300 RPM |
| `v8_9000` | 9,000 RPM | 7,600 - 10,100 RPM |

The magic: **all seven layers play simultaneously**, but we adjust their volumes in real-time. At any given RPM, you hear a blend of two adjacent layers crossfading into each other.

---

## Part 1: Defining a Layer

Each audio layer is defined with three key RPM values:

```swift
struct AudioLayer {
    let fileName: String      // The .wav file
    let centerRPM: Int        // Where this layer sounds "correct"
    let minRPM: Int           // Where it starts fading in
    let maxRPM: Int           // Where it finishes fading out
}
```

For example, the 2000 RPM layer:

```swift
AudioLayer(fileName: "v8_2000", centerRPM: 2000, minRPM: 800, maxRPM: 2700)
```

This layer:
- Is **silent** below 800 RPM
- **Fades in** from 800 → 2000 RPM
- Is at **full volume** at exactly 2000 RPM
- **Fades out** from 2000 → 2700 RPM
- Is **silent** above 2700 RPM

---

## Part 2: The Volume Calculation

Here's the function that calculates volume (0.0 to 1.0) for any layer at any RPM:

```swift
func volume(at rpm: Int) -> Float {
    let absRPM = abs(rpm)  // Handle negative RPM (regenerative braking)

    // Outside the layer's range = silent
    if absRPM < minRPM || absRPM > maxRPM {
        return 0.0
    }

    // Fading IN: minRPM → centerRPM
    if absRPM < centerRPM {
        let fadeRange = Float(centerRPM - minRPM)
        return Float(absRPM - minRPM) / fadeRange
    }

    // Fading OUT: centerRPM → maxRPM
    if absRPM > centerRPM {
        let fadeRange = Float(maxRPM - centerRPM)
        return 1.0 - Float(absRPM - centerRPM) / fadeRange
    }

    // Exactly at center = full volume
    return 1.0
}
```

### Example: What happens at 1,200 RPM?

Let's calculate the volume for each layer:

**v8_idle** (center: 800, min: 0, max: 1500):
```
1200 > 800 (center), so we're fading OUT
fadeRange = 1500 - 800 = 700
volume = 1.0 - (1200 - 800) / 700 = 1.0 - 0.57 = 0.43
```

**v8_2000** (center: 2000, min: 800, max: 2700):
```
1200 < 2000 (center), so we're fading IN
fadeRange = 2000 - 800 = 1200
volume = (1200 - 800) / 1200 = 0.33
```

**All other layers**: 0.0 (1200 is outside their ranges)

**Result**: You hear 43% idle + 33% v8_2000, blended together.

---

## Part 3: The Audio Engine Architecture

We use Apple's `AVAudioEngine` to build a real-time audio graph:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ PlayerNode  │ ──▶ │ VarispeedNode│ ──▶ │             │
│ (v8_idle)   │     │ (pitch)      │     │             │
└─────────────┘     └──────────────┘     │             │
                                         │   Main      │     ┌──────────┐
┌─────────────┐     ┌──────────────┐     │   Mixer     │ ──▶ │ Speakers │
│ PlayerNode  │ ──▶ │ VarispeedNode│ ──▶ │   Node      │     └──────────┘
│ (v8_2000)   │     │ (pitch)      │     │             │
└─────────────┘     └──────────────┘     │             │
                                         │             │
       ...           ...                 │             │
       (5 more layers)                   └─────────────┘
```

Each layer has:
- **PlayerNode**: Loops the audio file forever
- **VarispeedNode**: Adjusts pitch based on RPM distance from center

All feed into the **MainMixerNode**, which combines them for output.

### Setup Code

```swift
private func setupAudioEngine() {
    audioEngine = AVAudioEngine()

    for layerNode in layerNodes {
        // Attach nodes to the engine
        engine.attach(layerNode.playerNode)
        engine.attach(layerNode.varispeedNode)

        // Connect: Player → Varispeed → Mixer
        engine.connect(layerNode.playerNode,
                      to: layerNode.varispeedNode,
                      format: layerNode.buffer.format)
        engine.connect(layerNode.varispeedNode,
                      to: engine.mainMixerNode,
                      format: layerNode.buffer.format)

        // Start silent (crossfade will set proper levels)
        layerNode.playerNode.volume = 0
        layerNode.varispeedNode.rate = 1.0
    }

    try engine.start()

    // Start ALL layers looping simultaneously
    for layerNode in layerNodes {
        layerNode.playerNode.scheduleBuffer(layerNode.buffer,
                                           at: nil,
                                           options: .loops)
        layerNode.playerNode.play()
    }
}
```

**Key insight**: All 7 audio files loop forever from the start. We never stop/start them—we just adjust volumes. This eliminates any audio glitches during transitions.

---

## Part 4: The 60 FPS Update Loop

We use `CADisplayLink` to update audio parameters 60 times per second:

```swift
private func tick() {
    currentRPM = Float(targetRPM)
    let absRPM = abs(Int(currentRPM))

    // Volume boost: louder at high RPM (0.7x at idle, 1.5x at redline)
    let normalizedRPM = Float(absRPM) / Float(maxRPM)
    let rpmVolumeMultiplier = 0.7 + (1.5 - 0.7) * normalizedRPM

    // Update each layer
    for layerNode in layerNodes {
        // Get crossfade volume (0.0 - 1.0)
        let layerVolume = layerNode.layer.volume(at: Int(currentRPM))

        // Final = crossfade × RPM boost × user volume
        let finalVolume = layerVolume * rpmVolumeMultiplier * volume
        layerNode.playerNode.volume = finalVolume

        // Pitch shift based on RPM distance from center
        let rate = calculateRate(for: absRPM, layer: layerNode.layer)
        layerNode.varispeedNode.rate = rate
    }
}
```

Every frame, we:
1. Read the current RPM from OBD-II
2. Calculate each layer's crossfade volume
3. Apply an overall RPM-based volume curve (engines sound louder at high RPM)
4. Adjust pitch for each layer

---

## Part 5: Pitch Shifting

Even with crossfading, we need some pitch adjustment. If you're at 2,500 RPM but only have recordings at 2,000 and 3,400, the audio needs to stretch slightly.

```swift
private func calculateRate(for rpm: Int, layer: AudioLayer) -> Float {
    // Distance from where this audio was recorded
    let rpmDiff = Float(rpm - layer.centerRPM)

    // Scale: 0.5 rate change per 1,400 RPM difference
    let ratePerRPM: Float = 0.5 / 1400.0
    let rate = 1.0 + rpmDiff * ratePerRPM

    // Clamp to safe range (0.5x to 2.0x)
    return max(0.5, min(2.0, rate))
}
```

### Examples for v8_2000 (center = 2000):

| Current RPM | Rate | Effect |
|-------------|------|--------|
| 2,000 | 1.0 | Normal pitch |
| 2,700 | 1.25 | 25% faster/higher |
| 1,300 | 0.75 | 25% slower/lower |

The pitch shift is subtle because adjacent layers overlap. By the time you'd need significant pitch adjustment, the next layer is already fading in with its correct pitch.

---

## Visual Timeline

Here's what the crossfade looks like across the RPM range:

```
RPM:     0      800    1500   2000   2700   3400   4100   4800   5500
         │       │      │      │      │      │      │      │      │
idle:    █████████████████▓▓▓░░░
v8_2000:         ░░░▓▓▓▓███████████████▓▓▓░░░
v8_3400:                       ░░░▓▓▓▓███████████████▓▓▓░░░
v8_4800:                                     ░░░▓▓▓▓███████████...
v8_6200:                                                   ░░░▓▓▓...

Legend:  █ = full volume   ▓ = partial   ░ = fading   (blank) = silent
```

At any RPM, you typically hear **two layers** blending together, creating seamless transitions.

---

## Why This Works

1. **No audio restarts**: All layers loop continuously. No clicks, no gaps.

2. **Natural blending**: Adjacent recordings share similar characteristics, so crossfades sound smooth.

3. **Minimal pitch shifting**: Each layer only needs ±25% pitch adjustment before the next layer takes over.

4. **60 FPS updates**: Volume changes happen faster than human perception, so transitions feel instant.

5. **Real audio character**: Low RPM sounds like low RPM. High RPM sounds like high RPM. No chipmunk effects.

---

## The Code Files

| File | Purpose |
|------|---------|
| `Models/EngineProfile.swift` | Layer definitions and volume calculation |
| `Services/Audio/AudioEngineService.swift` | AVAudioEngine setup and real-time updates |

---

## Summary

Multi-layer crossfading is a technique used in games and simulators to create realistic, dynamic audio:

1. **Record** multiple audio samples at different RPM points
2. **Play** all samples simultaneously on loop
3. **Crossfade** volumes based on current RPM
4. **Pitch-shift** slightly to fill gaps between recordings
5. **Update** 60 times per second for smooth response

The result: engine audio that sounds authentic at any RPM, responds instantly to throttle input, and transitions smoothly across the entire range.

---

*RevEv uses this technique to simulate engine sounds for electric vehicles, pulling real-time motor RPM data from the OBD-II port via Bluetooth.*
