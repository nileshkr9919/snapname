import CoreServices
import Foundation

/// Finds screenshots that still have their timestamp name, and renames them.
/// Files are only ever renamed: contents are never touched and nothing is deleted.
enum Renamer {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
    /// Default macOS / iOS screenshot names ("Screenshot 2026-10-27 at 4.53.36 PM.png").
    static let screenshotPrefixes = ["Screenshot ", "Screen Shot "]
    /// Remembers the original name, and marks the file as done so it's never renamed twice.
    static let originalNameAttribute = "local.snapname.original"
    static let commentAttribute = "com.apple.metadata:kMDItemFinderComment"

    static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        if screenshotPrefixes.contains(where: name.hasPrefix) { return true }
        // Spotlight also knows screenshots taken with a non-English system language.
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool else { return false }
        return flag
    }

    static func isRenamed(_ url: URL) -> Bool {
        getxattr(url.path, originalNameAttribute, nil, 0, 0, 0) >= 0
    }

    /// Screenshots in `folder` that haven't been renamed yet, oldest first.
    static func pending(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { isScreenshot($0) && !isRenamed($0) }
            .sorted { creationDate($0) < creationDate($1) }
    }

    static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    /// Turns whatever the model said into a safe file name: "GitHub Log-in: Acme Corp!" → "github-log-in-acme-corp".
    static func sanitize(_ raw: String, maxLength: Int = 60) -> String? {
        let words = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
            .map(String.init)
        var name = ""
        for word in words {
            let next = name.isEmpty ? word : name + "-" + word
            if next.count > maxLength { break }
            name = next
        }
        return name.isEmpty ? nil : name
    }

    /// `folder/name.ext`, or `name-2.ext`, `name-3.ext`… if that's taken.
    static func uniqueURL(in folder: URL, name: String, ext: String, exists: (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.path)
    }) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(name)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Renames `url` and stores the description where Spotlight indexes it. Returns the new location.
    static func rename(_ url: URL, to name: String, description: String) throws -> URL {
        let folder = url.deletingLastPathComponent()
        let target = uniqueURL(in: folder, name: name, ext: url.pathExtension.lowercased())
        try FileManager.default.moveItem(at: url, to: target)
        setAttribute(originalNameAttribute, Data(url.lastPathComponent.utf8), on: target)
        if !description.isEmpty,
           let plist = try? PropertyListSerialization.data(fromPropertyList: description, format: .binary, options: 0) {
            setAttribute(commentAttribute, plist, on: target)
        }
        return target
    }

    private static func setAttribute(_ name: String, _ value: Data, on url: URL) {
        _ = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) }
    }
}
