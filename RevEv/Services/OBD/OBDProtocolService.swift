//
//  OBDProtocolService.swift
//  RevEv
//

import Foundation
import Combine

/// OBD-II protocol service for vehicle data communication
@Observable
@MainActor
final class OBDProtocolService {
    // MARK: - Published State

    private(set) var obdData = OBDData()
    private(set) var isPolling = false
    private(set) var isInitialized = false
    private(set) var transactions: [OBDTransaction] = []

    // MARK: - Dependencies

    let bluetoothService: BluetoothService
    private var commandQueue: OBDCommandQueue?

    // MARK: - Private Properties

    private var pollingTask: Task<Void, Never>?
    private let maxTransactions = 100

    // MARK: - Callbacks

    var onTransaction: ((OBDTransaction) -> Void)?

    // MARK: - Initialization

    init(bluetoothService: BluetoothService) {
        self.bluetoothService = bluetoothService
        self.commandQueue = OBDCommandQueue(bluetoothService: bluetoothService)
    }

    // MARK: - Public Methods

    /// Initialize the ELM327 adapter
    func initializeAdapter() async throws {
        guard let queue = commandQueue else {
            throw OBDError.notConnected
        }

        isInitialized = false

        for command in ELM327Commands.initSequence {
            do {
                let response = try await queue.execute(command, timeout: 5.0)
                logTransaction(command: command, response: response)

                // Check for successful response
                if command == ELM327Commands.reset {
                    // Reset returns ELM identifier
                    if !OBDParser.isELM(response) && !response.isEmpty {
                        // Some adapters might not return ELM, continue anyway
                    }
                    // Give adapter time to reset
                    try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                }
            } catch {
                logTransaction(command: command, response: error.localizedDescription, isError: true)
                // Continue with remaining commands even if some fail
            }
        }

        isInitialized = true
        bluetoothService.connectionState = .ready
    }

    /// Start polling for RPM and Speed data
    func startPolling(interval: TimeInterval = 0.1) {
        guard !isPolling else { return }

        isPolling = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollData()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Request a single RPM reading
    func requestRPM() async throws -> Int {
        guard let queue = commandQueue else {
            throw OBDError.notConnected
        }

        let response = try await queue.execute(OBDPid.rpm.rawValue)
        logTransaction(command: OBDPid.rpm.rawValue, response: response)

        if OBDParser.isNoData(response) {
            throw OBDError.noData
        }

        guard let rpm = OBDParser.parseRPM(from: response) else {
            throw OBDError.parseError
        }

        return rpm
    }

    /// Request a single Speed reading
    func requestSpeed() async throws -> Int {
        guard let queue = commandQueue else {
            throw OBDError.notConnected
        }

        let response = try await queue.execute(OBDPid.speed.rawValue)
        logTransaction(command: OBDPid.speed.rawValue, response: response)

        if OBDParser.isNoData(response) {
            throw OBDError.noData
        }

        guard let speed = OBDParser.parseSpeed(from: response) else {
            throw OBDError.parseError
        }

        return speed
    }

    /// Send a raw command
    func sendRawCommand(_ command: String) async throws -> String {
        guard let queue = commandQueue else {
            throw OBDError.notConnected
        }

        let response = try await queue.execute(command)
        logTransaction(command: command, response: response)
        return response
    }

    /// Clear transaction history
    func clearTransactions() {
        transactions.removeAll()
    }

    // MARK: - Private Methods

    private func pollData() async {
        guard let queue = commandQueue, isInitialized else { return }

        // Request RPM
        do {
            let response = try await queue.execute(OBDPid.rpm.rawValue)

            if let rpm = OBDParser.parseRPM(from: response) {
                self.obdData.rpm = rpm
                self.obdData.timestamp = Date()
            }
        } catch {
            // Silently continue on polling errors
        }

        // Request Speed
        do {
            let response = try await queue.execute(OBDPid.speed.rawValue)

            if let speed = OBDParser.parseSpeed(from: response) {
                self.obdData.speed = speed
            }
        } catch {
            // Silently continue on polling errors
        }
    }

    private func logTransaction(command: String, response: String, isError: Bool = false) {
        let transaction = OBDTransaction(command: command, response: response, isError: isError)

        self.transactions.append(transaction)

        // Limit transaction history
        if self.transactions.count > maxTransactions {
            self.transactions.removeFirst()
        }

        self.onTransaction?(transaction)
    }
}

// MARK: - Errors

enum OBDError: LocalizedError, Sendable {
    case notConnected
    case notInitialized
    case noData
    case parseError
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to OBD adapter"
        case .notInitialized:
            return "Adapter not initialized"
        case .noData:
            return "No data available"
        case .parseError:
            return "Failed to parse response"
        case .timeout:
            return "Request timeout"
        }
    }
}
