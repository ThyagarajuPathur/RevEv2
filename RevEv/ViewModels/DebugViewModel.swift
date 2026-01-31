//
//  DebugViewModel.swift
//  RevEv
//

import Foundation

/// ViewModel for debug terminal
@Observable
@MainActor
final class DebugViewModel {
    // MARK: - Dependencies

    private let obdViewModel: OBDViewModel

    // MARK: - State

    var commandInput: String = ""
    var isLoading = false

    var transactions: [OBDTransaction] {
        obdViewModel.protocolService.transactions
    }

    // MARK: - Initialization

    init(obdViewModel: OBDViewModel) {
        self.obdViewModel = obdViewModel
    }

    // MARK: - Methods

    func sendCommand() async {
        guard !commandInput.isEmpty else { return }

        let command = commandInput.uppercased()
        commandInput = ""
        isLoading = true

        _ = await obdViewModel.sendRawCommand(command)

        isLoading = false
    }

    func clearTransactions() {
        obdViewModel.protocolService.clearTransactions()
    }
}
