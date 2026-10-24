import AppKit

import SwiftUI
import UniformTypeIdentifiers

struct NoteRef: Codable {
    var path: String
    var hidden = false
}

// Stateless on purpose: Command Line Tools lack the SwiftUI macro plugin, so @State won't compile; AppKit owns the state.
struct NoteView: View {
    let url: URL
    let text: String
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 28) // sits in the transparent title bar, which is the drag handle
                .padding(.horizontal, 14)
            ScrollView {
                MarkdownView(blocks: Markdown.parse(text))
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .contextMenu {
            Button("Открыть в Obsidian") { NSWorkspace.shared.open(Markdown.obsidianURL("path", url.path)) }
            Button("Скрыть", action: onHide)
        }
    }
}

/// One folder level of the note tree; filled by the delegate when opened.
final class FolderMenu: NSMenu {
    let url: URL

    init(_ url: URL, delegate: NSMenuDelegate) {
        self.url = url
        super.init(title: url.lastPathComponent)
        self.delegate = delegate
        addItem(withTitle: "…", action: nil, keyEquivalent: "") // placeholder so the parent shows a submenu arrow
    }

    required init(coder: NSCoder) { fatalError("unused") }
}

@MainActor
final class AppDelegate:NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notes: [NoteRef] = []
    private var panels: [String: (panel: NSPanel, timer: Timer)] = [:]
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = UserDefaults.standard.data(forKey: "notes"),
           let saved = try? JSONDecoder().decode([NoteRef].self, from: data) {
            notes = saved
        }
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "MD Widgets")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        sync()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let folder = menu as? FolderMenu { return fillTree(folder) }
        if let vault = UserDefaults.standard.string(forKey: "vault") {
            let item = menu.addItem(withTitle: name(vault), action: nil, keyEquivalent: "")
            setIcon(item, "folder")
            item.submenu = FolderMenu(URL(fileURLWithPath: vault), delegate: self)
            add(menu, "Сменить папку…", #selector(chooseVault))
        } else {
            add(menu, "Выбрать папку заметок…", #selector(chooseVault))
        }
        add(menu, "Добавить файл…", #selector(addNotes), key: "n")
        if !notes.isEmpty { menu.addItem(.separator()) }
        for (i, note) in notes.enumerated() {
            let item = NSMenuItem(title: name(note.path), action: nil, keyEquivalent: "")
            item.state = note.hidden ? .off : .on
            let sub = NSMenu()
            add(sub, note.hidden ? "Показать" : "Скрыть", #selector(toggle(_:)), tag: i)
            add(sub, "Открыть в Obsidian", #selector(openInObsidian(_:)), tag: i)
            sub.addItem(.separator())
            add(sub, "Удалить из виджетов", #selector(remove(_:)), tag: i)
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add(menu, "Выйти", #selector(NSApplication.terminate(_:)), key: "q").target = NSApp
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", tag: Int = 0) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    @objc private func addNotes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.message = "Выберите заметки Obsidian"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let i = notes.firstIndex(where: { $0.path == url.path }) {
                notes[i].hidden = false
            } else {
                notes.append(NoteRef(path: url.path))
            }
        }
        save()
    }

    // Built lazily per folder on open, so large vaults don't get scanned up front.
    private func fillTree(_ menu: FolderMenu) {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: menu.url, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? [] // hides .obsidian, .trash
        let items = entries
            .map { (url: $0, isDir: (try? $0.resourceValues(forKeys: Set(keys)))?.isDirectory == true) }
            .filter { $0.isDir || $0.url.pathExtension.lowercased() == "md" }
            .sorted { $0.isDir != $1.isDir ? $0.isDir : $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        for entry in items {
            let item = NSMenuItem(title: name(entry.url.path), action: nil, keyEquivalent: "")
            if entry.isDir {
                item.title = entry.url.lastPathComponent
                setIcon(item, "folder")
                item.submenu = FolderMenu(entry.url, delegate: self)
            } else {
                setIcon(item, "doc.text")
                item.action = #selector(toggleFile(_:))
                item.target = self
                item.representedObject = entry.url.path
                item.state = notes.contains { $0.path == entry.url.path && !$0.hidden } ? .on : .off
            }
            menu.addItem(item)
        }
        if items.isEmpty { menu.addItem(withTitle: "Нет заметок", action: nil, keyEquivalent: "").isEnabled = false }
    }

    @objc private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Выберите папку с заметками (хранилище Obsidian)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: "vault")
    }

    @objc private func toggleFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        if let i = notes.firstIndex(where: { $0.path == path }) {
            notes[i].hidden.toggle()
        } else {
            notes.append(NoteRef(path: path))
        }
        save()
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        notes[sender.tag].hidden.toggle()
        save()
    }

    @objc private func openInObsidian(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(Markdown.obsidianURL("path", notes[sender.tag].path))
    }

    @objc private func remove(_ sender: NSMenuItem) {
        NSWindow.removeFrame(usingName: frameName(notes.remove(at: sender.tag).path))
        save()
    }

    private func hide(_ path: String) {
        guard let i = notes.firstIndex(where: { $0.path == path }) else { return }
        notes[i].hidden = true
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(notes), forKey: "notes")
        sync()
    }

    private func sync() {
        let visible = Set(notes.filter { !$0.hidden }.map(\.path))
        for (path, widget) in panels where !visible.contains(path) {
            widget.timer.invalidate()
            widget.panel.close()
            panels[path] = nil
        }
        for path in visible where panels[path] == nil {
            panels[path] = makePanel(path)
        }
    }

    private func makePanel(_ path: String) -> (panel: NSPanel, timer: Timer) {
        let offset = CGFloat(panels.count * 30)
        let panel = NSPanel(
            contentRect: NSRect(x: 120 + offset, y: 400 - offset, width: 300, height: 360),
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 180, height: 120)
        // Above desktop icons, below regular app windows; visible on every Space.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        let url = URL(fileURLWithPath: path)
        let onHide: () -> Void = { [weak self] in self?.hide(path) }
        let host = NSHostingView(rootView: NoteView(url: url, text: "", onHide: onHide))
        host.sizingOptions = []
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect

        panel.setFrameAutosaveName(frameName(path))
        panel.orderFrontRegardless()

        // Polling instead of a file watcher: Obsidian saves atomically, which breaks vnode watchers.
        var modDate: Date?
        let reload: () -> Void = {
            let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            guard date != modDate || date == nil else { return }
            modDate = date
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "> Файл не найден: \(path)"
            host.rootView = NoteView(url: url, text: text, onHide: onHide)
        }
        reload()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { reload() } }
        return (panel, timer)
    }

    private func setIcon(_ item: NSMenuItem, _ symbol: String) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        // macOS 27 hides menu item images unless asked to show them.
        if #available(macOS 27, *) { item.preferredImageVisibility = .visible }
    }

    private func frameName(_ path: String) -> String { "note:" + path }
    private func name(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
}

if CommandLine.arguments.contains("--selftest") {
    Markdown.selfTest()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
