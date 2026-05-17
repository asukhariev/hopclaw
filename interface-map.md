# MR4 interface map

Validated against **MR 4.0.124** on AWS EC2 Windows Server 2022 + Mesa3D 26.0.7 software OpenGL (with `MESA_GL_VERSION_OVERRIDE=4.6FC`). End-to-end export confirmed 2026-05-17 with `Bilateral Gait (7-IMU, 4-EMG, FDM-T).slk` (59 MB) landing in `C:\hopclaw\`.

## Window chrome (always present when MR4 is up)

- **Title bar:** `Noraxon MR 4.0.124` (top-left). Standard Windows controls top-right (min/max/close).
- **Brand strip:** `NORAXON` text logo, top-left, just below title bar, on dark teal/black background.
- **Top tab bar (right-aligned):** `Home` · `Measure` · `Database` · `View` · `Report`. The selected tab has a brighter underline/icon highlight.

Use the title bar text + the top tab bar as the always-on anchor that confirms "we are inside MR4."

---

## State catalog

### S0 — Cold-start license dialog
- **Title:** "Upgrade license | Noraxon MR"
- **Body:** "The software can be started N times within 30 days."
- **Buttons:** `Quit` · `Activate` · **Start** (green, default)
- **HopClaw action:** Press `Enter` (selects the default Start button).
- **Anchor reference:** captured during cold-launch runs (see `runs/<ts>-mr4-launch/`).

### S1 — Version-update prompt (occasional)
- **Title:** "Noraxon MR"
- **Body:** "A new version 4.2026.2 is available at the Noraxon web site."
- **Buttons:** `Skip this version` · `Remind me later` · **More info** (green, default)
- **HopClaw action:** Click `Remind me later` (or Tab → Enter). Do NOT click More info (opens browser).

### S2 — Home tab — application picker (idle baseline)
- **Selected tab:** Home (top, with home icon)
- **Body:** grid of large square tiles — Free Capture · Biofeedback · Symmetry · Gait · Powers Running · Jump · Balance · Mobility (more below the fold).
- **Right sidebar:** "Free Capture Protocols" (or whichever application is selected), a Subject dropdown (default: "MyoMetrics Demo Record" for our test box), and a large green **MEASURE** button bottom-right.
- **HopClaw action:** This is the idle waiting state when a recording is NOT in progress and the technician hasn't navigated to Database. HopClaw does nothing here unless triggered to export.
- **Reference:** `references/01-mr4-home-main-ui.png`

### S3 — Database tab — subject list (export-ready landing)
- **Selected tab:** Database
- **Breadcrumb:** `Home (Mobility, 30-Second Chair Stand) > Subject Database`
- **Three-column layout:**
  - Left: **Subjects** table (columns: Last Name, First Name, Size). Row "MyoMetrics Demo Record / / 36.1 MB" visible.
  - Middle: **Records** table (columns: #, Name, Date Measured, Size). Row "1 | Bilateral Gait (7-IMU, 4-EMG, FDM...) | 4/11/2024 21:52 | 36.1 MB".
  - Right: **Subject Database** sidebar with:
    - Reference Database button
    - Tags group: Filter / Add / Remove
    - Operations group: Use Checkmarks / Recompress Videos / Duplicate
    - **Data Transfer group: Import / Export** ← HopClaw's target button
- **HopClaw action:** Verify a subject row and a record row are selected (highlighted). If yes, click the **Export** button in the right sidebar.
- **Reference:** `references/02-mr4-database-export-dropdown.png` (with Export dropdown open) / `references/03-mr4-database-selected.png` (just the selected state).

### S4 — Export dropdown menu
Same as S3 but a context-style menu has appeared from the Export button. Items (top to bottom):
1. Export to External Location
2. Export Records to Another Subject
3. Export Records to Text Files (Legacy)
4. **Export Records to CSV Files (Legacy)**
5. Export Records to Excel (*.slk) Files
6. Export Records to (*.mat) MatLab Files
7. Export Records to (*.mat) MatLab Files (Legacy)
8. Export Pressure Data to XML
9. Export MyoMotion Data to Biovision BVH
10. Export Medilogic data to CSV
11. **Export Data to Separate CSV Files**
12. **Export Data to Single CSV Files** ← HopClaw production target (one CSV per session)
13. Export Records to C3D Files
14. Export Records to C3D Files (...)
15. Export Report Statistics to ...
16. Export Report Data to Separate ...

- **HopClaw action:** Click **Export Data to Single CSV Files** (one combined CSV per session — easiest for Hoplab cloud ingest).

### S5 — Filename input dialog
- **Title:** "Export To CSV (record '<record name>')" — or "Export To Excel" if user picked SLK
- **Body:** "Please enter name for the output file; the file extension .csv will be added automatically."
- **Input field:** Output file name = the record name pre-filled and selected (e.g. `Bilateral Gait (7-IMU, 4-EMG, FDM-T)`)
- **Buttons:** Cancel · **Ok** (green, default)
- **HopClaw action:** Press `Enter` to accept default name (or paste a structured name like `<ISO timestamp>_<subject_id>_<technician_id>` per the wiki SOP).

### S6 — "Choose directory" folder picker (standard Windows dialog)
- **Title:** "Choose directory."
- **Layout:** standard Windows folder browser. Address bar at top showing path. Left tree (This PC / Desktop / Documents / Downloads / etc.). Center listing. Bottom "Folder:" text field. Buttons "Select Folder" / "Cancel".
- **HopClaw action:**
  1. If the address bar already shows the configured target folder (e.g. `C:\hopclaw\exports\`) → click **Select Folder**.
  2. Otherwise, type the path into the Folder field at the bottom OR navigate via the tree, then click **Select Folder**.
- **Reference:** screenshot 5 in 2026-05-17 export run.

### S7 — Overwrite-confirm dialog (only if file already exists)
- **Title:** (none visible)
- **Body:** `File '<full path>' already exists. Do you want to overwrite it?`
- **Buttons:** No · **Yes** (green, default)
- **HopClaw action:** Press `Enter` to overwrite (production HopClaw should generate timestamped filenames so this dialog is rare; if it appears, overwrite is safe).

### S8 — "Please wait..." progress dialog
- **Title:** (none)
- **Body:** "Please wait ..." with an indeterminate progress bar.
- **HopClaw action:** Wait. Re-screenshot every 2 sec. When this state is no longer detected, proceed to S9.
- **Timeout policy:** if still in S8 after 60 sec, abort cycle and flag for human review (export hang).

### S9 — "Record(s) exported." success dialog
- **Title:** "Export"
- **Body:** "N record(s) exported."
- **Buttons:** **OK** (default)
- **HopClaw action:** Press `Enter`. Then notify the file-watcher process that a new CSV is ready at the expected path.

### S10 — Measure tab (recording in progress) — NOT YET MAPPED
The actual production trigger for HopClaw is "recording just finished" — that lives in the Measure tab. We have not yet captured the Measure-tab states (recording / paused / stopped) because we have no Ultium sensors in the cloud VM. To map these, either:
- Vítor sends a screen recording of an actual session, OR
- We capture during a real HOP Studio visit.

For v0 cloud testing, HopClaw can be triggered on-demand against existing Database records (which is what we just validated end-to-end).

---

## State transitions (happy path, on-demand export)

```
S2 (Home idle)
   |  click "Database" tab
   v
S3 (Database, record selected)
   |  click "Export" in right sidebar
   v
S4 (Export dropdown open)
   |  click "Export Data to Single CSV Files"
   v
S5 (Filename dialog)
   |  Enter
   v
S6 (Folder picker)
   |  Select Folder (current = target)
   v
S8 (Please wait...)        <-- (S7 overwrite if file exists, then S8)
   |  ~2-3 sec
   v
S9 (Success: "1 record(s) exported.")
   |  Enter
   v
S2/S3  (back to baseline)
```

## Negative cases — do NOT act when

- Title bar text is not "Noraxon MR" → wrong window, abort cycle.
- The Measure tab is selected (S10) → recording flow, HopClaw should not interfere.
- Any unfamiliar modal dialog → screenshot, log, flag for human review, do nothing.
- Subject or record row not highlighted in S3 → cannot determine what to export, abort.

## Open follow-ups

- Re-validate the same flow against **Export Data to Single CSV Files** specifically (we used .slk for proof-of-concept).
- Capture S10 (Measure tab in recording / paused / stopped states) — requires sensors or screen recording from Vítor.
- Confirm the title strings for S5 and S7 when CSV (not SLK) is chosen.
- Configure HopClaw with a pre-set target folder (e.g. `C:\hopclaw\exports\`) so S6 collapses to a single Select Folder click.
- Inject structured filenames in S5 (`<ISO timestamp>_<subject_id>_<technician_id>`) per the SOP wiki.
