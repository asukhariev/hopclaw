# HopClaw v0 — Windows 11 ARM VM in UTM (setup notes)

**Host**: Andrii's M1 Mac, macOS 26.4.1
**VM software**: UTM 4.7.5 (free, open source, Apple Silicon native)
**Guest OS**: Windows 11 ARM build 26100 (24H2)
**ISO**: `~/Desktop/26100.4349.250607-1500.ge_release_svc_refresh_CLIENTCONSUMER_RET_A64FRE_en-us.iso` (4.9 GB)

## Step-by-step (first-time create)

1. UTM opens with welcome screen → click **"Create a New Virtual Machine"** (or the **+** button in the toolbar).
2. Choose **"Virtualize"** (NOT Emulate — Virtualize uses Apple Virtualization Framework; Emulate would be x86-on-ARM and 10× slower).
3. Choose **"Windows"**.
4. On the Windows config screen:
   - ☐ **Import VHDX Image** — leave UNCHECKED (we have ISO, not VHDX)
   - ☑ **Install Windows 10 or higher** — keep checked
   - ☑ **Install drivers and SPICE tools** — keep checked (needed for shared clipboard / shared folders / smooth display)
   - **Boot ISO Image** → Browse → select the ISO at `~/Desktop/26100.4349...iso`
5. Hardware screen:
   - **Memory**: 8192 MB (8 GB) — gives Windows breathing room for MR3 + OpenClaw
   - **CPU Cores**: 4 (default)
   - **Enable hardware OpenGL acceleration**: optional, leave default
6. Storage screen:
   - **Storage size**: 64 GB (default fine)
7. Shared Directory:
   - **Path**: `/Users/andriysuharev/Documents/Claude/Projects/HOPLAB/hopclaw/` — so the VM can see our shared files (MR3 installer can be dropped here later)
8. Summary:
   - **Name**: `HopClaw Win11`
   - ☑ **Open VM Settings** — tick this so we can review after
9. Click **Save**.
10. Click the play (▶) button to boot the VM.

## Windows installer walk-through

Once the VM boots from the ISO:
1. Language/keyboard prompts — pick English (or whatever) → Next
2. Click **"Install Now"**
3. **"I don't have a product key"** → skip (Windows runs unactivated for dev/test fine; eventually need a key for permanent use)
4. Pick edition: **Windows 11 Pro** (more dev features than Home)
5. Accept license
6. **Custom install (Advanced)** → choose the 64 GB disk → Next
7. Wait ~10-20 min for file copy + reboot

## OOBE (Out-of-Box Experience) workaround for offline account

Windows 11 default OOBE forces a Microsoft account login. To bypass for a local-only dev account:
1. When you reach the "Let's connect you to a network" screen
2. Press `Shift + F10` to open Command Prompt
3. Run: `oobe\BypassNRO`
4. VM reboots, OOBE restarts
5. Now there's a "I don't have internet" option → click that → create a local account

## After Windows is up

1. Inside the VM, open File Explorer → "This PC" → look for the shared folder (should be a network share or mapped drive once SPICE tools install)
2. Copy `noraxon.mr.3.8.30.exe` from the shared folder to the Windows Desktop
3. Right-click → "Run as administrator" (MR3 installer probably wants admin)
4. Follow MR3 installer (Next / Next / Accept / Install)

## Phase 0 experiment (after MR3 installed)

1. Launch MR3 from Start menu or Desktop icon
2. **Observe**: does it open the main UI? Show a chart/recording area? Or does it complain "no Ultium receiver detected" and refuse?
3. Try clicking around — File menu, View menu, Settings
4. If the Export/Save dialogs are reachable WITHOUT a session loaded → great, HopClaw has navigation targets
5. If MR3 refuses to do anything without hardware → escalate (Vítor for sensor loan, or accept that v0 is blocked and pivot to v1 HOP Studio visit)

Record outcome in `runs/phase-0.md`.

## After Phase 0 (if green)

1. Install Node.js 24 LTS inside Windows: download installer from `nodejs.org` (or use winget: `winget install OpenJS.NodeJS.LTS`)
2. Open PowerShell/cmd → `npm install -g openclaw`
3. `openclaw onboard --install-daemon`
4. Write the watcher-loop prompt in `prompts/watch-mr3.md` (on Mac, accessible via shared folder)
5. Run first see+click test against MR3 UI
