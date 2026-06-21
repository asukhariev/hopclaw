# On-Site Action Plan — Therii PC, Day 1

> First in-the-wild test of HopClaw on the actual lab Windows PC. VPS run is green; this trip proves it on real hardware with the real Noraxon hardware + technician workflow.

**Date:** 2026-05-23
**Location:** HOP Studio (Therii PC)
**Goal:** Walk away with a repeatable Start → Record → Stop → Export → Upload loop on the lab kit. If repeatable without error, we're in a position to talk contract with Joao.

---

## 0. Hard constraints — do not deviate

| Constraint | Why | How to enforce |
| --- | --- | --- |
| **Display resolution = 1440 × 900 native** | All click coords in `scripts/drive-export.ps1` are hardcoded for this size. The script self-aborts at line 44 if it sees anything else. | Set it on the PC monitor *before* anything else. If the PC's native panel is higher, use a custom resolution / scaled mode that reports 1440×900 to Windows. |
| **MR4 version = 4.0.124** | Validated build. Different versions = different button positions. | `Help → About` in MR4. Snapshot it. |
| **MR4 launched and Database tab reachable from one click** | Step 2 of the export script assumes MR4 is the foreground window. | Pin MR4 to taskbar, launch it before kicking the runner. |
| **`C:\hopclaw\exports\` exists and is writable** | Export script writes the file there; runner reads it. | `mkdir C:\hopclaw\exports` on first install. |
| **One MR4 record selectable at coord (685, 192)** | Hardcoded "first record row" click. | Make sure at least one Bilateral Gait record exists in the DB before testing. |

---

## 1. What to bring

- This repo cloned on the Mac M1 (`~/hopclaw` or similar) so you can `git pull` mid-session
- Laptop charger + USB hub
- Phone with hotspot (in case studio wifi is captive-portal'd)
- The Vercel Blob token + `RUNNER_API_KEY` (matches what's set in `hop.agtc.app` Vercel project). Either keep them in 1Password or have a temp note ready to paste into `.env` on the PC.
- Notepad for noting any coord drift / surprises

---

## 2. Arrival → first-30-minutes checklist (do this with the on-PC Claude agent driving)

Paste the prompt block below into the **Claude agent running on the Therii PC** verbatim. It encodes the resolution lockdown and full install.

### Prompt block A — "prep the PC" (paste to PC's Claude agent)

````
You are setting up the HopClaw runner on this Windows PC for the first time.
Repo: https://github.com/asukhariev/hopclaw  (clone to C:\hopclaw-runner)

Hard requirements before you do anything else:
1. Set the primary display to EXACTLY 1440x900. Verify with:
     Add-Type -AssemblyName System.Windows.Forms
     [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
   If it doesn't say 1440x900, change Windows Display Settings (or set a
   custom resolution via Intel/NVIDIA control panel) and re-verify.
   DO NOT proceed until this prints 1440x900.

2. Confirm MR4 version is 4.0.124 (Help -> About). If different, STOP and
   report back. Do not auto-upgrade.

3. Make sure C:\hopclaw\exports\ exists and is writable.

4. Install Node 20+ if missing:
     winget install OpenJS.NodeJS.LTS
   Verify: node -v should be >= 20.

5. Clone the repo and install deps:
     git clone https://github.com/asukhariev/hopclaw.git C:\hopclaw-runner
     cd C:\hopclaw-runner\runner
     npm install

6. Create C:\hopclaw-runner\runner\.env with these values (ask me to
   paste the secret values; do NOT invent them):
     HOPAPP_URL=https://hop.agtc.app
     RUNNER_API_KEY=<I will paste>
     BLOB_READ_WRITE_TOKEN=<I will paste>
     HOPCLAW_DIR=C:\hopclaw
     POLL_MS=5000

7. Register the scheduled task that drives the export:
     powershell -ExecutionPolicy Bypass -File C:\hopclaw-runner\scripts\register-drive-export-task.ps1
   Then test the task can be triggered (without MR4 open yet, expect it to fail
   on the resolution/window check — that's fine, we just want to confirm
   schtasks /Run /TN HopClawDriveExport returns success exit code).

8. Report back when each step is done. STOP at step 1 if resolution is wrong.
````

You (on the Mac) shadow this from the M1 — when it asks for secrets, paste them. When it reports each step done, ack and continue.

---

## 3. Phase-by-phase workflow

### Phase 1 — Connect PC to the web app (no real device yet)

**What "connecting" means here:** the runner process on the PC is polling `hop.agtc.app/api/runner/poll` with the shared `RUNNER_API_KEY`. There is no UI pairing step — successful authenticated polls = connected.

**Steps:**
1. On the PC, in a foreground PowerShell (so you can see logs):
   ```powershell
   cd C:\hopclaw-runner\runner
   node --env-file=.env index.js
   ```
2. Watch for `HopClaw runner starting` + a repeating `Command: {type: 'noop'}` every 5 s. **That's "connected."**
3. From the Mac, open `https://hop.agtc.app`, click **Start** on a test session. Within 5 s the runner should log `Command: {type: 'start', session_id: '...'}` and the web UI should flip to `status: recording`.

✅ **Pass criteria:** Round-trip works in both directions (start + stop), even with no real export. (Stop will fail at export step — that's fine here, we just want to see the runner pick up the command.)

### Phase 2 — Dry-run export workflow with existing canned record

**Pre-req:** MR4 open on the Therii PC at 1440×900, at least one record in the DB at row position (685, 192).

1. Open MR4, navigate to Database tab once manually, click anywhere off any modal — leave it in a neutral state.
2. From the web app on the Mac, click **Start**, then **Stop** on the test session.
3. The runner will trigger `HopClawDriveExport` scheduled task → PS script runs the 10-step click sequence → file lands in `C:\hopclaw\exports\` → runner uploads to Vercel Blob → web app shows the download link.

✅ **Pass criteria:**
- `C:\hopclaw\drive-export.ok` written (not `.err`)
- New file in `C:\hopclaw\exports\` > 1 KB
- Web app shows `status: done` + clickable file link
- Downloading the link gives a valid CSV/SLK

❗ **If any click misses:**
- Take a screenshot (`scripts/screenshot.ps1` → `C:\hopclaw\screenshot.png`)
- The most common cause is resolution drift. Re-check `[Screen]::PrimaryScreen.Bounds`.
- Second cause: MR4 wasn't focused. Click on the MR4 title bar and re-run.
- Worst case: coordinates need rebinding for this monitor. See "Coordinate rebinding" below.

### Phase 3 — Hook up the real Noraxon device and update Start/Stop semantics

Right now the runner's `handleStart()` just posts `status: recording` and waits. The technician records in MR4 manually. With the real device on the subject:

1. Open MR4 → Measure tab → confirm sensors are paired and streaming.
2. Walk through one capture *manually* (no automation) to confirm the device + MR4 + technician are happy. Note the wall-clock duration of a typical capture.
3. Now run Start from the web app — technician begins capture in MR4. Run Stop from the web app when capture is done — the runner kicks the export sequence (Phase 2) against this fresh record.

We may need to update `handleStart`/`handleStop` if the technician's workflow needs different behavior (e.g. auto-click "Start recording" in MR4 on Start). Note any deltas here:

- [ ] Does technician want Start button to also click MR4's "Start measure"? (Coordinates for Measure tab live in `scripts/drive-measure.ps1` — already drafted, not yet wired.)
- [ ] Does Stop need to first stop MR4 recording before exporting? (Probably yes — needs a separate PS script.)
- [ ] Filename convention — does Joao want `<timestamp>_<subject>_<technician>.csv`? Currently it's whatever MR4 auto-names.

### Phase 4 — Real export

Same mechanics as Phase 2, but on the freshly-recorded data. Confirm the file is the right size (much bigger than the canned 59 MB? Compare to a manual export.).

### Phase 5 — Upload validation

1. Download the file from the web app's blob URL.
2. Open it in Excel / your viewer of choice. Spot-check that the columns and sample counts match what MR4 would export manually.
3. If column ordering or row counts differ from manual export, capture both files and diff them later.

### Phase 6 — Repeat for confidence

Repeat Phases 3–5 **at least 3 times back-to-back** without restarting the runner. Failure modes we're hunting:
- Stale marker files (`drive-export.ok` not cleared between runs)
- File-name collisions (overwrite confirm dialog handled by step 8.5)
- MR4 focus loss between cycles
- Runner crashes (look at the foreground log; if it's bad, switch to nssm service mode per `runner/README.md`)

✅ **Go/no-go for the Joao contract conversation:** 3 successful Start→record→Stop→export→upload cycles in a row, with downloadable valid files at the end, on the actual lab device. If we get there, we're shipping.

---

## 4. Pre-canned prompts to keep handy

### Prompt B — "drive one full export cycle" (paste to PC's Claude agent)

````
We're testing the full HopClaw loop. Before each cycle:

1. Verify Screen.PrimaryScreen.Bounds is still 1440x900. If not, STOP.
2. Verify MR4 is the foreground window with Home or Database tab visible
   and no modal dialogs open.
3. Clear stale markers:
     Remove-Item C:\hopclaw\drive-export.ok, C:\hopclaw\drive-export.err -ErrorAction SilentlyContinue
4. Confirm the runner process is still polling (look at its console log).
5. Tell me you're ready. I'll click Start then Stop from the web app.

After each cycle, report:
   - Did C:\hopclaw\drive-export.ok appear? If not, cat .err.
   - What file landed in C:\hopclaw\exports\? Size?
   - Did the runner log show 'Uploaded to: https://...'?
   - Did the web app show status: done with a download link?

If any step fails, take a screenshot via scripts/screenshot.ps1, attach it
to your reply, and DO NOT try to "fix" the coordinates yourself.
````

### Prompt C — "coordinate rebinding" (only if Phase 2 misses)

````
The click coordinates in scripts/drive-export.ps1 are missing buttons. We
need to remeasure them at this monitor's actual 1440x900 mapping.

1. Open MR4 fullscreen.
2. Take a screenshot via scripts/screenshot.ps1.
3. Open the screenshot in mspaint, hover each of these elements, and report
   the (x, y) cursor coords from the status bar:
     - Database tab text center
     - First record row center (Bilateral Gait, or whichever record exists)
     - Export button in right sidebar
     - "Export Data to Single CSV Files" menu item (after clicking Export)
     - "Select Folder" button in the folder picker
4. Report the 5 coord pairs back to me. Do NOT edit the script yet — I'll
   patch it from the Mac and push, then you'll git pull.
````

---

## 5. Failure-mode quick reference

| Symptom | First check | Fix |
| --- | --- | --- |
| Runner can't reach `hop.agtc.app` | `Invoke-WebRequest https://hop.agtc.app` | Studio firewall / captive portal. Use phone hotspot. |
| Poll returns 401 | `RUNNER_API_KEY` mismatch | Re-paste from Vercel env vars. |
| `schtasks /Run /TN HopClawDriveExport` fails | Task not registered | Re-run `register-drive-export-task.ps1`. |
| `drive-export.err` says "resolution mismatch" | Display setting drifted | Set 1440×900 again. RDP sessions can reset this. |
| Export script clicks wrong place | Resolution OR MR4 window resized | Maximize MR4, re-verify resolution, retry. If still wrong → Prompt C. |
| Blob upload fails | `BLOB_READ_WRITE_TOKEN` invalid or expired | Re-mint from Vercel Blob store, update `.env`, restart runner. |
| Web app stuck on `exporting` | Runner crashed mid-export | Look at runner console. Session will be marked `failed` after 90 s timeout. Restart runner. |

---

## 6. After the visit — what to log

Before you leave the studio, capture for the post-trip review:
- [ ] Exact PC specs (CPU, GPU, monitor model + native resolution)
- [ ] MR4 exact version string (Help → About screenshot)
- [ ] Final `.env` values (redact secrets, keep the URL/dir paths)
- [ ] Wall-clock duration of: capture, export script, upload — for one full cycle
- [ ] Any coordinate drift from 1440×900 baseline (if you had to rebind)
- [ ] List of things the technician asked for that we don't do yet — fuel for v1

---

## 7. Decision tree at end of day

```
Did 3 cycles pass back-to-back, with valid downloadable files?
├── YES  →  Set up nssm so the runner survives reboot.
│          →  Talk contract with Joao.
│          →  Open v1 backlog: filename convention, auto Start/Stop in MR4,
│             OpenClaw vision fallback, multi-record export.
│
└── NO   →  Capture failing screenshot + runner log + drive-export.log.
          →  Push everything to a `field-report/YYYY-MM-DD/` folder.
          →  Triage on the train home; aim to fix worst offender within 24h.
```

---

## 8. Reference files in this repo (so the PC agent knows where to look)

| File | What it is |
| --- | --- |
| `runner/index.js` | The polling loop (Node, foreground or as nssm service). |
| `runner/README.md` | Install + nssm service instructions. |
| `scripts/drive-export.ps1` | The 10-step click sequence. **All hardcoded coords live here.** |
| `scripts/register-drive-export-task.ps1` | Registers the scheduled task the runner triggers. |
| `scripts/screenshot.ps1` | Capture primary display to `C:\hopclaw\screenshot.png`. |
| `scripts/drive-measure.ps1` | Drafted but not wired — for auto-starting MR4 capture. |
| `interface-map.md` | State machine S0–S10 + visual anchors. Read if coords drift. |
| `prompts/watch-mr4.md` | Vision-based fallback prompt (not yet active in runner). |
| `references/*.png` | Ground-truth MR4 screenshots at 1440×900. Compare against PC screenshots if anything looks off. |
