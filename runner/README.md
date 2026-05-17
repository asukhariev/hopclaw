# HopClaw runner

Long-running Node.js poller for the lab Windows VM. Polls [hop.agtc.app](https://hop.agtc.app) every 5 s for Start / Stop commands, drives MR4 export, uploads the CSV/SLK to Vercel Blob.

## Quick start (on the Windows lab kit)

```powershell
# 1. Clone the repo (or extract a release zip)
git clone https://github.com/asukhariev/hopclaw.git C:\hopclaw-runner
cd C:\hopclaw-runner\runner

# 2. Install deps (Node 20+ required)
npm install

# 3. Configure
notepad .env
#   HOPAPP_URL=https://hop.agtc.app
#   RUNNER_API_KEY=<paste the same value you set in Vercel>
#   BLOB_READ_WRITE_TOKEN=<from the Vercel Blob store>
#   HOPCLAW_DIR=C:\hopclaw

# 4. Run (foreground, for testing)
node --env-file=.env index.js
```

## Run as a Windows service (production)

Use [nssm](https://nssm.cc/) — non-sucking service manager. One-time:

```powershell
nssm install hopclaw-runner "C:\Program Files\nodejs\node.exe"
nssm set    hopclaw-runner AppParameters "--env-file=C:\hopclaw-runner\runner\.env C:\hopclaw-runner\runner\index.js"
nssm set    hopclaw-runner AppDirectory "C:\hopclaw-runner\runner"
nssm set    hopclaw-runner Start SERVICE_AUTO_START
nssm start  hopclaw-runner
```

Survives reboots, restarts on crash.

## What it does (v0)

| Command from hop.agtc.app | Runner action |
| --- | --- |
| `start`  | Posts `status: recording` back. Technician drives MR4 manually. |
| `stop`   | Posts `status: exporting`, picks the latest `.slk`/`.csv` from `HOPCLAW_DIR`, posts `status: uploading`, PUTs to Vercel Blob, posts `status: done` with file URL. |
| `noop`   | Sleeps another `POLL_MS` ms and re-polls. |

## What v0 deliberately doesn't do

- It does NOT yet drive MR4 itself (clicking Export → CSV → Save Folder → OK). The PowerShell helpers for that are in [`hopclaw/scripts/`](../scripts/) (`click-button.ps1`, `send-enter-to-mr4.ps1`, `click-coords.ps1`). The hook is `driveExport()` in `index.js` — drop the real PS calls there.
- It does NOT yet watch the Measure tab for auto-detected "recording stopped". That needs the OpenClaw vision loop + the `interface-map.md` + `prompts/watch-mr4.md` we have.

Both are real but separate work, layered on top of the proven upload pipeline.
