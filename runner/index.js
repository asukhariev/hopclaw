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
async function driveMeasure(target, armed = false, readSensors = false) {
  const okPath  = "C:\\hopclaw\\drive-measure.ok";
  const errPath = "C:\\hopclaw\\drive-measure.err";
  const goPath  = "C:\\hopclaw\\measure.go";
  const rsPath  = "C:\\hopclaw\\readsensors.go";
  for (const p of [okPath, errPath]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  fs.writeFileSync("C:\\hopclaw\\measure.target", target === "running" ? "running" : "gait", "ascii");
  if (armed) fs.writeFileSync(goPath, "1", "ascii");
  else { try { fs.unlinkSync(goPath); } catch { /* ignore */ } }
  // Sensor OCR only when asked (Devices "check") — never on launch, to stay fast.
  if (armed && readSensors) fs.writeFileSync(rsPath, "1", "ascii");
  else { try { fs.unlinkSync(rsPath); } catch { /* ignore */ } }
  log(`Triggering MR4 measure-start (target=${target}; ${armed ? "ARMED — clicks MEASURE" : "nav-only"}${readSensors ? " +read-sensors" : ""})...`);
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawDriveMeasure"], { encoding: "utf-8" });
  if (trig.status !== 0) throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  try {
    const deadline = Date.now() + 60_000;
    while (Date.now() < deadline) {
      if (fs.existsSync(okPath)) return fs.readFileSync(okPath, "utf-8").trim();
      if (fs.existsSync(errPath)) throw new Error(`drive-measure reported: ${fs.readFileSync(errPath, "utf-8").trim()}`);
      await new Promise((r) => setTimeout(r, 1500));
    }
    throw new Error("drive-measure timed out (60s)");
  } finally {
    if (armed) { try { fs.unlinkSync(goPath); } catch { /* ignore */ } } // always disarm
    try { fs.unlinkSync(rsPath); } catch { /* ignore */ }
  }
}

/**
 * Click NEXT — the bottom-right primary button (same coord as MEASURE) — without
 * navigating. Used to advance the calibration screens (Calibrate Left -> NEXT ->
 * Calibrate Right -> NEXT). drive-measure.ps1 sees next.go and clicks (1462,873).
 */
async function driveNext() {
  const okPath  = "C:\\hopclaw\\drive-measure.ok";
  const errPath = "C:\\hopclaw\\drive-measure.err";
  const nextGo  = "C:\\hopclaw\\next.go";
  for (const p of [okPath, errPath]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  try { fs.unlinkSync("C:\\hopclaw\\measure.go"); } catch { /* ignore */ } // ensure not nav-mode
  fs.writeFileSync(nextGo, "1", "ascii");
  log("Triggering MR4 NEXT click (calibration)...");
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawDriveMeasure"], { encoding: "utf-8" });
  if (trig.status !== 0) throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  try {
    const deadline = Date.now() + 40_000;
    while (Date.now() < deadline) {
      if (fs.existsSync(okPath)) return fs.readFileSync(okPath, "utf-8").trim();
      if (fs.existsSync(errPath)) throw new Error(`drive-measure(next) reported: ${fs.readFileSync(errPath, "utf-8").trim()}`);
      await new Promise((r) => setTimeout(r, 1000));
    }
    throw new Error("drive-measure(next) timed out (40s)");
  } finally {
    try { fs.unlinkSync(nextGo); } catch { /* ignore */ }
  }
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

/**
 * Find a dialog button by its text (OCR) and click it — for the Save Data modal
 * (Save & View / Save & Measure Again), where a fixed coord is risky. Reuses the
 * HopClawDriveMeasure task in clicktext mode.
 */
async function driveClickText(find, avoid) {
  const okPath = "C:\\hopclaw\\drive-measure.ok";
  const errPath = "C:\\hopclaw\\drive-measure.err";
  const goPath = "C:\\hopclaw\\clicktext.go";
  for (const p of [okPath, errPath, "C:\\hopclaw\\clicktext.ok", "C:\\hopclaw\\clicktext.err"]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  for (const p of ["C:\\hopclaw\\next.go", "C:\\hopclaw\\measure.go"]) { try { fs.unlinkSync(p); } catch { /* ignore */ } }
  fs.writeFileSync("C:\\hopclaw\\clicktext.find", find, "ascii");
  fs.writeFileSync("C:\\hopclaw\\clicktext.avoid", avoid || "", "ascii");
  fs.writeFileSync(goPath, "1", "ascii");
  log(`Triggering MR4 click-text: find='${find}' avoid='${avoid}'`);
  const trig = spawnSync("schtasks.exe", ["/Run", "/TN", "HopClawDriveMeasure"], { encoding: "utf-8" });
  if (trig.status !== 0) throw new Error(`schtasks /Run failed: ${trig.stderr || trig.stdout}`);
  try {
    const deadline = Date.now() + 40_000;
    while (Date.now() < deadline) {
      if (fs.existsSync(okPath)) return fs.readFileSync(okPath, "utf-8").trim();
      if (fs.existsSync(errPath)) throw new Error(`click-text: ${fs.readFileSync(errPath, "utf-8").trim()}`);
      await new Promise((r) => setTimeout(r, 1000));
    }
    throw new Error("click-text timed out (40s)");
  } finally {
    try { fs.unlinkSync(goPath); } catch { /* ignore */ }
  }
}

/** Read the device-connection status that drive-measure.ps1 wrote (it invokes
 *  read-sensors.ps1 to OCR MR4's "Could not find sensors: …" dialog). Local
 *  only — never uploaded anywhere. */
function readSensorsJson() {
  try {
    const j = JSON.parse(fs.readFileSync("C:\\hopclaw\\sensors.json", "utf-8"));
    return { connected: !!j.connected, missing: Array.isArray(j.missing) ? j.missing : [] };
  } catch (e) {
    log(`readSensorsJson failed (non-fatal): ${e.message}`);
    return { connected: false, missing: [] };
  }
}

async function handleLabJob(job) {
  currentSubjectCustomerId = job.customer_id;

  if (job.kind === "select") {
    // Select the subject in MR4's live dropdown. found+selected -> ready; else not_found.
    const ok = await driveSubjectSelect(job.subject_name);
    log(`select '${job.subject_name}' -> ${ok ? "selected" : "not_found"}`);
    await postSubjectEvent(
      ok
        ? { customer_id: job.customer_id, result: "selected", subject_name: job.subject_name }
        : { customer_id: job.customer_id, result: "not_found" }
    );
  } else if (job.kind === "create") {
    // Create the subject (New dialog) — it auto-selects on OK -> ready.
    await driveSubjectCreate(job.subject_name);
    log(`create '${job.subject_name}' -> selected`);
    await postSubjectEvent({ customer_id: job.customer_id, result: "selected", subject_name: job.subject_name });
  } else if (job.kind === "launch") {
    // The subject is already selected (separate select clickflow + MR4 stays
    // reserved for this patient), so go straight to the protocol + MEASURE and
    // land on the measurement screen. We do NOT wait for / read sensors here —
    // that happens on demand in the Devices step (check command), which keeps
    // the "Starting…" launch fast.
    const target = job.target === "running" ? "running" : "gait";
    log(`launch: driving ${target} + MEASURE for '${job.subject_name}' (already selected)`);
    await driveMeasure(target, true); // armed: clicks MEASURE, brief settle, returns
    await postSubjectEvent({ customer_id: job.customer_id, result: "in_session", subject_name: job.subject_name });
  }
  currentSubjectCustomerId = null;
}

/** In-session command: click NEXT (calibration) or re-check device connection. */
async function handleCommand(job) {
  currentSubjectCustomerId = job.customer_id;
  if (job.kind === "next") {
    log(`command: NEXT (calibration) for '${job.subject_name}'`);
    await driveNext();
    await postSubjectEvent({ customer_id: job.customer_id, result: "next_done", subject_name: job.subject_name });
  } else if (job.kind === "check") {
    // Re-scan: re-run the measure flow (its nav Escape closes the old dialog) and
    // read the refreshed device-connection status.
    const target = job.target === "running" ? "running" : "gait";
    log(`command: re-check devices (re-scan ${target}) for '${job.subject_name}'`);
    await driveMeasure(target, true, true); // read-sensors: this is the device check
    const dev = readSensorsJson();
    log(`re-check: devices -> ${dev.missing.length ? "MISSING " + dev.missing.join(",") : "connected"}`);
    await postSubjectEvent({ customer_id: job.customer_id, result: "devices", subject_name: job.subject_name, missing: dev.missing });
  } else if (job.kind === "record") {
    // Tests step: click RECORD (the bottom-right primary button, same coord as
    // NEXT). The technician then runs the test in MR4 to the Save dialog.
    log(`command: RECORD (tests) for '${job.subject_name}'`);
    await driveNext(); // clicks (1462,873) = RECORD on the Preview screen
    await postSubjectEvent({ customer_id: job.customer_id, result: "recording", subject_name: job.subject_name });
  } else if (job.kind === "save_again") {
    // Save Data modal: click "Save & Measure Again" (save + re-record the whole test).
    log(`command: Save & Measure Again for '${job.subject_name}'`);
    await driveClickText("measure again", "discard");
    await postSubjectEvent({ customer_id: job.customer_id, result: "rerecord", subject_name: job.subject_name });
  } else if (job.kind === "save_view") {
    // Save Data modal: click "Save & View" (save the evaluation, go to view/report).
    log(`command: Save & View for '${job.subject_name}'`);
    await driveClickText("view", "");
    await postSubjectEvent({ customer_id: job.customer_id, result: "saved", subject_name: job.subject_name });
  } else if (job.kind === "report_nav") {
    // After Save & View: Report → Next → Next → Next (all the bottom-right button).
    log(`command: report nav (Report -> Next x3) for '${job.subject_name}'`);
    for (let i = 0; i < 4; i++) {
      await driveNext(); // clicks (1462,873): REPORT, then NEXT x3
      await sleep(2500); // let the next report screen load
    }
    await postSubjectEvent({ customer_id: job.customer_id, result: "reported", subject_name: job.subject_name });
  } else if (job.kind === "activate") {
    // Calibration already done — MR4 shows the Activate page; click ACTIVATE
    // (bottom-right primary button, same coord as NEXT) to reach the test.
    log(`command: ACTIVATE (calibration already done) for '${job.subject_name}'`);
    await driveNext(); // clicks (1462,873) = ACTIVATE
    await postSubjectEvent({ customer_id: job.customer_id, result: "activated", subject_name: job.subject_name });
  }
  currentSubjectCustomerId = null;
}

/**
 * Single-instance guard. A `schtasks /end` restart kills start.cmd but ORPHANS
 * its node child — and a non-admin SSH session can't taskkill that child across
 * the session boundary, so stale runners pile up and race for jobs (an old one
 * can win and run outdated behavior). We run inside the interactive session as
 * the same user, so here we CAN kill our siblings: drop every other node.exe on
 * startup, leaving only this process. Orphans have no start.cmd parent, so they
 * never respawn.
 */
function enforceSingleInstance() {
  try {
    const r = spawnSync(
      "taskkill",
      ["/F", "/FI", "IMAGENAME eq node.exe", "/FI", `PID ne ${process.pid}`],
      { encoding: "utf-8" }
    );
    const out = `${r.stdout || ""}${r.stderr || ""}`.replace(/\s+/g, " ").trim();
    log(`single-instance (pid ${process.pid}): ${out || "no siblings"}`);
  } catch (e) {
    log(`single-instance: kill failed (non-fatal): ${e.message}`);
  }
}

async function main() {
  enforceSingleInstance();
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
      } else if (job.type === "lab_job") {
        log("Lab job:", job.kind, "customer", job.customer_id, `'${job.subject_name}'`);
        await handleLabJob(job);
      } else if (job.type === "command") {
        log("Command:", job.kind, "customer", job.customer_id, `'${job.subject_name}'`);
        await handleCommand(job);
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
