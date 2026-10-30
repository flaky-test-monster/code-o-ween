// Compiled together with ui/CodeOWeenApp.swift (minus its @main) by tests/ui-check.sh.
// Arguments: OUTPUT_DIR SETTINGS_FILE_OF_THE_TEST_DISGUISE
import AppKit
import SwiftUI

@MainActor func snapshot<V: View>(_ view: V, size: CGSize, to path: String) {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: .aqua)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

@MainActor func runAndWait(_ store: InstanceStore, _ arguments: [String]) {
    store.run(arguments, successMessage: "OK")
    while store.isBusy { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
}

var failures = 0
@MainActor func expect(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("ok   \(label)") } else { failures += 1; print("FAIL \(label): \(detail())") }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let output = CommandLine.arguments[1]
    let settings = CommandLine.arguments[2]
    let store = InstanceStore()
    store.reload()
    guard store.instances.count == 1, let instance = store.instances.first else {
        print("FAIL expected exactly one disguise, found \(store.instances.count)")
        exit(1)
    }
    expect("instances are addressed by slug", instance.id == "ui-check", instance.id)
    expect("a bundle with an invalid slug is ignored and reported, without failing the status",
           !store.lastCommandFailed && store.listProblems.joined().contains("Evil") && !store.instances.contains { $0.id == "--all" },
           store.listProblems.joined())

    runAndWait(store, ["update", "does-not-exist", "--color", "red"])
    expect("errors are shown", store.lastCommandFailed && store.status.hasPrefix("Error: disguise"), store.status)

    try? FileManager.default.createDirectory(
        atPath: (settings as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? "{\"a\": ".write(toFile: settings, atomically: true, encoding: .utf8)
    runAndWait(store, ["update", instance.id, "--window-color", "on"])
    expect("a settings file that cannot be edited is an error, with the reason from stderr",
           store.lastCommandFailed && store.status.contains("could not update the settings"), store.status)
    expect("a failed tint change is not recorded", store.instances.first?.tintsWindow == false)
    try? "{}".write(toFile: settings, atomically: true, encoding: .utf8)
    runAndWait(store, ["update", instance.id, "--window-color", "on"])
    expect("the tint applies once the file is valid", !store.lastCommandFailed, store.status)
    expect("the list reloads", store.instances.first?.tintsWindow == true)

    let edit = EditState()
    edit.begin(store.instances.first!)
    expect("unchanged edit sends nothing", edit.updateArguments() == nil)
    edit.color = "teal"
    expect("edit sends only changes, by slug", edit.updateArguments() == ["update", "ui-check", "--color", "teal"],
           String(describing: edit.updateArguments()))
    expect("color changes need a rebuild", edit.needsRebuild)
    edit.color = instance.color
    edit.tintWindow = false
    expect("tint changes do not need a rebuild", !edit.needsRebuild && edit.updateArguments() == ["update", "ui-check", "--window-color", "off"])
    edit.iconChoice = .emoji
    edit.emoji = ""
    expect("empty emoji is invalid", !edit.isValid)

    // The app's color presets must match the CLI's.
    let colors = Process()
    let pipe = Pipe()
    colors.executableURL = Bundle.main.resourceURL!.appendingPathComponent("cli/code-o-ween")
    colors.arguments = ["colors"]
    colors.standardOutput = pipe
    try? colors.run()
    let cliPresets = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").map { $0.split(separator: " ").joined(separator: " ") }
    colors.waitUntilExit()
    expect("color presets match the CLI", cliPresets == colorPresets.map { "\($0.id) \($0.hex)" }, "\(cliPresets)")
    expect("custom colors round-trip", colorPresets.allSatisfy { hexString(from: swiftUIColor($0.hex)) == $0.hex }
        && hexString(from: swiftUIColor("#12ab9f")) == "#12AB9F" && hexValue(of: "#12ab9") == nil && hexValue(of: "Navy") == "#1A237E")

    let form = FormState()
    form.name = "  Spaced  "
    expect("names are trimmed", form.trimmedName == "Spaced" && form.canCreate)
    form.name = "--all"
    expect("names starting with '-' are rejected", !form.canCreate)
    expect("a new disguise starts with a custom costume", form.costume == Costume.custom)
    func recipe(_ id: String, extensions: Bool) -> AppRecipe {
        AppRecipe(id: id, label: id, isInstalled: true, supportsExtensions: extensions, source: "", status: "unverified")
    }
    expect("the app picker lists code editors only",
           recipe("vscode", extensions: true).isCodeEditor && recipe("vscodium", extensions: true).isCodeEditor
           && recipe(AppRecipe.other, extensions: false).isCodeEditor
           && !recipe("slack", extensions: false).isCodeEditor && !recipe("chrome", extensions: false).isCodeEditor)

    edit.begin(store.instances.first!)
    edit.color = "teal"
    // The list, since one disguise exists; the create form on request, as "Add More…" shows it.
    snapshot(ContentView(), size: CGSize(width: 600, height: 660), to: output + "/main.png")
    snapshot(ContentView(startsCreating: true), size: CGSize(width: 600, height: 760), to: output + "/create.png")
    snapshot(EditInstanceView(store: store, edit: edit), size: CGSize(width: 480, height: 640), to: output + "/edit.png")
    print(failures == 0 ? "PASS: UI command handling and edit logic (snapshots in \(output))" : "FAILURES: \(failures)")
    exit(failures == 0 ? 0 : 1)
}
