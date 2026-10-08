import Foundation
import AppKit

/// A bottle, as the command line tool writes it: `bottle.json` beside the Wine prefix.
struct Bottle: Identifiable, Codable, Hashable {
    var name: String
    var created: String?
    var windows: String?
    var graphics: String?
    var env: [String: String]?
    var programs: [Program]?
    var shortcuts: [Shortcut]?

    var id: String { name }

    struct Program: Codable, Hashable {
        var installer: String
        var when: String
    }

    struct Shortcut: Codable, Hashable, Identifiable {
        var name: String
        var path: String
        /// Flags the program needs to start under Wine, kept with the shortcut so that launching
        /// it does not mean remembering them.
        var args: [String]?
        var id: String { name }
    }
}

/// A bottle named by a sheet that is being presented.
struct BottleRef: Identifiable, Hashable {
    var id: String
}

/// Where each Direct3D version goes under a backend. The same table the command line prints, so
/// the window and the shell say the same thing.
enum Backend: String, CaseIterable, Identifiable {
    case dxmt
    case dxvk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dxmt: return "DXMT — Direct3D 10 and 11 straight to Metal"
        case .dxvk: return "DXVK — Direct3D 9, 10 and 11 on KosmicKrisp"
        }
    }

    /// Direct3D version to what serves it.
    var routing: [(String, String)] {
        switch self {
        case .dxmt:
            return [("9", "DXVK on KosmicKrisp"), ("10", "DXMT on Metal"),
                    ("11", "DXMT on Metal"), ("12", "vkd3d-proton on KosmicKrisp")]
        case .dxvk:
            return [("9", "DXVK on KosmicKrisp"), ("10", "DXVK on KosmicKrisp"),
                    ("11", "DXVK on KosmicKrisp"), ("12", "vkd3d-proton on KosmicKrisp")]
        }
    }

    /// Bottles made before the choice meant anything say wined3d, which was never what they got.
    static func named(_ name: String?) -> Backend {
        Backend(rawValue: name ?? "") ?? .dxmt
    }
}

/// What the runtime reports about itself.
struct RuntimeInfo {
    var path: String
    var variant: String
    var wineVersion: String
    var hasX86_64Emulator: Bool
    var hasX86Emulator: Bool

    var supports32Bit: Bool { variant == "release" }
}

/// The state the window draws from, and the only place that touches the file system
/// and the command line tool.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    @Published var selection: String?
    @Published private(set) var runtime: RuntimeInfo?
    @Published private(set) var log: String = ""
    @Published var busy: Bool = false
    @Published var presentNewBottle = false
    @Published var presentAddProgram: BottleRef? = nil

    private let home: URL
    private let runtimeURL: URL

    init() {
        let base = ProcessInfo.processInfo.environment["DECANTER_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/decanter")
        home = base
        runtimeURL = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["DECANTER_RUNTIME"] ?? base.appendingPathComponent("runtime").path)
        reload()
    }

    var selectedBottle: Bottle? { bottles.first { $0.name == selection } }

    // MARK: - reading

    func reload() {
        bottles = loadBottles()
        runtime = loadRuntime()
        if selection == nil || !bottles.contains(where: { $0.name == selection }) {
            selection = bottles.first?.name
        }
    }

    private func loadBottles() -> [Bottle] {
        let directory = home.appendingPathComponent("bottles")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        return entries
            .compactMap { entry -> Bottle? in
                let meta = entry.appendingPathComponent("bottle.json")
                guard let data = try? Data(contentsOf: meta) else { return nil }
                return try? decoder.decode(Bottle.self, from: data)
            }
            .sorted { $0.name < $1.name }
    }

    private func loadRuntime() -> RuntimeInfo? {
        let loader = runtimeURL.appendingPathComponent("bin/wine")
        guard FileManager.default.isExecutableFile(atPath: loader.path) else { return nil }

        func exists(_ relative: String) -> Bool {
            FileManager.default.fileExists(atPath: runtimeURL.appendingPathComponent(relative).path)
        }
        let variantFile = runtimeURL.appendingPathComponent("variant")
        let variant = (try? String(contentsOf: variantFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        var version = "unknown"
        let process = Process()
        process.executableURL = loader
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            version = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        }

        return RuntimeInfo(
            path: runtimeURL.path,
            variant: variant,
            wineVersion: version,
            hasX86_64Emulator: exists("lib/wine/aarch64-windows/xtajit64.dll"),
            hasX86Emulator: exists("lib/wine/aarch64-windows/xtajit.dll"))
    }

    // MARK: - the command line tool

    /// The tool this window drives. The window never reimplements bottle handling:
    /// one implementation, two front ends.
    private var cliURL: URL? {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["DECANTER_CLI"] {
            candidates.append(override)
        }
        // A packaged app carries the tool it was built with, so the window and the shell
        // cannot end up running different versions of it.
        if let bundled = Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .appendingPathComponent("SharedSupport/cli/decanter").path {
            candidates.append(bundled)
        }
        // Otherwise: beside the .app bundle, then the checkout this app was built in.
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("decanter").path)
        candidates.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("decanter/cli/decanter").path)
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private func runTool(_ arguments: [String], completion: ((Int32) -> Void)? = nil) {
        guard let cli = cliURL else {
            append("decanter: cannot find the command line tool. Set DECANTER_CLI to its path.")
            completion?(127)
            return
        }
        busy = true
        append("$ decanter " + arguments.joined(separator: " "))

        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(text) }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.busy = false
                self?.reload()
                completion?(finished.terminationStatus)
            }
        }
        do {
            try process.run()
        } catch {
            append("decanter: could not run the tool: \(error.localizedDescription)")
            busy = false
            completion?(126)
        }
    }

    private func append(_ text: String) {
        log += text.hasSuffix("\n") ? text : text + "\n"
    }

    // MARK: - actions

    func createBottle(named name: String, windows: String, graphics: String) {
        runTool(["bottle", "create", name, "--windows", windows, "--graphics", graphics, "--init"]) { _ in
            Task { @MainActor in self.selection = name }
        }
    }

    func deleteBottle(_ name: String) {
        runTool(["bottle", "rm", name, "--force"])
    }

    func runProgram(in bottle: String, path: String, arguments: [String] = []) {
        runTool(["run", bottle, path] + arguments)
    }

    func installProgram(in bottle: String, path: String) {
        runTool(["install", bottle, path])
    }

    func applyRecipe(_ recipe: String, to bottle: String) {
        runTool(["recipe", "apply", bottle, recipe])
    }

    func addShortcut(to bottle: String, name: String, path: String, arguments: [String] = []) {
        var command = ["shortcut", "add", bottle, name, path]
        if !arguments.isEmpty { command += ["--args"] + arguments }
        runTool(command)
    }

    func removeShortcut(from bottle: String, name: String) {
        runTool(["shortcut", "rm", bottle, name])
    }

    /// Change a bottle's Windows version or graphics backend after it was made.
    func update(_ bottle: String, windows: String? = nil, graphics: String? = nil) {
        var arguments = ["bottle", "set", bottle]
        if let windows { arguments += ["--windows", windows] }
        if let graphics { arguments += ["--graphics", graphics] }
        runTool(arguments)
    }

    func setEnvironment(_ assignments: [String], in bottle: String) {
        runTool(["env", bottle] + assignments)
    }

    /// Executables the bottle already has, for the "add a program" list.
    func suggestPrograms(in bottle: String, completion: @escaping ([String]) -> Void) {
        guard let cli = cliURL else { completion([]); return }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["shortcut", "suggest", bottle, "--limit", "60"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { completion([]); return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n").map(String.init) ?? []
        completion(lines)
    }

    /// Pick a Windows program (or an installer) and hand it to the bottle.
    func chooseAndRun(in bottle: String, installer: Bool) {
        let panel = NSOpenPanel()
        panel.title = installer ? "Choose an installer" : "Choose a Windows program"
        panel.allowedFileTypes = ["exe", "msi", "bat", "com"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if installer {
            installProgram(in: bottle, path: url.path)
        } else {
            runProgram(in: bottle, path: url.path)
        }
    }

    func clearLog() { log = "" }
}
