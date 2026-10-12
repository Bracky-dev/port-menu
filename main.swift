import SwiftUI
import AppKit

struct Listener: Identifiable, Hashable {
    let pid: Int32
    let command: String
    let port: Int
    let address: String
    var id: String { "\(pid)-\(port)" }
}

enum PortScanner {
    // Lists TCP sockets in LISTEN state using lsof's machine-readable output.
    static func scan() -> [Listener] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var results: [String: Listener] = [:]
        var pid: Int32 = 0
        var cmd = ""
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": cmd = value
            case "n":
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let addr = String(value[..<colon])
                let l = Listener(pid: pid, command: cmd, port: port, address: addr)
                results[l.id] = results[l.id] ?? l
            default: break
            }
        }
        return results.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }
}

@MainActor
final class PortStore: ObservableObject {
    @Published var listeners: [Listener] = []
    @Published var filter = ""
    @Published var lastError: String?
    private var timer: Timer?
    private var viewers = 0

    var filtered: [Listener] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return listeners }
        return listeners.filter { "\($0.port)".contains(q) || $0.command.lowercased().contains(q) }
    }

    func refresh() {
        Task.detached {
            let found = PortScanner.scan()
            await MainActor.run { self.listeners = found }
        }
    }

    // Window and menu bar popover can both be visible; poll while either is.
    func startPolling() {
        viewers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { timer?.invalidate(); timer = nil }
    }

    func kill(_ l: Listener, force: Bool) {
        if Darwin.kill(l.pid, force ? SIGKILL : SIGTERM) != 0 {
            lastError = "Couldn't stop \(l.command) (\(l.pid)): \(String(cString: strerror(errno)))"
        } else {
            lastError = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func open(_ l: Listener) {
        if let url = URL(string: "http://localhost:\(l.port)") { NSWorkspace.shared.open(url) }
    }
}

struct ContentView: View {
    @ObservedObject var store: PortStore
    var inWindow = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Listening ports").font(.headline)
                Spacer()
                Text("\(store.listeners.count)").foregroundStyle(.secondary)
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
            }
            TextField("Filter by port or process", text: $store.filter)
                .textFieldStyle(.roundedBorder)

            if store.filtered.isEmpty {
                Text(store.listeners.isEmpty ? "Nothing is listening." : "No matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.filtered) { l in Row(listener: l, store: store) }
                    }
                }
                .frame(maxHeight: inWindow ? .infinity : 360)
            }

            if inWindow { Spacer(minLength: 0) }
            if let err = store.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Text("⌥-click ✕ to force kill").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !inWindow {
                    Button("Open Window") { openWindow(id: "main"); NSApp.activate() }
                        .buttonStyle(.borderless)
                }
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(minWidth: inWindow ? 420 : 340, maxWidth: inWindow ? .infinity : 340,
               minHeight: inWindow ? 300 : nil, maxHeight: inWindow ? .infinity : nil)
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
    }
}

struct Row: View {
    let listener: Listener
    let store: PortStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(":\(listener.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(listener.command).lineLimit(1)
                Text("pid \(listener.pid) · \(listener.address)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { store.open(listener) } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless).help("Open http://localhost:\(listener.port)")
            Button {
                store.kill(listener, force: NSEvent.modifierFlags.contains(.option))
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                .buttonStyle(.borderless).help("Stop process (⌥ to force)")
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
        .onHover { hovering = $0 }
    }
}

@main
struct PortMenuApp: App {
    @StateObject private var store = PortStore()

    var body: some Scene {
        Window("PortMenu", id: "main") {
            ContentView(store: store, inWindow: true)
        }
        .defaultSize(width: 480, height: 520)

        MenuBarExtra {
            ContentView(store: store)
        } label: {
            Image(systemName: "network")
        }
        .menuBarExtraStyle(.window)
    }
}
