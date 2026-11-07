// ASSISTANT-RECONSTRUCTED (2026-11-06) — the original lib/stats.mjs lives in the
// owner's private foundry-intel repo and has not been received. This file is built
// only from the contracts exercised by the received code (jlens.mjs self-test,
// techniques/*.mjs call sites) and is verified by executing those contracts.
// It is NOT the owner's original. Replace on sight when the original arrives.

/** Arithmetic mean; 0 on empty input. */
export function mean(xs) {
  if (!xs || xs.length === 0) return 0
  return xs.reduce((a, b) => a + b, 0) / xs.length
}

/** Population variance; 0 on empty input. */
export function variance(xs) {
  if (!xs || xs.length === 0) return 0
  const m = mean(xs)
  return xs.reduce((a, x) => a + (x - m) * (x - m), 0) / xs.length
}

/**
 * Empirical probability mass function over samples.
 * Returns a Map key -> probability. keyFn maps a sample to its key
 * (identity by default).
 */
export function empiricalPmf(samples, keyFn = (x) => x) {
  const counts = new Map()
  for (const s of samples) {
    const k = keyFn(s)
    counts.set(k, (counts.get(k) || 0) + 1)
  }
  const pmf = new Map()
  const n = samples.length || 1
  for (const [k, c] of counts) pmf.set(k, c / n)
  return pmf
}

function pmfGet(pmf, key) {
  if (pmf instanceof Map) return pmf.get(key) || 0
  return pmf[key] || 0
}

function pmfKeys(pmf) {
  if (pmf instanceof Map) return [...pmf.keys()]
  return Object.keys(pmf)
}

/**
 * KL divergence D_KL(P || Q) in nats. Missing Q mass is floored at 1e-12
 * so the result stays finite; D_KL(P || P) is exactly 0.
 */
export function klDivergence(p, q) {
  let sum = 0
  for (const k of pmfKeys(p)) {
    const pv = pmfGet(p, k)
    if (pv <= 0) continue
    const qv = Math.max(pmfGet(q, k), 1e-12)
    sum += pv * Math.log(pv / qv)
  }
  return sum
}

/** Cosine distance = 1 - cosine similarity. Zero-vector safe. */
export function cosineDistance(a, b) {
  const va = Array.from(a)
  const vb = Array.from(b)
  let dot = 0
  let na = 0
  let nb = 0
  const n = Math.min(va.length, vb.length)
  for (let i = 0; i < n; i++) {
    dot += va[i] * vb[i]
    na += va[i] * va[i]
    nb += vb[i] * vb[i]
  }
  if (na === 0 || nb === 0) return 0
  const sim = dot / (Math.sqrt(na) * Math.sqrt(nb))
  return 1 - Math.max(-1, Math.min(1, sim))
}

/** Mean pairwise cosine distance over a set of vectors; 0 when fewer than 2. */
export function meanPairwiseDistance(vectors) {
  if (!vectors || vectors.length < 2) return 0
  let total = 0
  let pairs = 0
  for (let i = 0; i < vectors.length; i++) {
    for (let j = i + 1; j < vectors.length; j++) {
      total += cosineDistance(vectors[i], vectors[j])
      pairs++
    }
  }
  return pairs ? total / pairs : 0
}
