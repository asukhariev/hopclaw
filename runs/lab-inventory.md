# HopClaw lab-PC inventory — 2026-05-29

On-site engineer pass on the **real HOP Studio lab laptop**. Phase 1 (inventory) and
Phase 3 (read-only UIA dump + proposal) are complete. **Phase 2 (running an export) was
intentionally NOT executed — see the blocker section.** All actions in this pass were
read-only: no clicks or keystrokes were injected into MR4, no settings changed, nothing deleted.

- Repo: `C:\hopclaw-runner` (git, branch `main`, up to date with `origin/main`).
- Runtime dir: `C:\hopclaw` (exports + markers + deployed script).
- `git pull` at start: **Already up to date.**
- Working tree had pre-existing uncommitted changes (left untouched): `M runner/index.js`,
  `M scripts/drive-export.ps1`, untracked `runner/package-lock.json`. These are the
  1600×900 / auto-chain modifications described in `C:\hopclaw\HANDOFF.md` and are NOT mine.

---

## Phase 1 — Inventory

### MR software
| Field | Value |
|---|---|
| Product | Noraxon myoRESEARCH **MR4** |
| Exact version | **4.0.106** (NOTE: interface-map.md and the lab spec reference 4.0.124 — this box is 4.0.106) |
| Process name | `noraxon.mr` |
| PID (this pass) | 12268, started 2026-05-29 10:05:22 |
| Window title bar text | **`Noraxon MR 4.0.106`** |
| Window state now | **Minimized** (IsIconic=True, parked off-screen at -32000,-32000) |
| Install path / .exe | not resolved this pass (process was minimized; did not probe further to stay read-only). `list-mr4-windows.ps1` keys off process name `noraxon.mr`. |

**Usable UI without sensors?** Yes — the proven path runs entirely against existing
**Database** records (the `MyoMetrics Demo Record` / `Video Running Analysis` record), so a
live sensor stream is not required to export. MR4 opens to a usable UI without a recording.

**Receiver connected now?** **YES — sensors/receiver present.** Two USB devices enumerate as
`Noraxon Device` (Status OK). So a Noraxon receiver/dongle is physically attached right now.
(Presence ≠ active recording, but it raises the recording-risk bar — see blocker.)

### Display
| Field | Value |
|---|---|
| Native resolution | **1600 × 900** |
| Monitors | 1 (`\\.\DISPLAY1`, primary) |
| DPI / scaling | 96 DPI / **100%** |
| Matches proven script? | The **deployed** `drive-export.ps1` was re-mapped to **1600×900** on 2026-05-23 and its resolution guard (`$expectedW=1600`) **MATCHES** this machine. **It does NOT match the 1440×900 baseline named in the task brief** (the brief predates the re-map). |

### Runtime
| Field | Value |
|---|---|
| Node | **v24.16.0** |
| npm | **11.13.0** |
| openclaw | **NOT on PATH; no daemon, no service, no process** — OpenClaw is designed but not installed/wired here |
| Runner as nssm service | **NO** — no `hopclaw`/`nssm` service registered |
| Runner process running now | **NO** — no `node` process is currently running (nothing is polling right now) |
| Runner can reach + auth cloud | **YES** — `GET /api/runner/poll` with the `.env` Bearer key → **HTTP 200 `{"type":"noop"}`** |
| Runner env vars | Loaded from `C:\hopclaw-runner\runner\.env` (present), NOT OS env. `.env` keys present: HOPAPP_URL, RUNNER_API_KEY (64 chars, SET), BLOB_READ_WRITE_TOKEN (62 chars, SET), HOPCLAW_DIR, POLL_MS. As OS env vars all four are UNSET (by design — runner uses `--env-file`). Secrets not printed. |
| Scheduled task `HopClawDriveExport` | **Registered, State=Ready.** Last run 2026-05-23 18:16:30, LastTaskResult **0 (success)**. |

### Folders & markers
- `C:\hopclaw` ✔  `C:\hopclaw\exports` ✔
- `C:\hopclaw\drive-export.ok` ✔ (points at the last exported `.slk`)
- `C:\hopclaw\drive-export.err` — **absent** (good; last run succeeded)
- `C:\hopclaw\drive-export.log` ✔ (last run transcript, 2026-05-23 18:16, SUCCESS, 65 MB file)
- `C:\hopclaw\exports\` holds **6 `.slk` files** (~65 MB each) from the 2026-05-23 validation.
  > NOTE: the proven/deployed path actually exports **Excel `.slk`** (menu item "Excel SLK"),
  > NOT the "Export Data to Single CSV Files" that interface-map.md / watch-mr4.md target.
  > The CSV path is documented but unproven on this box.

### Network
| Target | Result |
|---|---|
| `https://hop.agtc.app/api/runner/poll` (no auth) | **HTTP 401** (reachable, auth required — expected) |
| same, with `.env` Bearer key | **HTTP 200 `{"type":"noop"}`** |
| Vercel Blob host (`*.public.blob.vercel-storage.com`) | **HTTP 400** (reachable) |
| A real uploaded blob object from runner.log (HEAD) | **HTTP 200, Content-Length 65508815** — upload pipeline confirmed end-to-end retrievable |

### Remote access
| Field | Value |
|---|---|
| OpenSSH **Server** (sshd) | **NOT installed / NOT running.** Only `ssh-agent` exists, and it is **Stopped + Disabled**. No listener on port 22/2222. **SSH-from-Mac is currently NOT possible.** |
| Hostname | **DESKTOP-856EQA5** |
| Username | **Admin** |
| LAN IP | **192.168.1.207** (Wi-Fi) |
| AnyDesk | **Running** (4 processes). **AnyDesk ID: 1492512877** (no alias set). `--get-id` CLI returned empty; ID read from `system.conf`. |

---

## Phase 2 — Verify the proven path  →  STOPPED (not executed)

**I did not run an export.** Three independent reasons, any one of which is a check-in blocker
under the safety rules:

1. **Resolution does not match the brief's baseline.** The brief says the proven script assumes
   **1440×900** and instructs: if the machine does not match, DO NOT run the coordinate script,
   report the mismatch, and stop. This machine is **1600×900**. (The *deployed* script was
   silently re-mapped to 1600×900 on 2026-05-23 and would pass its own guard — but that is a
   divergence from the brief I was given, so I am surfacing it rather than acting on it.)
2. **Sensors are connected.** Two `Noraxon Device` USB receivers are attached. Firing
   coordinate clicks/keys on a clinical machine with sensors present is exactly the high-risk
   action the safety rules gate.
3. **I cannot confirm MR4's state.** MR4 is **minimized**, and its UI is invisible to UI
   Automation (see Phase 3), so I cannot verify "Database tab, a record selectable, NO live
   recording" without restoring the window and injecting clicks. The rules say: when uncertain,
   screenshot, log, STOP — so I stopped.

Artifacts captured this pass (in `runs/`):
- `phase1-desktop.png` — full desktop (foreground was the browser/agent; MR4 was minimized).
- `phase1-mr4-window.png` — PrintWindow capture of MR4 (160×28; it is minimized).

**To unblock Phase 2 I need confirmation from you** (see chat summary). The most likely correct
path is: "yes, 1600×900 is the validated resolution now — proceed," after a human confirms MR4 is
on Database with a record selected and no patient recording is in progress.

---

## Phase 3 — Foundation for many workflows (proposal only; nothing built)

### UI Automation reality check (ran `dump-mr4-uia.ps1`, read-only)
**MR4's UI is effectively invisible to UI Automation.** The dump found **8 total elements in the
process and 0 named elements** — no Database tab, no record rows, no Export button, no menu items.
MR4 renders its own UI (OpenGL), so there are no UIA AutomationIds/Names to click.

**Consequence:** the goal of "replace hardcoded pixel coordinates with resolution-independent UIA
clicks" is **NOT achievable** for MR4's main window. Resolution-independent automation here must
come from one of:
- **Vision (OpenClaw / Claude-on-screenshots)** — the `prompts/watch-mr4.md` design. Robust to
  layout/resolution but needs OpenClaw installed (currently absent) and per-cycle model cost.
- **Template/anchor image matching** — locate the Export button etc. by image, click relative.
  No new dependency beyond an image-match lib; resolution-tolerant within reason.
- **Coordinate maps keyed by resolution** — keep pixel clicks but store one calibrated map per
  resolution and assert the live resolution before running (what the script half-does today).

This finding should be recorded as the architectural fork before any workflow registry is built.

### Proposed `workflows/` registry (do NOT build yet)
One spec per export type / assessment, so HopClaw can be told "run workflow X" instead of carrying
one hardcoded click path. Sketch:

```
workflows/
  _schema.md                  # the spec contract (fields below)
  export-single-csv.yml       # MR4 S4 item "Export Data to Single CSV Files"
  export-separate-csv.yml     # S4 "Export Data to Separate CSV Files"
  export-excel-slk.yml        # S4 "Export Records to Excel (*.slk)"  <-- the only PROVEN one today
  export-c3d.yml              # S4 "Export Records to C3D Files"
  export-matlab.yml           # S4 "Export Records to (*.mat) MatLab Files"
```

Each spec would declare:
- `id`, `description`, `mr4_menu_item` (verbatim S4 label from interface-map.md)
- `assessment_types` it applies to (e.g. Running Analysis, Bilateral Gait, Chair-Stand…)
- `state_path` (the S3→S4→S5→S6→S8→S9 sequence it expects)
- `target_dir` (default `C:\hopclaw\exports`)
- `filename_rule` (e.g. `yyMMdd_HHmmss_<subjectId>_<technicianId>` per the SOP wiki)
- `selector_strategy`: `pixel@1600x900` | `vision` | `template-match` (the fork above)
- `verify`: expected output extension + min size + landing dir
- `on_overwrite`, `timeout_s`, `safety: { abort_if_measure_tab: true, require_record_selected: true }`

A small dispatcher would pick the spec by command from `hop.agtc.app`, assert the live resolution
matches `selector_strategy`, and run it. This keeps the proven SLK path as `export-excel-slk.yml`
while the CSV / vision variants are added and validated one at a time.

---

## Top blockers to clear (summary)
1. **Resolution mismatch vs the brief (1600 vs 1440)** — confirm 1600×900 is now the source of truth.
2. **No SSH server** — install/enable OpenSSH Server (port 22) if you want to drive this over SSH from the Mac. AnyDesk (ID 1492512877) is the only remote channel up right now.
3. **Runner not running + not a service** — start it (or install via nssm) for the cloud loop to be live.
4. **CSV path unproven** — only `.slk` has been validated end-to-end; the documented CSV menu item has not.
5. **UIA is blind** — pick the resolution-independent strategy (vision vs template-match) before scaling to many workflows.
