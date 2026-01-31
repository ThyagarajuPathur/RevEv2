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
    private static func extractBytes(from response: String) -> [UInt8] {
        // Remove spaces and convert to bytes
        let cleaned = response
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()

        var bytes: [UInt8] = []
        var index = cleaned.startIndex

        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            let hexPair = String(cleaned[index..<nextIndex])

            if hexPair.count == 2, let byte = UInt8(hexPair, radix: 16) {
                bytes.append(byte)
            }

            index = nextIndex
        }

        return bytes
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
