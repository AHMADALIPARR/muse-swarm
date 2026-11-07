// ASSISTANT-RECONSTRUCTED (2026-11-06) — the original embeddings/local-embed.mjs
// lives in the owner's private foundry-intel repo and has not been received.
// The received code needs exactly one contract: embed(text) -> numeric vector
// usable with cosine distance (techniques/pbem.mjs, techniques/tps.mjs).
// This stand-in is a deterministic hashing embedding (unigrams + bigrams,
// FNV-1a buckets, L2-normalized): same text in, same vector out, no model,
// no network, no cost. It measures lexical-semantic spread only — coarser
// than a trained embedder, and every H_J number produced with it must be
// read with that limit attached. NOT the owner's original; replace on sight.

const DIM = 256

function fnv1a(str) {
  let h = 0x811c9dc5
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

function tokens(text) {
  return String(text || '')
    .toLowerCase()
    .match(/[a-z0-9']+/g) || []
}

export function embed(text) {
  const vec = new Float32Array(DIM)
  const toks = tokens(text)
  const grams = [...toks]
  for (let i = 0; i + 1 < toks.length; i++) grams.push(toks[i] + ' ' + toks[i + 1])
  for (const g of grams) {
    const h = fnv1a(g)
    const idx = h % DIM
    const sign = h & 0x80000000 ? -1 : 1
    vec[idx] += sign
  }
  let norm = 0
  for (let i = 0; i < DIM; i++) norm += vec[i] * vec[i]
  norm = Math.sqrt(norm)
  if (norm > 0) for (let i = 0; i < DIM; i++) vec[i] /= norm
  return vec
}
