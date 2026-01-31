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
    private var consecutiveTimeouts = 0
    private let maxConsecutiveTimeouts = 3

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
        bluetoothService.connectionState = .initializing

        do {
            // 1. Reset the adapter (Long timeout 5s)
            let resetResponse = try await queue.execute("AT Z", timeout: 5.0)
            logTransaction(command: "AT Z", response: resetResponse)
            
            // CRITICAL: Delay for adapter boot-up
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s
            
            // 2. Setup basics
            _ = try await queue.execute("AT E0") // Echo Off
            _ = try await queue.execute("AT L0") // Linefeeds Off
            
            // 3. Force CAN Protocol (ISO 15765-4 CAN 11/500)
            _ = try await queue.execute("AT SP 6")
            
            // 4. Force BMS Header (7E4)
            _ = try await queue.execute("AT SH 7E4")
            
            isInitialized = true
            bluetoothService.connectionState = .ready
            print("DEBUG: OBD Protocol Service Initialized (EV Mode - BMS 7E4)")
        } catch {
            logTransaction(command: "INIT", response: error.localizedDescription, isError: true)
            throw error
        }
    }

    /// Start polling for RPM and Speed data
    func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        Task {
            while isPolling {
                await pollData()
                // Throttled delay to prevent buffer overflow (500ms)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        isPolling = false
        // The Task will naturally exit its loop when `isPolling` becomes false
        // No need to explicitly cancel `pollingTask` if it's not stored.
        // If `pollingTask` was stored, it would be `pollingTask?.cancel()`
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

        var newData = self.obdData

        // 1. Request Motor RPM from BMS (220101)
        // Use 5s timeout for the long multi-line response
        var rpmSuccess = false
        do {
            let response = try await queue.execute("220101", timeout: 5.0)
            if let rpm = OBDParser.parseEVLongRPM(from: response) {
                newData.rpm = rpm
                newData.timestamp = Date()
                rpmSuccess = true
            }
        } catch {
            print("DEBUG: EV RPM Polling error: \(error)")
            if error.localizedDescription.contains("timeout") {
                handleTimeout()
            }
        }

        // 2. Request Speed (010D also works at 7E4 on most EVs)
        do {
            let response = try await queue.execute(OBDPid.speed.rawValue)
            if let speed = OBDParser.parseSpeed(from: response) {
                newData.speed = speed
                if !rpmSuccess { // If RPM failed but speed worked, reset timeout count
                    consecutiveTimeouts = 0
                }
            }
        } catch {
            print("DEBUG: EV Speed Polling error: \(error)")
            if error.localizedDescription.contains("timeout") {
                handleTimeout()
            }
        }
        
        // If at least one command succeeded, reset timeout counter
        if rpmSuccess {
            consecutiveTimeouts = 0
        }

        self.obdData = newData
    }

    private func handleTimeout() {
        consecutiveTimeouts += 1
        print("DEBUG: Consecutive timeouts: \(consecutiveTimeouts)/\(maxConsecutiveTimeouts)")
        
        if consecutiveTimeouts >= maxConsecutiveTimeouts {
            print("DEBUG: Max timeouts reached. Triggering self-healing recovery...")
            consecutiveTimeouts = 0
            Task {
                try? await initializeAdapter()
            }
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
