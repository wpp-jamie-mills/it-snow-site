#!/bin/bash
# Installs IT Snow into Claude Desktop (macOS): the extension (.mcpb), or, with --entry, the same release as a
# Claude Desktop mcpServers entry, for where the organisation blocks the extension.
#   curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash
#   curl -fsSL <same url> | bash -s -- --entry
# For an AI agent or a script (no terminal: it never asks, so whatever needs an answer needs its flag; it never
# quits or restarts Claude Desktop):
#   curl -fsSL <same url> | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --status
#   curl -fsSL <same url> | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --no-wait
#   curl -fsSL <same url> | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --entry --yes [--install-bun] [--no-wait]
#   curl -fsSL <same url> | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --entry --uninstall --yes
#
# Environment overrides (mainly for tests):
#   IT_SNOW_HOME             download folder (--dir wins; default ~/.it-snow-server; ~ and relative paths allowed)
#   IT_SNOW_INSTALL_BASE     base URL for the download files (default: the GitHub Pages site)
#   IT_SNOW_INSTALL_TTY      where questions are read from (default /dev/tty; /dev/null = no terminal)
#   IT_SNOW_CLAUDE_APP       path to Claude.app (default /Applications/Claude.app)
#   IT_SNOW_CHROME_APP       path to Google Chrome.app (default /Applications/Google Chrome.app)
#   IT_SNOW_INSTALL_NO_OPEN  1 = don't open Claude Desktop or its install dialog, just say what would happen
#   IT_SNOW_INSTALL_WAIT_SECS  how long to wait for the extension to appear, or the entry to start (default 600;
#                            0 with --no-wait, and 0 by default with IT_SNOW_INSTALL_NO_OPEN=1)
#   IT_SNOW_INSTALL_SETTLE_SECS  once Claude Desktop lists the extension, how long to keep checking that the
#                            organisation hasn't blocked it (default 10)
#   IT_SNOW_DATA_DIR         the entry's data folder, read as the server reads it (src/settings.ts normaliseDataDir):
#                            ~, ~/… and ${HOME} expanded, it must be absolute. Without it: the folder Claude Desktop's
#                            it-snow entry names, else ~/Library/Application Support/it-snow
#   IT_SNOW_CLAUDE_CONFIG    Claude Desktop's config file (default
#                            ~/Library/Application Support/Claude/claude_desktop_config.json)
#   IT_SNOW_CLAUDE_LOGS      Claude Desktop's log folder (default ~/Library/Logs/Claude)
#   IT_SNOW_BUN_CANDIDATES   where to look for Bun, separated by colons (default: bun on PATH, then BUN_CANDIDATES)
#   IT_SNOW_BREW             Homebrew's brew, or none (default: /opt/homebrew/bin/brew, on Apple silicon only)
#   IT_SNOW_OPEN / IT_SNOW_PGREP  the open and pgrep to use (default /usr/bin/open and /usr/bin/pgrep). Tests and CI
#                            point them at stand-ins, so they never see or open the real Claude Desktop.
#   IT_SNOW_INSTALLER_TEST   1 = honour the test seams below; without it they are ignored. Never set it for real.
#   IT_SNOW_BUN_BASE / IT_SNOW_BUN_SHA256 / IT_SNOW_BUN_ARCH  Bun's download address, the SHA-256 it must have
#                            and its asset (aarch64, x64 or x64-baseline) (need IT_SNOW_INSTALLER_TEST=1)
#   IT_SNOW_ARM_BREW         where Apple silicon's Homebrew is (default /opt/homebrew/bin/brew; needs
#                            IT_SNOW_INSTALLER_TEST=1)
set -euo pipefail

SITE_BASE_DEFAULT="https://wpp-jamie-mills.github.io/it-snow-site"

EXTENSION_NAME="it-snow"
APP_TITLE="IT Snow"
MIN_CLAUDE_VERSION="2.7032.0"
CLAUDE_BUNDLE_ID="com.anthropic.claudefordesktop"

# ---- The mcpServers entry (--entry) ----
# Keep equal to src/run-mode.ts ENTRY_NAME, LAUNCHER_NAME and MIN_BUN (a test checks).
ENTRY_NAME="it-snow"
LAUNCHER_NAME="it-snow-mcp"
BUN_MIN="1.3.0"
# The Bun the download route installs; keep equal to scripts/bun-pins.mjs and CI (a test checks). Run
# node scripts/bun-pins.mjs <version> to print new values.
BUN_VERSION="1.4.4"
BUN_SHA256_AARCH64="c240d7f0ccb90c263a849fcdb09b7ee62630d921348ed6aafda86b9d577bc510"
BUN_SHA256_X64="50a3491f73abc2fe81673171a85762d3bc2cc1680ccecadd983de99adf77977e"
BUN_SHA256_X64_BASELINE="d4a155adfbfd09155eb3ba05c9e3a544f39297d7a68616d3c7759f67ab5c47dc"
# Where the entry's launcher looks for Bun when it isn't on PATH, in order ($HOME is expanded). Keep equal to
# src/launcher.ts BUN_CANDIDATES (a test checks).
# shellcheck disable=SC2016
BUN_CANDIDATES='$HOME/.bun/bin/bun:/opt/homebrew/bin/bun:/usr/local/bin/bun'
ENTRY_SYSTEM_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# The only ways this installer looks at or opens Claude Desktop: absolute, so nothing on PATH stands in for them.
OPEN_BIN="${IT_SNOW_OPEN:-/usr/bin/open}"
PGREP_BIN="${IT_SNOW_PGREP:-/usr/bin/pgrep}"
# What an installed release holds (src/install-release.ts REQUIRED_FILES, and the installer itself; a test checks).
RELEASE_FILES="manifest.json package.json dist/index.js dist/install-release.js node_modules/playwright-core node_modules/@modelcontextprotocol/sdk"

# Colour only on a terminal, so agent and CI logs stay plain.
if [[ -t 1 && -t 2 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi
print_error() { printf '%b✗ %s%b\n' "$RED" "$1" "$NC" >&2; }
print_success() { printf '%b✓ %s%b\n' "$GREEN" "$1" "$NC"; }
print_warning() { printf '%b⚠ %s%b\n' "$YELLOW" "$1" "$NC"; }
print_step() { printf '%b→ %s%b\n' "$BLUE" "$1" "$NC"; }
die() {
  print_error "$1"
  exit 1
}
# A refusal: $1 says why and what to do; $2, if given, is the command to run again (with the missing flag).
refuse() {
  print_error "$1"
  if [[ -n "${2:-}" ]]; then printf '  %s\n' "$2" >&2; fi
  exit 1
}

usage() {
  cat <<'EOF'
IT Snow installer (macOS, Claude Desktop)

Usage:
  curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash
  curl -fsSL <same url> | bash -s -- --entry
  curl -fsSL <same url> | bash -s -- --status

Options:
  --dir <path>   Folder for the downloaded release (default: ~/.it-snow-server).
  --status       Print what is installed, then "Ready: yes" or one "Next:" line. Changes nothing.
  --no-wait      Exit once the steps are done instead of waiting for Claude Desktop. Exit 0 then means the
                 installer finished its steps, not that Claude Desktop runs IT Snow (check with --status).
  --uninstall    Remove the downloaded copy (the extension itself is removed in Claude Desktop).
  --yes          Allow --uninstall without a terminal; with --entry, the go-ahead to change Claude Desktop's
                 config, and only that.
  --help         This text.

Where the organisation blocks the extension, the same release runs as a Claude Desktop mcpServers entry:
  --entry        Install (or update) the released server and add the it-snow entry to Claude Desktop's
                 claude_desktop_config.json. It asks first and keeps a backup; with no terminal, --yes is that
                 go-ahead. Stable releases only. It never quits Claude Desktop: quit and reopen it yourself.
  --install-bun  With --entry: the go-ahead to install Bun, which the entry runs with, if it is missing: with
                 Apple silicon's Homebrew (/opt/homebrew) if you have it, else Bun's own release from GitHub
                 (pinned, checked against its SHA-256) into ~/.bun/bin. Separate from --yes. Never changes a
                 shell profile.
  --entry --uninstall  Remove only that entry (if it runs this installer's release) and the installed release.
                 Settings and the sign-in (the Chrome profile) are kept.

With no terminal (an AI agent, IT_SNOW_INSTALL_TTY=/dev/null) the installer never asks: a step that needs an
answer stops, says "Nothing was changed" and prints the command again with the flag it needs.
EOF
}

# ---------------------------------------------------------------- small helpers

lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# $1 with every $2 replaced by $3, literally: no pattern and no "&" meaning, in any bash (3.2's ${x//a/"b"} keeps
# the quotes; 5.2's ${x//a/b} turns & into the match).
replace_all() {
  local text="$1" out=""
  if [[ -z "$2" ]]; then
    printf '%s' "$text"
    return 0
  fi
  while [[ "$text" == *"$2"* ]]; do
    out+="${text%%"$2"*}$3"
    text="${text#*"$2"}"
  done
  printf '%s' "$out$text"
}

# An absolute path ($1, starting with /) spelt as Node's path.resolve spells it: "", "." and ".." segments resolved,
# "//" and a trailing "/" gone. String work only: nothing on disk is looked at.
normalise_path() {
  local part parts=() out=()
  IFS=/ read -r -a parts <<<"$1"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      '' | .) ;;
      ..) [[ ${#out[@]} -eq 0 ]] || unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  if [[ ${#out[@]} -eq 0 ]]; then echo /; else printf '/%s' "${out[@]}"; echo; fi
}

# IT_SNOW_DATA_DIR ($1) as the server reads it (src/settings.ts normaliseDataDir): trimmed; every ${HOME} expanded;
# any other ${…} counts as unset; ~ and ~/… expanded; it must then be absolute, and is spelt as path.resolve spells
# it. Prints nothing when the value is unset or unusable (the server then uses the default folder).
normalise_data_dir() {
  local d="$1"
  d="${d#"${d%%[![:space:]]*}"}"
  d="${d%"${d##*[![:space:]]}"}"
  [[ -n "$d" ]] || return 0
  # shellcheck disable=SC2016 # literal ${HOME} and ${: placeholders, not expansions
  d="$(replace_all "$d" '${HOME}' "$HOME")"
  # shellcheck disable=SC2016
  [[ "$d" != *'${'* ]] || return 0
  # shellcheck disable=SC2088 # a literal ~, as the person typed it
  if [[ "$d" == "~" ]]; then d="$HOME"; elif [[ "$d" == "~/"* ]]; then d="$HOME/${d:2}"; fi
  [[ "$d" == /* ]] || return 0
  normalise_path "$d"
}

# A folder the person gave (--dir, IT_SNOW_HOME) as an absolute path: ~ and ~/… expanded, a relative one taken from
# the folder the installer started in, then spelt as normalise_path spells it.
absolute_dir() {
  local d="$1"
  # shellcheck disable=SC2088 # a literal ~, as the person typed it
  if [[ "$d" == "~" ]]; then d="$HOME"; elif [[ "$d" == "~/"* ]]; then d="$HOME/${d:2}"; fi
  [[ "$d" == /* ]] || d="$START_DIR/$d"
  normalise_path "$d"
}

# Succeeds when version $1 (X.Y.Z; anything after - or + ignored) is at least $2.
version_at_least() {
  awk -v a="${1%%[-+]*}" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9]+(\.[0-9]+)*$/) exit 1
    n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 0
  }'
}

# Succeeds when version $1 is older than $2, by semantic versioning's rules: X.Y.Z compared as numbers; a pre-release
# (X.Y.Z-rc.N) is older than its X.Y.Z; pre-release identifiers compared one by one, numbers as numbers (rc.2 before
# rc.10), numbers before words, words as text, and fewer identifiers first when the rest are equal. Build metadata
# (+…) is ignored.
version_older() {
  [[ "$1" != "$2" ]] || return 1
  LC_ALL=C awk -v a="${1%%+*}" -v b="${2%%+*}" 'BEGIN {
    i = index(a, "-"); ac = i ? substr(a, 1, i - 1) : a; ap = i ? substr(a, i + 1) : ""
    i = index(b, "-"); bc = i ? substr(b, 1, i - 1) : b; bp = i ? substr(b, i + 1) : ""
    n = split(ac, x, "."); m = split(bc, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
    if (ap == bp || ap == "") exit 1
    if (bp == "") exit 0
    n = split(ap, p, "."); m = split(bp, q, ".")
    for (i = 1; i <= n && i <= m; i++) {
      if (p[i] == q[i]) continue
      pn = (p[i] ~ /^[0-9]+$/); qn = (q[i] ~ /^[0-9]+$/)
      if (pn && qn) exit ((p[i] + 0 < q[i] + 0) ? 0 : 1)
      if (pn) exit 0
      if (qn) exit 1
      exit (("" p[i]) < ("" q[i]) ? 0 : 1)
    }
    exit ((n < m) ? 0 : 1)
  }'
}

claude_version() {
  [[ -d "$CLAUDE_APP" ]] || return 1
  # Straight from the file (plutil), not through the preferences daemon (defaults); defaults only where plutil can't
  # print a raw value (macOS before 12).
  /usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$CLAUDE_APP/Contents/Info.plist" 2>/dev/null ||
    /usr/bin/defaults read "$CLAUDE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

chrome_present() { [[ -x "$CHROME_APP/Contents/MacOS/Google Chrome" ]]; }

claude_running() { "$PGREP_BIN" -x Claude >/dev/null 2>&1; }

# curl with bounds, so a site or network that stops answering fails instead of hanging the install: 20 s to connect,
# and a transfer that moves nothing for 60 s is abandoned. fetch_small also caps a small file's whole request at 30 s.
fetch() { curl -fsSL --connect-timeout 20 --speed-limit 1 --speed-time 60 "$@"; }
fetch_small() { fetch --max-time 30 "$@"; }

sha256_of() { shasum -a 256 <"$1" | awk '{ print $1 }'; }

# The version in a bundle's manifest.json ($1 = the .mcpb), or nothing when it can't be read.
bundle_version() {
  local v
  v="$({ unzip -p "$1" manifest.json 2>/dev/null || true; } | { /usr/bin/plutil -extract version raw -o - - 2>/dev/null || true; })"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] && printf '%s\n' "$v"
  return 0
}

# Reads a yes/no answer from the terminal (default no). Without a usable terminal the answer is no.
# The answer source must be a regular file (the tests' scripted answers) or a terminal; /dev/null or another
# device can't answer, so nothing is asked.
can_answer() {
  local p="$TTY_PATH"
  [[ -r "$p" ]] || return 1
  [[ -f "$p" ]] && return 0
  [[ -c "$p" ]] || return 1
  { [[ -t 3 ]]; } 2>/dev/null 3<"$p"
}

ask_yes_no() {
  local answer=""
  can_answer || return 1
  printf '%s [y/N] ' "$1"
  { read -r -t 600 answer <"$TTY_PATH"; } 2>/dev/null || true
  case "$(lowercase "$answer")" in y | yes) return 0 ;; *) return 1 ;; esac
}

# The command that runs this installer again with "$@" as its options, as it can be pasted: <site>/install.sh piped
# to bash. It carries what this run has that isn't the default: IT_SNOW_INSTALL_TTY=/dev/null when there is no
# terminal to answer in, the entry's data folder (IT_SNOW_DATA_DIR) and the download folder (--dir). Every value is
# shell-quoted, so a path with a space, $, quote or backslash pastes as it is. CMD_SITE names another site.
command_for() {
  local out a
  out="curl -fsSL $(printf '%q' "${CMD_SITE:-$SITE_BASE}")/install.sh | "
  can_answer || out+="IT_SNOW_INSTALL_TTY=/dev/null "
  [[ "$DATA_DIR" == "$DEFAULT_DATA_DIR" ]] || out+="IT_SNOW_DATA_DIR=$(printf '%q' "$DATA_DIR") "
  out+="bash -s --"
  for a in "$@"; do out+=" $(printf '%q' "$a")"; done
  [[ "$HOME_DIR" == "$DEFAULT_HOME_DIR" ]] || out+=" --dir $(printf '%q' "$HOME_DIR")"
  printf '%s\n' "$out"
}

# This run's command with $1 added (unless it is there already): what a refusal prints.
rerun_with() {
  local a
  for a in ${OPTS[@]+"${OPTS[@]}"}; do
    if [[ "$a" == "$1" ]]; then
      command_for ${OPTS[@]+"${OPTS[@]}"}
      return 0
    fi
  done
  command_for ${OPTS[@]+"${OPTS[@]}"} "$1"
}

# ---------------------------------------------------------------- what Claude Desktop says

# Version of the IT Snow extension that Claude Desktop lists as installed, or "none".
claude_extension_version() {
  osascript -l JavaScript - "$CLAUDE_SUPPORT/extensions-installations.json" "$EXTENSION_NAME" <<'JXA' 2>/dev/null || echo none
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(
    $(argv[0]).stringByResolvingSymlinksInPath,
    $.NSUTF8StringEncoding,
    null,
  );
  if (text.isNil()) return "none";
  try {
    const all = JSON.parse(text.js).extensions || {};
    const key = Object.keys(all).find((k) => k === argv[1] || k.endsWith("." + argv[1]));
    const version = key && all[key] ? String(all[key].version || "") : "";
    return /^[0-9A-Za-z.+-]{1,64}$/.test(version) ? version : "none";
  } catch (e) {
    return "none";
  }
}
JXA
}

# What Claude Desktop says about the extension's switch: enabled, disabled, blocked or unknown, or "none" when it
# isn't installed. blocked: the organisation switched it off (orgBlockedReason; only its presence is read).
claude_extension_switch() {
  osascript -l JavaScript - "$CLAUDE_SUPPORT" "$EXTENSION_NAME" <<'JXA' 2>/dev/null || echo unknown
ObjC.import("Foundation");
function read(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError($(path).stringByResolvingSymlinksInPath, $.NSUTF8StringEncoding, null);
  return text.isNil() ? undefined : JSON.parse(text.js);
}
function run(argv) {
  try {
    const all = (read(argv[0] + "/extensions-installations.json") || {}).extensions || {};
    const key = Object.keys(all).find((k) => k === argv[1] || k.endsWith("." + argv[1]));
    if (!key) return "none";
    if (!/^[A-Za-z0-9._-]+$/.test(key)) return "unknown";
    const s = read(argv[0] + "/Claude Extensions Settings/" + key + ".json");
    if (!s || typeof s !== "object") return "unknown";
    if (typeof s.orgBlockedReason === "string" && s.orgBlockedReason.trim()) return "blocked";
    return s.isEnabled === false ? "disabled" : s.isEnabled === true ? "enabled" : "unknown";
  } catch (e) {
    return "unknown";
  }
}
JXA
}

# True when the extension is installed and not switched off (blocked counts as off): with the entry too, Claude
# would see every tool twice.
extension_on() {
  [[ "$1" != none && "$2" != disabled && "$2" != blocked && "$2" != none ]]
}

# ---------------------------------------------------------------- the entry: its data folder

# The entry's data folder, DATA_DIR: IT_SNOW_DATA_DIR when the installer is given one, else the folder Claude
# Desktop's it-snow entry names in its env (so an entry with a folder of its own is still recognised as this
# installer's), else the default; each read as the server reads it. DATA_DIR_PROBLEM says why a given
# IT_SNOW_DATA_DIR can't be used (the server would use the default folder instead).
resolve_data_dir() {
  local given="${IT_SNOW_DATA_DIR:-}" from_entry="" cfg
  DATA_DIR="" DATA_DIR_PROBLEM=""
  if [[ -n "${given//[[:space:]]/}" ]]; then
    DATA_DIR="$(normalise_data_dir "$given")"
    # shellcheck disable=SC2016
    [[ -n "$DATA_DIR" ]] || DATA_DIR_PROBLEM='IT_SNOW_DATA_DIR isn'\''t a folder the server can use: it must be an absolute path (/…, ~/… or ${HOME}/…) with no other ${…} in it'
  elif cfg="$(config_target "$(claude_config_path)")"; then
    from_entry="$(entry_env_value "$cfg" IT_SNOW_DATA_DIR)"
    DATA_DIR="$(normalise_data_dir "$from_entry")"
  fi
  [[ -n "$DATA_DIR" ]] || DATA_DIR="$DEFAULT_DATA_DIR"
}

# The entry's data folder when it isn't the default (it then goes into the entry's env), else nothing.
custom_entry_data_dir() { [[ "$DATA_DIR" == "$DEFAULT_DATA_DIR" ]] || printf '%s\n' "$DATA_DIR"; }

# ---------------------------------------------------------------- the entry: Bun

# The Bun the entry would run with, or nothing: where its launcher looks (src/launcher.ts). Always succeeds.
find_bun() {
  local list candidates=() candidate
  if [[ -n "${IT_SNOW_BUN_CANDIDATES+set}" ]]; then
    list="$IT_SNOW_BUN_CANDIDATES"
  else
    # shellcheck disable=SC2016
    list="$(command -v bun 2>/dev/null || true):$(replace_all "$BUN_CANDIDATES" '$HOME' "${HOME%/}")"
  fi
  IFS=: read -r -a candidates <<<"$list"
  for candidate in ${candidates[@]+"${candidates[@]}"}; do
    if [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]]; then
      # A relative PATH entry gives a relative path: the entry and this installer run Bun from other folders.
      [[ "$candidate" == /* ]] || candidate="$(cd "$(dirname "$candidate")" && pwd -P)/${candidate##*/}"
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

bun_version() { "$1" --version 2>/dev/null | head -n 1 | tr -d '[:space:]' || true; }

# Bun's release asset for this Mac, as Bun's own installer chooses it: Apple silicon (also under Rosetta), else Intel
# with AVX2, else Intel's baseline build. IT_SNOW_BUN_ARCH chooses it in tests.
bun_asset() {
  if [[ "${IT_SNOW_INSTALLER_TEST:-}" == "1" && -n "${IT_SNOW_BUN_ARCH:-}" ]]; then
    printf 'bun-darwin-%s\n' "$IT_SNOW_BUN_ARCH"
    return 0
  fi
  if [[ "$(uname -m)" == arm64 || "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" == 1 ]]; then
    echo bun-darwin-aarch64
  elif sysctl -n machdep.cpu.leaf7_features 2>/dev/null | grep -qw AVX2; then
    echo bun-darwin-x64
  else
    echo bun-darwin-x64-baseline
  fi
}

# Homebrew's brew, or nothing. IT_SNOW_BREW names one (tests; "none" means there is none). Always succeeds.
# Only Apple silicon's own Homebrew (/opt/homebrew): Homebrew has Bun bottles for arm64 only, so an Intel Homebrew
# (/usr/local, or whichever brew is first on PATH) would build Bun from source with a large toolchain.
find_brew() {
  if [[ -n "${IT_SNOW_BREW+set}" ]]; then
    if [[ "$IT_SNOW_BREW" != none && -x "$IT_SNOW_BREW" ]]; then printf '%s\n' "$IT_SNOW_BREW"; fi
    return 0
  fi
  [[ "$(bun_asset)" == bun-darwin-aarch64 ]] || return 0
  local brew=/opt/homebrew/bin/brew
  if [[ "${IT_SNOW_INSTALLER_TEST:-}" == "1" && -n "${IT_SNOW_ARM_BREW:-}" ]]; then brew="$IT_SNOW_ARM_BREW"; fi
  if [[ -x "$brew" ]]; then printf '%s\n' "$brew"; fi
  return 0
}

# The folder Bun will be in once install_bun has run: Homebrew's own bin folder, or ~/.bun/bin.
bun_dir_after_install() {
  local brew
  brew="$(find_brew)"
  if [[ -n "$brew" ]]; then printf '%s\n' "${brew%/*}"; else printf '%s\n' "${HOME%/}/.bun/bin"; fi
}

# How the installer would install Bun, in words for the question, --status and the refusals.
bun_install_how() {
  if [[ -n "$(find_brew)" ]]; then
    echo "with Homebrew (brew install bun)"
  else
    echo "from Bun's GitHub release (Bun $BUN_VERSION, checked against its SHA-256) into ~/.bun/bin"
  fi
}

# Installs Bun (only after the person agreed, or --install-bun): with Homebrew if there is one (a failure stops,
# with no other route), else Bun's own release from GitHub at BUN_VERSION, checked against the pinned SHA-256 before
# anything is unpacked, into ~/.bun/bin. Never changes a shell profile and never replaces a Bun that is there.
install_bun() {
  local brew
  brew="$(find_brew)"
  if [[ -n "$brew" ]]; then
    print_step "Installing Bun with Homebrew (brew install bun)..."
    "$brew" install bun || {
      print_error "brew install bun failed (its output is above)"
      return 1
    }
    return 0
  fi
  local asset expected base url tmp actual listing bin="${HOME%/}/.bun/bin"
  asset="$(bun_asset)"
  case "$asset" in
    bun-darwin-aarch64) expected="$BUN_SHA256_AARCH64" ;;
    bun-darwin-x64) expected="$BUN_SHA256_X64" ;;
    bun-darwin-x64-baseline) expected="$BUN_SHA256_X64_BASELINE" ;;
    *)
      print_error "Bun has no release for this Mac ($asset)"
      return 1
      ;;
  esac
  base="https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION"
  if [[ "${IT_SNOW_INSTALLER_TEST:-}" == "1" ]]; then
    [[ -z "${IT_SNOW_BUN_BASE:-}" ]] || base="$IT_SNOW_BUN_BASE"
    [[ -z "${IT_SNOW_BUN_SHA256:-}" ]] || expected="$IT_SNOW_BUN_SHA256"
  fi
  url="${base%/}/$asset.zip"
  if [[ -e "$bin/bun" || -L "$bin/bun" ]]; then
    print_error "$bin/bun is there already but isn't a usable Bun $BUN_MIN or later; leaving it alone (update it with: $bin/bun upgrade)"
    return 1
  fi
  print_step "Installing Bun $BUN_VERSION from Bun's GitHub release into ~/.bun/bin..."
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/it-snow-bun.XXXXXX")" || return 1
  if ! fetch --proto '=https,http' "$url" -o "$tmp/bun.zip"; then
    rm -rf "$tmp"
    print_error "Download failed: $url"
    return 1
  fi
  actual="$(sha256_of "$tmp/bun.zip")"
  if [[ "$actual" != "$expected" ]]; then
    rm -rf "$tmp"
    print_error "Bun's checksum doesn't match — Bun wasn't installed"
    print_error "Expected: $expected"
    print_error "Got:      $actual"
    return 1
  fi
  # The zip must hold the binary and its folder, and nothing else.
  listing="$(unzip -Z1 "$tmp/bun.zip" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
  if [[ "$listing" != "$asset/ $asset/bun " ]]; then
    rm -rf "$tmp"
    print_error "Bun's release doesn't hold just $asset/bun, so it wasn't installed"
    return 1
  fi
  if ! unzip -q -o "$tmp/bun.zip" "$asset/bun" -d "$tmp" 2>/dev/null || [[ -L "$tmp/$asset/bun" || ! -f "$tmp/$asset/bun" ]]; then
    rm -rf "$tmp"
    print_error "Couldn't unpack $asset/bun from Bun's release"
    return 1
  fi
  if ! { mkdir -p "$bin" && install -m 755 "$tmp/$asset/bun" "$bin/.bun.$$" && mv -f "$bin/.bun.$$" "$bin/bun"; }; then
    rm -rf "$tmp" "$bin/.bun.$$"
    print_error "Couldn't put Bun in $bin"
    return 1
  fi
  rm -rf "$tmp"
  print_success "Installed Bun $(bun_version "$bin/bun") in $bin (your shell profiles weren't changed; the entry finds it there)"
}

# ---------------------------------------------------------------- the entry: Claude Desktop's config

# Claude Desktop's config file followed through symbolic links, so it is changed where it really is and the link
# stays. $1 = the path Claude Desktop reads. Fails (printing nothing) for a loop or a chain of more than 20 links.
config_target() {
  local p="$1" t n=0
  while [[ -L "$p" ]]; do
    [[ "$n" -lt 20 ]] || return 1
    t="$(readlink "$p")" || return 1
    [[ "$t" == /* ]] || t="$(dirname "$p")/$t"
    p="$t"
    n=$((n + 1))
  done
  printf '%s\n' "$p"
}

# The version of the release an entry runs ($1 = <server folder>/current/manifest.json): X.Y.Z, "none" when there is
# none, or "unreadable" when there is one but it can't be read (permissions, or not a release's manifest).
release_version() {
  osascript -l JavaScript - "$1" <<'JXA' 2>/dev/null || echo unreadable
ObjC.import("Foundation");
function run(argv) {
  const path = $(argv[0]).stringByResolvingSymlinksInPath;
  if (!$.NSFileManager.defaultManager.fileExistsAtPath(path)) return "none";
  const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (text.isNil()) return "unreadable";
  try {
    const version = String(JSON.parse(text.js).version || "");
    return /^[0-9]+\.[0-9]+\.[0-9]+$/.test(version) ? version : "unreadable";
  } catch (e) {
    return "unreadable";
  }
}
JXA
}

# A value in the env of Claude Desktop's it-snow entry ($1 = the config, $2 = the variable), or nothing.
entry_env_value() {
  osascript -l JavaScript - "$1" "$ENTRY_NAME" "$2" <<'JXA' 2>/dev/null || true
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (text.isNil()) return "";
  try {
    const entry = ((JSON.parse(text.js) || {}).mcpServers || {})[argv[1]];
    const value = entry && entry.env ? entry.env[argv[2]] : undefined;
    return typeof value === "string" ? value : "";
  } catch (e) {
    return "";
  }
}
JXA
}

# Reads or changes the entry in Claude Desktop's config file, with JavaScript for Automation (no jq, node or python),
# which keeps the keys' order and non-ASCII text. The entry this installer wants: command <launcher>, no args, and
# the existing entry's env (the person's settings) or a new one, with Bun's folder first on its PATH and
# IT_SNOW_DATA_DIR set to the data folder (removed for the default one).
#   entry_config state  <config> <launcher> <bun folder or ""> <data folder or "">
#     -> "missing" (no file), "invalid" (not a JSON object, or unreadable), "none" (no entry), "other" (it runs
#        something else), "ours" (it is the entry wanted) or "update" (it runs <launcher> but its env needs the data
#        folder or Bun's folder). An empty bun folder leaves PATH out of it.
#   entry_config add    <config> <launcher> <bun folder> <data folder or ""> <out>
#   entry_config remove <config> <launcher> "" "" <out>
#     -> "changed" (the whole new file is written to <out>), "unchanged", "invalid", or for remove "other" (an
#        entry that runs something else is left alone).
entry_config() {
  osascript -l JavaScript - "$ENTRY_NAME" "$ENTRY_SYSTEM_PATH" "$@" <<'JXA' 2>/dev/null || echo error
ObjC.import("Foundation");
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const unique = (dirs) => dirs.filter((d, i) => d && dirs.indexOf(d) === i);
function wanted(entry, launcher, bunDir, dataDir, systemPath) {
  let env;
  if (isObject(entry) && isObject(entry.env)) {
    // The person's settings stay; only Bun's folder and the data folder are made right.
    env = Object.assign({}, entry.env);
    if (bunDir) {
      if (typeof env.PATH === "string" && env.PATH.trim()) {
        if (env.PATH.split(":")[0] !== bunDir) env.PATH = bunDir + ":" + env.PATH;
      } else {
        env.PATH = unique([bunDir, ...systemPath.split(":")]).join(":");
      }
    }
  } else {
    env = { MCP_RUN_MODE: "config", PATH: unique([bunDir, ...systemPath.split(":")]).join(":") };
  }
  if (dataDir) env.IT_SNOW_DATA_DIR = dataDir;
  else delete env.IT_SNOW_DATA_DIR;
  return { command: launcher, args: [], env };
}
function same(entry, want) {
  if (!isObject(entry) || Object.keys(entry).sort().join() !== "args,command,env") return false;
  if (entry.command !== want.command || !Array.isArray(entry.args) || entry.args.length || !isObject(entry.env))
    return false;
  const a = Object.keys(entry.env).sort(), b = Object.keys(want.env).sort();
  return a.join("\u0000") === b.join("\u0000") && a.every((k) => entry.env[k] === want.env[k]);
}
function run(argv) {
  const [name, systemPath, action, path, launcher, bunDir, dataDir, out] = argv;
  let config = {};
  if ($.NSFileManager.defaultManager.fileExistsAtPath(path)) {
    const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    if (text.isNil()) return "invalid";
    try {
      config = JSON.parse(text.js);
    } catch (e) {
      return "invalid";
    }
    if (!isObject(config)) return "invalid";
  } else if (action === "state") {
    return "missing";
  }
  if (config.mcpServers !== undefined && !isObject(config.mcpServers)) return "invalid";
  const servers = config.mcpServers || {};
  const entry = servers[name];
  const runsOurs = isObject(entry) && entry.command === launcher;
  if (action === "state") {
    if (entry === undefined) return "none";
    if (!runsOurs) return "other";
    return same(entry, wanted(entry, launcher, bunDir, dataDir, systemPath)) ? "ours" : "update";
  }
  if (action === "remove") {
    if (entry === undefined) return "unchanged";
    if (!runsOurs) return "other";
    delete servers[name];
  } else if (action === "add") {
    const want = wanted(entry, launcher, bunDir, dataDir, systemPath);
    if (runsOurs && same(entry, want)) return "unchanged";
    servers[name] = want;
    config.mcpServers = servers;
  } else {
    return "error";
  }
  const ok = $(JSON.stringify(config, null, 2) + "\n").writeToFileAtomicallyEncodingError(
    out,
    false,
    $.NSUTF8StringEncoding,
    null,
  );
  return ok ? "changed" : "error";
}
JXA
}

# A new, empty file beside Claude Desktop's config ($1, the real file, links followed), for its replacement: in the
# same folder, so putting it in place is a rename, never a copy across volumes. Sets CONFIG_TEMP (removed if the run
# stops before it is used).
make_config_temp() {
  local dir
  dir="$(dirname "$1")"
  mkdir -p "$dir" || return 1
  CONFIG_TEMP="$(mktemp "$dir/.$(basename "$1").new-XXXXXX")"
}

# Puts the checked new config ($2, made by make_config_temp) in place of Claude Desktop's ($1), after copying the old
# one to <config>.bak-<date and time>-<random> (a name mktemp reserves), keeping the old file's permissions. Prints
# the backup's path (nothing if there was no file).
replace_config() {
  local cfg="$1" new="$2" backup="" mode
  if [[ -f "$cfg" ]]; then
    backup="$(mktemp "$cfg.bak-$(date '+%Y-%m-%dT%H%M%S')-XXXXXX")" || return 1
    cp -p "$cfg" "$backup" || return 1
    mode="$(stat -f '%Lp' "$cfg")" || return 1
    chmod "$mode" "$new" || return 1
  else
    chmod 600 "$new" || return 1
  fi
  mv -f "$new" "$cfg" || return 1
  printf '%s\n' "$backup"
}

# The entry as JSON, for adding it by hand (JSON.stringify, so it is valid whatever the paths hold).
# $1 = the launcher, $2 = Claude Desktop's config file, $3 = Bun's folder.
print_entry_by_hand() {
  echo "To add it yourself: back up $2, put this inside its \"mcpServers\" object, then quit and reopen"
  echo "Claude Desktop:"
  echo ""
  osascript -l JavaScript - "$ENTRY_NAME" "$1" "${3:+$3:}$ENTRY_SYSTEM_PATH" "$(custom_entry_data_dir)" <<'JXA' 2>/dev/null || true
function run(argv) {
  const env = { MCP_RUN_MODE: "config", PATH: argv[2] };
  if (argv[3]) env.IT_SNOW_DATA_DIR = argv[3];
  const lines = JSON.stringify({ [argv[0]]: { command: argv[1], args: [], env } }, null, 2).split("\n");
  return lines.slice(1, -1).join("\n");
}
JXA
  echo ""
}

# Whether the entry's extra write tools are on, as the server would resolve it: the entry's IT_SNOW_EXTRA_WRITES
# (when it sets one), else settings.json's extra_writes, else off. $1 = the config, $2 = <data folder>/settings.json.
extra_writes() {
  osascript -l JavaScript - "$1" "$ENTRY_NAME" "$2" <<'JXA' 2>/dev/null || echo unknown
ObjC.import("Foundation");
function read(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError($(path).stringByResolvingSymlinksInPath, $.NSUTF8StringEncoding, null);
  if (text.isNil()) return undefined;
  try {
    return JSON.parse(text.js);
  } catch (e) {
    return undefined;
  }
}
function run(argv) {
  const ON = ["1", "true", "yes", "on"];
  const on = (v) => v === true || (typeof v === "string" && ON.includes(v.trim().toLowerCase()));
  const entry = ((read(argv[0]) || {}).mcpServers || {})[argv[1]] || {};
  const fromEnv = entry.env && typeof entry.env.IT_SNOW_EXTRA_WRITES === "string" ? entry.env.IT_SNOW_EXTRA_WRITES.trim() : "";
  if (fromEnv && !fromEnv.startsWith("${")) return on(fromEnv) ? "on" : "off";
  const settings = read(argv[2]);
  if (settings && typeof settings === "object" && Object.prototype.hasOwnProperty.call(settings, "extra_writes"))
    return on(settings.extra_writes) ? "on" : "off";
  return "off";
}
JXA
}

# ---------------------------------------------------------------- the entry: its server in Claude Desktop's log

# What Claude Desktop's log for the entry says about its server, from its last start on:
#   "<none|starting|running|stopped|failed|unreadable> <UTC time> <error text, for failed>". $1 = the log file.
# Reads from the last start in the whole log: Desktop logs every message, so a busy server's start can be thousands
# of lines back.
server_state() {
  local from
  if [[ -f "$1" && ! -r "$1" ]]; then
    echo unreadable
    return 0
  fi
  [[ -f "$1" ]] || {
    echo none
    return 0
  }
  from="$(grep -a -n -E '^[0-9TZ:.-]+ \[[^]]*\] \[info\] Initializing server\.\.\.' "$1" 2>/dev/null | tail -n 1 | cut -d: -f1)"
  [[ -n "$from" ]] || {
    echo none
    return 0
  }
  # Only Claude Desktop's own words count: "<time> [<entry>] [<level>] <text>", matched at the start of <text>, so a
  # logged message whose content holds the same words changes nothing.
  tail -n "+$from" "$1" | LC_ALL=C tr -d '\000' | awk '
    match($0, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]*Z \[[^]]*\] \[[a-z]+\] /) {
      ts = substr($0, 1, index($0, " ") - 2)
      text = substr($0, RLENGTH + 1)
      level = $0
      sub(/^[^]]*\] \[/, "", level)
      sub(/\].*$/, "", level)
      if (level == "info" && index(text, "Initializing server...") == 1) { state = "starting"; since = ts; err = ""; next }
      if (state == "") next
      if (index(text, "Server transport closed unexpectedly") == 1) { state = "failed"; since = ts; next }
      if (level == "error") {
        if (err == "") err = substr(text, 1, 140)
        if (index(text, "Server disconnected") == 1) { state = "failed"; since = ts }
        next
      }
      if (state == "failed") next
      if (index(text, "Server transport closed") == 1) { state = "stopped"; since = ts; next }
      if (state == "starting" && (index(text, "Server started and connected") == 1 || index(text, "Message from server:") == 1)) { state = "running"; since = ts }
    }
    END { if (state == "") print "none"; else print state, since, err }'
}

# A UTC time from the log ("2026-10-15T13:58:54.739") as local time: "14:58" today, "15 Oct 14:58" otherwise.
local_time() {
  local epoch
  epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${1%%.*}" '+%s' 2>/dev/null)" || {
    printf '%s UTC\n' "${1%%.*}"
    return 0
  }
  if [[ "$(date -r "$epoch" '+%Y-%m-%d')" == "$(date '+%Y-%m-%d')" ]]; then
    date -r "$epoch" '+%H:%M'
  else
    date -r "$epoch" '+%e %b %H:%M' | sed 's/^ //'
  fi
}

# When a file or link last changed, as a UTC time in Claude Desktop's log format, or nothing.
changed_at() {
  local epoch
  epoch="$(stat -f '%m' "$1" 2>/dev/null)" || return 0
  date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%S'
}

describe_server() {
  case "$1" in
    running) echo "running since $(local_time "$2")" ;;
    starting) echo "starting since $(local_time "$2")" ;;
    stopped) echo "stopped at $(local_time "$2")" ;;
    failed) echo "failed at $(local_time "$2")${3:+: $3}" ;;
    unreadable) echo "unknown (Claude Desktop's log for it can't be read)" ;;
    *) echo "hasn't started yet" ;;
  esac
}

# Paths Claude Desktop uses (tests point them elsewhere).
claude_config_path() { printf '%s\n' "${IT_SNOW_CLAUDE_CONFIG:-$CLAUDE_SUPPORT/claude_desktop_config.json}"; }
entry_log_path() { printf '%s\n' "${IT_SNOW_CLAUDE_LOGS:-${HOME%/}/Library/Logs/Claude}/mcp-server-$ENTRY_NAME.log"; }

# The entry's state in Claude Desktop's config, as entry_config state says it ("invalid" for a link loop too),
# leaving Bun's folder out of it.
entry_config_state() {
  local cfg
  cfg="$(config_target "$(claude_config_path)")" || {
    echo invalid
    return 0
  }
  entry_config state "$cfg" "$DATA_DIR/server/$LAUNCHER_NAME" "" "$(custom_entry_data_dir)"
}

# ---------------------------------------------------------------- --status

print_status() {
  local claude chrome=missing ext_version switch bun bun_v="" server_dir release cfg_state release_line
  local e_srv e_since e_err switched stale=false entry_used=false open=false latest where next=""
  claude="$(claude_version || true)"
  if chrome_present; then chrome=present; fi
  ext_version="$(claude_extension_version)"
  switch="$(claude_extension_switch)"
  server_dir="$DATA_DIR/server"
  release="$(release_version "$server_dir/current/manifest.json")"
  cfg_state="$(entry_config_state)"
  read -r e_srv e_since e_err <<<"$(server_state "$(entry_log_path)")"
  switched="$(changed_at "$server_dir/current")"
  if [[ "$e_srv" == running && -n "$switched" && "$e_since" < "$switched" ]]; then stale=true; fi
  # In use: a release (even one that can't be read), its folder, or an it-snow key in the config.
  if [[ "$release" != none || -d "$server_dir" || "$cfg_state" =~ ^(ours|update|other)$ ]]; then entry_used=true; fi
  if claude_running; then open=true; fi

  echo "claude: ${claude:-not found}"
  echo "chrome: $chrome"
  echo "claude_extension: $ext_version"
  echo "claude_extension_state: $switch"
  bun="$(find_bun)"
  if [[ -n "$bun" ]]; then
    bun_v="$(bun_version "$bun")"
    echo "bun: $bun (${bun_v:-unknown})"
  else
    echo "bun: not installed (only the mcpServers entry needs it; --entry offers to install it $(bun_install_how))"
  fi
  case "$cfg_state" in
    ours | update) where="in Claude Desktop's config as $ENTRY_NAME" ;;
    other) where="Claude Desktop's $ENTRY_NAME entry runs something else" ;;
    invalid | error) where="Claude Desktop's config can't be read as JSON" ;;
    *) where="not in Claude Desktop's config" ;;
  esac
  case "$release" in
    none) release_line="no release installed" ;;
    unreadable) release_line="release unknown (its manifest can't be read)" ;;
    *) release_line="release $release" ;;
  esac
  echo "entry: $release_line, $where"
  if [[ "$entry_used" == true ]]; then
    if [[ "$open" == true ]]; then
      echo "entry_server: $(describe_server "$e_srv" "$e_since" "$e_err")"
    else
      echo "entry_server: not running (Claude Desktop isn't open)"
    fi
  fi
  # Presence only: the profile folder holds the Okta session; nothing in it is read.
  if [[ -d "$DATA_DIR/profile" ]]; then
    echo "session: Chrome profile present"
  else
    echo "session: none yet (sign in from the chat)"
  fi
  latest="$(fetch --max-time 15 "$SITE_BASE/latest.version" 2>/dev/null | tr -d '[:space:]' || true)"
  [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || latest=unknown
  echo "latest: $latest"
  if [[ "$latest" != unknown ]]; then
    # The entry installs stable releases only: a pre-release is never offered to it.
    if [[ "$entry_used" == true ]]; then
      if [[ "$latest" != *-* && "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && version_older "$release" "$latest"; then
        echo "update: $latest is available (Update now on the update card in Claude, or run the --entry command again)"
      fi
    elif [[ "$ext_version" != none ]] && version_older "$ext_version" "$latest"; then
      echo "update: $latest is available (run the install command again)"
    fi
  fi

  if [[ "$chrome" == missing ]]; then
    next="install Google Chrome, then run this again"
  elif [[ -z "$claude" ]]; then
    next="install Claude Desktop (https://claude.ai/download), then run this again"
  elif [[ "$entry_used" == true ]]; then
    if [[ -z "$bun" ]]; then
      next="install Bun $BUN_MIN or later, which the $ENTRY_NAME entry runs with (ask first): $ENTRY_CMD --install-bun"
    elif [[ -z "$bun_v" ]]; then
      next="the Bun at $bun doesn't say its version: update or reinstall it (brew upgrade bun, or see https://bun.sh), then run this again"
    elif ! version_at_least "$bun_v" "$BUN_MIN"; then
      next="update Bun at $bun to $BUN_MIN or later, which the $ENTRY_NAME entry runs with (brew upgrade bun, or $bun upgrade)"
    elif [[ "$release" == none ]]; then
      next="install the release for the $ENTRY_NAME entry: $ENTRY_CMD"
    elif [[ "$release" == unreadable ]]; then
      next="the installed release can't be read ($server_dir/current/manifest.json): fix its permissions, or install it again: $ENTRY_CMD"
    elif [[ "$cfg_state" == invalid || "$cfg_state" == error ]]; then
      next="Claude Desktop's claude_desktop_config.json can't be read as JSON: fix it, then run $ENTRY_CMD"
    elif [[ "$cfg_state" == update ]]; then
      next="update the $ENTRY_NAME entry in Claude Desktop's config to its data folder: $ENTRY_CMD"
    elif [[ "$cfg_state" != ours ]]; then
      next="add the $ENTRY_NAME entry to Claude Desktop's config: $ENTRY_CMD"
    elif extension_on "$ext_version" "$switch"; then
      next="switch the extension off (Settings > Extensions > $APP_TITLE): with the entry on too, Claude sees every tool twice."
    elif [[ "$open" != true ]]; then
      next="open Claude Desktop."
    elif [[ "$e_srv" == unreadable ]]; then
      next="Claude Desktop's log for the entry can't be read ($(entry_log_path)): fix its permissions, then run this again"
    elif [[ "$e_srv" == failed ]]; then
      next="quit and reopen Claude Desktop; if it still fails, see ~/Library/Logs/Claude/mcp-server-$ENTRY_NAME.log."
    elif [[ "$e_srv" == none || "$e_srv" == stopped ]]; then
      next="quit Claude Desktop (⌘Q) and open it again, so it starts the $ENTRY_NAME entry."
    elif [[ "$e_srv" == running && "$stale" == true ]]; then
      next="quit Claude Desktop (⌘Q) and open it again, so it starts release $release."
    elif [[ "$e_srv" != running ]]; then
      next="wait a minute and check again: Claude Desktop is starting the $ENTRY_NAME entry."
    fi
  elif [[ "$switch" == blocked ]]; then
    next="your organisation blocks the extension: install it as an mcpServers entry instead: $ENTRY_CMD"
  elif [[ "$ext_version" == none ]]; then
    next="run the install command, then click Install in Claude Desktop."
  elif [[ "$switch" == disabled ]]; then
    next="switch the extension on in Claude Desktop: Settings > Extensions > $APP_TITLE."
  elif [[ "$open" != true ]]; then
    next="open Claude Desktop."
  fi
  if [[ -n "$next" ]]; then echo "Next: $next"; else echo "Ready: yes"; fi
}

# ---------------------------------------------------------------- downloads

# True when every name in the download folder $1 is one this installer writes there (the files of a release, their
# .tmp copies, its temporary folders) or .DS_Store, so removing it removes nothing else.
download_dir_is_ours() {
  local f
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [[ -e "$f" || -L "$f" ]] || continue
    case "${f##*/}" in
      latest.mcpb | latest.mcpb.sha256 | latest.version | latest.mcpb.tmp | latest.mcpb.sha256.tmp | \
        latest.version.tmp | .download.?????? | .DS_Store) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

is_plain_file() { [[ -f "$1" && ! -L "$1" ]]; }

# True when an interrupted --entry run's temporary folder holds only what this script puts there.
download_leftover_is_ours() {
  local f
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [[ -e "$f" || -L "$f" ]] || continue
    case "${f##*/}" in
      latest.mcpb | latest.mcpb.sha256 | latest.version | config.??????) is_plain_file "$f" || return 1 ;;
      # An --entry run unpacks the release here before installing it.
      release) [[ -d "$f" && ! -L "$f" ]] || return 1 ;;
      *) return 1 ;;
    esac
  done
  return 0
}

TEMP_DIR=""
CONFIG_TEMP=""
cleanup_temp() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then rm -rf "$TEMP_DIR"; fi
  if [[ -n "$CONFIG_TEMP" && -f "$CONFIG_TEMP" ]]; then rm -f "$CONFIG_TEMP"; fi
}

# ---------------------------------------------------------------- --entry

# --entry, once the release is downloaded and checked ($HOME_DIR/latest.mcpb, SHA-256 $2, version $1 read from its own
# manifest): installs it with the release's own install-release, then adds or updates the entry in Claude Desktop's
# config, and waits for Claude Desktop to start it (up to $5 seconds). $3 = Bun. $4 = the go-ahead for the config:
# "yes" (asked, or --yes), "ours" (no change was expected, so none was asked for) or "no" (declined in a terminal).
install_entry() {
  local version="$1" sha="$2" bun="$3" consent="$4" wait_secs="$5"
  local cfg entry_log server_dir before_release release launcher out f bun_dir="${3%/*}"
  cfg="$(config_target "$(claude_config_path)")" || refuse "Claude Desktop's config is a symbolic link that never ends (a loop, or more than 20 links), so nothing was changed"
  entry_log="$(entry_log_path)"
  server_dir="$DATA_DIR/server"
  before_release="$(release_version "$server_dir/current/manifest.json")"
  [[ "$before_release" != unreadable ]] || before_release=none

  # Its files, not only its version: a damaged release is installed again.
  local intact=true
  [[ -x "$server_dir/$LAUNCHER_NAME" && -f "$server_dir/current/.installed-release" ]] || intact=false
  for f in $RELEASE_FILES; do [[ -e "$server_dir/current/$f" ]] || intact=false; done
  if [[ "$before_release" == "$version" && "$intact" == true ]]; then
    launcher="$server_dir/$LAUNCHER_NAME"
    print_success "Release $version is already installed in $server_dir"
  elif [[ "$before_release" != none && "$intact" == true ]] && version_older "$version" "$before_release"; then
    # Never a silent downgrade: the entry keeps the newer release it has (Update now may have installed it).
    launcher="$server_dir/$LAUNCHER_NAME"
    print_warning "Release $before_release is installed, newer than the site's $version; keeping it."
  else
    print_step "Installing the release for the $ENTRY_NAME entry..."
    local stage="$TEMP_DIR/release"
    mkdir -p "$stage"
    unzip -q -o "$HOME_DIR/latest.mcpb" -d "$stage" >/dev/null 2>&1 || die "Couldn't unpack $HOME_DIR/latest.mcpb; Claude Desktop's config wasn't changed"
    [[ -f "$stage/dist/install-release.js" ]] || die "$HOME_DIR/latest.mcpb is a release from before the mcpServers entry; nothing was changed"
    # The release installs itself (src/install-release.ts): it checks the bundle again, unpacks it beside the version
    # in use and switches to it. Claude Desktop's config isn't touched yet. Every path here is absolute.
    if ! out="$(cd "$stage" && IT_SNOW_DATA_DIR="$DATA_DIR" "$bun" --no-env-file \
      "$stage/dist/install-release.js" --bundle "$HOME_DIR/latest.mcpb" --sha256 "$sha" 2>&1)"; then
      print_error "Installing the release failed, so Claude Desktop's config wasn't changed:"
      printf '%s\n' "$out" | tail -n 15 >&2
      exit 1
    fi
    launcher="$(printf '%s\n' "$out" | sed -n 's/^Claude Desktop entry command: //p' | tail -n 1)"
    [[ -n "$launcher" && -x "$launcher" ]] || die "The release installed, but didn't say where its command is; Claude Desktop's config wasn't changed"
    server_dir="${launcher%/*}"
  fi
  release="$(release_version "$server_dir/current/manifest.json")"
  if [[ "$before_release" != none && "$before_release" != "$release" ]]; then
    print_success "Installed release $release (was $before_release) in $server_dir"
  elif [[ "$before_release" == none ]]; then
    print_success "Installed release $release in $server_dir"
  fi

  local cfg_state changed=false
  cfg_state="$(entry_config state "$cfg" "$launcher" "$bun_dir" "$(custom_entry_data_dir)")"
  case "$cfg_state" in
    ours)
      print_success "Claude Desktop's config already has the $ENTRY_NAME entry"
      ;;
    none | missing | other | update)
      if [[ "$consent" == no ]]; then
        print_warning "Claude Desktop's config wasn't changed, as you chose."
        print_entry_by_hand "$launcher" "$cfg" "$bun_dir"
        return 0
      fi
      if [[ "$consent" != yes ]]; then
        print_warning "Claude Desktop's $ENTRY_NAME entry needs a change this run didn't ask about (Bun is in $bun_dir), so the config wasn't changed."
        print_entry_by_hand "$launcher" "$cfg" "$bun_dir"
        return 0
      fi
      local result backup
      make_config_temp "$cfg" || die "Couldn't create a temporary file beside $cfg; it wasn't changed"
      result="$(entry_config add "$cfg" "$launcher" "$bun_dir" "$(custom_entry_data_dir)" "$CONFIG_TEMP")"
      [[ "$result" == changed && "$(entry_config state "$CONFIG_TEMP" "$launcher" "$bun_dir" "$(custom_entry_data_dir)")" == ours ]] ||
        die "Couldn't prepare the new config ($result); $cfg wasn't changed"
      backup="$(replace_config "$cfg" "$CONFIG_TEMP")" || die "Couldn't write $cfg"
      changed=true
      case "$cfg_state" in
        other) print_success "Pointed Claude Desktop's $ENTRY_NAME entry at release $release${backup:+ (backup: $backup)}" ;;
        update) print_success "Updated Claude Desktop's $ENTRY_NAME entry (its data folder and Bun's folder)${backup:+ (backup: $backup)}" ;;
        *) print_success "Added the $ENTRY_NAME entry to Claude Desktop's config${backup:+ (backup: $backup)}" ;;
      esac
      ;;
    *)
      print_error "Claude Desktop's config can't be read as JSON, so it was left alone: $cfg"
      print_entry_by_hand "$launcher" "$cfg" "$bun_dir" >&2
      exit 1
      ;;
  esac

  if extension_on "$(claude_extension_version)" "$(claude_extension_switch)"; then
    print_warning "The $APP_TITLE extension is switched on too, so Claude would see every tool twice. Keep one:"
    echo "  switch the extension off in Claude Desktop (Settings > Extensions > $APP_TITLE),"
    echo "  or remove the entry with: $(command_for --entry --uninstall)"
  fi

  # Claude Desktop reads its config when it starts: wait for a start of the entry from now on (or, when nothing
  # changed, one that runs this release already).
  local start_ts already=false srv since err switched
  start_ts="$(date -u '+%Y-%m-%dT%H:%M:%S')"
  read -r srv since err <<<"$(server_state "$entry_log")"
  switched="$(changed_at "$server_dir/current")"
  if [[ "$changed" != true && "$srv" == running && -n "$switched" && ! "$since" < "$switched" ]] && claude_running; then
    already=true
  fi
  if [[ "$already" != true ]]; then
    echo ""
    if claude_running; then
      echo "In Claude Desktop: quit it (Claude > Quit Claude, or ⌘Q) and open it again, so it starts the"
      echo "$ENTRY_NAME entry."
    elif [[ "${IT_SNOW_INSTALL_NO_OPEN:-}" == "1" ]]; then
      print_step "Would open: open -a $(printf '%q' "$CLAUDE_APP")"
    else
      print_step "Opening Claude Desktop..."
      "$OPEN_BIN" -a "$CLAUDE_APP" || print_warning "Couldn't open Claude Desktop. Open it yourself."
    fi
    echo ""
  fi
  local ready=false waited=0
  while [[ "$already" != true ]]; do
    read -r srv since err <<<"$(server_state "$entry_log")"
    if [[ "$srv" == running && ! "$since" < "$start_ts" ]]; then
      ready=true
      break
    fi
    if [[ "$srv" == failed && ! "$since" < "$start_ts" ]]; then break; fi
    [[ "$waited" -lt "$wait_secs" ]] || break
    [[ "$waited" -ne 0 ]] || print_step "Waiting for Claude Desktop to start the $ENTRY_NAME entry (up to $((wait_secs / 60)) minutes)..."
    # Keep the temporary folder fresh so nothing mistakes a long wait for a leftover.
    touch "$TEMP_DIR" 2>/dev/null || true
    sleep 2
    waited=$((waited + 2))
  done

  echo ""
  if [[ "$already" == true ]]; then
    print_success "Already up to date and running: the $ENTRY_NAME entry, release $release"
  elif [[ "$ready" == true ]]; then
    print_success "Installed and running: the $ENTRY_NAME entry, release $release"
  elif [[ "$srv" == failed && ! "$since" < "$start_ts" ]]; then
    print_error "Claude Desktop started the $ENTRY_NAME entry, but it failed${err:+: $err}"
    print_error "Quit and reopen Claude Desktop; if it still fails, see ~/Library/Logs/Claude/mcp-server-$ENTRY_NAME.log."
    exit 1
  elif [[ "$wait_secs" -eq 0 ]]; then
    print_success "Done. Quit Claude Desktop (⌘Q) and open it again if it was open, so it starts the $ENTRY_NAME"
    echo "entry, then start a new chat."
  else
    print_error "Claude Desktop hasn't started the $ENTRY_NAME entry within $((wait_secs / 60)) minutes."
    print_error "Quit Claude Desktop (⌘Q) and open it again, then check with the --status command below."
    echo "Check the install any time with:"
    echo "  $STATUS_CMD"
    exit 1
  fi
  echo ""
  echo "Next, in a new chat in Claude Desktop:"
  echo "  1. Ask \"am I signed in to ServiceNow?\". The first tool opens Chrome for the Okta sign-in."
  if [[ "$(extra_writes "$cfg" "$DATA_DIR/settings.json")" == off ]]; then
    echo "  2. Extra write tools (approvals, catalog orders, record patches) are off. To turn them on, ask Claude to"
    echo "     \"show my IT Snow settings\", switch on Enable extra write tools on the card, then quit and reopen"
    echo "     Claude Desktop."
  fi
  echo ""
  echo "Check the install any time with:"
  echo "  $STATUS_CMD"
}

# --entry --uninstall: removes the entry from Claude Desktop's config (only one that runs the installed release; a
# backup is kept) and the installed release. Settings and the Chrome profile (the sign-in) are kept.
uninstall_entry() {
  local cfg server_dir launcher cfg_state has_release=false
  cfg="$(config_target "$(claude_config_path)")" || refuse "Claude Desktop's config is a symbolic link that never ends (a loop, or more than 20 links), so nothing was changed"
  server_dir="$DATA_DIR/server"
  launcher="$server_dir/$LAUNCHER_NAME"
  cfg_state="$(entry_config state "$cfg" "$launcher" "" "$(custom_entry_data_dir)")"
  if [[ -f "$launcher" && -d "$server_dir/versions" ]]; then has_release=true; fi
  if [[ "$cfg_state" == invalid || "$cfg_state" == error ]]; then
    refuse "Claude Desktop's config can't be read as JSON, so nothing was changed: $cfg. Fix it, then run this again"
  fi
  local ours=false
  [[ "$cfg_state" != ours && "$cfg_state" != update ]] || ours=true
  if [[ "$ours" != true && "$has_release" != true ]]; then
    [[ "$cfg_state" != other ]] || print_warning "Claude Desktop's $ENTRY_NAME entry runs something else; leaving it alone."
    print_success "Nothing to remove: no $ENTRY_NAME entry from this installer and no release in $server_dir."
    exit 0
  fi
  local what=() question
  [[ "$ours" != true ]] || what+=("the $ENTRY_NAME entry in Claude Desktop's config (a backup is kept)")
  [[ "$has_release" != true ]] || what+=("the installed release in $server_dir")
  question="Remove $(printf '%s and ' "${what[@]}")"
  question="${question% and }?"
  if [[ "$YES" != true ]] && ! ask_yes_no "$question"; then
    refuse "Not removed (with no terminal, add --yes). Nothing was changed." "$(rerun_with --yes)"
  fi
  if [[ "$ours" == true ]]; then
    local result backup
    make_config_temp "$cfg" || die "Couldn't create a temporary file beside $cfg; it wasn't changed"
    result="$(entry_config remove "$cfg" "$launcher" "" "" "$CONFIG_TEMP")"
    [[ "$result" == changed && "$(entry_config state "$CONFIG_TEMP" "$launcher" "" "")" == none ]] ||
      die "Couldn't prepare the new config ($result); $cfg wasn't changed"
    backup="$(replace_config "$cfg" "$CONFIG_TEMP")" || die "Couldn't write $cfg"
    print_success "Removed the $ENTRY_NAME entry from Claude Desktop's config${backup:+ (backup: $backup)}"
  elif [[ "$cfg_state" == other ]]; then
    print_warning "Claude Desktop's $ENTRY_NAME entry runs something else; left it alone."
  fi
  if [[ "$has_release" == true ]]; then
    rm -rf "${server_dir:?}"
    print_success "Removed $server_dir"
  fi
  echo "Quit Claude Desktop and open it again. Kept: the folder $DATA_DIR with your settings and the Chrome"
  echo "profile that holds your sign-in (the extension uses it too; delete it yourself if you no longer need it)."
}

# ---------------------------------------------------------------- the extension (.mcpb)

# Warns when the it-snow entry is in Claude Desktop's config as well as the extension: every tool twice.
warn_if_entry_too() {
  [[ "$(entry_config_state)" =~ ^(ours|update)$ ]] || return 0
  print_warning "The $ENTRY_NAME mcpServers entry is set up too, so Claude would see every tool twice. Keep one:"
  echo "  remove the entry with: $(command_for --entry --uninstall)"
  echo "  or switch the extension off in Claude Desktop (Settings > Extensions > $APP_TITLE)."
}

# Says that the organisation blocks the extension and what works instead, then stops.
blocked_stop() {
  print_error "$1"
  echo "  Your organisation blocks this extension, so Claude Desktop keeps it switched off. Install the same" >&2
  echo "  release as a Claude Desktop mcpServers entry instead:" >&2
  echo "    $ENTRY_CMD" >&2
  exit 1
}

install_extension() {
  local wait_secs="$1"
  mkdir -p "$HOME_DIR"
  print_step "Downloading the latest extension"
  fetch_small "$SITE_BASE/latest.version" -o "$HOME_DIR/latest.version.tmp" ||
    die "Couldn't download latest.version from $SITE_BASE."
  VERSION="$(tr -d '[:space:]' <"$HOME_DIR/latest.version.tmp")"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "The site's latest.version isn't a release version ($VERSION)."

  fetch "$SITE_BASE/latest.mcpb" -o "$BUNDLE.tmp" || die "Couldn't download latest.mcpb from $SITE_BASE."
  fetch_small "$SITE_BASE/latest.mcpb.sha256" -o "$HOME_DIR/latest.mcpb.sha256.tmp" ||
    die "Couldn't download the checksum from $SITE_BASE."

  local expected actual bundle_v
  expected="$(awk 'NR == 1 { print $1 }' "$HOME_DIR/latest.mcpb.sha256.tmp" | tr '[:upper:]' '[:lower:]')"
  actual="$(sha256_of "$BUNDLE.tmp")"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    rm -f "$BUNDLE.tmp" "$HOME_DIR/latest.version.tmp" "$HOME_DIR/latest.mcpb.sha256.tmp"
    die "Checksum mismatch — nothing was installed. The download did not match $SITE_BASE/latest.mcpb.sha256."
  fi
  # Decisions use the version the checked bundle says it is, never only the site's label.
  bundle_v="$(bundle_version "$BUNDLE.tmp")"
  if [[ "$bundle_v" != "$VERSION" ]]; then
    rm -f "$BUNDLE.tmp" "$HOME_DIR/latest.version.tmp" "$HOME_DIR/latest.mcpb.sha256.tmp"
    die "The site's latest.version ($VERSION) doesn't match the release it serves (${bundle_v:-a manifest that can not be read}), so nothing was installed. This can happen for a few minutes while a new release propagates; wait and run this again."
  fi
  mv "$BUNDLE.tmp" "$BUNDLE"
  mv "$HOME_DIR/latest.version.tmp" "$INSTALLED_FILE"
  mv "$HOME_DIR/latest.mcpb.sha256.tmp" "$HOME_DIR/latest.mcpb.sha256"
  print_success "Downloaded $VERSION (SHA-256 verified)"

  local current switch
  current="$(claude_extension_version)"
  switch="$(claude_extension_switch)"
  if [[ "$current" == "$VERSION" && "$switch" == enabled ]]; then
    print_success "Already up to date and running: $VERSION"
    warn_if_entry_too
    printf 'Ask Claude "how many open incidents do I have?" in a new chat.\n'
    exit 0
  fi

  # Installing the extension again doesn't help when the organisation blocks it: say what does, before the dialog.
  if [[ "$switch" == blocked ]]; then
    blocked_stop "Claude Desktop has the $APP_TITLE extension, but your organisation blocks it."
  fi

  if [[ "${IT_SNOW_INSTALL_NO_OPEN:-}" == "1" ]]; then
    print_warning "Would open Claude Desktop's install dialog for $BUNDLE (IT_SNOW_INSTALL_NO_OPEN=1)."
  else
    print_step "Opening Claude Desktop's install dialog"
    "$OPEN_BIN" -b "$CLAUDE_BUNDLE_ID" "$BUNDLE" || {
      print_warning "Couldn't open Claude Desktop. Open $BUNDLE yourself to install it."
      exit 1
    }
  fi

  printf '\nClick Install in Claude Desktop, then come back here.\n'
  if [[ "$wait_secs" == "0" ]]; then
    printf 'Then start a new chat and ask "how many open incidents do I have?".\n'
    exit 0
  fi

  printf 'Waiting for Claude Desktop to install %s' "$VERSION"
  local elapsed=0 now_version settle settled
  while [[ "$elapsed" -lt "$wait_secs" ]]; do
    now_version="$(claude_extension_version)"
    if [[ "$now_version" == "$VERSION" ]]; then
      printf '\n'
      # Claude Desktop can mark the extension blocked a moment after it lists it: keep looking for a few seconds.
      settle="${IT_SNOW_INSTALL_SETTLE_SECS:-10}"
      [[ "$settle" =~ ^[0-9]+$ ]] || settle=10
      settled=0
      while :; do
        switch="$(claude_extension_switch)"
        if [[ "$switch" == blocked ]]; then
          blocked_stop "Claude Desktop installed the $APP_TITLE extension, but your organisation blocks it."
        fi
        [[ "$settled" -lt "$settle" ]] || break
        sleep 1
        settled=$((settled + 1))
      done
      print_success "Installed $VERSION"
      if [[ "$switch" == disabled ]]; then
        print_warning "It is switched off: turn it on in Claude Desktop → Settings → Extensions."
      fi
      warn_if_entry_too
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
}

# ---------------------------------------------------------------- main

main() {
  [[ -n "${HOME:-}" ]] || die "HOME isn't set, so the installer can't find your home folder"
  START_DIR="$(pwd -P 2>/dev/null || pwd)"
  # This run's options, for the commands it prints (the download folder is added from HOME_DIR).
  OPTS=()
  local dir_override="" dir_given=false mode=install no_wait=false entry=false install_bun_ok=false
  YES=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ $# -ge 2 && -n "$2" ]] || die "--dir needs a path"
        dir_override="$2"
        dir_given=true
        shift 2
        ;;
      --dir=*)
        dir_override="${1#--dir=}"
        [[ -n "$dir_override" ]] || die "--dir needs a path"
        dir_given=true
        shift
        ;;
      --status)
        mode=status
        OPTS+=(--status)
        shift
        ;;
      --uninstall)
        # --status wins: it only reads.
        if [[ "$mode" != status ]]; then mode=uninstall; fi
        OPTS+=(--uninstall)
        shift
        ;;
      --no-wait)
        no_wait=true
        OPTS+=(--no-wait)
        shift
        ;;
      --yes | -y)
        YES=true
        OPTS+=(--yes)
        shift
        ;;
      --entry)
        entry=true
        OPTS+=(--entry)
        shift
        ;;
      --install-bun)
        install_bun_ok=true
        OPTS+=(--install-bun)
        shift
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done
  if [[ "$install_bun_ok" == true && ("$entry" != true || "$mode" != install) ]]; then
    die "--install-bun goes with --entry: the mcpServers entry is what needs Bun"
  fi
  trap cleanup_temp EXIT

  # Every path is made absolute now, before anything changes: later steps run from other folders.
  DEFAULT_HOME_DIR="$(normalise_path "${HOME%/}/.it-snow-server")"
  if [[ "$dir_given" == true ]]; then
    HOME_DIR="$(absolute_dir "$dir_override")"
  else
    HOME_DIR="$(absolute_dir "${IT_SNOW_HOME:-$DEFAULT_HOME_DIR}")"
  fi
  SITE_BASE="${IT_SNOW_INSTALL_BASE:-$SITE_BASE_DEFAULT}"
  SITE_BASE="${SITE_BASE%/}"
  TTY_PATH="${IT_SNOW_INSTALL_TTY:-/dev/tty}"
  CLAUDE_APP="${IT_SNOW_CLAUDE_APP:-/Applications/Claude.app}"
  CHROME_APP="${IT_SNOW_CHROME_APP:-/Applications/Google Chrome.app}"
  CLAUDE_SUPPORT="${HOME%/}/Library/Application Support/Claude"
  BUNDLE="$HOME_DIR/latest.mcpb"
  INSTALLED_FILE="$HOME_DIR/latest.version"
  DEFAULT_DATA_DIR="$(normalise_path "${HOME%/}/Library/Application Support/it-snow")"
  resolve_data_dir
  # The commands --status and the messages point to, as they can be pasted (under curl | bash there is no local
  # install.sh). With no terminal, the no-terminal form; never with --yes or --install-bun, which need the person's
  # go-ahead first.
  ENTRY_CMD="$(command_for --entry)"
  STATUS_CMD="$(command_for --status)"

  # How long to wait for Claude Desktop: IT_SNOW_INSTALL_WAIT_SECS, else 600 (0 when nothing is opened); --no-wait 0.
  local wait_secs="${IT_SNOW_INSTALL_WAIT_SECS:-}"
  if [[ -z "$wait_secs" ]]; then
    if [[ "${IT_SNOW_INSTALL_NO_OPEN:-}" == "1" ]]; then wait_secs=0; else wait_secs=600; fi
  fi
  [[ "$wait_secs" =~ ^[0-9]+$ ]] || wait_secs=600
  if [[ "$no_wait" == true ]]; then wait_secs=0; fi

  if [[ "$mode" == status ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || die "IT Snow is macOS only."
    print_status
    exit 0
  fi

  if [[ "$entry" == true && -n "$DATA_DIR_PROBLEM" ]]; then
    refuse "$DATA_DIR_PROBLEM. Nothing was changed."
  fi

  if [[ "$mode" == uninstall && "$entry" == true ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || die "IT Snow is macOS only."
    uninstall_entry
    exit 0
  fi

  if [[ "$mode" == uninstall ]]; then
    if [[ ! -d "$HOME_DIR" ]]; then
      print_warning "Nothing to remove: $HOME_DIR does not exist."
      exit 0
    fi
    download_dir_is_ours "$HOME_DIR" ||
      die "$HOME_DIR holds files this installer didn't put there, so it was left alone. Nothing was changed."
    if [[ "$YES" != true ]] && ! ask_yes_no "Remove $HOME_DIR?"; then
      die "Refusing to remove $HOME_DIR without --yes (and there is no terminal to ask)."
    fi
    rm -rf "${HOME_DIR:?}"
    print_success "Removed $HOME_DIR."
    print_warning "The extension itself is still installed: remove it in Claude Desktop → Settings → Extensions."
    exit 0
  fi

  # ---- preflight (both routes)
  print_step "Checking this Mac"
  [[ "$(uname -s)" == "Darwin" ]] || die "IT Snow is macOS only."
  chrome_present || die "Google Chrome is required and was not found at $CHROME_APP. Install it from https://www.google.com/chrome/ and run this again."
  print_success "Google Chrome found"
  if [[ ! -d "$CLAUDE_APP" ]]; then
    die "Claude Desktop is not installed at $CLAUDE_APP. Install it from https://claude.ai/download and run this again."
  fi
  local claude
  claude="$(claude_version || true)"
  if [[ -z "$claude" ]]; then
    print_warning "Couldn't read Claude Desktop's version; IT Snow needs $MIN_CLAUDE_VERSION or later."
  elif ! version_at_least "$claude" "$MIN_CLAUDE_VERSION"; then
    die "Claude Desktop $claude is too old: IT Snow needs $MIN_CLAUDE_VERSION or later. Update Claude Desktop, then run this again."
  else
    print_success "Claude Desktop $claude"
  fi
  local tool
  for tool in curl shasum osascript awk sed unzip; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not available"
  done

  if [[ "$entry" != true ]]; then
    install_extension "$wait_secs"
  fi

  # ---- --entry: every check and question first, before anything is downloaded or installed.
  print_step "Installing IT Snow as a Claude Desktop mcpServers entry ($ENTRY_NAME). It never quits Claude Desktop."

  # Channel: the entry installs only stable releases (src/install-release.ts).
  local site_version stable_cmd
  stable_cmd="$(CMD_SITE="$SITE_BASE_DEFAULT" command_for ${OPTS[@]+"${OPTS[@]}"})"
  site_version="$(fetch --max-time 15 "$SITE_BASE/latest.version" 2>/dev/null | tr -d '[:space:]' || true)"
  [[ -n "$site_version" ]] || refuse "Couldn't download latest.version from $SITE_BASE. Nothing was changed."
  if [[ "$site_version" == *-* ]]; then
    refuse "This site serves a pre-release ($site_version), and the $ENTRY_NAME entry installs only stable releases. Nothing was changed. Use the stable site:" "$stable_cmd"
  fi
  [[ "$site_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    refuse "The site's latest.version isn't a release version ($site_version). Nothing was changed."

  # Bun: the entry runs with it. Installing software is the person's call: a question in a terminal, else
  # --install-bun (their go-ahead). It is installed only once the download has been checked, below.
  local bun bun_v need_bun=false how bun_dir
  bun="$(find_bun)"
  if [[ -n "$bun" ]]; then
    bun_v="$(bun_version "$bun")"
    if [[ -z "$bun_v" ]]; then
      refuse "The Bun at $bun doesn't say its version (bun --version printed nothing), so the $ENTRY_NAME entry can't rely on it. Nothing was changed. Update or reinstall it (brew upgrade bun, or see https://bun.sh), then run this again"
    elif ! version_at_least "$bun_v" "$BUN_MIN"; then
      refuse "Bun $bun_v at $bun is older than $BUN_MIN, which the $ENTRY_NAME entry needs. Nothing was changed. Update it (brew upgrade bun, or $bun upgrade), then run this again"
    fi
    print_success "Bun $bun_v: $bun"
    bun_dir="${bun%/*}"
  else
    how="$(bun_install_how)"
    print_warning "Bun isn't installed, and the $ENTRY_NAME entry runs with it."
    if [[ "$install_bun_ok" == true ]] || ask_yes_no "Install Bun now, $how?"; then
      need_bun=true
    elif can_answer; then
      refuse "Bun wasn't installed, so nothing was changed. Install it yourself (brew install bun, or see https://bun.sh), then run this again:" \
        "$(command_for ${OPTS[@]+"${OPTS[@]}"})"
    else
      refuse "Nothing was changed. With the user's go-ahead, run this again with --install-bun to install Bun $how (or install Bun yourself: brew install bun):" \
        "$(rerun_with --install-bun)"
    fi
    bun_dir="$(bun_dir_after_install)"
  fi

  # Claude Desktop's config: the person's go-ahead to change it, now rather than after the download.
  local cfg_path pre_state question cfg_consent=no
  cfg_path="$(config_target "$(claude_config_path)")" || refuse "Claude Desktop's config is a symbolic link that never ends (a loop, or more than 20 links), so nothing was changed"
  pre_state="$(entry_config state "$cfg_path" "$DATA_DIR/server/$LAUNCHER_NAME" "$bun_dir" "$(custom_entry_data_dir)")"
  case "$pre_state" in
    ours) cfg_consent=ours ;;
    none | missing | other | update)
      case "$pre_state" in
        other) question="Claude Desktop's $ENTRY_NAME entry runs something else. Point it at this release, keeping its env ($cfg_path; a backup is kept)?" ;;
        update) question="Update Claude Desktop's $ENTRY_NAME entry: its data folder, and Bun's folder first on its PATH ($cfg_path; a backup is kept)?" ;;
        *) question="Add the $ENTRY_NAME entry to Claude Desktop's config ($cfg_path; a backup is kept)?" ;;
      esac
      if [[ "$YES" == true ]] || ask_yes_no "$question"; then
        cfg_consent=yes
      elif ! can_answer; then
        case "$pre_state" in
          other) refuse "Nothing was changed. Claude Desktop's $ENTRY_NAME entry runs something else; with the user's go-ahead to point it at this release (its env is kept), run this again with --yes:" "$(rerun_with --yes)" ;;
          update) refuse "Nothing was changed. Claude Desktop's $ENTRY_NAME entry needs its data folder or Bun's folder updated; with the user's go-ahead to change Claude Desktop's config, run this again with --yes:" "$(rerun_with --yes)" ;;
        esac
        refuse "Nothing was changed. With the user's go-ahead to change Claude Desktop's config, run this again with --yes:" \
          "$(rerun_with --yes)"
      fi
      ;;
    *)
      refuse "Claude Desktop's config can't be read as JSON, so nothing was changed: $cfg_path. Fix it (Claude Desktop needs valid JSON too), then run this again"
      ;;
  esac

  # The download folder: new, or one of ours. Leftovers of a killed run: only our own temporary folders, a day old.
  if [[ -e "$HOME_DIR" && ! -d "$HOME_DIR" ]]; then refuse "Not a folder: $HOME_DIR. Nothing was changed."; fi
  if [[ -d "$HOME_DIR" ]]; then
    download_dir_is_ours "$HOME_DIR" ||
      refuse "$HOME_DIR holds files this installer didn't put there. Nothing was changed. Choose another folder with --dir."
    local leftover
    for leftover in "$HOME_DIR"/.download.??????; do
      [[ -d "$leftover" && ! -L "$leftover" ]] || continue
      [[ -z "$(find "$leftover" -maxdepth 0 -mtime -1 2>/dev/null)" ]] || continue
      ! download_leftover_is_ours "$leftover" || rm -rf "$leftover"
    done
  else
    mkdir -p "$HOME_DIR" || die "Couldn't create $HOME_DIR"
  fi

  # Download into a temporary folder and check it before anything is changed.
  TEMP_DIR="$(mktemp -d "$HOME_DIR/.download.XXXXXX")" || die "Couldn't create a temporary folder"
  print_step "Downloading the latest release"
  fetch_small "$SITE_BASE/latest.version" -o "$TEMP_DIR/latest.version" || die "Couldn't download latest.version from $SITE_BASE."
  fetch "$SITE_BASE/latest.mcpb" -o "$TEMP_DIR/latest.mcpb" || die "Couldn't download latest.mcpb from $SITE_BASE."
  fetch_small "$SITE_BASE/latest.mcpb.sha256" -o "$TEMP_DIR/latest.mcpb.sha256" || die "Couldn't download the checksum from $SITE_BASE."
  local label version expected actual
  label="$(tr -d '[:space:]' <"$TEMP_DIR/latest.version")"
  expected="$(awk 'NR == 1 { print tolower($1) }' "$TEMP_DIR/latest.mcpb.sha256")"
  actual="$(sha256_of "$TEMP_DIR/latest.mcpb")"
  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "$expected" != "$actual" ]]; then
    print_error "Checksum mismatch — nothing was installed"
    print_error "Expected: ${expected:-<none>}"
    print_error "Got:      $actual"
    print_error "This can happen for up to about 10 minutes while a new release propagates; wait and run the installer again."
    exit 1
  fi
  # From here on, the version is the one the checked bundle says it is; the site's label must agree with it.
  version="$(bundle_version "$TEMP_DIR/latest.mcpb")"
  if [[ -z "$version" || "$version" != "$label" ]]; then
    refuse "The site's latest.version ($label) doesn't match the release it serves (${version:-a manifest that can not be read}), so nothing was changed. This can happen for a few minutes while a new release propagates; wait and run this again."
  fi
  if [[ "$version" == *-* ]]; then
    refuse "This site serves a pre-release ($version), and the $ENTRY_NAME entry installs only stable releases. Nothing was changed. Use the stable site:" "$stable_cmd"
  fi
  local name
  for name in latest.mcpb latest.mcpb.sha256 latest.version; do
    if [[ -d "$HOME_DIR/$name" ]]; then die "$HOME_DIR/$name is a folder; move it out of the way and run the installer again"; fi
    mv -f "$TEMP_DIR/$name" "$HOME_DIR/$name"
  done
  print_success "Downloaded $version (SHA-256 verified)"

  # Before anything is installed (Bun included): the release must be able to install itself as the entry.
  # (grep without -q reads the whole list, so unzip never dies of a closed pipe under pipefail)
  unzip -Z1 "$HOME_DIR/latest.mcpb" 2>/dev/null | grep -x 'dist/install-release.js' >/dev/null ||
    die "The site's release ($version) is from before the mcpServers entry, so it can't be installed as one. The verified download is kept in $HOME_DIR; nothing else was changed"
  if [[ "$need_bun" == true ]]; then
    install_bun || die "Bun wasn't installed, so the entry wasn't set up (only the verified download is kept, in $HOME_DIR). Install Bun yourself (brew install bun, or see https://bun.sh), then run this again"
    bun="$(find_bun)"
    [[ -n "$bun" ]] || die "Bun was installed, but the installer can't find it (looked on your PATH, in ~/.bun/bin, /opt/homebrew/bin and /usr/local/bin)"
    version_at_least "$(bun_version "$bun")" "$BUN_MIN" || die "The Bun at $bun is older than $BUN_MIN"
    print_success "Bun $(bun_version "$bun"): $bun"
  fi
  install_entry "$version" "$actual" "$bun" "$cfg_consent" "$wait_secs"
}

main "$@"
