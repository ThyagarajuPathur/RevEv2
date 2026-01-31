//
//  OBDCommandQueue.swift
//  RevEv
//

import Foundation

/// Actor-based command queue to ensure only one OBD command is in flight at a time
@globalActor
actor OBDCommandActor {
    static let shared = OBDCommandActor()
}

/// MainActor command queue to ensure only one OBD command is in flight at a time
@MainActor
final class OBDCommandQueue {
    private let bluetoothService: BluetoothService
    private var isExecuting = false

    init(bluetoothService: BluetoothService) {
        self.bluetoothService = bluetoothService
    }

    /// Execute a command and return the response
    /// Commands are serialized to prevent garbled responses
    func execute(_ command: String, timeout: TimeInterval = 5.0) async throws -> String {
        // Wait for any in-flight command to complete
        while isExecuting {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        isExecuting = true
        defer { isExecuting = false }

        // Increased delay between commands for adapter stability (200ms)
        try await Task.sleep(nanoseconds: 200_000_000) 

        return try await bluetoothService.sendCommand(command, timeout: timeout)
    }

    /// Execute a batch of commands in sequence
    func executeBatch(_ commands: [String], timeout: TimeInterval = 5.0) async throws -> [String] {
        var responses: [String] = []

        for command in commands {
            let response = try await execute(command, timeout: timeout)
            responses.append(response)
        }

        return responses
    }
}
