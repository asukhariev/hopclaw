#!/usr/bin/env node
/**
 * HopClaw runner — polls hop.agtc.app every POLL_MS for commands, drives
 * MR4 export on the lab Windows VM, uploads the result to Vercel Blob.
 *
 * Env vars (set in .env or shell):
 *   HOPAPP_URL              default https://hop.agtc.app
 *   RUNNER_API_KEY          shared secret; matches RUNNER_API_KEY in hopapp
 *   BLOB_READ_WRITE_TOKEN   Vercel Blob token for direct uploads
 *   HOPCLAW_DIR             default C:\hopclaw   (where MR4 exports land)
 *   POLL_MS                 default 5000
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { put } from "@vercel/blob";

const HOPAPP   = process.env.HOPAPP_URL || "https://hop.agtc.app";
const KEY      = process.env.RUNNER_API_KEY || "";
const BLOB_TOK = process.env.BLOB_READ_WRITE_TOKEN || "";
const DIR      = process.env.HOPCLAW_DIR || "C:\\hopclaw";
const POLL_MS  = Number(process.env.POLL_MS || 5000);

function log(...args) {
  console.log(new Date().toISOString(), ...args);
}

function authHeaders(extra = {}) {
  const h = { "Content-Type": "application/json", ...extra };
  if (KEY) h["Authorization"] = `Bearer ${KEY}`;
  return h;
}

async function poll() {
  const r = await fetch(`${HOPAPP}/api/runner/poll`, { headers: authHeaders() });
  if (!r.ok) throw new Error(`poll http ${r.status}`);
  return r.json();
}

async function postEvent(body) {
  const r = await fetch(`${HOPAPP}/api/runner/event`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(body),
  });
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new Error(`event http ${r.status} ${text}`);
  }
  return r.json();
}

function listSlkAndCsv(dirPath) {
  if (!fs.existsSync(dirPath)) return [];
  return fs
    .readdirSync(dirPath)
    .filter((f) => /\.(slk|csv)$/i.test(f))
    .map((f) => {
      const p = path.join(dirPath, f);
      const st = fs.statSync(p);
      return { name: f, path: p, mtime: st.mtimeMs, size: st.size };
    })
    .sort((a, b) => b.mtime - a.mtime);
}

/**
 * Drive MR4 export via the PowerShell helpers already in C:\hopclaw\.
 * Sequence (assumes MR4 is open on Database tab with record selected):
 *   1. Click Export button (right sidebar)
 *   2. Click "Export Data to Single CSV Files" menu item
 *   3. Enter through filename dialog (accept default)
 *   4. Select Folder on folder picker (assumes C:\hopclaw\exports is target)
 *   5. Yes on overwrite confirm if any
 *   6. Wait for "Please wait..." to clear
 *   7. Enter to close success dialog
 *
 * v0 SHORT-CIRCUIT: if MR4 driving isn't ready, we just pick the latest
 * .slk/.csv already in HOPCLAW_DIR and upload that. Proves the full pipeline
 * end-to-end. Real driving plugs into the same callsite.
 */
async function driveExport() {
  // Trigger the HopClawDriveExport scheduled task (runs in the user's
  // interactive RDP session — required for SendKeys/UI Automation to reach
  // the MR4 window). The PS script writes one of:
  //   C:\hopclaw\drive-export.ok    -> full path to the new file
  //   C:\hopclaw\drive-export.err   -> error message
  const okPath  = "C:\\hopclaw\\drive-export.ok";
  const errPath = "C:\\hopclaw\\drive-export.err";
  const exportDir = path.join(DIR, "exports");

  // Snapshot before — used as fallback if marker file logic misses
  const before = new Set(listSlkAndCsv(exportDir).map((f) => f.name));

  // Clear stale markers
  for (const p of [okPath, errPath]) {
    try { fs.unlinkSync(p); } catch { /* ignore */ }
  }

  log("Triggering MR4 export via scheduled task...");
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawDriveExport"], { encoding: "utf-8" });
  if (trig.status !== 0) {
    throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  }

  // Poll for completion marker (max 90 sec — covers Mesa-rendered MR4 + dialogs)
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (fs.existsSync(okPath)) {
      const newFilePath = fs.readFileSync(okPath, "utf-8").trim();
      log("Export OK:", newFilePath);
      const st = fs.statSync(newFilePath);
      return { name: path.basename(newFilePath), path: newFilePath, mtime: st.mtimeMs, size: st.size };
    }
    if (fs.existsSync(errPath)) {
      const msg = fs.readFileSync(errPath, "utf-8").trim();
      throw new Error(`drive-export reported: ${msg}`);
    }
    await new Promise((r) => setTimeout(r, 2000));
  }

  // Timeout fallback: if there's a brand-new file in the exports dir, use it
  const after = listSlkAndCsv(exportDir);
  const newOnes = after.filter((f) => !before.has(f.name));
  if (newOnes[0]) {
    log("WARN: no marker file but found new export, using it");
    return newOnes[0];
  }
  throw new Error("drive-export timed out (90s) and no new file appeared");
}

async function uploadToBlob(sessionId, filePath) {
  const filename = path.basename(filePath);
  const data = fs.readFileSync(filePath);
  const blobKey = `exports/${sessionId}/${filename}`;
  const contentType = filename.toLowerCase().endsWith(".csv")
    ? "text/csv"
    : "application/octet-stream";
  const { url } = await put(blobKey, data, {
    access: "public",
    contentType,
    token: BLOB_TOK || undefined,
    addRandomSuffix: false,
    allowOverwrite: true,
  });
  return { url, filename, size: data.length };
}

async function handleStop(sessionId) {
  await postEvent({
    session_id: sessionId,
    status: "exporting",
    progress: "Driving MR4 Export -> CSV...",
  });

  const file = await driveExport();
  log("Picked file:", file.path, file.size, "bytes");

  await postEvent({
    session_id: sessionId,
    status: "uploading",
    progress: `Uploading ${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB)...`,
  });

  const uploaded = await uploadToBlob(sessionId, file.path);
  log("Uploaded to:", uploaded.url);

  await postEvent({
    session_id: sessionId,
    status: "done",
    progress: "Available below.",
    file_url: uploaded.url,
    file_name: uploaded.filename,
    file_size_bytes: uploaded.size,
  });
}

async function handleStart(sessionId) {
  // For v0 there's no proactive sensor wiring. We just acknowledge that
  // recording is in progress; the technician drives MR4 themselves.
  await postEvent({
    session_id: sessionId,
    status: "recording",
    progress: "Runner online. Record in MR4, then hit Stop & Export.",
  });
}

async function tick() {
  try {
    const cmd = await poll();
    if (cmd.type === "noop") return;
    log("Command:", cmd);
    if (cmd.type === "start") await handleStart(cmd.session_id);
    if (cmd.type === "stop")  await handleStop(cmd.session_id);
  } catch (err) {
    log("Tick error:", err.message);
  }
}

async function main() {
  log(`HopClaw runner starting`);
  log(`  HOPAPP_URL      = ${HOPAPP}`);
  log(`  HOPCLAW_DIR     = ${DIR}`);
  log(`  POLL_MS         = ${POLL_MS}`);
  log(`  RUNNER_API_KEY  = ${KEY ? "(set)" : "(unset)"}`);
  log(`  BLOB_READ_WRITE_TOKEN = ${BLOB_TOK ? "(set)" : "(unset)"}`);
  for (;;) {
    await tick();
    await new Promise((r) => setTimeout(r, POLL_MS));
  }
}

main().catch((err) => {
  log("Fatal:", err);
  process.exit(1);
});
