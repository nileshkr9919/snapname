# Snapname

**Screenshots that name themselves — fully on your Mac.**

`Screenshot 2026-10-27 at 3.10.44 PM.png` → `github-pull-request-review-comments.png`

Snapname sits in your menu bar. Every new screenshot is shown to a local vision model (via [Ollama](https://ollama.com)), renamed to what it shows, and given a one-line description that Spotlight indexes. Later, ⌘-Space "review comments" finds it.

- Nothing leaves your Mac. Screenshots often show bank pages, messages and passwords; they're only sent to Ollama on `localhost`.
- Files are only renamed — never edited or deleted. The original name is kept in the `local.snapname.original` extended attribute.
- New screenshots are named automatically. Older ones only when you choose **Name N Existing Screenshots** from the menu.

## Install

Requires macOS 14+, [Ollama](https://ollama.com), and Swift 6 (Xcode 16+ or the Command Line Tools).

```sh
git clone <this repo> && cd snapname
ollama pull gemma4          # any Ollama model with vision works
./build.sh --install        # builds and launches ~/Applications/Snapname.app
```

Click **Allow** when macOS asks for Desktop access, and turn on **Open at Login** in the menu.

## Settings

```sh
defaults write local.snapname model llava        # use another vision model (default gemma4)
defaults write local.snapname folder ~/Pictures  # watch another folder (default: your screenshot location)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Released under the [MIT License](LICENSE).
