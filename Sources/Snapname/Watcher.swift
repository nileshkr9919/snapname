import Foundation

/// Calls `onChange` (debounced) whenever files are added to, removed from or renamed in a folder.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func watch(_ folder: URL) {
        stop()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Where macOS saves screenshots (set in the Screenshot app's Options menu), else the Desktop.
    /// `defaults write local.snapname folder <path>` (or `-folder <path>` at launch) overrides it.
    static func screenshotFolder() -> URL {
        if let override = UserDefaults.standard.string(forKey: "folder") {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
