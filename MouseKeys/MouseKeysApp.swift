import SwiftUI
import ApplicationServices
import CoreGraphics

// MARK: - Data Model

enum MappingScope: Codable, Equatable {
    case global
    case app(bundleIdentifier: String, displayName: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier
        case displayName
    }

    private enum ScopeType: String, Codable {
        case global
        case app
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ScopeType.self, forKey: .type) ?? .global

        switch type {
        case .global:
            self = .global
        case .app:
            guard let bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier), !bundleIdentifier.isEmpty else {
                self = .global
                return
            }
            let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            self = .app(bundleIdentifier: bundleIdentifier, displayName: displayName)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode(ScopeType.global, forKey: .type)
        case .app(let bundleIdentifier, let displayName):
            try container.encode(ScopeType.app, forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encodeIfPresent(displayName, forKey: .displayName)
        }
    }

    var identityKey: String {
        switch self {
        case .global:
            return "global"
        case .app(let bundleIdentifier, _):
            return "app:\(bundleIdentifier.lowercased())"
        }
    }

    var label: String {
        switch self {
        case .global:
            return "All Applications"
        case .app(let bundleIdentifier, let displayName):
            return displayName ?? bundleIdentifier
        }
    }

    var sortRank: Int {
        switch self {
        case .global: return 0
        case .app: return 1
        }
    }

    func matches(bundleIdentifier: String) -> Bool {
        switch self {
        case .global:
            return true
        case .app(let expectedBundleIdentifier, _):
            return expectedBundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }
}

struct ButtonMapping: Codable, Identifiable, Equatable {
    var id: String { "\(mouseButton)-\(scope.identityKey)" }
    let mouseButton: Int64
    var keyCode: CGKeyCode
    var modifiers: CGEventFlags
    var scope: MappingScope

    private enum CodingKeys: String, CodingKey {
        case mouseButton
        case keyCode
        case modifiers
        case scope
    }

    init(mouseButton: Int64, keyCode: CGKeyCode, modifiers: CGEventFlags, scope: MappingScope = .global) {
        self.mouseButton = mouseButton
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.scope = scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mouseButton = try container.decode(Int64.self, forKey: .mouseButton)
        keyCode = try container.decode(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decode(CGEventFlags.self, forKey: .modifiers)
        scope = try container.decodeIfPresent(MappingScope.self, forKey: .scope) ?? .global
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mouseButton, forKey: .mouseButton)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(scope, forKey: .scope)
    }

    var mouseButtonLabel: String {
        switch mouseButton {
        case 2: return "Middle Click (Button 3)"
        default: return "Button \(mouseButton + 1)"
        }
    }

    var shortcutLabel: String {
        var parts: [String] = []
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        parts.append(keyCodeName(keyCode))
        return parts.joined()
    }

    var scopeLabel: String {
        scope.label
    }

    static var defaultMappings: [ButtonMapping] {
        [
            ButtonMapping(mouseButton: 3, keyCode: 0x21, modifiers: .maskCommand),  // Button 4 → ⌘[
            ButtonMapping(mouseButton: 4, keyCode: 0x1E, modifiers: .maskCommand),  // Button 5 → ⌘]
        ]
    }
}

extension CGEventFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(UInt64.self)
        self.init(rawValue: raw)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Mapping Store

final class MappingStore: ObservableObject {
    static let shared = MappingStore()

    @Published var mappings: [ButtonMapping] = [] {
        didSet { save() }
    }

    private let key = "buttonMappings"

    init() {
        load()
    }

    func mapping(for button: Int64, frontmostBundleIdentifier: String?) -> ButtonMapping? {
        if let frontmostBundleIdentifier,
           let appScopedMapping = mappings.first(where: {
               $0.mouseButton == button && $0.scope != .global && $0.scope.matches(bundleIdentifier: frontmostBundleIdentifier)
           }) {
            return appScopedMapping
        }

        return mappings.first { $0.mouseButton == button && $0.scope == .global }
    }

    func addOrUpdate(_ mapping: ButtonMapping) {
        if let idx = mappings.firstIndex(where: {
            $0.mouseButton == mapping.mouseButton && $0.scope.identityKey == mapping.scope.identityKey
        }) {
            mappings[idx] = mapping
        } else {
            mappings.append(mapping)
        }
    }

    func remove(_ mapping: ButtonMapping) {
        mappings.removeAll {
            $0.mouseButton == mapping.mouseButton && $0.scope.identityKey == mapping.scope.identityKey
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ButtonMapping].self, from: data) {
            mappings = decoded
        } else {
            mappings = ButtonMapping.defaultMappings
        }
    }
}

// MARK: - Recording State

final class RecordingState: ObservableObject {
    static let shared = RecordingState()
    @Published var isRecording = false {
        didSet {
            if isRecording {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var lastRecordedButton: Int64?

    private var localMonitor: Any?
    private var globalMonitor: Any?

    private func startMonitoring() {
        // Local monitor catches events when our app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            self?.handleRecordedEvent(event)
            return nil // swallow
        }
        // Global monitor catches events when other apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            self?.handleRecordedEvent(event)
        }
        print("[MouseKeys] Recording monitors started")
    }

    private func stopMonitoring() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        print("[MouseKeys] Recording monitors stopped")
    }

    private func handleRecordedEvent(_ event: NSEvent) {
        let button = Int64(event.buttonNumber)
        print("[MouseKeys] Recorded button press: \(button) (buttonNumber: \(event.buttonNumber))")
        DispatchQueue.main.async {
            self.lastRecordedButton = button
            self.isRecording = false
        }
    }
}

final class FrontmostApplicationTracker: ObservableObject {
    static let shared = FrontmostApplicationTracker()

    @Published private(set) var displayBundleIdentifier = "Unknown"

    private let stateQueue = DispatchQueue(label: "MouseKeys.FrontmostApplicationTracker")
    private var currentBundleIdentifier: String?
    private var activationObserver: NSObjectProtocol?

    private init() {
        currentBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        displayBundleIdentifier = currentBundleIdentifier ?? "Unknown"

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setCurrentBundleIdentifier(app?.bundleIdentifier)
        }
    }

    var bundleIdentifier: String? {
        stateQueue.sync { currentBundleIdentifier }
    }

    private func setCurrentBundleIdentifier(_ bundleIdentifier: String?) {
        stateQueue.async {
            self.currentBundleIdentifier = bundleIdentifier
        }

        let displayValue = bundleIdentifier ?? "Unknown"
        DispatchQueue.main.async {
            self.displayBundleIdentifier = displayValue
        }
    }
}

// MARK: - Event Tap

func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Ignore non-otherMouseDown events
    guard type == .otherMouseDown else {
        return Unmanaged.passRetained(event)
    }

    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    let frontmostBundleIdentifier = FrontmostApplicationTracker.shared.bundleIdentifier
    print("[MouseKeys] Event tap saw button: \(buttonNumber)")

    // If recording, let the event pass through so NSEvent monitors can see it
    if RecordingState.shared.isRecording {
        return Unmanaged.passRetained(event)
    }

    // Look up mapping
    guard let mapping = MappingStore.shared.mapping(for: buttonNumber, frontmostBundleIdentifier: frontmostBundleIdentifier) else {
        return Unmanaged.passRetained(event)
    }

    guard let source = CGEventSource(stateID: .hidSystemState) else {
        return Unmanaged.passRetained(event)
    }

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: false) else {
        return Unmanaged.passRetained(event)
    }

    keyDown.flags = mapping.modifiers
    keyUp.flags = mapping.modifiers
    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)

    return nil
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var store = MappingStore.shared
    @ObservedObject var recording = RecordingState.shared
    @ObservedObject var appTracker = FrontmostApplicationTracker.shared
    @State private var showingAddSheet = false

    private var sortedMappings: [ButtonMapping] {
        store.mappings.sorted { lhs, rhs in
            if lhs.mouseButton != rhs.mouseButton {
                return lhs.mouseButton < rhs.mouseButton
            }
            if lhs.scope.sortRank != rhs.scope.sortRank {
                return lhs.scope.sortRank < rhs.scope.sortRank
            }
            return lhs.scopeLabel.localizedCaseInsensitiveCompare(rhs.scopeLabel) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Mouse Button Mappings")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                Text("Current App: \(appTracker.displayBundleIdentifier)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()

            Divider()

            if store.mappings.isEmpty {
                VStack(spacing: 12) {
                    Text("No mappings configured")
                        .foregroundStyle(.secondary)
                    Text("Click + to add a new mapping")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedMappings) { mapping in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapping.mouseButtonLabel)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text("→ \(mapping.shortcutLabel)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(mapping.scopeLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.remove(mapping)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 360, height: 320)
        .sheet(isPresented: $showingAddSheet) {
            AddMappingView(store: store, recording: recording)
        }
    }
}

struct AddMappingView: View {
    @ObservedObject var store: MappingStore
    @ObservedObject var recording: RecordingState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKeyCode: CGKeyCode = 0x21
    @State private var useCommand = true
    @State private var useShift = false
    @State private var useOption = false
    @State private var useControl = false
    @State private var selectedScopePreset: ScopePreset = .allApplications
    @State private var customBundleIdentifier = ""
    @State private var customAppName = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Mapping")
                .font(.headline)

            // Step 1: Record mouse button
            GroupBox("1. Mouse Button") {
                VStack(spacing: 8) {
                    if let button = recording.lastRecordedButton {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(buttonLabel(button))
                                .font(.system(.body, design: .rounded, weight: .medium))
                        }
                        Button("Re-record") {
                            recording.lastRecordedButton = nil
                            recording.isRecording = true
                        }
                        .font(.caption)
                    } else if recording.isRecording {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Press a mouse button now...")
                                .foregroundStyle(.orange)
                        }
                        Button("Cancel") {
                            recording.isRecording = false
                        }
                        .font(.caption)
                    } else {
                        Button("Record Mouse Button") {
                            recording.isRecording = true
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(8)
            }

            // Step 2: Choose keyboard shortcut
            GroupBox("2. Keyboard Shortcut") {
                VStack(spacing: 8) {
                    Picker("Key", selection: $selectedKeyCode) {
                        ForEach(commonKeys, id: \.code) { key in
                            Text(key.name).tag(key.code)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 12) {
                        Toggle("⌘", isOn: $useCommand)
                        Toggle("⇧", isOn: $useShift)
                        Toggle("⌥", isOn: $useOption)
                        Toggle("⌃", isOn: $useControl)
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(8)
            }

            // Step 3: Scope
            GroupBox("3. Scope") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Application", selection: $selectedScopePreset) {
                        ForEach(ScopePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedScopePreset == .custom {
                        TextField("Bundle ID (e.g. com.apple.Safari)", text: $customBundleIdentifier)
                            .textFieldStyle(.roundedBorder)
                        TextField("App Name (optional)", text: $customAppName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }

            // Preview
            if let button = recording.lastRecordedButton {
                Text("\(buttonLabel(button)) [\(selectedScopeLabel)] → \(previewShortcut)")
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
            }

            // Actions
            HStack {
                Button("Cancel") {
                    recording.isRecording = false
                    recording.lastRecordedButton = nil
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    guard let button = recording.lastRecordedButton, let scope = selectedScope else { return }
                    var flags = CGEventFlags()
                    if useCommand { flags.insert(.maskCommand) }
                    if useShift { flags.insert(.maskShift) }
                    if useOption { flags.insert(.maskAlternate) }
                    if useControl { flags.insert(.maskControl) }
                    store.addOrUpdate(ButtonMapping(mouseButton: button, keyCode: selectedKeyCode, modifiers: flags, scope: scope))
                    recording.lastRecordedButton = nil
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(recording.lastRecordedButton == nil || selectedScope == nil)
            }
        }
        .padding()
        .frame(width: 360)
        .onDisappear {
            recording.isRecording = false
        }
    }

    private var previewShortcut: String {
        var parts: [String] = []
        if useCommand { parts.append("⌘") }
        if useShift { parts.append("⇧") }
        if useOption { parts.append("⌥") }
        if useControl { parts.append("⌃") }
        parts.append(keyCodeName(selectedKeyCode))
        return parts.joined()
    }

    private func buttonLabel(_ button: Int64) -> String {
        switch button {
        case 2: return "Middle Click (Button 3)"
        default: return "Button \(button + 1)"
        }
    }

    private var selectedScope: MappingScope? {
        switch selectedScopePreset {
        case .allApplications, .safari, .googleChrome, .finder, .terminal:
            return selectedScopePreset.scope
        case .custom:
            let bundleIdentifier = customBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleIdentifier.isEmpty else { return nil }
            let appName = customAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            return .app(bundleIdentifier: bundleIdentifier, displayName: appName.isEmpty ? nil : appName)
        }
    }

    private var selectedScopeLabel: String {
        selectedScope?.label ?? "Custom"
    }
}

enum ScopePreset: String, CaseIterable, Identifiable {
    case allApplications
    case safari
    case googleChrome
    case finder
    case terminal
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allApplications: return "All Applications"
        case .safari: return "Safari"
        case .googleChrome: return "Google Chrome"
        case .finder: return "Finder"
        case .terminal: return "Terminal"
        case .custom: return "Custom App..."
        }
    }

    var scope: MappingScope {
        switch self {
        case .allApplications:
            return .global
        case .safari:
            return .app(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        case .googleChrome:
            return .app(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
        case .finder:
            return .app(bundleIdentifier: "com.apple.finder", displayName: "Finder")
        case .terminal:
            return .app(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")
        case .custom:
            return .global
        }
    }
}

// MARK: - Key Code Helpers

struct KeyEntry {
    let code: CGKeyCode
    let name: String
}

let commonKeys: [KeyEntry] = [
    KeyEntry(code: 0x21, name: "["),
    KeyEntry(code: 0x1E, name: "]"),
    KeyEntry(code: 0x00, name: "A"),
    KeyEntry(code: 0x0B, name: "B"),
    KeyEntry(code: 0x08, name: "C"),
    KeyEntry(code: 0x02, name: "D"),
    KeyEntry(code: 0x0E, name: "E"),
    KeyEntry(code: 0x03, name: "F"),
    KeyEntry(code: 0x05, name: "G"),
    KeyEntry(code: 0x04, name: "H"),
    KeyEntry(code: 0x22, name: "I"),
    KeyEntry(code: 0x26, name: "J"),
    KeyEntry(code: 0x28, name: "K"),
    KeyEntry(code: 0x25, name: "L"),
    KeyEntry(code: 0x2E, name: "M"),
    KeyEntry(code: 0x2D, name: "N"),
    KeyEntry(code: 0x1F, name: "O"),
    KeyEntry(code: 0x23, name: "P"),
    KeyEntry(code: 0x0C, name: "Q"),
    KeyEntry(code: 0x0F, name: "R"),
    KeyEntry(code: 0x01, name: "S"),
    KeyEntry(code: 0x11, name: "T"),
    KeyEntry(code: 0x20, name: "U"),
    KeyEntry(code: 0x09, name: "V"),
    KeyEntry(code: 0x0D, name: "W"),
    KeyEntry(code: 0x07, name: "X"),
    KeyEntry(code: 0x10, name: "Y"),
    KeyEntry(code: 0x06, name: "Z"),
    KeyEntry(code: 0x12, name: "1"),
    KeyEntry(code: 0x13, name: "2"),
    KeyEntry(code: 0x14, name: "3"),
    KeyEntry(code: 0x15, name: "4"),
    KeyEntry(code: 0x17, name: "5"),
    KeyEntry(code: 0x16, name: "6"),
    KeyEntry(code: 0x1A, name: "7"),
    KeyEntry(code: 0x1C, name: "8"),
    KeyEntry(code: 0x19, name: "9"),
    KeyEntry(code: 0x1D, name: "0"),
    KeyEntry(code: 0x18, name: "="),
    KeyEntry(code: 0x1B, name: "-"),
    KeyEntry(code: 0x27, name: "'"),
    KeyEntry(code: 0x29, name: ";"),
    KeyEntry(code: 0x2A, name: "\\"),
    KeyEntry(code: 0x2B, name: ","),
    KeyEntry(code: 0x2C, name: "/"),
    KeyEntry(code: 0x2F, name: "."),
    KeyEntry(code: 0x32, name: "`"),
    KeyEntry(code: 0x24, name: "Return"),
    KeyEntry(code: 0x30, name: "Tab"),
    KeyEntry(code: 0x31, name: "Space"),
    KeyEntry(code: 0x33, name: "Delete"),
    KeyEntry(code: 0x35, name: "Escape"),
    KeyEntry(code: 0x7B, name: "←"),
    KeyEntry(code: 0x7C, name: "→"),
    KeyEntry(code: 0x7D, name: "↓"),
    KeyEntry(code: 0x7E, name: "↑"),
    KeyEntry(code: 0x7A, name: "F1"),
    KeyEntry(code: 0x78, name: "F2"),
    KeyEntry(code: 0x63, name: "F3"),
    KeyEntry(code: 0x76, name: "F4"),
    KeyEntry(code: 0x60, name: "F5"),
    KeyEntry(code: 0x61, name: "F6"),
    KeyEntry(code: 0x62, name: "F7"),
    KeyEntry(code: 0x64, name: "F8"),
    KeyEntry(code: 0x65, name: "F9"),
    KeyEntry(code: 0x6D, name: "F10"),
    KeyEntry(code: 0x67, name: "F11"),
    KeyEntry(code: 0x6F, name: "F12"),
]

func keyCodeName(_ code: CGKeyCode) -> String {
    commonKeys.first { $0.code == code }?.name ?? "Key \(code)"
}

// MARK: - App

@main
struct MouseKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("MouseKeys", systemImage: "computermouse") {
            Button("Settings...") {
                appDelegate.showSettings()
            }
            Divider()
            Button("Quit MouseKeys") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = FrontmostApplicationTracker.shared

        let trusted = AXIsProcessTrusted()
        print("[MouseKeys] Accessibility trusted: \(trusted)")
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        let eventMask = CGEventMask(
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("[MouseKeys] Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[MouseKeys] Event tap created and enabled successfully")
    }

    func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MouseKeys Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
