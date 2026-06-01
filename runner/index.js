#!/usr/bin/env node
/**
 * HopClaw runner — long-polls hop.agtc.app for jobs (lab_runner evaluation
 * steps), drives the MR4 export on the lab Windows machine, uploads the result
 * to Vercel Blob, and reports step events back.
 *
 * Env vars (set in .env or shell):
 *   HOPAPP_URL              default https://hop.agtc.app
 *   RUNNER_API_KEY          shared secret; matches RUNNER_API_KEY in hopapp
 *   BLOB_READ_WRITE_TOKEN   Vercel Blob token for direct uploads
 *   HOPCLAW_DIR             default C:\hopclaw   (where MR4 exports land)
 *   POLL_MS                 default 500
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { put } from "@vercel/blob";

const HOPAPP   = process.env.HOPAPP_URL || "https://hop.agtc.app";
const KEY      = process.env.RUNNER_API_KEY || "";
const BLOB_TOK = process.env.BLOB_READ_WRITE_TOKEN || "";
const DIR      = process.env.HOPCLAW_DIR || "C:\\hopclaw";
const POLL_MS  = Number(process.env.POLL_MS || 500);
// Active MR4 "OPENDATA" database whose persons store we read for the find check.
const MR4_DB_DIR = process.env.MR4_DB_DIR || "C:\\Users\\Admin\\Desktop\\Noraxon MR data HOP Lab";

// Long-poll tuning. The server holds /api/runner/poll open until a job is
// ready or ~25s passes; the runner re-polls immediately on each response.
const LONG_POLL_TIMEOUT_MS = 30_000; // client abort; must exceed the server's ~25s hold
const IDLE_FLOOR_MS = POLL_MS;       // min gap only if the server returns fast (pre-deploy short-poll)
const ERROR_BACKOFF_MS = 2000;       // back off after a failed poll/handle
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function log(...args) {
  console.log(new Date().toISOString(), ...args);
}

function authHeaders(extra = {}) {
  const h = { "Content-Type": "application/json", ...extra };
  if (KEY) h["Authorization"] = `Bearer ${KEY}`;
  return h;
}

async function poll() {
  // Long-poll: the server holds this request open until a job is ready (or
  // ~25s elapses). Abort a bit past the server's deadline so a dead connection
  // can't hang the loop forever.
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), LONG_POLL_TIMEOUT_MS);
  try {
    const r = await fetch(`${HOPAPP}/api/runner/poll`, {
      headers: authHeaders(),
      signal: ctrl.signal,
    });
    if (!r.ok) throw new Error(`poll http ${r.status}`);
    return r.json();
  } finally {
    clearTimeout(timer);
  }
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
 * Triggers the HopClawDriveExport scheduled task (runs in the interactive
 * session — required for SendKeys/UI Automation to reach the MR4 window),
 * then waits for the .ok / .err marker file.
 */
async function driveExport() {
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

async function uploadToBlob(keyPrefix, filePath) {
  const filename = path.basename(filePath);
  const data = fs.readFileSync(filePath);
  const blobKey = `exports/${keyPrefix}/${filename}`;
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

/**
 * Drive MR4 measure-start: navigate to the gait|running protocol and (only if
 * armed via C:\hopclaw\measure.go) click MEASURE. Navigation-only by default —
 * a real recording never starts unless the box is explicitly armed.
 */
async function driveMeasure(target) {
  const okPath  = "C:\\hopclaw\\drive-measure.ok";
  const errPath = "C:\\hopclaw\\drive-measure.err";
  for (const p of [okPath, errPath]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  fs.writeFileSync("C:\\hopclaw\\measure.target", target === "running" ? "running" : "gait", "ascii");
  log(`Triggering MR4 measure-start (target=${target}; nav-only unless measure.go armed)...`);
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawDriveMeasure"], { encoding: "utf-8" });
  if (trig.status !== 0) throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (fs.existsSync(okPath)) return fs.readFileSync(okPath, "utf-8").trim();
    if (fs.existsSync(errPath)) throw new Error(`drive-measure reported: ${fs.readFileSync(errPath, "utf-8").trim()}`);
    await new Promise((r) => setTimeout(r, 1500));
  }
  throw new Error("drive-measure timed out (60s)");
}

let currentStepId = null;

/** Execute one lab_runner step: drive the MR4 export, upload it, attach the file. */
async function handleStep(job) {
  currentStepId = job.step_id;

  // Measure-start: navigate MR4 to the gait|running protocol (+ gated MEASURE).
  if (job.action === "mr4_measure") {
    const target = (job.config && job.config.target) || "gait";
    await postEvent({ step_id: job.step_id, progress: `Navigating MR4 to the ${target} protocol…` });
    const result = await driveMeasure(target);
    await postEvent({
      step_id: job.step_id,
      status: "done",
      progress: result,
      result: { target, at: new Date().toISOString() },
    });
    return;
  }

  if (job.action !== "mr4_export") {
    throw new Error(`unknown lab_runner action: ${job.action}`);
  }

  await postEvent({ step_id: job.step_id, progress: "Driving MR4 Export -> CSV..." });

  const file = await driveExport();
  log("Picked file:", file.path, file.size, "bytes");

  await postEvent({
    step_id: job.step_id,
    progress: `Uploading ${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB)...`,
  });

  const uploaded = await uploadToBlob(job.evaluation_id, file.path);
  log("Uploaded to:", uploaded.url);

  await postEvent({
    step_id: job.step_id,
    status: "done",
    progress: "Available below.",
    result: { uploaded_at: new Date().toISOString() },
    file: { url: uploaded.url, name: uploaded.filename, size_bytes: uploaded.size },
  });
}

// ── Subject jobs: find / create an MR4 Subject for a customer ─────────────────
let currentSubjectCustomerId = null;

async function postSubjectEvent(body) {
  const r = await fetch(`${HOPAPP}/api/runner/subject-event`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(body),
  });
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new Error(`subject-event http ${r.status} ${text}`);
  }
  return r.json();
}

/** Read MR4's persons store (shared-read) via the PowerShell helper -> JSON. */
function listMr4Subjects() {
  const r = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", `${DIR}\\mr4-subjects.ps1`, "-Db", MR4_DB_DIR, "-Json"],
    { encoding: "utf-8" }
  );
  if (r.status !== 0) throw new Error(`mr4-subjects failed: ${r.stderr || r.stdout}`);
  const out = (r.stdout || "").trim();
  if (!out || out.startsWith("NO_PERSONS_DIR")) return [];
  try {
    const j = JSON.parse(out);
    return Array.isArray(j) ? j : [j];
  } catch {
    return [];
  }
}

/** Drive the create-subject scheduled task; returns the proof screenshot path. */
async function driveSubjectCreate(subjectName) {
  const okPath = `${DIR}\\drive-subject.ok`;
  const errPath = `${DIR}\\drive-subject.err`;
  const proofPath = `${DIR}\\subject-5-created.png`;
  for (const p of [okPath, errPath]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  fs.writeFileSync(`${DIR}\\subject.name`, subjectName, "ascii");
  fs.writeFileSync(`${DIR}\\subject.go`, "1", "ascii");
  log("Triggering MR4 subject create:", subjectName);
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawDriveSubject"], { encoding: "utf-8" });
  if (trig.status !== 0) throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  try {
    const deadline = Date.now() + 60_000;
    while (Date.now() < deadline) {
      if (fs.existsSync(okPath)) return proofPath;
      if (fs.existsSync(errPath)) throw new Error(`drive-subject: ${fs.readFileSync(errPath, "utf-8").trim()}`);
      await sleep(1500);
    }
    throw new Error("drive-subject timed out (60s)");
  } finally {
    try { fs.unlinkSync(`${DIR}\\subject.go`); } catch { /* ignore */ }
    try { fs.unlinkSync(`${DIR}\\subject.name`); } catch { /* ignore */ }
  }
}

/** Drive the select-subject scheduled task; returns true if found+selected. */
async function driveSubjectSelect(subjectName) {
  const okPath = `${DIR}\\select-subject.ok`;
  const errPath = `${DIR}\\select-subject.err`;
  for (const p of [okPath, errPath]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  fs.writeFileSync(`${DIR}\\subject.select`, subjectName, "ascii");
  log("Triggering MR4 subject select:", subjectName);
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawSelectSubject"], { encoding: "utf-8" });
  if (trig.status !== 0) throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  const deadline = Date.now() + 75_000;
  while (Date.now() < deadline) {
    if (fs.existsSync(okPath)) return true;
    if (fs.existsSync(errPath)) return false;
    await sleep(1500);
  }
  return false;
}

async function handleSubjectJob(job) {
  currentSubjectCustomerId = job.customer_id;
  const code = (job.mr4_code || "").toLowerCase();

  if (job.kind === "find" || job.kind === "select") {
    // Select-as-check: locate the subject in MR4's live dropdown (covers in-memory
    // subjects) and select it. Success = found AND now selected; fail = not in MR4.
    const ok = await driveSubjectSelect(job.subject_name);
    log(`select-as-check '${job.subject_name}' -> ${ok ? "linked" : "not_found"}`);
    await postSubjectEvent(
      ok
        ? { customer_id: job.customer_id, result: "linked", subject_name: job.subject_name }
        : { customer_id: job.customer_id, result: "not_found" }
    );
  } else if (job.kind === "create") {
    // Guard against duplicates: if we already linked this customer, the subject
    // exists in MR4 (possibly only in memory, so find can't see it) — don't recreate.
    if (job.already_linked) {
      log(`create skipped — already linked, avoiding duplicate: ${job.subject_name}`);
    } else {
      await driveSubjectCreate(job.subject_name);
    }
    await postSubjectEvent({ customer_id: job.customer_id, result: "linked", subject_name: job.subject_name });
  }
  currentSubjectCustomerId = null;
}

async function main() {
  log(`HopClaw runner starting (long-poll, step model)`);
  log(`  HOPAPP_URL      = ${HOPAPP}`);
  log(`  HOPCLAW_DIR     = ${DIR}`);
  log(`  IDLE_FLOOR_MS   = ${IDLE_FLOOR_MS}`);
  log(`  RUNNER_API_KEY  = ${KEY ? "(set)" : "(unset)"}`);
  log(`  BLOB_READ_WRITE_TOKEN = ${BLOB_TOK ? "(set)" : "(unset)"}`);
  for (;;) {
    const startedAt = Date.now();
    currentStepId = null;
    currentSubjectCustomerId = null;
    try {
      const job = await poll(); // blocks until a job is ready or the server's deadline
      if (job.type === "step") {
        log("Job:", job.action, "step", job.step_id, "eval", job.evaluation_id);
        await handleStep(job);
      } else if (job.type === "subject_job") {
        log("Subject job:", job.kind, "customer", job.customer_id, `'${job.subject_name}'`);
        await handleSubjectJob(job);
      }
    } catch (err) {
      log("Loop error:", err.message);
      // Mark the in-flight job as failed so the UI doesn't get stuck
      if (currentStepId) {
        try {
          await postEvent({ step_id: currentStepId, status: "failed", error: err.message });
          log("Marked step", currentStepId, "as failed");
        } catch (postErr) {
          log("Also failed to post failure status:", postErr.message);
        }
      }
      if (currentSubjectCustomerId) {
        try {
          await postSubjectEvent({ customer_id: currentSubjectCustomerId, result: "failed", error: err.message });
          log("Marked subject job for", currentSubjectCustomerId, "as failed");
        } catch (postErr) {
          log("Also failed to post subject failure:", postErr.message);
        }
      }
      await sleep(ERROR_BACKOFF_MS);
    } finally {
      currentStepId = null;
      currentSubjectCustomerId = null;
    }
    // The server already waited; this floor only prevents a hot loop if it
    // returned almost instantly (e.g. an old short-poll deployment).
    const elapsed = Date.now() - startedAt;
    if (elapsed < IDLE_FLOOR_MS) await sleep(IDLE_FLOOR_MS - elapsed);
  }
}

main().catch((err) => {
  log("Fatal:", err);
  process.exit(1);
});
