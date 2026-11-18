# IT Snow

**Work your ServiceNow tickets from Claude, through the Okta session you already have. No API account, no OAuth client, no admin ticket.**

Version **0.6.1** · macOS · Claude Desktop · extension, or mcpServers entry where the extension is blocked

- [Install: for people](#install-for-people)
- [Install: for AI agents](#install-for-ai-agents)
- [Install the entry by hand](#install-the-entry-by-hand)
- [What you can do](#what-you-can-do)
- [Sign in](#sign-in)
- [Tools](#tools)
- [Security and privacy](#security-and-privacy)
- [Troubleshooting](#troubleshooting)

---

## Install: for people

There are two paths. If you can install the extension, follow the steps here. If your organisation blocks the
extension, follow [If your organisation blocks the extension](#if-your-organisation-blocks-the-extension) instead.
Not sure? Start with the extension: the installer tells you if your organisation blocks it.

### If you can install the extension

You need macOS with Google Chrome and Claude Desktop 2.7032.0 or later. Open Terminal and run:

```bash
curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash
```

Then:

1. Click **Install** in the dialog Claude Desktop opens.
2. Start a new chat in Claude Desktop and ask "how many open incidents do I have?".
3. The first time, a Chrome window opens on the ServiceNow portal: sign in with Okta there (FastPass or Touch ID).

After that it keeps itself up to date: once a day it checks for a new version, and Claude offers it on an update card
in the chat. Click Update now, then Install in Claude Desktop's dialog; nothing is installed until you do. Running the
same command again also updates.

### If your organisation blocks the extension

If Claude Desktop says "Extension is not approved for your organization", or the installer says your organisation blocks the extension, you can run the same release as a Claude Desktop `mcpServers` entry instead. An entry is a few lines in Claude Desktop's settings that start IT Snow's server directly, without the extension. You get the same tools and update card, and your Okta sign-in carries over: both use the same Chrome profile. You need Google Chrome, as for the extension. Open Terminal and run:

```bash
curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash -s -- --entry
```

Then:

1. Answer the installer's questions. It asks everything before it changes anything. It may offer to install Bun, a small program the entry runs with (with Homebrew on an Apple silicon Mac that has it, otherwise Bun's own release from GitHub, checked before it is installed); if you say no, it stops and nothing is changed. It asks before adding the entry to Claude Desktop's settings, and keeps a backup of them; if you say no, it installs IT Snow and prints the entry for you to add yourself.
2. Quit Claude Desktop (⌘Q) and open it again: it reads its settings only when it starts. The installer never quits it (it opens it if it isn't running), and waits up to 10 minutes until the entry is running.
3. Start a new chat and ask "am I signed in to ServiceNow?". The first time, IT Snow's own Chrome window opens on the ServiceNow portal: sign in with Okta there (FastPass or Touch ID), as with the extension.

It then works like the extension:

- **Updates:** once a day it checks for a new version, and Claude shows the same update card. **Update now** installs the new release itself, beside the one you have: there's no Claude Desktop install dialog for the entry. Then quit and reopen Claude Desktop to start it. **Not now** hides that version for a week.
- **Settings:** the same settings as the extension (Check for updates, Enable extra write tools and Read-only), plus Approvals. They start at their defaults: the entry doesn't read what you set in the extension. Ask Claude to "show my IT Snow settings": a card shows them, and you change them there. They apply when you quit and reopen Claude Desktop. If you changed one in the extension (for example turned on Read-only, or turned off Check for updates), set it again on this card.
- **Write tools:** as in the extension, Claude can file an incident, comment and resolve, and the extra write tools (approvals, catalog orders, record patches and raw API writes) are off until you turn on **Enable extra write tools** on the settings card. **Read-only** turns every write off.
- **Approvals:** by default ("In the chat", as in the extension), each write is first a dry run that shows what it would change, and ServiceNow changes only when Claude repeats it with `confirm: true`. Claude Desktop may also ask your permission before a write tool runs, depending on its tool permissions. For a check that is yours alone, set **Approvals** to "On an approval card" on the settings card: each change then waits on a card that shows exactly what it will do, with Approve and Decline.
- **Keep only one** of the extension and the entry switched on, or Claude sees every tool twice.
- **Remove:** run the same command with `--uninstall` added at the end (`... | bash -s -- --entry --uninstall`), then quit and reopen Claude Desktop. It removes the entry, after a backup of Claude Desktop's settings, and the installed release. To remove everything, also delete the folder `~/Library/Application Support/it-snow` (your sign-in, settings and `writes.jsonl`; the extension uses it too), the download folder `~/.it-snow-server`, and the backups of Claude Desktop's settings (`claude_desktop_config.json.bak-…` in `~/Library/Application Support/Claude`). A Bun the installer put in `~/.bun/bin` stays too.

If you'd rather not run the installer, see [Install the entry by hand](#install-the-entry-by-hand). If something goes wrong, see [Troubleshooting](#troubleshooting).

## Install: for AI agents

These steps are for an AI agent installing this for someone, not for people. Installing it yourself? Use the steps
above.

Run every installer command exactly as shown, starting with `set -o pipefail;`: without it, a download that fails still exits 0. Empty output, or only a `curl: (N) …` line, means nothing ran. A `Next:` line may show an installer command, without `set -o pipefail;` or in the form for people: don't run it as shown, but run the matching command from these steps instead.

1. **Check the machine.** Continue only if `uname -s` prints `Darwin` and both `/Applications/Claude.app` and `/Applications/Google Chrome.app` exist. Otherwise tell the user what is missing.
2. **Run the installer** with this one command. It downloads the extension, checks its SHA-256 (nothing changes before the check passes) and opens Claude Desktop's install dialog. With no terminal it never prompts and answers no to every question, and `--no-wait` makes it exit once the dialog is open. Exit 0 means it finished its steps, not that Claude Desktop installed the extension. Exit 1 means it stopped, with the reason on stderr. If the reason is that the user's organisation blocks the extension ("… but your organisation blocks it"), switching it on can't help: ask the user, then follow the steps for the mcpServers entry below.

```bash
set -o pipefail; curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --no-wait
```

3. **Hand over to the user.** Ask them to click Install in the dialog Claude Desktop opened. You can't do it for them. Never ask for a password or a token: nothing in the install needs one.
4. **Verify.** Run `set -o pipefail; curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --status`; it changes nothing. It should print `Ready: yes`; otherwise its `Next:` line says the one thing left to do. It doesn't say who is signed in: ask the user to start a new chat and ask "am I signed in to ServiceNow?". The first time, IT Snow's own Chrome window opens on the ServiceNow portal, and only the user can sign in with Okta there. If its `claude_extension_state:` line says `blocked`, follow the steps for the mcpServers entry below instead.
5. **Write tools.** Filing an incident, commenting and resolving work, each a dry run until confirmed; the extra write tools start off. Only the user turns them on (Enable extra write tools, in the extension's settings): never change a setting for them.
6. **Updates look after themselves.** Once a day the extension checks for a new version and Claude shows the user an update card. Only the user can click Update now and then Install; to update straight away, run the install command again.

### If the user's organisation blocks the extension

These steps are for an AI agent installing the entry for someone, not for people. Without a terminal the installer asks nothing, so you ask the user, and you act only on their answers. Never ask for a password or a token: nothing here needs one.

Run every installer command exactly as shown here, starting with `set -o pipefail;`. Without it, a download that fails still exits 0. Empty output, or only a `curl: (N) …` line, means nothing ran: tell the user, and try again later. A `Next:` line, or a refusal, may show an installer command, without `set -o pipefail;` or in the form for people. Don't run it as shown: run the matching command from these steps, with only the flags the user agreed to.

1. Run `set -o pipefail; curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --status`. It changes nothing. Continue only if its `claude_extension_state:` line says `blocked` (Claude Desktop shows "Extension is not approved for your organization"), or the user asks for the entry. If its `chrome:` line says `missing`, ask the user to install Google Chrome first: IT Snow signs in through it either way.
2. Read the `bun:` line. It shows where Bun is and its version, or says `not installed` and how the installer would install it. If Bun is not installed, ask the user whether you may install it, and say how: with Homebrew on an Apple silicon Mac that has it (`brew install bun`), otherwise Bun 1.4.4 from Bun's own GitHub release, checked against a SHA-256 pinned in the installer, into `~/.bun/bin` (shell profiles aren't changed, and a Bun that is already there is never replaced). Add `--install-bun` only if they agree, and never install Bun any other way. If they say no, stop: the entry can't run without Bun. If the line shows a Bun older than 1.3.0, the installer stops with exit 1 and says how to update it (`brew upgrade bun`, or `<that bun> upgrade`): ask the user before you update Bun, and never do it unasked.
3. Ask the user whether the installer may add the `it-snow` entry to Claude Desktop's `claude_desktop_config.json`. It keeps a backup, and every other entry and setting in the file. If the `entry:` line says `Claude Desktop's it-snow entry runs something else`, say that this entry will be pointed at the IT Snow release instead (its `env` settings are kept). `--yes` stands for this go-ahead, and only this. If the `entry:` line says `Claude Desktop's config can't be read as JSON`, stop and tell the user: the installer doesn't change a file it can't read.

Then run this, adding `--install-bun` if the user agreed to install Bun:

```bash
set -o pipefail; curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --entry --yes --no-wait
```

It checks everything before it changes anything. Exit 0 means it finished its steps (the release installed, the entry added or pointed), not that Claude Desktop runs the entry yet. Exit 1 means it stopped, with the reason on stderr. Without Bun and without `--install-bun`, or without `--yes`, it prints "Nothing was changed" and the flag that is missing: add that flag to the command above only with the user's go-ahead. Any other non-zero exit, with a `curl: (N) …` line, means the download failed and nothing ran. If it says `brew install bun failed`, stop and tell the user: they install Bun themselves (https://bun.sh, 1.3.0 or later), then you run the command again.

Ask the user to quit Claude Desktop (⌘Q) and open it again: it reads its config only when it starts. Never quit it yourself: you may be running inside it. If you are, hand over now and do the check below in the new chat.

Then run the `--status` command again. It should print `Ready: yes`, an `entry_server: running since …` line, and `entry: release X.Y.Z, in Claude Desktop's config as it-snow`, where X.Y.Z is the version on its `latest:` line, with no `update:` line. Otherwise do what its `Next:` line says, with the commands from these steps. Then ask the user to start a new chat in Claude Desktop (a chat opened before the entry ran never gets its tools) and ask "am I signed in to ServiceNow?". The first time, IT Snow's own Chrome window opens on the ServiceNow portal, and only the user can sign in with Okta there.

What the installer does: with `--install-bun` and no Bun, it installs Bun as above. It downloads the same release as the extension (`latest.mcpb`) and checks its SHA-256, then runs that release's own installer, which installs it in `~/Library/Application Support/it-snow/server`. It then adds the `it-snow` entry to `~/Library/Application Support/Claude/claude_desktop_config.json`: a backup first, every other key, the keys' order, non-ASCII text and the file's permissions kept, an existing entry's `env` kept, and a file it can't read as JSON left alone. As with any JSON tool, a key made only of digits moves to the front and a number too long for JavaScript is rounded, and `--entry --uninstall` can leave an empty `"mcpServers": {}`. It never quits Claude Desktop.

- **Settings start at their defaults.** The entry doesn't read the extension's settings; only the sign-in carries over (both use the same Chrome profile). Ask the user whether they changed any setting in the extension (for example Read-only on, or Check for updates off). If they did, they set it again on the entry's settings card (`now_settings`, or ask Claude to "show my IT Snow settings").
- **Write tools:** filing an incident, commenting and resolving work as in the extension. The extra write tools (approvals, catalog orders, record patches and raw API writes) start off. Only the user turns them on, on the settings card: never change a setting for them.
- **Approvals** are "In the chat" by default, as in the extension. Nothing on the server asks the user: each write is a dry run until it is called with `confirm: true`, and Claude Desktop may show its own permission prompt. Show the user the dry run, and confirm only what they agreed to. With **Approvals** set to "On an approval card", each change also waits for the user on a card.
- **Updates:** the update card's **Update now** installs the new release beside the running one, with no Claude Desktop dialog; the user then quits and reopens Claude Desktop to start it. You can't click the card for them. Running the `--entry` command above again also updates.
- **Settings in the entry's `env`** win and are locked on the settings card: `IT_SNOW_CHECK_UPDATES`, `IT_SNOW_EXTRA_WRITES`, `IT_SNOW_READONLY` and `IT_SNOW_APPROVALS`. None is a secret. Otherwise the card saves settings in `~/Library/Application Support/it-snow/settings.json`.
- **Tools missing from the chat:** Claude Desktop keeps tool permissions by connector name, so an earlier connector called `it-snow` can hide some tools. Ask the user to open Customize > Connectors > `it-snow` and set the tool groups to Needs approval or Always allow.
- **Remove,** with the user's go-ahead: `set -o pipefail; curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --entry --uninstall --yes`. It removes the entry (keeping a backup) and the installed release. It keeps the folder `~/Library/Application Support/it-snow` (sign-in, settings, `writes.jsonl`), the download folder `~/.it-snow-server`, the backups of `claude_desktop_config.json` (`.bak-…` beside it) and Bun: delete those only if the user asks. The user then quits and reopens Claude Desktop.

## Install the entry by hand

If you'd rather not run the installer, you can set up the mcpServers entry yourself. You need Google Chrome and [Bun](https://bun.sh) 1.3.0 or later (`brew install bun`). In Terminal, in a new, empty folder, run:

```bash
curl -fsSLO https://wpp-jamie-mills.github.io/it-snow-site/latest.mcpb
curl -fsSLO https://wpp-jamie-mills.github.io/it-snow-site/latest.mcpb.sha256
shasum -a 256 -c latest.mcpb.sha256
unzip -q latest.mcpb -d bundle
bun --no-env-file bundle/dist/install-release.js --bundle latest.mcpb --sha256 "$(cut -d ' ' -f 1 latest.mcpb.sha256)"
```

`shasum` must print `latest.mcpb: OK`; if it doesn't, stop. The last command is the release's own installer: it checks the bundle again, installs it in `~/Library/Application Support/it-snow/server`, and prints the entry to add. It doesn't change Claude Desktop's settings.

Then back up Claude Desktop's settings, `~/Library/Application Support/Claude/claude_desktop_config.json`, for example by copying it to `claude_desktop_config.json.bak` beside it. Add the `"it-snow"` entry the installer printed inside the file's `"mcpServers"` object (add `"mcpServers": {}` if there isn't one). It looks like this, with your home folder in `command`:

```json
"it-snow": {
  "command": "/Users/<you>/Library/Application Support/it-snow/server/it-snow-mcp",
  "args": [],
  "env": {"MCP_RUN_MODE": "config", "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
}
```

If your Bun isn't in `~/.bun/bin`, `/opt/homebrew/bin` or `/usr/local/bin`, put its folder first in `PATH`, or the entry stops with "Bun not found". Check the file with `python3 -m json.tool < ~/Library/Application\ Support/Claude/claude_desktop_config.json`: one invalid file stops every Claude Desktop server. Then quit Claude Desktop (⌘Q), open it again, start a new chat and ask "am I signed in to ServiceNow?". You can delete the folder you downloaded into.

The entry then works as the installer's does, with the settings card and the update card. To remove it, delete the `"it-snow"` entry from the file, quit and reopen Claude Desktop, and delete `~/Library/Application Support/it-snow/server`.

## What you can do

IT Snow puts your ServiceNow queue, knowledge base and catalog inside the conversation. Ask what is open on you, what an approval is waiting for, which request is stuck, or whether anyone has already reported the thing you are about to report.

- **Your work** — requests, requested items (RITMs), incidents and approvals, all in one answer
- **Any record** — by number or `sys_id`, from any table you can read, with structured filters and paging
- **The conversation** — read Additional comments and Work notes, and add a comment
- **Files** — list attachments and download one to disk
- **Knowledge** — search published articles and read the full body
- **Catalog** — find an item and see the variables it needs before ordering
- **People** — look up a colleague, their title, department and manager
- **Assets** — the hardware assigned to you
- **Writes** — file an incident through the portal form so its Description is filled in, comment on a ticket, resolve one

## Sign in

IT Snow uses a dedicated Chrome profile, not an API credential. The first time a tool needs ServiceNow, a Chrome window opens on the portal: complete Okta (FastPass or Touch ID) there, then the session is kept in the profile and reused on every start.

`now_login` shows a sign-in card in the chat. Its button opens Chrome again, the card polls until the sign-in completes, and then reports who is signed in. Nothing is ever typed into the card.

The window must stay alive. Minimise it if you like, but quitting Chrome ends the session; call `now_login` to start again.

## Configuration

| Setting | Default | Meaning |
| --- | --- | --- |
| `IT_SNOW_URL` | `https://prodwpp.service-now.com` | Instance base URL |
| `IT_SNOW_PORTAL` | `/sp` | Portal path used to pick up the session |
| `IT_SNOW_READONLY` | `false` | Refuse all writes |
| `IT_SNOW_EXTRA_WRITES` | `false` | Enable approvals, orders, patches, raw writes |
| `IT_SNOW_HIDE` | `minimize` | Idle window: `minimize`, `offset`, `none` |
| `IT_SNOW_LOGIN_BOUNDS` | `160,120,1200,820` | Where the window appears for sign-in |
| `IT_SNOW_HEADLESS` | `false` | Headless cannot complete Okta sign-in |
| `IT_SNOW_EXECUTABLE` | autodetected | Chrome binary |
| `IT_SNOW_DATA_DIR` | OS app-data dir | Profile, `daemon.json`, `writes.jsonl` |
| `IT_SNOW_CHECK_UPDATES` | set by the extension | Daily update check |
| `IT_SNOW_APPROVALS` | `chat` | The mcpServers entry only: `chat` (as in the extension: each write is a dry run until confirmed, and Claude Desktop's own permission prompt) or `auto` (each write also waits on an approval card) |

## Tools

Every tool the server has, in the extension and in the mcpServers entry. With the default settings, Claude can call 30 of them in the extension: the read tools, the write tools, `now_login` and `check_for_updates`. ✅ = enabled write, 🔒 = refused until you turn on **Enable extra write tools**. **Card only** tools are called by a card's buttons, and Claude Desktop doesn't offer them to Claude.

**Read**

| Tool | What it does |
| --- | --- |
| `now_status` | Session state, Chrome presence, signed-in user |
| `now_whoami` | Your ServiceNow profile |
| `now_query` | Structured query: filters, ordering, fields, paging |
| `now_count` | Aggregate count, optionally grouped |
| `now_get_record` | One record, or up to 50 in one call, by number or `sys_id`; the table is inferred from the prefix |
| `now_search` | Full-text search across tasks |
| `now_my_requests` | Catalog requests (`scope=caller\|opened\|watching\|assigned\|all`) |
| `now_my_items` | Requested items / RITMs (`scope`) |
| `now_my_incidents` | Incidents you called in, opened, watch or are assigned (`scope`) |
| `now_my_approvals` | Approvals waiting on you |
| `now_my_open_work` | Open incidents, requests, RITMs and approvals in one answer (scope-aware) |
| `now_request_details` | A request with its RITMs, approvals and comments |
| `now_comments` | Journal: Additional comments and Work notes |
| `now_attachments` | Files on a record |
| `now_attachment_get` | Download one file |
| `now_kb_search` | Search knowledge articles |
| `now_kb_article` | Read one article |
| `now_catalog_search` | Find catalog items |
| `now_catalog_item` | Item plus its variables |
| `now_find_person` | User by name, email or username |
| `now_my_assets` | Hardware assigned to you |

**Write**

| Tool | What it does |
| --- | --- |
| `now_add_comment` ✅ | Append an Additional comment |
| `now_create_incident` ✅ | File an incident through a portal form; Description filled, result checked |
| `now_resolve_incident` ✅ | Resolve with close code and notes |
| `now_update_record` 🔒 | Patch any record |
| `now_approve` 🔒 | Approve or reject |
| `now_order_catalog_item` 🔒 | Place a catalog order, or submit a record producer |
| `now_api` 🔒 | Raw `/api/...` escape hatch |

**Sign-in, updates and settings**

| Tool | What it does |
| --- | --- |
| `now_login` | Sign-in card (opens Chrome on the portal) |
| `now_login_start` | Card only: the sign-in card's button, which opens Chrome on the portal |
| `now_login_status` | Card only: the sign-in card checks whether the sign-in has completed |
| `check_for_updates` | Only with **Check for updates** on: shows the update card |
| `install_update` | Card only, with **Check for updates** on: downloads and verifies the new version, then opens Claude Desktop's installer (the extension) or installs it beside the running one (the entry) |
| `snooze_update` | Card only, with **Check for updates** on: doesn't offer this version for a week |
| `now_settings` | The mcpServers entry only: the settings card (Check for updates, Enable extra write tools, Read-only, Approvals) |
| `now_save_settings` | The mcpServers entry only. Card only: saves the settings card |

**Approval cards** (the mcpServers entry only, with **Approvals** set to "On an approval card")

| Tool | What it does |
| --- | --- |
| `now_approve_held_write` | Card only: the approval card's Approve, which runs the change you approved |
| `now_decline_held_write` | Card only: the approval card's Decline, which drops the change |

## Security and privacy

- No password is stored anywhere. The Okta session lives in a dedicated Chrome profile, exactly as it would in a browser.
- The update check fetches `latest.version` from the landing page once a day; nothing about you is sent. Only **Update now** downloads the bundle, and its SHA-256 is verified first. For the extension, Claude Desktop's own install dialog then asks you; for the mcpServers entry, **Update now** installs it beside the running copy.
- Attachments are downloaded with the browser session's own permissions; nothing is uploaded.
- Requests go only to `prodwpp.service-now.com` and the landing page. There is no telemetry.
- Writes are limited to the three tools above, unless you turn on **Enable extra write tools**, and recorded in `writes.jsonl`.
- `install.sh --entry` changes Claude Desktop's `claude_desktop_config.json` only with your go-ahead, and only its own `it-snow` entry, after a backup. It installs Bun only with your go-ahead: with Homebrew, or Bun's GitHub release checked against a SHA-256 pinned in the installer. It never quits Claude Desktop.
- The installer's SHA-256 check catches a damaged or partial download, not a compromised site: the checksum and the installer come from the same site. Read `install.sh` before you run it if that matters to you.
- Report a security problem directly to the maintainer through their GitHub profile, https://github.com/wpp-jamie-mills, not in a public issue. Include what you saw and how to repeat it; leave tokens and personal data out.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `Chrome: missing` | Install Google Chrome, then call `now_status` again |
| `Okta sign-in required` | Session expired: `now_login`, complete the sign-in, retry |
| A write returns 200 but nothing changed | The field is read-only; the result's `ignored` list names it |
| `403 User Not Authorized` | Table or row ACL. Not a bug |
| Comments look empty in raw JSON | Read `display_value`, not `value` |
| Chrome won't start | Another Chrome holds the profile: quit it, delete `daemon.json`, retry |
| Tools missing in an old chat | Open a new chat; Claude attaches tools at chat start |
| Extension shows as failed, disconnects at start-up | Versions before 0.2.2 used Playwright 1.65, which exits under Claude Desktop's built-in Node 18. Install 0.2.2 or later |
| Update card says checksum mismatch | Pages can lag a release by minutes; try again shortly |
| "Extension is not approved for your organization" | Your organisation blocks the extension, and switching it on doesn't help. Run the same release as an mcpServers entry instead: see [If your organisation blocks the extension](#if-your-organisation-blocks-the-extension) |
| The Okta sign-in in IT Snow's Chrome window is refused, with a message about your organisation's policy | Your organisation's sign-in policy doesn't allow it. Nothing on your Mac can change that, and the mcpServers entry signs in the same way as the extension |
| `brew install bun` failed while installing the entry | Run `brew doctor` and fix what it reports, or install Bun yourself from https://bun.sh (1.3.0 or later), then run the `--entry` command again |
| The entry's tools are missing from the chat | Start a new chat after reopening Claude Desktop. If some are still missing, Claude Desktop kept the tool permissions of an earlier connector with the same name: open Customize > Connectors > `it-snow` and set the tool groups to Needs approval or Always allow |
| Every tool appears twice | The extension and the entry are both on. Switch one off: the extension in Settings > Extensions, or the entry with the `--entry` command and `--uninstall` |
| The entry doesn't start | Run the installer with `--status` (`... \| bash -s -- --status`): its `entry_server:` and `Next:` lines say what is wrong. Claude Desktop's log for it is `~/Library/Logs/Claude/mcp-server-it-snow.log`; read it from its last `Initializing server...` line. Claude Desktop starts two processes for the entry, one for chats and one for agent mode: that is normal |
| "Bun not found" in the entry's log | Run the `--entry` command again and let it install Bun, or install Bun yourself (`brew install bun`, or from https://bun.sh) |
| Claude Desktop's settings file looks different after the installer changed it | The installer rewrites `claude_desktop_config.json` as JSON tools do: a key made only of digits moves to the front, a number too long for JavaScript is rounded, and removing the entry can leave an empty `"mcpServers": {}`. Everything else is kept, and the backup beside it (`claude_desktop_config.json.bak-…`) has the file as it was |
| The entry is gone after a restart | Something rewrote Claude Desktop's settings file. Quit Claude Desktop (⌘Q) first, then run the `--entry` command again: the installer opens Claude Desktop itself when it is done |
| You want the entry without the installer | See [Install the entry by hand](#install-the-entry-by-hand) |

---

<sub>Generated from the project README for version 0.6.1. It is rebuilt automatically with each release.</sub>
