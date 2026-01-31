//
//  OBDParser.swift
//  RevEv
//

import Foundation

/// Parser for OBD-II responses
enum OBDParser {
    /// Parse RPM response (PID 010C)
    /// Format: 41 0C XX YY where RPM = ((XX * 256) + YY) / 4
    static func parseRPM(from response: String) -> Int? {
        let bytes = extractBytes(from: response)

        // Find the 41 0C header
        guard let headerIndex = findHeader(bytes: bytes, header: [0x41, 0x0C]),
              headerIndex + 2 < bytes.count else {
            return nil
        }

        let a = Int(bytes[headerIndex])
        let b = Int(bytes[headerIndex + 1])

        return ((a * 256) + b) / 4
    }

    /// Parse Speed response (PID 010D)
    /// Format: 41 0D XX where Speed = XX km/h
    static func parseSpeed(from response: String) -> Int? {
        let bytes = extractBytes(from: response)

        // Find the 41 0D header
        guard let headerIndex = findHeader(bytes: bytes, header: [0x41, 0x0D]),
              headerIndex + 1 < bytes.count else {
            return nil
        }

        return Int(bytes[headerIndex])
    }

    /// Check if response indicates no data
    static func isNoData(_ response: String) -> Bool {
        let upper = response.uppercased()
        return upper.contains("NO DATA") ||
               upper.contains("UNABLE TO CONNECT") ||
               upper.contains("ERROR") ||
               upper.contains("?")
    }

    /// Check if response indicates successful initialization
    static func isOK(_ response: String) -> Bool {
        response.uppercased().contains("OK")
    }

    /// Check if response is ELM327 identifier
    static func isELM(_ response: String) -> Bool {
        response.uppercased().contains("ELM")
    }

    // MARK: - Private Helpers

    /// Extract hex bytes from response string
    /// Extract bytes from an OBD-II response string, handling multi-line formats
    private static func extractBytes(from response: String) -> [UInt8] {
        var bytes: [UInt8] = []
        
        // Split by lines and process each line
        let lines = response.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if trimmed.isEmpty || trimmed == ">" { continue }
            
            // Remove line prefix if present (e.g., "0:", "1:")
            var dataPart = trimmed
            if let colonIndex = trimmed.firstIndex(of: ":") {
                dataPart = String(trimmed[trimmed.index(after: colonIndex)...])
            } else if trimmed.count <= 3 {
                // Likely a length header (e.g. "03E") - skip it
                continue
            }
            
            // Clean the data part of any non-hex characters
            let hexOnly = dataPart.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            
            // Convert pairs to bytes
            var index = hexOnly.startIndex
            while index < hexOnly.endIndex {
                let nextIndex = hexOnly.index(index, offsetBy: 2, limitedBy: hexOnly.endIndex) ?? hexOnly.endIndex
                let pair = hexOnly[index..<nextIndex]
                if pair.count == 2, let byte = UInt8(pair, radix: 16) {
                    bytes.append(byte)
                }
                index = nextIndex
            }
        }
        
        return bytes
    }

    /// Parse long EV BMS responses (e.g., 220101) to find Motor RPM
    static func parseEVLongRPM(from response: String) -> Int? {
        let bytes = extractBytes(from: response)
        
        // Mode 22 response starts with 62 [PID_HI] [PID_LO]
        // 220101 -> 62 01 01
        guard let headerIndex = findHeader(bytes: bytes, header: [0x62, 0x01, 0x01]) else {
            return nil
        }
        
        // For common EVs (Hyundai/Kia/Genesis), Motor RPM is often at offset 53-54 or 55-56
        // in the data stream (after the 62 01 01 header).
        // Let's use offset 55 as the primary based on common PID lists.
        let offset = 55
        if bytes.count > headerIndex + offset + 1 {
            let a = bytes[headerIndex + offset]
            let b = bytes[headerIndex + offset + 1]
            let raw = Int16(bitPattern: UInt16(a) << 8 | UInt16(b))
            return abs(Int(raw))
        }
        
        return nil
    }

    /// Find header bytes in response and return the index of the first data byte
    private static func findHeader(bytes: [UInt8], header: [UInt8]) -> Int? {
        guard bytes.count >= header.count else { return nil }

        for i in 0...(bytes.count - header.count) {
            var match = true
            for j in 0..<header.count {
                if bytes[i + j] != header[j] {
                    match = false
                    break
                }
            }
            if match {
                return i + header.count
            }
        }

        return nil
    }
}
