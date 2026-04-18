#!/usr/bin/env node
/**
 * Cross-seed stuck-torrent cleanup sidecar.
 *
 * WHAT
 *   Triages qBit torrents that cross-seed injected as partial-match season
 *   packs and left stuck (tag=cross-seed, stoppedDL, progress<1.0).
 *   Threshold = seasonFromEpisodes from the running cross-seed config:
 *     - progress >= threshold → start the torrent (pull missing pieces).
 *     - progress <  threshold → unlink marker, qBit-delete with files.
 *
 * WHY
 *   Cross-seed's autoResumeMaxDownload is hard-capped at 50 MiB by its
 *   schema, so anything bigger sits paused waiting for a human. This is
 *   that human, using cross-seed's own configured season threshold.
 *
 * HOW
 *   Native sidecar (K8s 1.28+) in the cross-seed Deployment, sharing the
 *   cross-seed PVC at /config so it can require() config.js and unlink
 *   markers under /config/cross-seeds/. qBit session opened once at
 *   startup, SID cookie reused across iterations, re-login on 401/403.
 *
 *   Each SLEEP_SECONDS:
 *     1. GET /api/v2/torrents/info?tag=cross-seed
 *     2. Validate + classify (stoppedDL, progress<1.0, not previously
 *        complete, age >= MIN_AGE_HOURS).
 *     3. For each candidate, compare progress to threshold: start or
 *        (unlink marker → qBit-delete-with-files).
 *     4. Log a summary.
 *
 *   CLEANUP_APPLY=false (default) is dry-run.
 *
 * ENV
 *   QBITTORRENT_URL   (required)  http[s]://user:pass@host[:port]
 *   CROSS_SEED_CONFIG (default /config/config.js)    cross-seed config
 *   CROSS_SEEDS_DIR   (default /config/cross-seeds)  marker location
 *   ACTIONS_LOG_PATH  (default /config/cleanup-actions.log)  persistent
 *                     append-only record of every action taken (or would
 *                     take, in dry-run); one logfmt line per candidate
 *                     outcome.
 *   MIN_AGE_HOURS     (default 2)     candidate age floor
 *   SLEEP_SECONDS     (default 3600)  per-iteration delay
 *   CLEANUP_APPLY     (default false) destructive mode toggle
 */

'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');

const HASH_RE = /^[0-9a-f]{40}$/;
const REQUEST_TIMEOUT_MS = 30_000;

// --- env -----------------------------------------------------------------

const {
  QBITTORRENT_URL,
  MIN_AGE_HOURS = '2',
  SLEEP_SECONDS = '3600',
  CLEANUP_APPLY = 'false',
  CROSS_SEEDS_DIR = '/config/cross-seeds',
  CROSS_SEED_CONFIG = '/config/config.js',
  ACTIONS_LOG_PATH = '/config/cleanup-actions.log',
} = process.env;

if (!QBITTORRENT_URL) {
  console.error('QBITTORRENT_URL is required');
  process.exit(1);
}

const minAgeHours = Number.parseFloat(MIN_AGE_HOURS);
if (!Number.isFinite(minAgeHours) || minAgeHours < 0) {
  console.error(`invalid MIN_AGE_HOURS: ${MIN_AGE_HOURS}`);
  process.exit(1);
}

const sleepSeconds = Number.parseFloat(SLEEP_SECONDS);
if (!Number.isFinite(sleepSeconds) || sleepSeconds <= 0) {
  console.error(`invalid SLEEP_SECONDS: ${SLEEP_SECONDS}`);
  process.exit(1);
}
const sleepMs = sleepSeconds * 1000;

const applyMode = CLEANUP_APPLY.toLowerCase() === 'true';

// --- logging (logfmt-ish: `ts level msg k=v k=v ...`) --------------------

function log(level, msg, fields = {}) {
  const pairs = Object.entries(fields)
    .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
    .join(' ');
  const line = `${new Date().toISOString()} ${level} ${msg}`;
  console.log(pairs ? `${line} ${pairs}` : line);
}

/**
 * Append one line per action to ACTIONS_LOG_PATH for persistent review.
 * Also mirrors to stdout via log(). File-write failures are warned but
 * never propagate — the action itself should not fail if logging fails.
 */
async function logAction(level, fields) {
  log(level, fields.action ?? 'action', fields);
  try {
    const pairs = Object.entries(fields)
      .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
      .join(' ');
    await fs.appendFile(
      ACTIONS_LOG_PATH,
      `${new Date().toISOString()} ${level} ${pairs}\n`,
    );
  } catch (err) {
    log('warn', 'failed to append to actions log', {
      err: err.message,
      path: ACTIONS_LOG_PATH,
    });
  }
}

// --- qBit URL + config --------------------------------------------------

function parseQbitUrl(raw) {
  const u = new URL(raw);
  if (!u.username || !u.password) {
    throw new Error('QBITTORRENT_URL must embed user:password');
  }
  return {
    base: `${u.protocol}//${u.host}`,
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password),
  };
}

const qbit = parseQbitUrl(QBITTORRENT_URL);
let sidCookie = null;

function loadSeasonThreshold() {
  const abs = path.resolve(CROSS_SEED_CONFIG);
  const { seasonFromEpisodes: t } = require(abs);
  if (typeof t !== 'number' || !Number.isFinite(t)) {
    throw new Error(
      `seasonFromEpisodes missing or invalid in ${abs}: ${JSON.stringify(t)}`,
    );
  }
  if (t <= 0 || t > 1) {
    throw new Error(
      `seasonFromEpisodes out of range in ${abs}: ${t} (expected (0, 1])`,
    );
  }
  return t;
}

// --- qBit HTTP ----------------------------------------------------------

async function qbitLogin() {
  const body = new URLSearchParams({
    username: qbit.user,
    password: qbit.password,
  }).toString();
  const resp = await fetch(`${qbit.base}/api/v2/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Referer: qbit.base,
    },
    body,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  const text = (await resp.text()).trim();
  if (resp.status !== 200 || text !== 'Ok.') {
    throw new Error(`login failed: status=${resp.status} body=${text}`);
  }
  const sid = resp.headers.getSetCookie().find((c) => c.startsWith('SID='));
  if (!sid) throw new Error('login returned Ok. but no SID cookie');
  sidCookie = sid.split(';')[0];
  log('info', 'qBit login successful', { base: qbit.base, user: qbit.user });
}

async function qbitFetch(method, apiPath, formBody) {
  if (!sidCookie) await qbitLogin();
  const url = `${qbit.base}${apiPath}`;

  const buildInit = () => {
    const init = {
      method,
      headers: { Referer: qbit.base, Cookie: sidCookie },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    };
    if (formBody) {
      init.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      init.body = new URLSearchParams(formBody).toString();
    }
    return init;
  };

  let resp = await fetch(url, buildInit());
  if (resp.status === 401 || resp.status === 403) {
    log('warn', 'auth failed; re-logging in', {
      status: resp.status,
      method,
      path: apiPath,
    });
    sidCookie = null;
    await qbitLogin();
    resp = await fetch(url, buildInit());
  }
  return resp;
}

async function fetchCrossSeedTorrents() {
  const resp = await qbitFetch('GET', '/api/v2/torrents/info?tag=cross-seed');
  if (!resp.ok) {
    throw new Error(
      `list torrents failed: status=${resp.status} body=${await resp.text()}`,
    );
  }
  const parsed = await resp.json();
  if (!Array.isArray(parsed)) {
    throw new Error(
      `unexpected /torrents/info response shape: ${typeof parsed}`,
    );
  }
  const bad = parsed.findIndex((item) => !isPlainObject(item));
  if (bad !== -1) {
    throw new Error(
      `/torrents/info element at index ${bad} is not an object: ${typeof parsed[bad]}`,
    );
  }
  return parsed;
}

async function deleteTorrent(hash) {
  const resp = await qbitFetch('POST', '/api/v2/torrents/delete', {
    hashes: hash,
    deleteFiles: 'true',
  });
  if (!resp.ok) {
    throw new Error(
      `qBit delete failed: status=${resp.status} body=${await resp.text()}`,
    );
  }
}

async function startTorrent(hash) {
  // qBit 5.x renamed /resume to /start (Web API v2.11.0).
  const resp = await qbitFetch('POST', '/api/v2/torrents/start', {
    hashes: hash,
  });
  if (!resp.ok) {
    throw new Error(
      `qBit start failed: status=${resp.status} body=${await resp.text()}`,
    );
  }
}

// --- marker handling ----------------------------------------------------

async function findMarkers(hash) {
  // hash is validated as 40 hex chars upstream; matching by substring.
  let entries;
  try {
    entries = await fs.readdir(CROSS_SEEDS_DIR);
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  return entries
    .filter((n) => n.endsWith('.torrent') && n.toLowerCase().includes(hash))
    .map((n) => path.join(CROSS_SEEDS_DIR, n));
}

async function isSafeMarker(p) {
  if (!p.endsWith('.torrent')) return false;
  try {
    const lst = await fs.lstat(p);
    if (lst.isSymbolicLink()) return false;
    const real = await fs.realpath(p);
    const root = await fs.realpath(CROSS_SEEDS_DIR);
    if (path.dirname(real) !== root) return false;
    const st = await fs.stat(real);
    return st.isFile();
  } catch {
    return false;
  }
}

// --- classification -----------------------------------------------------

function isNumber(x) {
  return typeof x === 'number' && Number.isFinite(x);
}

function isPlainObject(x) {
  return typeof x === 'object' && x !== null && !Array.isArray(x);
}

/**
 * Type-validate a qBit torrent record; return our canonical shape or null.
 * Separates shape validation from eligibility (in classify()).
 */
function extractFields(t) {
  const name = typeof t.name === 'string' ? t.name : '?';

  if (typeof t.hash !== 'string') {
    log('warn', 'skipping: hash missing or non-string', { name, raw: t.hash });
    return null;
  }
  const hash = t.hash.toLowerCase();
  if (!HASH_RE.test(hash)) {
    log('warn', 'skipping: hash fails v1 validation', { name, raw: t.hash });
    return null;
  }

  if (typeof t.state !== 'string') {
    log('warn', 'skipping: state missing or non-string', { name, hash, raw: t.state });
    return null;
  }
  if (!isNumber(t.progress)) {
    log('warn', 'skipping: progress missing or non-numeric', { name, hash, raw: t.progress });
    return null;
  }

  const completionOn = t.completion_on ?? 0;
  if (!isNumber(completionOn)) {
    log('warn', 'skipping: completion_on non-numeric', { name, hash, raw: completionOn });
    return null;
  }

  if (!isNumber(t.added_on)) {
    log('warn', 'skipping: added_on missing or non-numeric', { name, hash, raw: t.added_on });
    return null;
  }

  return {
    hash,
    name,
    state: t.state,
    progress: t.progress,
    completionOn,
    addedOn: t.added_on,
    savePath: typeof t.save_path === 'string' ? t.save_path : '?',
    contentPath: typeof t.content_path === 'string' ? t.content_path : '?',
  };
}

/**
 * Eligibility. Returns age_hours if the torrent is a cleanup candidate,
 * else null. Only logs for safety-guard skips; state/progress/age misses
 * are silent to keep logs readable.
 */
function classify(fields, nowSec) {
  if (fields.state !== 'stoppedDL') return null;
  if (fields.progress >= 1.0) return null;

  if (fields.completionOn > 0) {
    log('info', 'skipping: previously completed — not a fresh partial inject', {
      name: fields.name,
      hash: fields.hash,
      completion_on: fields.completionOn,
    });
    return null;
  }

  const ageHours = (nowSec - fields.addedOn) / 3600;
  return ageHours < minAgeHours ? null : ageHours;
}

// --- per-candidate action -----------------------------------------------

/**
 * Policy: qBit's `progress` is authoritative. Cross-seed injects with
 * skipRecheck:false, which triggers a qBit recheck at inject time; after
 * that, progress reflects on-disk reality. We do not re-recheck here.
 *
 * Delete path: unlink marker(s) FIRST, then qBit-delete. If qBit delete
 * then fails, the marker is already gone so cross-seed cannot re-inject,
 * and the next sweep finishes removing the qBit torrent. Zero-match case
 * still proceeds to qBit-delete (handles prior-partial-failure retry).
 * Refuses to unlink if any matched path fails structural validation.
 */
async function processCandidate(fields, ageHours, threshold) {
  const markers = await findMarkers(fields.hash);
  const action = fields.progress >= threshold ? 'start' : 'delete';
  const ctx = {
    action,
    apply: applyMode,
    name: fields.name,
    hash: fields.hash,
    state: fields.state,
    progress: fields.progress,
    threshold,
    age_hours: ageHours,
    save_path: fields.savePath,
    content_path: fields.contentPath,
    markers,
  };

  if (!applyMode) {
    await logAction('info', { ...ctx, result: 'dryrun' });
    return 'dryrun';
  }

  if (action === 'start') {
    try {
      await startTorrent(fields.hash);
      await logAction('info', { ...ctx, result: 'ok' });
      return 'started';
    } catch (err) {
      await logAction('error', { ...ctx, result: 'fail', err: err.message });
      throw err;
    }
  }

  // delete path
  const safety = await Promise.all(markers.map(isSafeMarker));
  const invalid = markers.filter((_, i) => !safety[i]);
  if (invalid.length > 0) {
    await logAction('error', {
      ...ctx,
      result: 'refused',
      reason: 'invalid-markers',
      invalid,
    });
    return 'fail';
  }

  try {
    for (const p of markers) await fs.unlink(p);
    await deleteTorrent(fields.hash);
    await logAction('info', { ...ctx, result: 'ok' });
    return 'deleted';
  } catch (err) {
    await logAction('error', { ...ctx, result: 'fail', err: err.message });
    throw err;
  }
}

// --- sweep --------------------------------------------------------------

/**
 * One cleanup iteration. Per-candidate failures are caught and counted;
 * pre-loop failures (list fetch, auth errors) propagate to main()'s loop
 * wrapper.
 */
async function sweep(threshold) {
  const nowSec = Math.floor(Date.now() / 1000);
  const torrents = await fetchCrossSeedTorrents();

  const candidates = [];
  for (const t of torrents) {
    const fields = extractFields(t);
    if (!fields) continue;
    const ageHours = classify(fields, nowSec);
    if (ageHours === null) continue;
    candidates.push({ fields, ageHours });
  }

  const counts = { started: 0, deleted: 0, failed: 0 };

  for (const { fields, ageHours } of candidates) {
    try {
      const outcome = await processCandidate(fields, ageHours, threshold);
      if (outcome === 'started') counts.started++;
      else if (outcome === 'deleted') counts.deleted++;
      else if (outcome === 'fail') counts.failed++;
    } catch (err) {
      log('error', 'failed to process candidate', {
        name: fields.name,
        hash: fields.hash,
        err: err.message,
      });
      if (err.stack) console.error(err.stack);
      counts.failed++;
    }
  }

  log('info', 'sweep done', {
    seen: candidates.length,
    ...counts,
    threshold,
    apply: applyMode,
  });
}

// --- main ---------------------------------------------------------------

async function main() {
  // Threshold loads once; the Reloader annotation restarts the pod on
  // ConfigMap changes, so there's no need to re-read each sweep.
  const threshold = loadSeasonThreshold();
  log('info', 'starting', {
    base: qbit.base,
    apply: applyMode,
    threshold,
    min_age_h: minAgeHours,
    sleep_s: sleepSeconds,
    dir: CROSS_SEEDS_DIR,
    config: CROSS_SEED_CONFIG,
    actions_log: ACTIONS_LOG_PATH,
  });
  await qbitLogin();

  // sweep-first, sleep-after — first sweep runs immediately on container start
  while (true) {
    try {
      await sweep(threshold);
    } catch (err) {
      log('error', 'sweep iteration failed; will retry after sleep', {
        err: err.message,
      });
      if (err.stack) console.error(err.stack);
    }
    await new Promise((r) => setTimeout(r, sleepMs));
  }
}

main().catch((err) => {
  log('fatal', 'unrecoverable error', { err: err.message });
  if (err.stack) console.error(err.stack);
  process.exit(1);
});
