# IT Snow

**Work your ServiceNow tickets from Claude, through the Okta session you already have. No API account, no OAuth client, no admin ticket.**

Version **0.3.0** · macOS · Claude Desktop · extension

- [Install: for people](#install-for-people)
- [Install: for AI agents](#install-for-ai-agents)
- [What you can do](#what-you-can-do)
- [Security and privacy](#security-and-privacy)
- [Troubleshooting](#troubleshooting)

---

## Install: for people

Open Terminal and run:

```bash
curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | bash
```

After that it keeps itself up to date: once a day it checks for a new version, and Claude offers it on an update card
in the chat. Click Update now, then Install in Claude Desktop's dialog; nothing is installed until you do. Running the
same command again also updates.

## Install: for AI agents

Use these steps if you are an AI agent installing this for a user.

1. **Check the machine.** macOS with Google Chrome and Claude Desktop 2.7032.0 or later.
2. **Run the installer** with this one command. It downloads the release, checks its SHA-256 (nothing runs before the check passes) and installs it. With no terminal it never prompts and answers no to every question. It exits non-zero, with the reason on stderr, if anything fails.

```bash
curl -fsSL https://wpp-jamie-mills.github.io/it-snow-site/install.sh | IT_SNOW_INSTALL_TTY=/dev/null bash -s -- --no-wait
```

3. **Verify.** Run the installer again with `--status` (after `bash -s --`). It should print Chrome: present and either the signed-in user or Next: sign in from the chat.
4. **Updates look after themselves.** Once a day the extension checks for a new version and Claude shows the user an update card. Only the user can click Update now and then Install; to update straight away, run the install command again.

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
- **Writes** — file an incident, comment on a ticket, resolve one

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

## Security and privacy

- No password is stored anywhere. The Okta session lives in a dedicated Chrome profile, exactly as it would in a browser.
- The update check fetches `latest.version` from the landing page once a day; nothing about you is sent. Only **Update now** downloads the bundle, and its SHA-256 is verified before Claude Desktop is asked to install it.
- Attachments are downloaded with the browser session's own permissions; nothing is uploaded.
- Requests go only to `prodwpp.service-now.com` and the landing page. There is no telemetry.
- Writes are limited to the three tools above and recorded in `writes.jsonl`.

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

---

<sub>Generated from the project README for version 0.3.0. It is rebuilt automatically with each release.</sub>
