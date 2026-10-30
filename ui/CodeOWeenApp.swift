import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Disguise: Identifiable, Hashable {
    /// The CLI's slug; commands address disguises by it, never by display name.
    let id: String
    let name: String
    let kind: String
    let family: String
    let label: String
    let color: String
    let extensionsMode: String
    let iconKind: String?
    let emoji: String?
    let pinnedFolder: String?
    let tintsWindow: Bool
    let appURL: URL

    /// The window tint, the emoji title, and a pinned folder only apply to VS Code-style apps.
    var isVSCodeStyle: Bool { family == "vscode" }

    var summary: String {
        var parts = [label, color]
        if extensionsMode != "none" {
            parts.append("\(extensionsMode) extensions")
        }
        return parts.joined(separator: " · ")
    }
}

/// One entry of `code-o-ween apps --porcelain`.
struct AppRecipe: Identifiable, Hashable {
    static let other = "generic"

    let id: String
    let label: String
    let isInstalled: Bool
    let supportsExtensions: Bool
    let source: String
    /// "verified", "unverified" or "broken"; see the recipe notes in the CLI.
    let status: String

    var isBroken: Bool { status == "broken" }

    /// The manager only dresses up code editors: the VS Code-style recipes, which the listing
    /// marks as the ones with an extension directory, plus "Other app…" for an editor it does
    /// not know by name. Browsers and chat apps stay available to the CLI.
    var isCodeEditor: Bool { id == Self.other || supportsExtensions }
}

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let errors: String
}

enum IconChoice: String, CaseIterable, Identifiable {
    case keep = "Keep"
    case builtIn = "Default"
    case emoji = "Emoji"
    case custom = "Image"

    var id: String { rawValue }

    /// A new disguise has no icon to keep.
    static let forNewDisguise: [IconChoice] = [.builtIn, .emoji, .custom]
}

/// The shape the CLI's slugify produces: lower-case letters and digits, single dashes between.
func isValidSlug(_ slug: String) -> Bool {
    slug.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
}

/// Mirrors the CLI's is_vscode_style_app: a bundle that ships VS Code's product.json and CLI.
func isVSCodeStyleBundle(_ path: String) -> Bool {
    guard !path.isEmpty else { return false }
    let app = URL(fileURLWithPath: expandTilde(path))
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/app/product.json").path)
        && FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/app/bin").path, isDirectory: &isDirectory)
        && isDirectory.boolValue
}

func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

func iconInputIsValid(_ choice: IconChoice, emoji: String, imagePath: String) -> Bool {
    switch choice {
    case .emoji: return !emoji.isEmpty
    case .custom: return !imagePath.isEmpty
    case .keep, .builtIn: return true
    }
}

struct Costume: Identifiable {
    /// The costume picker's first entry: no preset, the icon and color are chosen by hand.
    static let custom = "Custom"

    let id: String
    let emoji: String
    let color: String
}

@MainActor
final class FormState: ObservableObject {
    @Published var name = ""
    @Published var recipe = "vscode"
    @Published var sourceAppPath = ""
    @Published var costume = Costume.custom
    @Published var color = "orange"
    @Published var iconChoice: IconChoice = .emoji
    @Published var emoji = "🎃"
    @Published var customIconPath = ""
    @Published var isolatedExtensions = false
    /// Passes --trust-source: accept a validly signed build that is not from an identified
    /// developer (VSCodium, for example). Never implied.
    @Published var trustSource = false
    @Published var pinnedFolder = ""
    @Published var tintWindow = true
    @Published var instanceToRemove: Disguise?
    /// The create form was asked for ("Add More…"). It also shows by itself while there is
    /// nothing to list, which needs no request.
    @Published var isPresented: Bool

    init(isPresented: Bool = false) {
        self.isPresented = isPresented
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The name and icon are valid. Whether the chosen app can be disguised is up to the view,
    /// which knows the selected recipe.
    var canCreate: Bool {
        !trimmedName.isEmpty && !trimmedName.hasPrefix("-")
            && iconInputIsValid(iconChoice, emoji: emoji, imagePath: customIconPath)
    }
}

@MainActor
final class EditState: ObservableObject {
    @Published var instance: Disguise?
    @Published var color = "blue"
    @Published var iconChoice: IconChoice = .keep
    @Published var emoji = ""
    @Published var customIconPath = ""
    @Published var pinnedFolder = ""
    @Published var tintWindow = true

    func begin(_ instance: Disguise) {
        color = instance.color
        switch instance.iconKind {
        case "emoji": iconChoice = .emoji
        case "built-in": iconChoice = .builtIn
        default: iconChoice = .keep
        }
        emoji = instance.emoji ?? ""
        customIconPath = ""
        pinnedFolder = instance.pinnedFolder ?? ""
        tintWindow = instance.tintsWindow
        self.instance = instance
    }

    /// Arguments for `update`, containing only what changed; nil when nothing changed.
    func updateArguments() -> [String]? {
        guard let instance else { return nil }
        var arguments: [String] = []
        if color != instance.color {
            arguments += ["--color", color]
        }
        switch iconChoice {
        case .keep:
            break
        case .emoji:
            if instance.iconKind != "emoji" || emoji != (instance.emoji ?? "") {
                arguments += ["--emoji", emoji]
            }
        case .custom:
            if !customIconPath.isEmpty {
                arguments += ["--icon", expandTilde(customIconPath)]
            }
        case .builtIn:
            if instance.iconKind != "built-in" {
                arguments.append("--built-in-icon")
            }
        }
        if instance.isVSCodeStyle {
            let folder = expandTilde(pinnedFolder)
            if folder != (instance.pinnedFolder ?? "") {
                arguments += folder.isEmpty ? ["--no-folder"] : ["--folder", folder]
            }
            if tintWindow != instance.tintsWindow {
                arguments += ["--window-color", tintWindow ? "on" : "off"]
            }
        }
        return arguments.isEmpty ? nil : ["update", instance.id] + arguments
    }

    var isValid: Bool {
        iconInputIsValid(iconChoice, emoji: emoji, imagePath: customIconPath)
    }

    /// Color and icon changes rebuild the app, which requires quitting it first.
    var needsRebuild: Bool {
        guard let arguments = updateArguments() else { return false }
        return arguments.contains { ["--color", "--emoji", "--icon", "--built-in-icon"].contains($0) }
    }
}

@MainActor
final class InstanceStore: ObservableObject {
    @Published var instances: [Disguise] = []
    @Published var recipes: [AppRecipe] = []
    @Published var isBusy = false
    @Published var status = "Ready for trick or treat"
    @Published var lastCommandFailed = false
    /// Problems with the bundles on disk found while listing them. Kept apart from the command
    /// status: reload() runs after every command, and a bad bundle must not turn a success red.
    @Published var listProblems: [String] = []
    /// False until the first reload(), so an empty list is not mistaken for "no disguises yet".
    @Published private(set) var hasLoaded = false

    private var cliURL: URL {
        // Deliberately not overridable: the environment must not choose the program this runs.
        guard let resources = Bundle.main.resourceURL else {
            return URL(fileURLWithPath: "/usr/bin/false")
        }
        return resources.appendingPathComponent("cli/code-o-ween")
    }

    /// Where disguises live. Like the CLI's ${VAR:-fallback}, an empty override is no override.
    private var appRoots: [URL] {
        if let override = ProcessInfo.processInfo.environment["CODE_O_WEEN_APP_ROOT"], !override.isEmpty {
            return [URL(fileURLWithPath: override)]
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Applications/Code-o-ween", isDirectory: true)]
    }

    func reload() {
        let manager = FileManager.default
        var found: [Disguise] = []
        var invalidSlugs: [String] = []
        for root in appRoots {
            let urls = (try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for appURL in urls where appURL.pathExtension == "app" {
                let resources = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
                guard let slug = readMetadata("slug", from: resources) else { continue }
                // Metadata is unverified data; a bundle claiming the slug "--all" must never
                // turn its Refresh into "refresh --all".
                guard isValidSlug(slug) else { invalidSlugs.append(appURL.lastPathComponent); continue }
                // The pinned folder and the window tint live in the profile, so they can change
                // without rebuilding the app.
                let profile = readMetadata("profile", from: resources)
                    .map { URL(fileURLWithPath: $0, isDirectory: true) }
                let setting = { (key: String) in profile.flatMap { Self.readValue(key, in: $0) } }
                found.append(Disguise(
                    id: slug,
                    name: readMetadata("name", from: resources) ?? appURL.deletingPathExtension().lastPathComponent,
                    kind: readMetadata("kind", from: resources) ?? "vscode",
                    family: readMetadata("family", from: resources) ?? "vscode",
                    label: readMetadata("label", from: resources) ?? "Visual Studio Code",
                    color: readMetadata("color", from: resources) ?? "blue",
                    extensionsMode: readMetadata("extensions", from: resources) ?? "shared",
                    iconKind: readMetadata("icon-kind", from: resources),
                    emoji: readMetadata("emoji", from: resources),
                    pinnedFolder: setting("pinned-folder").flatMap { $0.isEmpty ? nil : $0 },
                    tintsWindow: setting("window-tint") == "on",
                    appURL: appURL
                ))
            }
        }
        var problems: [String] = []
        if !invalidSlugs.isEmpty {
            problems.append("Ignored \(invalidSlugs.sorted().joined(separator: ", ")): the recorded name is not valid.")
        }
        // Two bundles claiming one slug would make every command ambiguous, so say so rather
        // than acting on an arbitrary one.
        let duplicates = Set(found.map(\.id).filter { slug in found.filter { $0.id == slug }.count > 1 })
        if !duplicates.isEmpty {
            problems.append("More than one disguise claims the name \(duplicates.sorted().joined(separator: ", ")). Remove or rename the extra app bundles.")
        }
        listProblems = problems
        hasLoaded = true
        instances = found.filter { !duplicates.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadRecipes() {
        let executable = cliURL
        Task {
            let result = await Self.execute(executable, arguments: ["apps", "--porcelain"])
            let parsed: [AppRecipe] = result.output.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 4 else { return nil }
                return AppRecipe(
                    id: fields[0],
                    label: fields[1],
                    isInstalled: fields[2] == "yes",
                    supportsExtensions: fields[3] == "yes",
                    source: fields.count > 4 ? fields[4] : "",
                    status: fields.count > 5 ? fields[5] : "unverified"
                )
            }
            if result.status == 0 {
                recipes = parsed
            } else {
                lastCommandFailed = true
                status = result.errors.isEmpty ? "Could not list the supported apps" : result.errors
            }
        }
    }

    func run(_ arguments: [String], successMessage: String, completion: (@MainActor () -> Void)? = nil) {
        guard !isBusy else { return }
        isBusy = true
        lastCommandFailed = false
        status = "Working…"
        let executable = cliURL

        Task {
            let result = await Self.execute(executable, arguments: arguments)
            isBusy = false
            // Always reload: a failed `refresh --all` may still have rebuilt some disguises.
            reload()
            if result.status == 0 {
                let warnings = Self.lines(of: result.errors, startingWith: ["Warning:"])
                status = ([successMessage] + warnings).joined(separator: "\n")
                completion?()
            } else {
                lastCommandFailed = true
                let errors = Self.lines(of: result.errors, startingWith: ["Error:"])
                status = errors.isEmpty
                    ? (result.errors.isEmpty ? (result.output.isEmpty ? "Command failed" : result.output) : result.errors)
                    : errors.joined(separator: "\n")
            }
        }
    }

    func clearError() {
        lastCommandFailed = false
    }

    func open(_ instance: Disguise) {
        run(["open", instance.id], successMessage: "Opened \(instance.name)")
    }

    func refresh(_ instance: Disguise) {
        run(["refresh", instance.id], successMessage: "Refreshed \(instance.name)")
    }

    func refreshAll() {
        run(["refresh", "--all"], successMessage: "Refreshed all disguises")
    }

    func remove(_ instance: Disguise) {
        run(["remove", instance.id, "--yes"], successMessage: "Removed \(instance.name)")
    }

    /// Reads `Contents/Resources/code-o-ween.<key>`.
    private func readMetadata(_ key: String, from directory: URL) -> String? {
        let url = directory.appendingPathComponent("code-o-ween.\(key)")
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readValue(_ filename: String, in directory: URL) -> String? {
        guard let value = try? String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8) else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lines(of text: String, startingWith prefixes: [String]) -> [String] {
        text.split(separator: "\n").map(String.init).filter { line in prefixes.contains { line.hasPrefix($0) } }
    }

    /// Runs the CLI off the main actor. Standard error goes to a temporary file so that neither
    /// stream can fill up and block the process while the other is being read.
    nonisolated private static func execute(_ executable: URL, arguments: [String]) async -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        let errorsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-o-ween-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: errorsURL) }
        guard FileManager.default.createFile(atPath: errorsURL.path, contents: nil),
              let errorsHandle = try? FileHandle(forWritingTo: errorsURL) else {
            return CommandResult(status: 1, output: "", errors: "Could not create a temporary file")
        }
        defer { try? errorsHandle.close() }
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorsHandle
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = { (data: Data) in
                String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            return CommandResult(
                status: process.terminationStatus,
                output: text(data),
                errors: text((try? Data(contentsOf: errorsURL)) ?? Data())
            )
        } catch {
            return CommandResult(status: 1, output: "", errors: error.localizedDescription)
        }
    }
}

/// Preset colors, mirroring the CLI's COLOR_TABLE, darkest first (tests/ui-check.sh keeps them in sync).
/// A disguise's color is a preset name or any "#RRGGBB" value.
struct ColorPreset: Identifiable {
    let id: String
    let hex: String
}

let colorPresets = [
    ColorPreset(id: "black", hex: "#212121"), ColorPreset(id: "navy", hex: "#1A237E"),
    ColorPreset(id: "magenta", hex: "#AD1457"), ColorPreset(id: "indigo", hex: "#3F51B5"),
    ColorPreset(id: "brown", hex: "#795548"), ColorPreset(id: "slate", hex: "#546E7A"),
    ColorPreset(id: "purple", hex: "#7E57C2"), ColorPreset(id: "lime", hex: "#4F7D2A"),
    ColorPreset(id: "yellow", hex: "#946A00"), ColorPreset(id: "orange", hex: "#BF4F00"),
    ColorPreset(id: "green", hex: "#1E8255"), ColorPreset(id: "teal", hex: "#007F88"),
    ColorPreset(id: "red", hex: "#D13C3C"), ColorPreset(id: "blue", hex: "#2276D2"),
    ColorPreset(id: "pink", hex: "#D33682")
]

/// The "#RRGGBB" for a stored color value (preset name or hex), if it is valid.
func hexValue(of value: String) -> String? {
    if let preset = colorPresets.first(where: { $0.id == value.lowercased() }) { return preset.hex }
    let digits = value.dropFirst()
    guard value.hasPrefix("#"), digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
    return value.uppercased()
}

func swiftUIColor(_ value: String) -> Color {
    guard let hex = hexValue(of: value), let number = UInt32(hex.dropFirst(), radix: 16) else { return .gray }
    return Color(
        .sRGB,
        red: Double((number >> 16) & 0xFF) / 255,
        green: Double((number >> 8) & 0xFF) / 255,
        blue: Double(number & 0xFF) / 255
    )
}

func hexString(from color: Color) -> String? {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
}

struct InstanceIcon: View {
    let instance: Disguise
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: instance.appURL.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Preset swatches plus the system color picker for any other color.
struct ColorPickerRow: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 10), count: 8)

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack {
                Text("Color")
                Spacer()
                if selection.hasPrefix("#") {
                    Text(selection)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .help("Choose any color")
            }
            LazyVGrid(columns: columns, alignment: .trailing, spacing: 10) {
                ForEach(colorPresets) { preset in
                    Button {
                        selection = preset.id
                    } label: {
                        Circle()
                            .fill(swiftUIColor(preset.hex))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if selection == preset.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(preset.id.capitalized)
                    .accessibilityLabel(Text(preset.id.capitalized))
                    .accessibilityAddTraits(selection == preset.id ? [.isSelected] : [])
                }
            }
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { swiftUIColor(selection) },
            set: { if let hex = hexString(from: $0) { selection = hex } }
        )
    }
}

/// Icon source picker plus the emoji field or image chooser that goes with it.
struct IconEditor: View {
    let choices: [IconChoice]
    @Binding var choice: IconChoice
    @Binding var emoji: String
    @Binding var imagePath: String

    var body: some View {
        Picker("Icon", selection: $choice) {
            ForEach(choices) { item in Text(item.rawValue).tag(item) }
        }
        .pickerStyle(.segmented)

        switch choice {
        case .keep:
            Text("Keeps the current icon. Color changes recolor only Emoji and Default icons.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .emoji:
            EmojiPickerRow(emoji: $emoji)
                .help("Also shown at the start of the VS Code window title")
        case .custom:
            HStack {
                TextField("Image", text: $imagePath, prompt: Text("SVG, PNG, or ICNS"))
                Button("Choose…") {
                    if let file = chooseIconFile() { imagePath = file }
                }
            }
        case .builtIn:
            EmptyView()
        }
    }
}

/// A grid of emoji to pick from, plus the system emoji palette for any other one. One emoji at a
/// time: whatever is typed, pasted, or inserted by the palette replaces the current one.
struct EmojiPickerRow: View {
    @Binding var emoji: String
    @FocusState private var fieldIsFocused: Bool

    static let suggestions = [
        "🎃", "👻", "🧛", "🧙", "🕷️", "💀", "🦇", "🧟",
        "🕸️", "🔮", "🧪", "🐈‍⬛", "🍬", "🌙", "⚡️", "🔥",
        "🚀", "🛠️", "🧩", "🐙", "🦄", "🐸", "🌵", "🍕"
    ]

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack {
                Text("Emoji")
                Spacer()
                TextField("Other emoji", text: singleEmoji, prompt: Text("🎃"))
                    .labelsHidden()
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .frame(width: 52)
                    .focused($fieldIsFocused)
                    .accessibilityLabel(Text("Emoji"))
                Button("More…", action: showPalette)
                    .help("Pick any emoji from the system palette")
            }
            LazyVGrid(columns: columns, alignment: .trailing, spacing: 6) {
                ForEach(Self.suggestions, id: \.self) { item in
                    Button {
                        emoji = item
                    } label: {
                        Text(item)
                            .font(.title2)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(emoji == item ? Color.accentColor.opacity(0.22) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(emoji == item ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(item))
                    .accessibilityAddTraits(emoji == item ? [.isSelected] : [])
                }
            }
        }
    }

    /// Keeps the last character only, so inserting into a filled field picks rather than appends.
    /// A Swift Character is a whole grapheme cluster, so multi-codepoint emoji survive.
    private var singleEmoji: Binding<String> {
        Binding(
            get: { emoji },
            set: { emoji = $0.last.map(String.init) ?? "" }
        )
    }

    /// The system emoji palette inserts into the focused text field; focus it first, and let
    /// that take effect before the palette comes up.
    private func showPalette() {
        fieldIsFocused = true
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

struct FolderPickerRow: View {
    @Binding var path: String

    var body: some View {
        HStack {
            TextField("Project folder", text: $path, prompt: Text("Optional: opens when launched"))
            if !path.isEmpty {
                Button {
                    path = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Unpin folder")
            }
            Button("Choose…") {
                if let folder = chooseFolder(startingAt: path) { path = folder }
            }
        }
    }
}

struct TintToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Tint the VS Code window with this color", isOn: $isOn)
    }
}

@MainActor
func chooseFolder(startingAt path: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Pin Folder"
    if !path.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: expandTilde(path), isDirectory: true)
    }
    return panel.runModal() == .OK ? panel.url?.path : nil
}

@MainActor
func chooseIconFile() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = ["svg", "png", "jpg", "jpeg", "tif", "tiff", "webp", "icns"]
        .compactMap { UTType(filenameExtension: $0) }
    return panel.runModal() == .OK ? panel.url?.path : nil
}

struct EditInstanceView: View {
    @ObservedObject var store: InstanceStore
    @ObservedObject var edit: EditState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let instance = edit.instance {
                HStack(spacing: 12) {
                    InstanceIcon(instance: instance, size: 48)
                    Text("Edit \(instance.name)")
                        .font(.title2.weight(.semibold))
                }
            }

            Form {
                ColorPickerRow(selection: $edit.color)
                IconEditor(
                    choices: IconChoice.allCases,
                    choice: $edit.iconChoice,
                    emoji: $edit.emoji,
                    imagePath: $edit.customIconPath
                )
                if edit.instance?.isVSCodeStyle ?? false {
                    FolderPickerRow(path: $edit.pinnedFolder)
                    TintToggle(isOn: $edit.tintWindow)
                }
            }
            .formStyle(.grouped)
            .disabled(store.isBusy)

            if edit.needsRebuild {
                Label("Quit this disguise before applying color or icon changes.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.lastCommandFailed {
                Text(store.status)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
                Button("Cancel") { edit.instance = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isBusy)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(edit.updateArguments() == nil || !edit.isValid || store.isBusy)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func apply() {
        guard let arguments = edit.updateArguments(), let instance = edit.instance else { return }
        store.run(arguments, successMessage: "Updated \(instance.name)") {
            // Close only the sheet this change was made from.
            if edit.instance?.id == instance.id { edit.instance = nil }
        }
    }
}

struct ContentView: View {
    @StateObject private var store = InstanceStore()
    @StateObject private var form = FormState()
    @StateObject private var edit = EditState()

    private let costumes = [
        Costume(id: "Pumpkin", emoji: "🎃", color: "orange"),
        Costume(id: "Ghost", emoji: "👻", color: "purple"),
        Costume(id: "Vampire", emoji: "🧛", color: "red"),
        Costume(id: "Witch", emoji: "🧙", color: "green"),
        Costume(id: "Spider", emoji: "🕷️", color: "teal"),
        Costume(id: "Skeleton", emoji: "💀", color: "pink")
    ]

    init(startsCreating: Bool = false) {
        _form = StateObject(wrappedValue: FormState(isPresented: startsCreating))
    }

    /// The window shows one thing at a time: the create form while there is nothing to list or
    /// after "Add More…", otherwise the list of disguises.
    private var showsCreateForm: Bool {
        form.isPresented || (store.hasLoaded && store.instances.isEmpty)
    }

    var body: some View {
        Group {
            if showsCreateForm {
                createForm
            } else {
                instanceList
            }
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 560, idealHeight: 660)
        // The Pumpkin costume's orange, so controls match the app icon and the default disguise.
        .tint(swiftUIColor("orange"))
        .onAppear {
            store.reload()
            store.loadRecipes()
        }
        .alert("Remove disguise?", isPresented: Binding(
            get: { form.instanceToRemove != nil },
            set: { if !$0 { form.instanceToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { form.instanceToRemove = nil }
            Button("Remove", role: .destructive) {
                if let instance = form.instanceToRemove { store.remove(instance) }
                form.instanceToRemove = nil
            }
        } message: {
            Text("The app will be removed, but its settings will be kept.")
        }
        .sheet(isPresented: Binding(
            get: { edit.instance != nil },
            set: { if !$0 { edit.instance = nil } }
        )) {
            EditInstanceView(store: store, edit: edit)
        }
    }

    private func beginEdit(_ instance: Disguise) {
        store.clearError()
        edit.begin(instance)
    }

    private var selectedRecipe: AppRecipe? {
        store.recipes.first { $0.id == form.recipe }
    }

    private var editorRecipes: [AppRecipe] {
        store.recipes.filter(\.isCodeEditor)
    }

    private var isCustomCostume: Bool {
        form.costume == Costume.custom
    }

    private var isOtherApp: Bool {
        form.recipe == AppRecipe.other
    }

    private var supportsExtensions: Bool { isVSCodeStyle }

    /// The recipe listing marks VS Code-style apps as the ones with a separate extension
    /// directory, which is also what the window tint and a pinned folder need.
    private var isVSCodeStyle: Bool {
        if isOtherApp { return isVSCodeStyleBundle(form.sourceAppPath) }
        return selectedRecipe?.supportsExtensions ?? false
    }

    /// What the create button promises to disguise.
    private var targetLabel: String {
        if isOtherApp {
            let path = form.sourceAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "app" : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return selectedRecipe?.label ?? "VS Code"
    }

    private var instanceList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Disguises")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: store.reload) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload list")
            }
            .padding()

            if !store.listProblems.isEmpty {
                Label(store.listProblems.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    .textSelection(.enabled)
            }

            List(store.instances) { instance in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: instance.appURL.path))
                        .resizable()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name).fontWeight(.medium)
                        Text(instance.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Each row carries its own actions; Refresh stays in the context menu.
                    HStack(spacing: 6) {
                        Button("Open") { store.open(instance) }
                        Button("Edit…") { beginEdit(instance) }
                        Button(role: .destructive) {
                            form.instanceToRemove = instance
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Remove \(instance.name)…")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.isBusy)
                }
                .padding(.vertical, 3)
                .contextMenu {
                    // Disabled while a command runs, like the row buttons: store.run drops commands
                    // while busy, which would otherwise dismiss a confirmation and do nothing.
                    Group {
                        Button("Edit…") { beginEdit(instance) }
                        Button("Open") { store.open(instance) }
                        Button("Refresh") { store.refresh(instance) }
                        Divider()
                        Button("Remove…", role: .destructive) { form.instanceToRemove = instance }
                    }
                    .disabled(store.isBusy)
                }
            }

            HStack {
                Button {
                    store.clearError()
                    form.isPresented = true
                } label: {
                    Label("Add More…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n")
                Spacer()
                Button("Refresh All", action: store.refreshAll)
                    .disabled(store.isBusy)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            statusLine
                .padding()
        }
    }

    private var statusLine: some View {
        Text(store.status)
            .font(.caption)
            .foregroundColor(store.lastCommandFailed ? .red : .secondary)
            .lineLimit(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                // The bundle's AppIcon (the carved pumpkin); a generic app icon outside the built app.
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dress up your apps")
                        .font(.title.weight(.semibold))
                    Text("Give VS Code or another code editor a Halloween costume, a distinct Dock identity, and its own private stash of settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Form {
                Picker("App", selection: $form.recipe) {
                    ForEach(editorRecipes) { recipe in
                        Text(recipeTitle(recipe)).tag(recipe.id)
                    }
                }
                .onChange(of: form.recipe) { newValue in
                    // Trust was given for one build; a different app needs a fresh decision.
                    form.trustSource = false
                    if newValue == AppRecipe.other && form.sourceAppPath.isEmpty {
                        chooseSourceApp()
                    }
                }
                .onChange(of: form.sourceAppPath) { _ in
                    form.trustSource = false
                }

                if isOtherApp {
                    HStack {
                        TextField("App bundle", text: $form.sourceAppPath, prompt: Text("/Applications/Some App.app"))
                        Button("Choose…", action: chooseSourceApp)
                    }
                }

                TextField("Name", text: $form.name, prompt: Text("my fancy.side.project.com"))

                Picker("Costume", selection: $form.costume) {
                    Text("Custom").tag(Costume.custom)
                    ForEach(costumes) { item in
                        Text("\(item.emoji)  \(item.id)").tag(item.id)
                    }
                }
                .onChange(of: form.costume) { newValue in
                    // Custom keeps whatever icon and color were set; a preset replaces them.
                    guard let selected = costumes.first(where: { $0.id == newValue }) else { return }
                    form.emoji = selected.emoji
                    form.color = selected.color
                    form.iconChoice = .emoji
                }

                if isCustomCostume {
                    IconEditor(
                        choices: IconChoice.forNewDisguise,
                        choice: $form.iconChoice,
                        emoji: $form.emoji,
                        imagePath: $form.customIconPath
                    )
                }

                ColorPickerRow(selection: $form.color)

                if isVSCodeStyle {
                    FolderPickerRow(path: $form.pinnedFolder)
                    TintToggle(isOn: $form.tintWindow)
                }

                if supportsExtensions {
                    Toggle("Use a separate extension directory", isOn: $form.isolatedExtensions)
                }

                if showsTrustOption {
                    Toggle("Trust this app's signature even if it is not from an identified developer", isOn: $form.trustSource)
                        .help("Needed for builds such as VSCodium that are validly signed but not Apple-notarized")
                }
            }
            .formStyle(.grouped)
            .disabled(store.isBusy)

            HStack {
                // With nothing to list there is nowhere to go back to.
                if !store.instances.isEmpty {
                    Button("Cancel") { form.isPresented = false }
                        .keyboardShortcut(.cancelAction)
                        .disabled(store.isBusy)
                }
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
                Button("Disguise \(targetLabel)", action: createInstance)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || store.isBusy)
            }

            statusLine
        }
        .padding(24)
    }

    private func recipeTitle(_ recipe: AppRecipe) -> String {
        if recipe.id == AppRecipe.other { return "Other app…" }
        var notes: [String] = []
        if !recipe.isInstalled { notes.append("not found") }
        if recipe.isBroken { notes.append("not working") } else if recipe.status != "verified" { notes.append("not yet verified") }
        return notes.isEmpty ? recipe.label : "\(recipe.label) (\(notes.joined(separator: ", ")))"
    }

    /// Verified recipes are pinned to their publisher, so trusting another signature makes no
    /// sense there; everything else may be a build the CLI would otherwise refuse.
    private var showsTrustOption: Bool {
        isOtherApp || (selectedRecipe?.status ?? "verified") != "verified"
    }

    /// Mirrors the CLI, which refuses these before copying anything.
    private var selectedRecipeIsBroken: Bool {
        !isOtherApp && (selectedRecipe?.isBroken ?? false)
    }

    private var canCreate: Bool {
        guard form.canCreate, !selectedRecipeIsBroken else { return false }
        if isOtherApp && form.sourceAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    private func createInstance() {
        var arguments = ["create", form.trimmedName, "--color", form.color]
        if isOtherApp {
            arguments += ["--source", expandTilde(form.sourceAppPath)]
        } else {
            arguments += ["--app", form.recipe]
        }
        if showsTrustOption && form.trustSource {
            arguments.append("--trust-source")
        }
        switch form.iconChoice {
        case .emoji: arguments += ["--emoji", form.emoji]
        case .custom: arguments += ["--icon", expandTilde(form.customIconPath)]
        case .builtIn: arguments.append("--built-in-icon")
        case .keep: break
        }
        if supportsExtensions {
            arguments += ["--extensions", form.isolatedExtensions ? "isolated" : "shared"]
        }
        if isVSCodeStyle {
            let folder = expandTilde(form.pinnedFolder)
            if !folder.isEmpty { arguments += ["--folder", folder] }
            arguments += ["--window-color", form.tintWindow ? "on" : "off"]
        }
        let created = form.trimmedName
        store.run(arguments, successMessage: "Created \(created)") {
            form.name = ""
            form.pinnedFolder = ""
            // Trust is granted per disguise, not carried into the next one.
            form.trustSource = false
            // Back to the list, which now has the new disguise; a failure keeps the form up.
            form.isPresented = false
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["svg", "png", "jpg", "jpeg", "tif", "tiff", "webp", "icns"]
            .compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            form.customIconPath = url.path
        }
    }

    private func chooseSourceApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            form.sourceAppPath = url.path
        }
    }
}

@main
struct CodeOWeenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
