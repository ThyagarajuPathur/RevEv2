//
//  DebugTerminalView.swift
//  RevEv
//

import SwiftUI

/// Debug terminal for raw OBD commands
struct DebugTerminalView: View {
    @Bindable var viewModel: DebugViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                CyberpunkTheme.darkBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Terminal output
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(viewModel.transactions) { transaction in
                                    TransactionRow(transaction: transaction)
                                        .id(transaction.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.transactions.count) { _, _ in
                            if let last = viewModel.transactions.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .background(Color.black)

                    // Input area
                    HStack(spacing: 12) {
                        Text(">")
                            .font(.cyberpunkBody)
                            .foregroundStyle(CyberpunkTheme.neonGreen)

                        TextField("Enter command...", text: $viewModel.commandInput)
                            .font(.cyberpunkBody)
                            .foregroundStyle(CyberpunkTheme.textPrimary)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($isInputFocused)
                            .onSubmit {
                                Task {
                                    await viewModel.sendCommand()
                                }
                            }

                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(CyberpunkTheme.neonCyan)
                                .scaleEffect(0.8)
                        } else {
                            Button {
                                Task {
                                    await viewModel.sendCommand()
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(CyberpunkTheme.neonCyan)
                            }
                            .disabled(viewModel.commandInput.isEmpty)
                        }
                    }
                    .padding()
                    .background(CyberpunkTheme.cardBackground)
                }
            }
            .navigationTitle("Debug Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.clearTransactions()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(CyberpunkTheme.neonRed)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(CyberpunkTheme.neonCyan)
                }
            }
            .toolbarBackground(CyberpunkTheme.cardBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct TransactionRow: View {
    let transaction: OBDTransaction

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: transaction.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Command line
            HStack(spacing: 8) {
                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CyberpunkTheme.textMuted)

                Text(">")
                    .foregroundStyle(CyberpunkTheme.neonGreen)

                Text(transaction.command)
                    .foregroundStyle(CyberpunkTheme.neonCyan)
            }
            .font(.system(size: 14, design: .monospaced))

            // Response line
            Text(transaction.response)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(transaction.isError ? CyberpunkTheme.neonRed : CyberpunkTheme.textPrimary)
                .padding(.leading, 80)
        }
    }
}

/// Quick command buttons for common OBD commands
struct QuickCommandsView: View {
    let onCommand: (String) -> Void

    private let commands = [
        ("ATZ", "Reset"),
        ("ATI", "Info"),
        ("ATRV", "Voltage"),
        ("010C", "RPM"),
        ("010D", "Speed"),
        ("0100", "PIDs")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commands, id: \.0) { command, label in
                    Button {
                        onCommand(command)
                    } label: {
                        VStack(spacing: 2) {
                            Text(command)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CyberpunkTheme.neonCyan)
                            Text(label)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CyberpunkTheme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(CyberpunkTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(CyberpunkTheme.neonCyan.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    DebugTerminalView(viewModel: DebugViewModel(obdViewModel: OBDViewModel()))
}
