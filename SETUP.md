# HopClaw — Mac ↔ Windows lab-machine setup runbook

Generic, repeatable procedure to connect a **control Mac** to a **new Windows lab machine**
and verify the box has everything in place for HopClaw automation work (watching the
Noraxon myoRESEARCH UI, exporting, uploading). Written so a Claude session can execute it
end-to-end against any machine — no machine-specific IPs or names are baked in.

> Run this **before** any automation/calibration task on a new device. Calibration
> (e.g. re-anchoring clicks for a different screen resolution) assumes this setup is done.

---

## 0. Mental model (read first)

Two planes, deliberately separated:

| Plane | Lives on | Used for |
| --- | --- | --- |
| **Control plane** | Mac, over **SSH + git** | Run commands on the box, sync code, read logs, trigger tasks — all from the Mac. |
| **GUI plane** | Windows **interactive console session** (viewed via **AnyDesk**) | The actual screenshotting + clicking of the target app. |

**The single most important constraint:** an SSH session is *non-interactive* — it has **no
desktop**. Over SSH you can see processes, files, and services, but **not windows, and you
cannot screenshot or click the GUI.** Anything that touches the app's UI must run in the
**console session**, normally by triggering a **Scheduled Task** (which executes in that
session) from SSH. A screenshot captured from a non-interactive context comes back blank/tiny.

Source-of-truth rule: **the git repo is canonical.** Deployed files (in the deploy dir) are
generated *from* the repo, one-way. Never hand-edit a deployed file. `git pull` at the start
of every session, `commit + push` at the end.

---

## 1. Variables (fill these in per machine — keep them out of the committed doc)

| Placeholder | Meaning | Example shape |
| --- | --- | --- |
| `<WIN_HOST>` | Windows hostname | `desktop-xxxxxxx` |
| `<WIN_USER>` | day-to-day login on the box (often a **standard**, non-admin user) | `admin` |
| `<WIN_ADMIN>` | a real **Administrator** account on the box (for one-time installs) | `Administrador` / `Hoplab` |
| `<TAILNET>` | your Tailscale MagicDNS tailnet suffix | `tailXXXXXX.ts.net` |
| `<MAC_KEY>` | per-machine SSH key path on the Mac | `~/.ssh/hopclaw_<label>` |
| `<REPO_URL>` | the HopClaw git remote | `https://github.com/<org>/hopclaw.git` |
| `<REPO_DIR>` | repo clone path on Windows | `C:\hopclaw-runner` |
| `<DEPLOY_DIR>` | where deployed scripts/exports live on Windows | `C:\hopclaw` |

**Prefer MagicDNS over IPs** everywhere: `<WIN_HOST>.<TAILNET>` survives IP changes and keeps
this doc portable. Get it from the Tailscale app (Devices → the machine → "Tailscale addresses").

---

## 2. Prerequisites (gather before you start)

- [ ] **Admin credentials for the box.** ⚠️ The interactive login (`<WIN_USER>`) is frequently a
      *standard* user with **no elevation token**. Installing OpenSSH Server (and most setup)
      needs a **separate Administrator account** (`<WIN_ADMIN>`) entered at a UAC prompt. Confirm
      you (or the client, e.g. the lab owner) can supply these — otherwise §4 is blocked.
- [ ] **One Tailscale account** used on **both** machines (same tailnet).
- [ ] **Homebrew** on the Mac.
- [ ] **AnyDesk** (or RDP) access to the box for the GUI plane + the one-time elevated step.
- [ ] The **target app installed** on the box (Noraxon myoRESEARCH / MR4). Note its exact version.

---

## 3. Network channel — Tailscale (both machines, same tailnet)

### 3a. Mac  `[MAC]`
```bash
brew install --cask tailscale          # if the final pkg step needs sudo, run this in a real
                                        # Terminal where you can type your Mac password
open -a Tailscale                       # menu-bar icon → Log in → sign in to the tailnet
```
⚠️ **macOS gotcha:** the Tailscale **Network Extension** does *not* enable from the
`System Settings → Login Items & Extensions` toggle. It activates when you log in via the app
and **Allow** the VPN/network-extension prompt. If it refuses: `System Settings → Privacy &
Security` → scroll down → **Allow** the blocked system software, then **reboot** and reopen
the app. Verify:
```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4
```

### 3b. Windows  `[WINDOWS]`
Install Tailscale (`winget install --id tailscale.tailscale -e`, or the installer from
tailscale.com/download — the MSI may prompt for admin), then launch it and **sign in to the
SAME account**, or `tailscale up`.

⚠️ **Windows gotcha:** a **non-admin** `tailscale status` on the box can falsely report
`NeedsLogin` / no `100.x` address even when the system service is fully connected. **Do not
trust it** — verify from the Mac instead (next step), which is authoritative.

### 3c. Verify from the Mac  `[MAC]`
```bash
tailscale status                        # both peers should be listed on the tailnet
tailscale ping <WIN_HOST>               # expect "pong from <WIN_HOST> ..."
```
A `pong` = the tunnel is live regardless of what the Windows CLI claims.

---

## 4. Remote shell — OpenSSH Server on Windows  `[WINDOWS — ELEVATED, one-time]`

⚠️ Must run in an **elevated** PowerShell as `<WIN_ADMIN>`. Over AnyDesk: Start → type
"PowerShell" → **right-click → Run as administrator** → enter `<WIN_ADMIN>` credentials at UAC.
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
# make the SSH default shell PowerShell (so remote commands run in PS, not cmd):
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
Get-Service sshd        # expect Status: Running
```
> If you paste all lines at once and `Start-Service` errors with "service not found", the
> feature install hadn't finished — just re-run `Start-Service sshd; Set-Service -Name sshd
> -StartupType Automatic; Get-Service sshd`.

---

## 5. Key-based auth (so the Mac connects non-interactively)

⚠️ **Password SSH cannot be automated from the Mac terminal** (no TTY to type a password into).
Key auth is mandatory.

### 5a. Mac — make a per-machine key  `[MAC]`
```bash
ssh-keygen -t ed25519 -N "" -C "mac->hopclaw-<label>" -f <MAC_KEY>
cat <MAC_KEY>.pub        # copy this line
```

### 5b. Windows — authorize the key  `[WINDOWS — as <WIN_USER>, no elevation]`
For a **standard** user the key goes in the per-user file:
```powershell
$pub = '<PASTE THE MAC PUBLIC KEY LINE>'
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
Add-Content -Path "$env:USERPROFILE\.ssh\authorized_keys" -Value $pub -Encoding ascii
icacls "$env:USERPROFILE\.ssh\authorized_keys" /inheritance:r /grant "$($env:USERNAME):F" /grant "SYSTEM:F"
```
⚠️ If `<WIN_USER>` is itself an **Administrator**, Windows OpenSSH ignores the per-user file and
reads `C:\ProgramData\ssh\administrators_authorized_keys` instead (ACL: Administrators + SYSTEM
only). The per-user file above is correct for the common standard-user case.

### 5c. Verify from the Mac  `[MAC]`
```bash
ssh -i <MAC_KEY> -o StrictHostKeyChecking=accept-new <WIN_USER>@<WIN_HOST>.<TAILNET> whoami
# expect: <WIN_HOST>\<WIN_USER>
```
(The "post-quantum key exchange" warning some clients print is harmless on a private tailnet.)

---

## 6. Code & config  `[WINDOWS, via SSH from the Mac]`
```powershell
git clone <REPO_URL> <REPO_DIR>
cd <REPO_DIR>\runner ; npm install
Copy-Item .env.example .env            # then fill RUNNER_API_KEY, BLOB_READ_WRITE_TOKEN, HOPAPP_URL
```
⚠️ **Never commit `.env`** or anything with secrets — confirm `.gitignore` covers it.
Re-confirm the source-of-truth rule from §0: edit in the repo → commit → push → deploy; never
hand-edit files in `<DEPLOY_DIR>`.

---

## 7. "Ready for work" check  `[MAC → box, read-only]`

### Running a PowerShell script over SSH cleanly
Quoting through zsh→ssh→PowerShell is painful. Encode the script and use `-EncodedCommand`:
```bash
B64=$(iconv -f UTF-8 -t UTF-16LE <<'PS' | base64 | tr -d '\n'
<your PowerShell here>
PS
)
ssh -i <MAC_KEY> <WIN_USER>@<WIN_HOST>.<TAILNET> "powershell -NoProfile -EncodedCommand $B64"
```

### Recon script (drop it into the pattern above)
```powershell
$ErrorActionPreference='SilentlyContinue'
"== host =="; hostname; whoami
"== interactive sessions =="; try { quser } catch { "none" }   # need an ACTIVE console session for GUI work
"== key processes =="; Get-Process *noraxon*,*myor*,openclaw*,node*,*tailscale*,sshd 2>$null |
  Select ProcessName,Id,@{n='RAM_MB';e={[int]($_.WS/1MB)}} | Sort ProcessName | Format-Table -Auto
"== repo =="; if (Test-Path '<REPO_DIR>\.git') { git -C '<REPO_DIR>' log --oneline -1; git -C '<REPO_DIR>' status -sb } else { "repo missing" }
"== display resolution =="; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
```
Green-light criteria: target app running, an **Active console session** exists, repo present &
in sync, Tailscale/sshd up. (`node`/runner does **not** need to be running for setup.)

### Prove GUI capture works (not a blank frame)
Because of the §0 session boundary, verify a real screenshot via the **console-session**
scheduled-task pattern, then pull the file back over SSH and confirm its size is realistic
(a few hundred KB, not <1 KB). Use the repo's `scripts/screenshot.ps1` /
`setup-screenshot-task.ps1`; trigger with `schtasks /Run /TN <task>` from SSH so it runs in
the interactive session. If the capture is tiny/empty, it ran in the wrong session.

---

## 8. Per-machine calibration (the part that changes between devices)

Every new box can differ in **screen resolution / DPI**, and the target app (MR4) exposes **no
usable UI-Automation tree** (element-name clicking is impossible). So driving it is
**vision + template-image matching**, which is resolution-specific and must be re-anchored
per machine:

1. Record the resolution (recon script above) and **lock the display** to a known value, OR
   plan to recalibrate.
2. Capture fresh **reference screenshots** of each click target at this machine's resolution
   (into `references/` + `runs/`), and update/verify the template anchors.
3. Validate **one** action end-to-end in the console session before trusting any automation.
4. Keep all GUI actions in the console session (scheduled-task dispatch). Never fire blind
   clicks — this is a live clinical machine; a wrong click during a real session is unacceptable.

---

## 9. Hard-won gotchas (quick reference)

- **macOS Tailscale extension** won't enable from the Settings toggle → log in via the app +
  Allow the prompt; may need Privacy & Security → Allow + a reboot.
- **Non-admin `tailscale status` on Windows lies** (`NeedsLogin`) → trust the Mac's `tailscale ping`.
- **The login user is often non-admin** → keep a real `<WIN_ADMIN>` account ready for §4; the
  on-box agent cannot elevate itself.
- **No password SSH from automation** → always key auth (§5).
- **SSH ≠ desktop** → processes visible, GUI not. Screenshots/clicks only in the console session.
- **Repo is source of truth** → one-way deploy, never hand-edit deployed files, never commit `.env`.
- **Use MagicDNS, not IPs.** Use a **per-machine SSH key**.
