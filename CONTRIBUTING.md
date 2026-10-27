# Contributing to Snapname

Thanks for helping! Snapname is a small, local-first macOS menu bar app. Two principles guide every change:

1. **Local and free.** No cloud services, accounts, telemetry or paid APIs. The only network traffic is to Ollama on `localhost`. Screenshots are private by nature.
2. **Never lose a file.** Snapname only renames. It never edits, overwrites or deletes a screenshot, and always records the original name. Anything touching files needs a test.

## Getting started
```sh
git clone <this repo> && cd <repo>
ollama pull gemma4
swift test             # unit tests (no Ollama needed)
./build.sh --install   # build, install to ~/Applications and relaunch
```
Requires macOS 14+ and Swift 6 (Xcode 16+ or the Command Line Tools).

To try changes without touching your Desktop, point the app at a test folder:
```sh
build/Snapname.app/Contents/MacOS/Snapname -folder ~/snapname-test
```

## Code map
| File | What it does |
|---|---|
| `AppDelegate.swift` | Menu bar item and menu, naming queue, pause, open at login |
| `Watcher.swift` | Watches the screenshot folder; finds where macOS saves screenshots |
| `Namer.swift` | Prompt and request to the local Ollama vision model |
| `Renamer.swift` | Screenshot detection, name cleanup, safe rename, Spotlight description |
| `install.sh` | One-line installer: Ollama, the model, and the latest release (or a source build) |
| `scripts/make-icon.swift` | Draws the app icon (`Resources/AppIcon.icns` and `icon.png`) |

### How a screenshot gets named
1. The folder watcher fires; files that look like screenshots (default macOS/iOS name, or Spotlight's `kMDItemIsScreenCapture`) and lack the `local.snapname.original` attribute are queued.
2. The image goes to Ollama, which replies with JSON: a hyphenated `name` and a one-sentence `description`.
3. The name is cleaned to `a-z0-9-` (max 60 characters), made unique (`-2`, `-3`…), and the file is renamed.
4. The original name goes in `local.snapname.original`; the description goes in `com.apple.metadata:kMDItemFinderComment`, which Spotlight indexes.

## Pull requests
- Keep PRs focused; describe the user-visible change.
- `swift test` must pass (CI runs it on every PR).
- If you change the prompt, include a few example before/after names (describe the screenshots, don't attach private ones).
- Match the existing style: small types, comments only where the *why* isn't obvious.
