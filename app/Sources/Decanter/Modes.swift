import SwiftUI
import AppKit

/// The two shapes of the same thing.
///
/// A **system** is one Windows environment that several programs share: install what you like
/// into it, and they are all there next time. An **application** is one program frozen into a
/// bundle that carries its own Windows environment and its own runtime, so it can be copied
/// somewhere else and opened there, on a Mac that has never heard of Decanter.
enum Mode: String, CaseIterable, Identifiable {
    case systems
    case applications

    var id: String { rawValue }
    var title: String { self == .systems ? "Systems" : "Applications" }
}

struct ApplicationsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if store.exported.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text("No exported applications yet").font(.title3)
                Text("A system holds several programs and needs Decanter to run them.\n"
                     + "An application is one program with everything it needs inside it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("Open a system, then Export as an Application…")
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        } else {
            List {
                ForEach(store.exported) { entry in
                    HStack {
                        Image(systemName: "macwindow.on.rectangle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.program)
                            Text(entry.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Reveal") { store.reveal(entry.path) }
                            .buttonStyle(.link)
                        Button("Forget") { store.forget(entry) }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }
}

/// Freeze one program out of a system.
struct ExportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let bottle: String

    @State private var program = ""
    @State private var destination = ""

    var shortcuts: [Bottle.Shortcut] {
        store.bottles.first { $0.name == bottle }?.shortcuts ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export from \(bottle)").font(.headline)
            Text("The program is copied into an app of its own, with the Windows environment it "
                 + "runs in and the runtime that runs it. It needs nothing else afterwards, and "
                 + "the space is shared with what is already installed until one of them changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Program", selection: $program) {
                    ForEach(shortcuts) { shortcut in
                        Text(shortcut.name).tag(shortcut.name)
                    }
                }
                LabeledContent("Save as") {
                    HStack {
                        Text(destination.isEmpty ? "Choose a place…" : destination)
                            .foregroundStyle(destination.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { choose() }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Export") {
                    store.export(bottle: bottle, program: program, to: destination)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(program.isEmpty || destination.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { program = shortcuts.first?.name ?? "" }
    }

    private func choose() {
        let panel = NSSavePanel()
        panel.title = "Where the application goes"
        panel.nameFieldStringValue = program.isEmpty ? "Program.app" : "\(program).app"
        panel.allowedFileTypes = ["app"]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url.path
    }
}
