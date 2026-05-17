# MR3 reference screenshots

This folder is where **you (the human)** drop screenshots of MR3 in known states. Claude reads each PNG from here to author the interface map and the OpenClaw prompt — Claude cannot see the VM live, so this is the one irreducible human eyeball step.

## Capture checklist

After MR3 is installed in the Windows VM, take a screenshot of each state below and save it in this folder with the exact filename. On Mac: `Cmd-Shift-4`, drag a box around the MR3 window, the PNG lands on your Desktop — drag it here and rename.

| Filename | State | What should be visible |
| --- | --- | --- |
| `01-just-opened.png` | MR3 cold start | Main window after first launch, no session loaded, default empty state |
| `02-recording-in-progress.png` | Mid-recording | Live waveform animating, Stop button active in toolbar, timestamp counter incrementing |
| `03-recording-stopped.png` | **Export-ready target state** | Recording finished, waveform finalized (static), Stop greyed out, Record re-enabled, status bar idle |
| `04-file-menu-open.png` | File menu opened | File menu dropped down showing the Export option |
| `05-export-csv-dialog.png` | CSV export dialog | The confirm dialog after clicking Export → CSV, ready to save |

**Bonus (helpful but optional):**
- `99-no-hardware-warning.png` — if MR3 throws a "no Ultium receiver detected" modal on launch, capture it. Tells us whether Phase 0 needs escalation.
- `99-error-state.png` — anything weird that could trip the watcher.

## What happens after you drop them here

1. Ping Claude: "references are in."
2. Claude reads each PNG, writes `interface-map.md` with verbal landmarks per state (toolbar layout, waveform region, status bar text, negative cases).
3. Claude writes `prompts/watch-mr3.md` — a multimodal prompt referencing both the verbal map AND the reference images as visual anchors for OpenClaw.

## Notes

- Crop tight to the MR3 window — chrome from UTM or Windows doesn't help and can confuse the vision model.
- If MR3's UI looks different on your machine vs. what's documented, capture what you actually see. Reality wins.
- If you can't reach a state (e.g. can't record without a sensor), drop a `phase-0-blocker.png` of the failure modal — that's a Phase 0 escalation signal, not a missing screenshot.
