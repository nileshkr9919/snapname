import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private lazy var watcher = FolderWatcher { [weak self] in self?.folderChanged() }
    private var folder = FolderWatcher.screenshotFolder()
    /// Screenshots taken after launch are named automatically; older ones only when asked.
    private let launchDate = Date()

    private var queue: [URL] = []
    private var isRunning = false
    private var done = 0
    private var total = 0
    private var failed: Set<URL> = []
    private var lastRenamed: URL?
    private var problem: String?
    private var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: "paused") }
        set { UserDefaults.standard.set(newValue, forKey: "paused") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        watcher.watch(folder)
        Namer.warmUp()
        folderChanged()
        // The screenshot location can change in the Screenshot app's Options menu.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screencapture.prefsChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFolder() }
        }
    }

    // MARK: - Naming

    private func folderChanged() {
        refreshFolder()
        let fresh = Renamer.pending(in: folder).filter { Renamer.creationDate($0) >= launchDate.addingTimeInterval(-5) }
        enqueue(fresh)
    }

    private func refreshFolder() {
        let current = FolderWatcher.screenshotFolder()
        guard current != folder else { return }
        folder = current
        watcher.watch(folder)
    }

    @objc private func nameExisting() {
        enqueue(Renamer.pending(in: folder))
    }

    private func enqueue(_ urls: [URL]) {
        let new = urls.filter { !queue.contains($0) && !failed.contains($0) }
        guard !new.isEmpty else { return }
        if !isRunning { done = 0; total = 0 }
        queue += new
        total += new.count
        run()
    }

    private func run() {
        guard !isRunning, !isPaused, !queue.isEmpty else { return }
        isRunning = true
        updateIcon()
        Task {
            while !isPaused, !queue.isEmpty {
                let url = queue.removeFirst()
                guard FileManager.default.fileExists(atPath: url.path), !Renamer.isRenamed(url) else {
                    done += 1
                    continue
                }
                do {
                    let result = try await Namer.describe(url)
                    problem = nil
                    if let name = Renamer.sanitize(result.name) {
                        lastRenamed = try Renamer.rename(url, to: name, description: result.description)
                    } else {
                        failed.insert(url)
                    }
                    done += 1
                } catch NamerError.notRunning {
                    // Try again on the next screenshot, once Ollama is back.
                    problem = NamerError.notRunning.errorDescription
                    queue.insert(url, at: 0)
                    break
                } catch let error as NamerError {
                    problem = error.errorDescription
                    if case .modelMissing = error {
                        queue.insert(url, at: 0)
                        break
                    }
                    failed.insert(url)
                    done += 1
                } catch {
                    failed.insert(url)
                    done += 1
                }
            }
            isRunning = false
            updateIcon()
        }
    }

    // MARK: - Menu

    private func updateIcon() {
        let symbol = problem != nil ? "exclamationmark.triangle"
            : isPaused ? "pause.circle"
            : isRunning ? "text.viewfinder"
            : "camera.viewfinder"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Snapname")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if let problem {
            status = problem
        } else if isPaused {
            status = "Paused"
        } else if isRunning {
            status = "Naming \(min(done + 1, total)) of \(total)…"
        } else {
            status = "Watching \(FileManager.default.displayName(atPath: folder.path))"
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false

        if let lastRenamed {
            let item = menu.addItem(withTitle: "Show “\(lastRenamed.lastPathComponent)”",
                                    action: #selector(revealLast), keyEquivalent: "")
            item.target = self
        }
        menu.addItem(.separator())

        let pending = Renamer.pending(in: folder).filter { !queue.contains($0) && !failed.contains($0) }.count
        let existing = menu.addItem(
            withTitle: pending == 0 ? "No Unnamed Screenshots" : "Name \(pending) Existing Screenshot\(pending == 1 ? "" : "s")",
            action: pending == 0 ? nil : #selector(nameExisting), keyEquivalent: "")
        existing.target = self
        existing.isEnabled = pending > 0

        let pause = menu.addItem(withTitle: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = isPaused ? .on : .off

        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snapname", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func revealLast() {
        guard let lastRenamed else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRenamed])
    }

    @objc private func togglePause() {
        isPaused.toggle()
        updateIcon()
        if !isPaused { folderChanged(); run() }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
