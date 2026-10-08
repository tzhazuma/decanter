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
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("Bottles") {
                    ForEach(store.bottles) { bottle in
                        Label(bottle.name, systemImage: "shippingbox")
                            .tag(bottle.name)
                    }
                }
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
                    LabeledContent("Windows version", value: bottle.windows ?? "win10")
                    LabeledContent("Graphics", value: bottle.graphics ?? "wined3d")
                    if let created = bottle.created {
                        LabeledContent("Created", value: created)
                    }
                }

                Section("Programs") {
                    HStack {
                        Button {
                            store.chooseAndRun(in: bottle.name, installer: false)
                        } label: {
                            Label("Run a Program…", systemImage: "play")
                        }
                        Button {
                            store.chooseAndRun(in: bottle.name, installer: true)
                        } label: {
                            Label("Install…", systemImage: "arrow.down.circle")
                        }
                    }
                    if let programs = bottle.programs, !programs.isEmpty {
                        ForEach(programs, id: \.installer) { program in
                            LabeledContent((program.installer as NSString).lastPathComponent,
                                           value: program.when)
                        }
                    } else {
                        Text("Nothing installed yet.")
                            .foregroundStyle(.secondary)
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
