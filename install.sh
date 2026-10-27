#!/bin/zsh
# Snapname installer. Needs nothing preinstalled: it fetches Ollama, a vision model
# and a ready-made Snapname app. Paste this into Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/nileshkr9919/snapname/main/install.sh | zsh
#
# Options (as environment variables or flags):
#   MODEL=gemma3:4b …           use a different Ollama vision model (default gemma4)
#   UPDATE_MODELS=1 …           also download a newer version of the model you already have
#   ./install.sh --from-source  build the app yourself instead of downloading it
#                               (installs Apple's Command Line Tools if needed)
#
# Safe to re-run at any time; it also updates Snapname to the latest release.
set -euo pipefail

# Wrapped in braces so the whole script is read before it runs (safe with curl | zsh).
{
REPO="${SNAPNAME_REPO:-nileshkr9919/snapname}"
RELEASE_URL="${RELEASE_URL:-https://github.com/$REPO/releases/latest/download/Snapname.zip}"
SOURCE_URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
OLLAMA_URL="https://ollama.com/download/Ollama-darwin.zip"
MODEL="${MODEL:-gemma4}"
BUNDLE_ID="${BUNDLE_ID:-local.snapname}"
APPS="$HOME/Applications"
FROM_SOURCE=0
[[ "${1:-}" == "--from-source" ]] && FROM_SOURCE=1

# When run from a checkout (not piped from curl), we can build from the local source.
SRC_DIR=""
if [[ -f "${0:A}" && -f "${0:A:h}/Package.swift" ]]; then
    SRC_DIR="${0:A:h}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { print -P "\n%F{yellow}==>%f %B$1%b"; }
ok()   { print -P "    %F{green}✓%f $1"; }
note() { print -P "    %F{yellow}!%f $1"; }
fail() { print -P "\n%F{red}✗ $1%f"; exit 1; }

# ---------------------------------------------------------------------------
step "Checking your Mac"
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
(( macos_major >= 14 )) || fail "Snapname needs macOS 14 Sonoma or later (you have $(sw_vers -productVersion))."
ok "macOS $(sw_vers -productVersion)"

memory_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
ok "${memory_gb} GB memory"
if [[ "$MODEL" == "gemma4" ]] && (( memory_gb < 16 )); then
    note "gemma4 needs about 10 GB of memory. If naming feels slow, re-run with a"
    note "smaller vision model:  MODEL=gemma3:4b ./install.sh"
fi
free_gb=$(( $(df -k "$HOME" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
(( free_gb >= 12 )) || note "Only ${free_gb} GB of disk space free; the model needs about 10 GB."

# ---------------------------------------------------------------------------
step "Setting up Ollama (runs the AI model on your Mac)"
OLLAMA=""
for candidate in "$(command -v ollama 2>/dev/null || true)" \
                 /Applications/Ollama.app/Contents/Resources/ollama \
                 "$APPS/Ollama.app/Contents/Resources/ollama"; do
    [[ -n "$candidate" && -x "$candidate" ]] && { OLLAMA="$candidate"; break; }
done

if [[ -z "$OLLAMA" ]]; then
    note "Ollama isn't installed yet. Downloading it…"
    curl -fL --progress-bar "$OLLAMA_URL" -o "$WORK/Ollama.zip" || fail "Couldn't download Ollama. Check your internet connection."
    target="/Applications"
    [[ -w "$target" ]] || { target="$APPS"; mkdir -p "$target"; }
    ditto -x -k "$WORK/Ollama.zip" "$target"
    OLLAMA="$target/Ollama.app/Contents/Resources/ollama"
    ok "Installed Ollama to $target"
fi

if ! curl -sf http://localhost:11434/api/version >/dev/null; then
    note "Starting Ollama…"
    open -a Ollama 2>/dev/null || ("$OLLAMA" serve >/dev/null 2>&1 &)
    for _ in {1..60}; do
        curl -sf http://localhost:11434/api/version >/dev/null && break
        sleep 1
    done
    curl -sf http://localhost:11434/api/version >/dev/null ||
        fail "Ollama didn't start. Open the Ollama app from Applications, then run this installer again."
fi
ok "Ollama is running"

step "Downloading the AI model (first time only, can take a while)"
# A model that's already present is kept as-is (re-running shouldn't re-download ~10 GB);
# set UPDATE_MODELS=1 to fetch a newer version.
have_model() { [[ -z "${UPDATE_MODELS:-}" ]] && "$OLLAMA" show "$1" >/dev/null 2>&1 </dev/null; }

have_model "$MODEL" || "$OLLAMA" pull "$MODEL" </dev/null || fail "Couldn't download the $MODEL model."
ok "$MODEL (looks at your screenshots)"

# ---------------------------------------------------------------------------
ensure_command_line_tools() {
    if xcrun --find swift >/dev/null 2>&1; then return; fi
    note "Apple's Command Line Tools are needed to build from source."
    note "A window will open: click Install and wait for it to finish (about 5–15 minutes)."
    xcode-select --install 2>/dev/null || true
    for _ in {1..360}; do
        xcrun --find swift >/dev/null 2>&1 && { ok "Command Line Tools installed"; return; }
        sleep 5
    done
    fail "Command Line Tools didn't finish installing. Run this installer again once they have."
}

install_prebuilt() {
    note "Downloading Snapname…"
    curl -fL --progress-bar "$RELEASE_URL" -o "$WORK/Snapname.zip" || return 1
    ditto -x -k "$WORK/Snapname.zip" "$WORK/app"
    [[ -d "$WORK/app/Snapname.app" ]] || return 1
    pkill -x Snapname 2>/dev/null || true
    mkdir -p "$APPS"
    rm -rf "$APPS/Snapname.app"
    ditto "$WORK/app/Snapname.app" "$APPS/Snapname.app"
    open "$APPS/Snapname.app"
}

install_from_source() {
    ensure_command_line_tools
    local dir="$SRC_DIR"
    if [[ -z "$dir" ]]; then
        note "Downloading the source code…"
        curl -fL --progress-bar "$SOURCE_URL" -o "$WORK/source.tar.gz" || fail "Couldn't download the source code."
        mkdir -p "$WORK/source"
        tar -xzf "$WORK/source.tar.gz" -C "$WORK/source" --strip-components 1
        dir="$WORK/source"
    fi
    swift_major="$(swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -1)"
    (( ${swift_major:-0} >= 6 )) ||
        fail "Swift 6 or later is needed (found ${swift_major:-none}). Update macOS / Command Line Tools in System Settings → Software Update."
    note "Building (about a minute)…"
    BUNDLE_ID="$BUNDLE_ID" "$dir/build.sh" --install
}

step "Installing Snapname"
if (( FROM_SOURCE )) || { [[ -n "$SRC_DIR" ]] && xcrun --find swift >/dev/null 2>&1; }; then
    install_from_source
elif ! install_prebuilt; then
    note "Couldn't download a ready-made app; building it from source instead."
    install_from_source
fi
[[ "$MODEL" != "gemma4" ]] && defaults write "$BUNDLE_ID" model "$MODEL"
ok "Snapname installed in $APPS"

print -P "
%F{green}%BAll set!%b%f Snapname is in your menu bar (the viewfinder icon, top right of the screen).

  • Click %BAllow%b when macOS asks for access to your Desktop.
  • Take a screenshot (%B⌘⇧4%b). A few seconds later it has a real name.
  • Find it later with Spotlight (%B⌘-Space%b) by what's in it.
  • Click the menu bar icon → %BOpen at Login%b so it's always running, and
    %BName Existing Screenshots%b to clean up the ones you already have.

To update later, run the same install command again.
"
}
