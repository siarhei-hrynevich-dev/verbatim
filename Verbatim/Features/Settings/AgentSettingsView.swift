import AppKit
import SwiftUI

/// Settings › Agents: the MCP server that lets AI agents on this Mac search and read recordings.
struct AgentSettingsView: View {
    @Bindable var viewModel: AgentSettingsViewModel

    @State private var isConfirmingNewToken = false
    @FocusState private var isEditingPort: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            server
            connection
        }
        .padding(SettingsLayout.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Create a new token?",
            isPresented: $isConfirmingNewToken
        ) {
            Button("Create New Token", role: .destructive, action: viewModel.regenerateToken)
        } message: {
            Text("Agents connected with the current token are refused until they are given the new one.")
        }
    }

    // MARK: - Server

    private var server: some View {
        SettingsSection(
            title: "MCP Server",
            footnote: String(
                localized: """
                    Agents can search and read transcripts and summaries, and can’t change or delete anything. What an \
                    agent reads is sent to the model it uses, which may run in the cloud.
                    """
            )
        ) {
            SettingsToggleRow(
                title: "Allow AI Agents to Read Recordings",
                detail: String(localized: "Runs a Model Context Protocol server that only this Mac can reach."),
                isOn: $viewModel.isEnabled
            )
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Status", detail: viewModel.statusDetail) {
                if viewModel.canRetry {
                    Button("Try Again", action: viewModel.retry)
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
                ModelStatusChip(
                    title: viewModel.statusTitle,
                    icon: viewModel.isRunning ? .check : .circle,
                    iconColor: viewModel.isRunning ? VerbatimColor.green : VerbatimColor.secondaryText
                )
            }
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Port", detail: viewModel.portIssue) {
                TextField("Port", text: $viewModel.portText)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 72)
                    .focused($isEditingPort)
                    .onSubmit(viewModel.applyPort)
                    .onChange(of: isEditingPort) { _, isEditing in
                        if !isEditing {
                            viewModel.applyPort()
                        }
                    }
            }
        }
    }

    // MARK: - Connection

    private var connection: some View {
        SettingsSection(
            title: "Connect an Agent",
            footnote: String(
                localized: """
                    Paste the command into Terminal for Claude Code, or add the configuration to an agent or editor \
                    that supports MCP servers over HTTP. Links in answers, such as verbatim://recording/…, open the \
                    moment in Verbatim.
                    """
            )
        ) {
            SettingsRow(title: "Server Address") {
                Text(verbatim: viewModel.serverURL)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                copyButton("Copy Server Address", text: viewModel.serverURL)
            }
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Access Token", detail: String(localized: "Sent by agents as a bearer token.")) {
                Text(verbatim: viewModel.tokenDisplay)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 190, alignment: .trailing)
                    .textSelection(.enabled)
                Button(viewModel.isTokenRevealed ? "Hide" : "Show") { viewModel.isTokenRevealed.toggle() }
                    .buttonStyle(.verbatim(.secondary, size: .inline))
                copyButton("Copy Access Token", text: viewModel.token)
                Button("New Token…") { isConfirmingNewToken = true }
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Claude Code", detail: String(localized: "A command that adds this server.")) {
                Button("Copy Command") { copy(viewModel.claudeCodeCommand) }
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
            GroupedDivider(leadingInset: 12)
            SettingsRow(
                title: "Other Agents",
                detail: String(localized: "An mcpServers entry for Cursor, VS Code, Claude Desktop and others.")
            ) {
                Button("Copy Configuration") { copy(viewModel.jsonConfiguration) }
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
        }
    }

    private func copyButton(_ label: LocalizedStringKey, text: String) -> some View {
        Button {
            copy(text)
        } label: {
            IconView(.copy, size: 13)
        }
        .buttonStyle(SettingsIconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
