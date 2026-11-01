#!/usr/bin/env bash
# claude-switch installer: https://github.com/qxlies/claude-switch
#   curl -fsSL https://raw.githubusercontent.com/qxlies/claude-switch/main/install.sh | bash
set -euo pipefail

REPO="qxlies/claude-switch"
BRANCH="${CLAUDE_SWITCH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "claude-switch only works on macOS."

# python3: on a fresh macOS /usr/bin/python3 is a stub that needs the Command Line Tools
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
  warn "Python 3.8+ is required. On macOS it comes with the Command Line Tools:"
  echo "    xcode-select --install"
  fail "Install the Command Line Tools and run the installer again."
fi

[ -d "/Applications/Claude.app" ] || warn "Claude Desktop was not found in /Applications. claude-switch will install, but it only works with Claude Desktop."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "${CLAUDE_SWITCH_SRC:-}" ]; then
  cp "$CLAUDE_SWITCH_SRC" "$tmp/claude-switch"            # local install from a clone
else
  say "Downloading claude-switch…"
  curl -fsSL "$RAW/claude-switch" -o "$tmp/claude-switch" || fail "Could not download $RAW/claude-switch"
fi
head -1 "$tmp/claude-switch" | grep -q python3 || fail "The downloaded file doesn't look like claude-switch."
chmod +x "$tmp/claude-switch"

say "Installing…"
CLAUDE_SWITCH_INSTALLER=1 python3 "$tmp/claude-switch" install

# Put ~/.local/bin on PATH
bindir="$HOME/.local/bin"
case ":$PATH:" in
  *":$bindir:"*) ;;
  *)
    rc="$HOME/.zshrc"
    [ "${SHELL##*/}" = "bash" ] && rc="$HOME/.bash_profile"
    if ! grep -qs '.local/bin' "$rc"; then
      printf '\n# claude-switch\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      say "Added ~/.local/bin to PATH in $rc. Open a new terminal window."
    fi
    ;;
esac

version="$("$bindir/claude-switch" --version 2>/dev/null || echo claude-switch)"
echo
say "Done: $version"
cat <<'EOF'

  Getting started (from a regular Terminal, not from inside Claude):

    claude-switch save main     # remember the current account
    claude-switch add work      # sign in to a second account
    claude-switch use main      # switch between them

  Or open the "Claude Switch" app from Spotlight (⌘ Space).
  Help: claude-switch --help

EOF
