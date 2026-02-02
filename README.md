# RevEv

An iOS app that simulates realistic engine sounds for electric vehicles using real-time OBD-II data.

## What It Does

RevEv connects to your EV's OBD-II port via a Bluetooth ELM327 adapter, reads the motor RPM in real-time, and plays dynamic V8 engine sounds that respond to your driving. Accelerate and hear the engine roar. Lift off and hear it settle back to idle.

## Features

- **Real-time OBD-II Connection** - Connects to ELM327 Bluetooth adapters to read motor RPM at 20Hz
- **Multi-layer Audio Crossfade** - 16 audio layers at 500 RPM intervals for seamless sound transitions
- **Pitch-matched Blending** - RPM-ratio based pitch shifting ensures smooth crossfades without audible "shifts"
- **Equal-power Crossfade** - Sine/cosine volume curves maintain constant perceived loudness
- **EV Support** - Works with Hyundai Ioniq 5, Kia EV6, Kona EV, Niro EV (E-GMP and older platforms)
- **Auto-connect** - Remembers your OBD adapter and reconnects automatically
- **Low Latency** - 5ms audio buffer + 60fps updates for responsive sound

## How It Works

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  EV      │────▶│  ELM327  │────▶│  iPhone  │────▶│  Audio   │
│  CAN Bus │ OBD │  Adapter │ BLE │  App     │     │  Output  │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
     │                                  │
     │                                  ▼
   Motor                         Multi-layer
   RPM data                      engine sound
   (-10100 to +10100)            crossfade
```

1. **OBD Connection** - App scans for ELM327 adapters, connects via Bluetooth LE
2. **RPM Polling** - Sends PID 220101/2101 every 50ms to read motor RPM
3. **Audio Engine** - 16 audio layers play simultaneously, volumes adjusted based on RPM
4. **Crossfade** - As RPM changes, layers fade in/out with equal-power curves
5. **Pitch Shift** - Each layer's playback rate = currentRPM / recordedRPM

## Audio Layers

| Layer | Center RPM | Pitch Shift Range |
|-------|-----------|-------------------|
| v8_idle | 800 | - |
| v8_2000 | 2000 | ±12.5% |
| v8_2500 | 2500 | ±10% |
| v8_3000 | 3000 | ±8% |
| ... | ... | ... |
| v8_9000 | 9000 | ±3% |

16 layers total, recorded at 500 RPM intervals from idle to 9000 RPM.

## Supported Vehicles

Tested with E-GMP platform EVs:
- Hyundai Ioniq 5
- Hyundai Ioniq 6
- Kia EV6
- Genesis GV60

Also supports older Hyundai/Kia EVs:
- Hyundai Kona Electric
- Kia Niro EV

## Requirements

- iOS 17.0+
- Bluetooth ELM327 OBD-II adapter (Veepeak, OBDLink, or compatible)
- Electric vehicle with CAN bus access

## Project Structure

```
RevEv/
├── Models/
│   ├── EngineProfile.swift      # Audio layer definitions
│   └── OBDData.swift            # RPM/Speed data model
├── Services/
│   ├── Audio/
│   │   └── AudioEngineService.swift   # AVAudioEngine + crossfade
│   ├── Bluetooth/
│   │   ├── BluetoothService.swift     # CoreBluetooth connection
│   │   └── BluetoothConstants.swift   # UUIDs, AT commands
│   └── OBD/
│       ├── OBDProtocolService.swift   # Initialization, polling
│       └── OBDParser.swift            # Response parsing
├── ViewModels/
│   ├── AudioViewModel.swift
│   └── OBDViewModel.swift
├── Views/
│   ├── DashboardView.swift      # Main UI
│   └── Gauges/                  # RPM/Speed gauges
└── Resources/
    └── Audio/                   # 16 WAV files
```

## Documentation

See the [docs](./docs) folder for detailed technical guides:
- [Multi-Layer Crossfade Explained](./docs/multi-layer-crossfade-explained.md)
- [Bluetooth OBD Implementation Guide](./docs/bluetooth-obd-implementation-guide.md)

## License

MIT
