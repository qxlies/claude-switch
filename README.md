# claude-switch

**English** | [Русский](README.ru.md)

**Switch accounts in Claude Desktop on macOS while keeping your local chats shared.**

Normally, if you sign out of Claude Desktop and sign in with another account, the Code (and Cowork) tab comes up empty, because local sessions are tied to the account. `claude-switch` remembers the sign-ins of several accounts and switches between them with one command or one click. All your local chats move with you to whichever account is active.

```text
$ claude-switch list
 ● main                 c4d2a3b1/fb6c95e4  active  ← workspace
   work                 9a1e77f0/2b4d1c88  sign-in saved

$ claude-switch use work
[12:04:10] Quitting Claude… (confirm if the app asks)
[12:04:13] Sign-in for 'main' saved
[12:04:13] Moving workspace c4d2a3b1/fb6c95e4 → 9a1e77f0/2b4d1c88
[12:04:13] Switched to 'work'. Launching Claude.
```

- **One-click switching.** Use the **Claude Switch** app (Spotlight) or `claude-switch use <name>`.
- **Shared local workspace.** Code and Cowork sessions, scheduled tasks, sidebar groups, per-folder permission modes and session presets move with every switch.
- **No signing in again.** Each account's sign-in is saved locally and restored when you switch back.
- **Backup before every change.** The last 8 are kept in `~/.claude-switch/backups/`.
- **No dependencies.** One Python file, standard library only.

> [!IMPORTANT]
> This is an unofficial tool and is not affiliated with Anthropic. It relies on Claude Desktop's internal data layout, which may change in a future update. Tested with Claude Desktop 4.4212 on macOS (Apple Silicon).

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [The Claude Switch app](#the-claude-switch-app)
- [What is shared and what isn't](#what-is-shared-and-what-isnt)
- [How it works](#how-it-works)
- [Backups and recovery](#backups-and-recovery)
- [Troubleshooting](#troubleshooting)
- [Security and privacy](#security-and-privacy)
- [Updating and uninstalling](#updating-and-uninstalling)

## Requirements

- macOS
- [Claude Desktop](https://claude.ai/download) in `/Applications`
- Python 3.8+. It comes with the Xcode Command Line Tools; if you don't have them, run `xcode-select --install`

## Installation

Run this in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/qxlies/claude-switch/main/install.sh | bash
```

The installer:

1. puts the `claude-switch` command in `~/.local/bin` and adds that folder to your `PATH` (in `~/.zshrc`) if needed;
2. builds the **Claude Switch** app in `~/Applications`, which you can open from Spotlight.

<details>
<summary>Manual install from a clone</summary>

```bash
git clone https://github.com/qxlies/claude-switch.git
cd claude-switch
CLAUDE_SWITCH_SRC=./claude-switch ./install.sh
```

Or without the installer at all: `python3 claude-switch install`.

</details>

## Quick start

> [!WARNING]
> Run these commands from a **regular Terminal**, not from Claude's built-in terminal or chat: switching quits and relaunches Claude. If you do run it from inside Claude, nothing breaks (the work continues in the background), but the window showing the output closes.

**1. Remember your current account.** Claude is not restarted.

```bash
claude-switch save main
```

**2. Add a second account.**

```bash
claude-switch add work
```

Claude quits and reopens on the sign-in screen. Sign in to the second account **with claude.ai**. The script notices the sign-in, moves your chats to the new account and relaunches Claude. If you don't sign in within 15 minutes, it restores the previous account.

**3. Switch.**

```bash
claude-switch use main
claude-switch use work
```

Or open **Claude Switch** from Spotlight and pick an account.

## Commands

| Command | What it does |
| --- | --- |
| `claude-switch` | List profiles and show a command summary |
| `claude-switch list` | List profiles: `●` is the current sign-in, `← workspace` is where your chats are now |
| `claude-switch save <name>` | Save the current sign-in as a profile; if it's already saved, rename it |
| `claude-switch add <name>` | Add a new account through the sign-in screen |
| `claude-switch use <name>` | Switch to a profile |
| `claude-switch sync` | Move chats to the account that is signed in now (if you signed in outside the script) |
| `claude-switch remove <name>` | Remove a profile: only its saved sign-in, chats are not touched |
| `claude-switch gui` | Account menu in a macOS dialog |
| `claude-switch update` | Update to the latest version |
| `claude-switch uninstall [--purge]` | Uninstall; `--purge` also removes profiles and backups |
| `claude-switch --version` | Show the version |

`use`, `add` and `sync` accept `--force`: if Claude doesn't quit within a minute (for example, a confirmation dialog is open), the script ends it with `SIGTERM`.

Profile names can contain letters, digits, `-`, `_` and `.`, with no spaces.

## The Claude Switch app

The installer adds a **Claude Switch** app to `~/Applications`. Open it from Spotlight (`⌘ Space` → "Claude Switch") or keep it in the Dock. It shows your accounts:

- `● main`: the account you are signed in to right now;
- **＋ Add account…**: same as `add`;
- **Save current sign-in as…**: shown when the current sign-in isn't saved yet;
- **⟳ Move chats to the current account**: shown when your chats are under a different account.

Progress and errors arrive as macOS notifications. A detailed log is written to `~/.claude-switch/switch.log`.

> [!NOTE]
> The first time you use it, macOS may ask whether Claude Switch can control Claude. Allow it, otherwise it can't quit and relaunch Claude.

## What is shared and what isn't

| Moves between accounts | Stays with its account |
| --- | --- |
| Local Code sessions (your whole chat history) | Chats on claude.ai and in the cloud |
| Cowork sessions and scheduled tasks | Cloud sessions and Remote Control |
| Sidebar groups and sections in Code | Organization connectors and MCP servers |
| Per-folder permission modes, session presets | The account's usage limits and plan |
| Sessions' scratch folders | Gateway (3P) mode sessions, which use a separate data folder |

Claude Code transcripts live in `~/.claude/projects` and don't depend on the account, so they are always shared.

The `claude` terminal command (Claude Code CLI) is not affected: it has its own sign-in.

## How it works

<details>
<summary>Details for the curious</summary>

Claude Desktop keeps its data in `~/Library/Application Support/Claude`.

**Sign-in** consists of the claude.ai cookies (the `Cookies` file, `sessionKey*`), the web storage (`Local Storage`, `Session Storage`, `IndexedDB`) and the `oauth:tokenCache*` keys in `config.json`. All of it is encrypted with the "Claude Safe Storage" Keychain key, which is the same for every account on this Mac. So a sign-in snapshot can be saved and put back while the app is closed.

**Local sessions** live in

```text
claude-code-sessions/<account ID>/<organization ID>/
local-agent-mode-sessions/<account ID>/<organization ID>/
```

Another account looks for sessions in another folder, which is why they "disappear". A symlink won't do: the app opens these folders with `O_NOFOLLOW` and treats a symlink as tampering. So on each switch the folder is physically moved under the new account's IDs (`rename`, instant). If files conflict, the workspace being carried wins and the other copy goes into the backup.

**What `use` does:**

1. Quits Claude gracefully (AppleScript `quit`).
2. Refreshes the snapshot of the current account's sign-in. Tokens get refreshed over time, so the snapshot is taken on every switch.
3. Backs up configs and sessions.
4. Restores the target account's sign-in and sets `lastKnownAccountUuid` to it. Without this, the app decides a different person signed in and wipes its token cache and connectors.
5. Moves the workspace and copies the per-account settings.
6. Sets the mode choice to claude.ai and launches Claude.

**About Gateway (3P) mode.** If Gateway is configured in Claude Desktop, an app started without a claude.ai sign-in switches itself to Gateway (the `deploymentMode` flag in `~/Library/Application Support/Claude-3p/claude_desktop_config.json`). The script sets `deploymentMode: "1p"` and launches Claude with `--claude-first-party-sign-in`, the same way the app does when you choose to sign in with claude.ai.

The script's own state lives in `~/.claude-switch/`:

```text
state.json            profiles and where the workspace is now
profiles/<name>/auth/ an account's saved sign-in
backups/              the last 8 backups
switch.log            log of background operations
```

</details>

## Backups and recovery

Before every `use`, `add` and `sync`, the script saves `config.json`, `claude_desktop_config.json`, `ccd-session-presets.json` and the `claude-code-sessions` and `local-agent-mode-sessions` folders to `~/.claude-switch/backups/<date>-<action>/`.

If something goes wrong, restore manually:

```bash
osascript -e 'quit app "Claude"'
B=~/.claude-switch/backups/<backup-folder>
D=~/Library/Application\ Support/Claude
cp "$B"/*.json "$D"/
rsync -a "$B/claude-code-sessions/" "$D/claude-code-sessions/"
rsync -a "$B/local-agent-mode-sessions/" "$D/local-agent-mode-sessions/"
open -a Claude
```

`rsync` without `--delete` only adds files and never removes any. If the chats end up under a different account after restoring, run `claude-switch sync`.

## Troubleshooting

**Claude opened on the sign-in screen after switching.**
The saved sign-in expired. This usually happens when an account wasn't used for about a month, or after "sign out everywhere" on another device. Just sign in again: the script refreshes the snapshot on the next switch.

**Claude opened in Gateway mode.**
Fixed in 1.1.0, so update with `claude-switch update`. If you still end up in Gateway, click "Sign out" and sign in with claude.ai.

**Chats disappeared after signing in to another account directly in Claude.**
They aren't deleted, they are under the previous account. Run `claude-switch sync`. To avoid this, don't use "Sign out" inside Claude; switch with the script instead.

**"Claude did not quit".**
Claude is most likely showing a confirmation dialog (for example, sessions are running). Confirm it, or rerun the command with `--force`.

**`command not found: claude-switch`.**
Open a new terminal window. If that doesn't help, add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

**Where to look for details.**
The script's log is `~/.claude-switch/switch.log`. Claude's logs are in `~/Library/Logs/Claude/main.log`.

## Security and privacy

- Everything runs locally: the script sends nothing anywhere and talks to no servers (except GitHub, in `update`).
- Saved sign-ins are stored in `~/.claude-switch/profiles` with `700` permissions (only your macOS user can read them). They are encrypted with Claude's key from your Keychain, so they are useless on another computer.

> [!CAUTION]
> Don't publish or send anyone your `~/.claude-switch` folder: on this Mac it holds working sign-ins to your accounts.

## Updating and uninstalling

```bash
claude-switch update             # latest version from GitHub
claude-switch uninstall          # remove the command and the app, keep profiles
claude-switch uninstall --purge  # remove everything, including saved sign-ins and backups
```

Uninstalling doesn't touch your chats: they stay in the folder of whichever account is active.

## License

[MIT](LICENSE)
