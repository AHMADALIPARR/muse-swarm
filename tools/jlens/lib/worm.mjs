// ASSISTANT-RECONSTRUCTED (2026-11-06) — the original lib/worm.mjs lives in the
// owner's private foundry-intel repo and has not been received. This WORM chain
// is built only from the contracts exercised by the received code:
//   sealRecord(path, record) -> seal string; successive seals differ
//   verifyChain(path) -> { valid, length, tip }; a two-record chain verifies
//   resultsPath(dir), ensureResultsDir(dir), sha256(text)
// Append-only JSONL; each line carries prev + seal = sha256(prev || canonical
// record JSON). It is NOT the owner's original. Replace on sight when it arrives.

import { createHash } from 'node:crypto'
import { appendFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'

export function sha256(text) {
  return createHash('sha256').update(String(text), 'utf8').digest('hex')
}

export function ensureResultsDir(dir) {
  mkdirSync(dir, { recursive: true })
  return dir
}

/** Default chain file for a run: results/jlens-YYYY-MM-DD.jsonl */
export function resultsPath(dir) {
  const day = new Date().toISOString().slice(0, 10)
  return resolve(dir, `jlens-${day}.jsonl`)
}

function canonical(record) {
  // Records in the received code are flat JSON-safe objects; a stable
  // stringify over sorted keys keeps seals reproducible.
  const keys = Object.keys(record).sort()
  const out = {}
  for (const k of keys) out[k] = record[k]
  return JSON.stringify(out)
}

function lastTip(path) {
  if (!existsSync(path)) return 'GENESIS'
  const lines = readFileSync(path, 'utf8').split('\n').filter((l) => l.trim().length)
  if (!lines.length) return 'GENESIS'
  try {
    const last = JSON.parse(lines[lines.length - 1])
    return last.seal || 'GENESIS'
  } catch {
    return 'GENESIS'
  }
}

/** Append a record to the chain; returns its seal. */
export function sealRecord(path, record) {
  const prev = lastTip(path)
  const seal = sha256(prev + canonical(record))
  appendFileSync(path, JSON.stringify({ ...record, prev, seal }) + '\n', 'utf8')
  return seal
}

/** Recompute the whole chain; returns { valid, length, tip }. */
export function verifyChain(path) {
  if (!existsSync(path)) return { valid: false, length: 0, tip: null }
  const lines = readFileSync(path, 'utf8').split('\n').filter((l) => l.trim().length)
  let prev = 'GENESIS'
  for (const line of lines) {
    let rec
    try {
      rec = JSON.parse(line)
    } catch {
      return { valid: false, length: lines.length, tip: prev }
    }
    const { prev: storedPrev, seal, ...record } = rec
    if (storedPrev !== prev) return { valid: false, length: lines.length, tip: prev }
    if (sha256(prev + canonical(record)) !== seal) {
      return { valid: false, length: lines.length, tip: prev }
    }
    prev = seal
  }
  return { valid: true, length: lines.length, tip: prev }
}
