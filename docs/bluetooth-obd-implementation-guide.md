# iOS Bluetooth OBD-II Implementation Guide

Connect to ELM327 OBD-II adapters via Bluetooth Low Energy (BLE) to read real-time motor RPM from electric vehicles.

---

## 1. Bluetooth UUIDs (ELM327 Adapters)

```
Veepeak/Generic:
  Service:  FFF0
  Write:    FFF2
  Notify:   FFF1

Generic FFE0:
  Service:  FFE0
  RW Char:  FFE1 (same for read/write)

OBDLink:
  Service:  E7810A71-73AE-499D-8C15-FAA9AEF0C3F2
  Write:    BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F
```

---

## 2. Connection Flow

```
1. CBCentralManager.scanForPeripherals(withServices: nil)
2. Filter by name: "OBD", "ELM", "Veepeak", "Vlink"
3. Connect to peripheral
4. Discover services → discover characteristics
5. Enable notifications on notify characteristic
6. Send commands via write characteristic
7. Receive responses via didUpdateValue delegate
```

---

## 3. Command/Response Protocol

| Aspect | Detail |
|--------|--------|
| **Send** | Append `\r` (carriage return) to command |
| **Receive** | Buffer data until `>` terminator received |
| **Timeout** | 3-5 seconds per command |
| **Encoding** | ASCII |

---

## 4. ELM327 Initialization Sequence

```
AT Z      → Reset adapter (wait 1s after)
AT E0     → Echo off
AT L0     → Linefeeds off
AT SP 6   → Set protocol: ISO 15765-4 CAN (11-bit, 500kbaud)
AT SH 7E4 → Set header to BMS ECU (for EV motor RPM)
```

---

## 5. RPM Polling (Electric Vehicles)

### Request PIDs (try in order)

```
220101  → E-GMP platform (Hyundai Ioniq 5, Kia EV6)
2101    → Older EVs (Kona EV, Niro EV)
```

### Response Parsing

| Field | Value |
|-------|-------|
| Response header | `62 01 01` (for 220101) or `61 01` (for 2101) |
| RPM location | Byte offset 53-54 after header |
| Data format | Signed 16-bit integer (big-endian) |
| Negative value | Regenerative braking |
| Positive value | Driving/accelerating |
| Range | -10100 to +10100 RPM |

### Parsing Example (Swift)

```swift
let bytes = extractHexBytes(from: response)
let headerIndex = findHeader(bytes, [0x62, 0x01, 0x01])
let a = bytes[headerIndex + 53]
let b = bytes[headerIndex + 54]
let rpm = Int16(bitPattern: UInt16(a) << 8 | UInt16(b))
```

---

## 6. Polling Loop

```
Interval: 50ms (20Hz)

Flow:
  1. Send "220101\r"
  2. Wait for response (timeout 5s)
  3. Parse RPM from bytes 53-54
  4. If fails, try "2101\r"
  5. If 3 consecutive timeouts → re-initialize adapter
```

---

## 7. Key Implementation Details

| Component | Detail |
|-----------|--------|
| Write type | `.withResponse` preferred, fallback `.withoutResponse` |
| Response terminator | `>` character |
| Multi-line responses | Split by `\n`, skip line prefixes like `0:`, `1:` |
| Error responses | `NO DATA`, `UNABLE TO CONNECT`, `ERROR`, `?` |
| Hex parsing | Remove spaces, convert pairs to bytes |

---

## 8. Standard OBD PIDs (ICE Vehicles)

If targeting gasoline/diesel vehicles instead of EVs:

### Engine RPM (PID 010C)

```
Request:  010C
Response: 41 0C XX YY
Formula:  RPM = ((XX × 256) + YY) / 4
```

### Vehicle Speed (PID 010D)

```
Request:  010D
Response: 41 0D XX
Formula:  Speed = XX km/h
```

---

## 9. Required iOS Permissions (Info.plist)

```xml
<key>NSBluetoothAlwaysAndWhenInUseUsageDescription</key>
<string>Connect to OBD-II adapter for vehicle data</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>Connect to OBD-II adapter for vehicle data</string>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

---

## 10. Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  iOS App        │     │  ELM327         │     │  Vehicle        │
│  (CoreBluetooth)│────▶│  Adapter        │────▶│  CAN Bus        │
│                 │ BLE │  (Bluetooth)    │OBD-II│  (ECU/BMS)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘

Data Flow:
  App sends AT/OBD command via BLE write characteristic
  ELM327 translates to CAN bus request
  Vehicle ECU responds with data
  ELM327 translates to hex string response
  App receives via BLE notify characteristic
  App parses hex bytes to extract RPM/Speed
```

---

## 11. Error Handling

| Scenario | Action |
|----------|--------|
| Bluetooth powered off | Show error, wait for state change |
| Device not found | Retry scan, check adapter power |
| Connection lost | Auto-reconnect after 1s delay |
| Command timeout | Retry, after 3 failures re-initialize |
| NO DATA response | Vehicle may be off or PID unsupported |
| Parse failure | Log raw response for debugging |

---

## 12. Files Reference (RevEv Project)

| File | Purpose |
|------|---------|
| `BluetoothService.swift` | CoreBluetooth connection management |
| `BluetoothConstants.swift` | UUID definitions, AT commands |
| `OBDProtocolService.swift` | Initialization, polling loop |
| `OBDCommandQueue.swift` | Command serialization |
| `OBDParser.swift` | Response parsing, RPM extraction |

---

*This guide covers the complete BLE → ELM327 → OBD-II → RPM pipeline for iOS.*
