import SwiftUI
import AppKit

@main
struct DecanterApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Decanter") {
            ContentView().environmentObject(store)
        }
        .defaultSize(width: 940, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bottle…") { store.presentNewBottle = true }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .help) {
                Link("Decanter Guide", destination: URL(string: "https://github.com/tzhazuma/decanter/blob/main/docs/guide.md")!)
                Link("Report a Problem", destination: URL(string: "https://github.com/tzhazuma/decanter/issues")!)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {                List(selection: $store.selection) {
                    Section("Bottles") {
                        ForEach(store.bottles) { bottle in
                            Label(bottle.name, systemImage: "shippingbox")
                                .tag(bottle.name)
                        }
                    }
                }
                Divider()
                RuntimeStatusView()
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button { store.presentNewBottle = true } label: {
                        Label("New Bottle", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let bottle = store.selectedBottle {
                BottleView(bottle: bottle)
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $store.presentNewBottle) {
            NewBottleSheet()
        }
        .sheet(item: $store.presentAddProgram) { ref in
            AddProgramSheet(bottle: ref.id)
        }
    }
}

struct RuntimeStatusView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let runtime = store.runtime {
                Label(runtime.wineVersion, systemImage: "cpu")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Badge(text: runtime.variant,
                          ok: true,
                          help: runtime.variant == "dev"
                            ? "Development runtime: no Apple Developer account needed, 64-bit programs only"
                            : "Release runtime: runs 32-bit programs too")
                    if runtime.supports32Bit {
                        Badge(text: "32-bit", ok: true, help: "The 32-bit emulator is available")
                    } else {
                        Badge(text: "64-bit only", ok: false,
                              help: "32-bit Windows programs need the release runtime, which needs a paid Apple Developer account")
                    }
                }
                if !runtime.hasX86_64Emulator {
                    Text("No x86-64 emulator installed.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Label("No runtime", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct Badge: View {
    let text: String
    let ok: Bool
    var help: String = ""

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ok ? Color.green.opacity(0.18) : Color.orange.opacity(0.18),
                        in: Capsule())
            .foregroundStyle(ok ? .green : .orange)
            .help(help)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No bottles yet").font(.title2)
            Text("A bottle is an isolated Windows environment: its own C: drive,\nits own registry, its own installed programs.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if store.runtime == nil {
                RuntimeMissingView()
            } else {
                Button("New Bottle…") { store.presentNewBottle = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }
}

struct RuntimeMissingView: View {
    var body: some View {
        VStack(spacing: 8) {
            Label("No runtime installed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Build one with:  scripts/bootstrap-runtime.sh --dev")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BottleView: View {
    @EnvironmentObject var store: Store
    let bottle: Bottle

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Bottle") {
                    LabeledContent("Name", value: bottle.name)
                    Picker("Windows version", selection: Binding(
                        get: { bottle.windows ?? "win10" },
                        set: { store.update(bottle.name, windows: $0) })) {
                        Text("Windows 7").tag("win7")
                        Text("Windows 10").tag("win10")
                        Text("Windows 11").tag("win11")
                    }
                    Picker("Graphics", selection: Binding(
                        get: { bottle.graphics ?? "wined3d" },
                        set: { store.update(bottle.name, graphics: $0) })) {
                        Text("WineD3D (built in)").tag("wined3d")
                        Text("DXMT (Direct3D 10/11 on Metal)").tag("dxmt")
                    }
                    if let created = bottle.created {
                        LabeledContent("Created", value: created)
                    }
                }

                Section("Programs") {
                    if let shortcuts = bottle.shortcuts, !shortcuts.isEmpty {
                        ForEach(shortcuts) { shortcut in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(shortcut.name)
                                    Text(shortcut.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    store.runProgram(in: bottle.name, path: shortcut.path)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.borderless)
                                .help("Run \(shortcut.name)")
                                Button {
                                    store.removeShortcut(from: bottle.name, name: shortcut.name)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this shortcut")
                            }
                        }
                    } else {
                        Text("No programs yet. Install one, then add it here.")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button {
                            store.chooseAndRun(in: bottle.name, installer: true)
                        } label: {
                            Label("Install a Windows program…", systemImage: "arrow.down.circle")
                        }
                        Button {
                            store.chooseAndRun(in: bottle.name, installer: false)
                        } label: {
                            Label("Run once…", systemImage: "play")
                        }
                        Button {
                            store.presentAddProgram = BottleRef(id: bottle.name)
                        } label: {
                            Label("Add to the list…", systemImage: "plus")
                        }
                    }
                }

                Section("Recipes") {
                    HStack {
                        Button("Visual C++ runtime") {
                            store.applyRecipe("vcrun2015", to: bottle.name)
                        }
                        Button(".NET 4.8 (untested)") {
                            store.applyRecipe("dotnet48", to: bottle.name)
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Delete Bottle", role: .destructive) {
                            store.deleteBottle(bottle.name)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            LogPane()
        }
        .navigationTitle(bottle.name)
    }
}

struct LogPane: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if store.busy { ProgressView().controlSize(.small) }
                Text("Output").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { store.clearLog() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.log.isEmpty ? "Nothing yet." : store.log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .id("end")
                }
                .onChange(of: store.log) { _, _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            .frame(height: 180)
            .background(.background.secondary)
        }
    }
}

struct AddProgramSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let bottle: String

    @State private var name = ""
    @State private var path = ""
    @State private var suggestions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a program to \(bottle)").font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Windows path", text: $path,
                          prompt: Text("C:\\Program Files\\Vendor\\app.exe"))
            }

            if !suggestions.isEmpty {
                Text("Already in this bottle — click to use:")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                path = suggestion
                                if name.isEmpty {
                                    name = ((suggestion as NSString)
                                        .lastPathComponent as NSString)
                                        .deletingPathExtension
                                }
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    store.addShortcut(to: bottle, name: name, path: path)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || path.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            store.suggestPrograms(in: bottle) { suggestions = $0 }
        }
    }
}

struct NewBottleSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var windows = "win10"
    @State private var graphics = "wined3d"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Bottle").font(.headline)
            Form {
                TextField("Name", text: $name)
                Picker("Windows version", selection: $windows) {
                    Text("Windows 7").tag("win7")
                    Text("Windows 10").tag("win10")
                    Text("Windows 11").tag("win11")
                }
                Picker("Graphics", selection: $graphics) {
                    Text("WineD3D (built in)").tag("wined3d")
                    Text("DXMT (Direct3D 10/11 on Metal)").tag("dxmt")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    store.createBottle(named: name, windows: windows, graphics: graphics)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
