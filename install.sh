#!/bin/bash
# Installs the IT Snow extension (.mcpb) into Claude Desktop (macOS).
#   curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash
# For an AI agent or a script (no terminal: never prompts, does not wait):
#   curl -fsSL <same url> | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --no-wait
#
# Environment overrides (mainly for tests):
#   IT_SNOW_HOME             download folder (--dir wins; default ~/.it-snow-server)
#   IT_SNOW_INSTALL_BASE     base URL for the download files (default: the GitHub Pages site)
#   IT_SNOW_INSTALL_TTY      where questions are read from (default /dev/tty; /dev/null = no terminal)
#   IT_SNOW_CLAUDE_APP       path to Claude.app (default /Applications/Claude.app)
#   IT_SNOW_CHROME_APP       path to Google Chrome.app (default /Applications/Google Chrome.app)
#   IT_SNOW_INSTALL_NO_OPEN  1 = don't open Claude Desktop, just say what would happen
#   IT_SNOW_INSTALL_WAIT_SECS  how long to wait for the extension to appear (default 600; 0 with --no-wait)
set -euo pipefail

SITE_BASE_DEFAULT="https://wpp-jamie-mills.github.io/it-snow-site"

EXTENSION_NAME="it-snow"
MIN_CLAUDE_VERSION="2.7032.0"
CLAUDE_BUNDLE_ID="com.anthropic.claudefordesktop"

if [[ -t 1 && -t 2 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi
print_error() { printf '%b✗ %s%b\n' "$RED" "$1" "$NC" >&2; }
print_success() { printf '%b✓ %s%b\n' "$GREEN" "$1" "$NC"; }
print_warning() { printf '%b⚠ %s%b\n' "$YELLOW" "$1" "$NC"; }
print_step() { printf '%b→ %s%b\n' "$BLUE" "$1" "$NC"; }
die() { print_error "$1"; exit 1; }

usage() {
  cat <<'EOF'
IT Snow installer (macOS, Claude Desktop)

Usage:
  curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash
  ... | bash -s -- --status
  ... | bash -s -- --uninstall --yes

Options:
  --dir <path>   Folder for the downloaded extension (default: ~/.it-snow-server).
  --status       Print what is installed and what is left to do. Changes nothing.
  --no-wait      Open Claude Desktop's install dialog and exit without waiting.
  --uninstall    Remove the downloaded copy (the extension itself is removed in Claude Desktop).
  --yes          Allow --uninstall without a terminal.
  --help         This text.
EOF
}

# ---------------------------------------------------------------- arguments
DIR_OVERRIDE=""
MODE="install"
WAIT_OVERRIDE=""
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR_OVERRIDE="${2:-}"; [ -n "$DIR_OVERRIDE" ] || die "--dir needs a path"; shift 2 ;;
    --status) MODE="status"; shift ;;
    --uninstall) MODE="uninstall"; shift ;;
    --no-wait) WAIT_OVERRIDE="0"; shift ;;
    --yes) YES=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

HOME_DIR="${DIR_OVERRIDE:-${IT_SNOW_HOME:-$HOME/.it-snow-server}}"
SITE_BASE="${IT_SNOW_INSTALL_BASE:-$SITE_BASE_DEFAULT}"
SITE_BASE="${SITE_BASE%/}"
TTY_PATH="${IT_SNOW_INSTALL_TTY:-/dev/tty}"
CLAUDE_APP="${IT_SNOW_CLAUDE_APP:-/Applications/Claude.app}"
CHROME_APP="${IT_SNOW_CHROME_APP:-/Applications/Google Chrome.app}"
WAIT_SECS="${WAIT_OVERRIDE:-${IT_SNOW_INSTALL_WAIT_SECS:-600}}"
if [ "${IT_SNOW_INSTALL_NO_OPEN:-}" = "1" ] && [ -z "$WAIT_OVERRIDE" ]; then WAIT_SECS=0; fi
BUNDLE="$HOME_DIR/latest.mcpb"
INSTALLED_FILE="$HOME_DIR/latest.version"

can_answer() { [[ "$TTY_PATH" != "/dev/null" ]] && { : <"$TTY_PATH"; } 2>/dev/null; }
ask_yes_no() {
  can_answer || return 1
  printf '%s [y/N] ' "$1" >"$TTY_PATH"
  local answer
  read -r answer <"$TTY_PATH" || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

version_ge() { # version_ge A B -> A >= B
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ] && [ "$1" != "" ]
}

claude_version() {
  [ -d "$CLAUDE_APP" ] || return 1
  /usr/bin/defaults read "$CLAUDE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

extension_state() { # prints "<version> <enabled|disabled>" or nothing
  local file="$HOME/Library/Application Support/Claude/extensions-installations.json"
  [ -f "$file" ] || return 1
  /usr/bin/python3 - "$file" "$EXTENSION_NAME" <<'PY' 2>/dev/null || return 1
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
for key, value in (data.get("extensions") or {}).items():
    if str(key).endswith("." + sys.argv[2]):
        version = (value or {}).get("version")
        if version:
            print(version)
            sys.exit(0)
sys.exit(1)
PY
}

extension_enabled() {
  local file
  file="$(ls "$HOME/Library/Application Support/Claude/Claude Extensions Settings/"*.it-snow.json 2>/dev/null | head -n1)"
  [ -n "$file" ] || return 1
  /usr/bin/python3 - "$file" "$EXTENSION_NAME" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
print("enabled" if data.get("isEnabled") else "disabled")
PY
}

chrome_present() { [ -x "$CHROME_APP/Contents/MacOS/Google Chrome" ]; }

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else sha256sum "$1" | awk '{print $1}'; fi
}

downloaded_version() { [ -f "$INSTALLED_FILE" ] && tr -d '[:space:]' <"$INSTALLED_FILE"; }

# ---------------------------------------------------------------- status
print_status() {
  local dl ext enabled claude chrome
  dl="$(downloaded_version || true)"
  ext="$(extension_state || true)"
  enabled="$(extension_enabled || true)"
  claude="$(claude_version || true)"
  chrome="missing"; chrome_present && chrome="present"

  printf 'Downloaded:  %s\n' "${dl:-nothing}"
  printf 'Chrome:      %s\n' "$chrome"
  printf 'Claude:      %s\n' "${claude:-not found}"
  if [ -n "$ext" ]; then
    printf 'Extension:   %s (%s)\n' "$ext" "${enabled:-state unknown}"
  else
    printf 'Extension:   not installed\n'
  fi
  if [ -f "$HOME/Library/Application Support/it-snow/daemon.json" ]; then
    printf 'Session:     Chrome profile present\n'
  else
    printf 'Session:     no profile yet (sign in from the chat)\n'
  fi

  if [ "$chrome" = "missing" ]; then
    printf 'Next:        install Google Chrome, then run this again\n'
  elif [ -z "$ext" ]; then
    printf 'Next:        run the install command and click Install in Claude Desktop\n'
  elif [ "$ext" != "${dl:-$ext}" ]; then
    printf 'Next:        run this installer to update to %s\n' "${dl:-?}"
  elif [ "$enabled" != "enabled" ]; then
    printf 'Next:        switch the extension on in Claude Desktop → Settings → Extensions\n'
  else
    printf 'Ready:       yes — ask Claude "how many open incidents do I have?"\n'
  fi
}

# ---------------------------------------------------------------- uninstall
if [ "$MODE" = "uninstall" ]; then
  if [ ! -d "$HOME_DIR" ]; then
    print_warning "Nothing to remove: $HOME_DIR does not exist."
    exit 0
  fi
  if [ "$YES" -ne 1 ] && ! ask_yes_no "Remove $HOME_DIR?"; then
    die "Refusing to remove $HOME_DIR without --yes (and there is no terminal to ask)."
  fi
  rm -rf "$HOME_DIR"
  print_success "Removed $HOME_DIR."
  print_warning "The extension itself is still installed: remove it in Claude Desktop → Settings → Extensions."
  exit 0
fi

if [ "$MODE" = "status" ]; then
  print_status
  exit 0
fi

# ---------------------------------------------------------------- preflight
print_step "Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || die "IT Snow is macOS only."
chrome_present || die "Google Chrome is required and was not found at $CHROME_APP. Install it from https://www.google.com/chrome/ and run this again."
print_success "Google Chrome found"

if [ ! -d "$CLAUDE_APP" ]; then
  die "Claude Desktop is not installed at $CLAUDE_APP. Install it from https://claude.ai/download and run this again."
fi
claude="$(claude_version || true)"
if [ -z "$claude" ]; then
  print_warning "Couldn't read Claude Desktop's version; the extension needs $MIN_CLAUDE_VERSION or later."
elif ! version_ge "$claude" "$MIN_CLAUDE_VERSION"; then
  die "Claude Desktop $claude is too old: the extension needs $MIN_CLAUDE_VERSION or later. Update Claude Desktop, then run this again."
else
  print_success "Claude Desktop $claude"
fi

# ---------------------------------------------------------------- download
mkdir -p "$HOME_DIR"
print_step "Downloading the latest extension"
curl -fsSL "$SITE_BASE/latest.version" -o "$HOME_DIR/latest.version.tmp" ||
  die "Couldn't download latest.version from $SITE_BASE."
VERSION="$(tr -d '[:space:]' <"$HOME_DIR/latest.version.tmp")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "The site's latest.version isn't a release version ($VERSION)."

curl -fsSL "$SITE_BASE/latest.mcpb" -o "$BUNDLE.tmp" || die "Couldn't download latest.mcpb from $SITE_BASE."
curl -fsSL "$SITE_BASE/latest.mcpb.sha256" -o "$HOME_DIR/latest.mcpb.sha256.tmp" ||
  die "Couldn't download the checksum from $SITE_BASE."

EXPECTED="$(awk 'NR == 1 { print $1 }' "$HOME_DIR/latest.mcpb.sha256.tmp" | tr '[:upper:]' '[:lower:]')"
ACTUAL="$(sha256_of "$BUNDLE.tmp")"
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  rm -f "$BUNDLE.tmp" "$HOME_DIR/latest.version.tmp" "$HOME_DIR/latest.mcpb.sha256.tmp"
  die "Checksum mismatch — nothing was installed. The download did not match $SITE_BASE/latest.mcpb.sha256."
fi
mv "$BUNDLE.tmp" "$BUNDLE"
mv "$HOME_DIR/latest.version.tmp" "$INSTALLED_FILE"
mv "$HOME_DIR/latest.mcpb.sha256.tmp" "$HOME_DIR/latest.mcpb.sha256"
print_success "Downloaded $VERSION (SHA-256 verified)"

current="$(extension_state || true)"
if [ "$current" = "$VERSION" ] && [ "$(extension_enabled || true)" = "enabled" ]; then
  print_success "Already up to date and running: $VERSION"
  printf 'Ask Claude "how many open incidents do I have?" in a new chat.\n'
  exit 0
fi

# ---------------------------------------------------------------- install
if [ "${IT_SNOW_INSTALL_NO_OPEN:-}" = "1" ]; then
  print_warning "Would open Claude Desktop's install dialog for $BUNDLE (IT_SNOW_INSTALL_NO_OPEN=1)."
else
  print_step "Opening Claude Desktop's install dialog"
  /usr/bin/open -b "$CLAUDE_BUNDLE_ID" "$BUNDLE" || {
    print_warning "Couldn't open Claude Desktop. Open $BUNDLE yourself to install it."
    exit 1
  }
fi

printf '\nClick Install in Claude Desktop, then come back here.\n'
if [ "$WAIT_SECS" = "0" ]; then
  printf 'Then start a new chat and ask "how many open incidents do I have?".\n'
  exit 0
fi

printf 'Waiting for Claude Desktop to install %s' "$VERSION"
elapsed=0
while [ "$elapsed" -lt "$WAIT_SECS" ]; do
  now_version="$(extension_state || true)"
  if [ "$now_version" = "$VERSION" ]; then
    printf '\n'
    print_success "Installed $VERSION"
    if [ "$(extension_enabled || true)" = "disabled" ]; then
      print_warning "It is switched off: turn it on in Claude Desktop → Settings → Extensions."
    fi
    printf 'Start a new chat and ask "how many open incidents do I have?" — the first tool opens Chrome for Okta.\n'
    exit 0
  fi
  sleep 2
  elapsed=$((elapsed + 2))
  printf '.'
done

printf '\n'
print_warning "Claude Desktop hasn't listed $VERSION yet. Finish the Install dialog, then run this again with --status."
exit 1
