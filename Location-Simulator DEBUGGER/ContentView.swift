import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var logger = LocationLogger()
    @State private var isExporting = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sessionSummary
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                Divider()

                controls
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                Divider()

                if logger.entries.isEmpty {
                    ContentUnavailableView(
                        "No observations yet",
                        systemImage: "location.circle",
                        description: Text("Start a session, set a baseline, and mark changes as they happen.")
                    )
                } else {
                    List(logger.entries) { entry in
                        Text(entry.displayText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(entry.recordType == "event" ? .secondary : .primary)
                            .padding(.vertical, 3)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("location-simulator debugger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isConfirmingClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear log")
                    .disabled(logger.entries.isEmpty || logger.isRunning)
                }
            }
            .confirmationDialog(
                "Clear all recorded entries?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear Log", role: .destructive) {
                    logger.clearLog()
                }
                Button("Cancel", role: .cancel) {}
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: logger.exportFilename,
                onCompletion: { result in
                    logger.reportExportResult(result)
                }
            )
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    logger.mark("app_active")
                case .inactive:
                    logger.mark("app_inactive")
                case .background:
                    logger.mark("app_backgrounded")
                @unknown default:
                    logger.mark("app_phase_unknown")
                }
            }
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(logger.status)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Permission: \(logger.permissionSummary) · \(logger.locationServicesSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(logger.deviceSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Text("Fixes: \(logger.fixCount)")
                Text("Baseline: \(logger.baselineSummary)")
                Text("Max: \(logger.maximumDisplacementSummary)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var controls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Button {
                    logger.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(logger.isRunning)

                Button {
                    logger.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!logger.isRunning)

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    logger.setBaseline()
                } label: {
                    Label("Set Baseline", systemImage: "scope")
                }
                .buttonStyle(.bordered)
                .disabled(!logger.isRunning || logger.fixCount == 0)

                Menu {
                    Section("Accessory state") {
                        Button("Accessory connected") { logger.mark("accessory_connected") }
                        Button("Location input started") { logger.mark("location_input_started") }
                        Button("Location input stopped") { logger.mark("location_input_stopped") }
                        Button("Accessory disconnected") { logger.mark("accessory_disconnected") }
                    }
                    Section("Test condition") {
                        Button("Wi-Fi changed") { logger.mark("wifi_changed") }
                        Button("Cellular data changed") { logger.mark("cellular_data_changed") }
                        Button("Other change") { logger.mark("other_change") }
                    }
                } label: {
                    Label("Mark Event", systemImage: "tag")
                }
                .buttonStyle(.bordered)
                .disabled(!logger.isRunning)

                Spacer()
            }

            HStack {
                Button {
                    exportDocument = CSVDocument(text: logger.csvText)
                    isExporting = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(logger.entries.isEmpty)

                Spacer()
            }
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    ContentView()
}

