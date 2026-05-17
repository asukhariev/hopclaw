# HopClaw — Variant A scaffold

OpenClaw-driven bot that watches Noraxon MR3 inside a Windows 11 VM, waits for the export-ready state, clicks File → Export → CSV, and (later) uploads the CSV to Hoplab cloud.

**Canonical workflow doc:** [wiki-hopclaw-workflow](https://agtc.app/dashboard/projects/a7e1dec2-354e-426c-9049-0193ec5911cc) — how Claude and OpenClaw split the work.

**Task:** HopClaw MVP — watch MR3, auto-export & upload (Variant A) — `88931131-1ffc-432e-ae1d-f455084541db`

## The loop, in one diagram

```
┌─────────── Mac (Claude) ───────────┐         ┌────── Windows 11 VM (OpenClaw) ──────┐
│                                    │         │                                       │
│  references/  ←── user drops 5    │         │   MR3.exe  (the target lab app)      │
│  interface-map.md   screenshots   │         │      ↑                                │
│  prompts/watch-mr3.md ──────────►│ shared  │ ←──┘  screenshots every N seconds    │
│                                    │ folder  │   vision model classifies state      │
│  runs/ ◄────────────────────────── │ (UTM)   │   acts: File → Export → CSV         │
│   Claude reads screenshot+JSON     │         │   writes runs/<ts>/screenshot.png    │
│   refines the prompt               │         │            + decision.json           │
│                                    │         │                                       │
└────────────────────────────────────┘         └───────────────────────────────────────┘
```

## Where to start

| You're at... | Read first | Then do |
| --- | --- | --- |
| Fresh repo, no VM yet | `notes/vm-setup.md` | Install UTM, Windows 11, MR3 |
| MR3 installed in VM | `references/README.md` | Capture the 5 reference screenshots |
| References dropped | (Claude) `interface-map.md` | Claude reads refs and writes the map |
| Map written | (Claude) `prompts/watch-mr3.md` | Claude writes the multimodal prompt |
| Prompt ready | `scripts/bootstrap.ps1` | Run inside VM to install Node + OpenClaw |
| OpenClaw running | `runs/README.md` | Trigger first cycle, Claude reviews output |

## File layout

```
hopclaw/
├── README.md             ← this file (index)
├── notes/
│   └── vm-setup.md       ← UTM / Win 11 / MR3 install runbook
├── references/           ← USER drops MR3 screenshots here
│   └── README.md         ← capture checklist
├── interface-map.md      ← CLAUDE writes after references arrive
├── prompts/
│   └── watch-mr3.md      ← CLAUDE writes; OpenClaw loads
├── scripts/
│   └── bootstrap.ps1     ← one-shot Windows install
└── runs/                 ← OpenClaw writes per-cycle artifacts
    └── README.md         ← artifact format spec
```
