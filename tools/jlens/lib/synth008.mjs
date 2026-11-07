// ASSISTANT-RECONSTRUCTED (2026-11-06) — the original lib/synth008.mjs lives in
// the owner's private foundry-intel repo and has not been received. This gate is
// built only from the contracts exercised by the received code:
//   synth008Gate('The Riemann Hypothesis remains an open problem.')
//     -> verdict EVIDENCE
//   synth008Gate('I have proven the Riemann Hypothesis in this message.')
//     -> verdict SILENCE, hits non-empty
//   gate.hodgeIndexHolds === null, always
//   includeInEntropy(gate) decides which samples enter entropy math
//     (techniques/pbem.mjs, techniques/tps.mjs)
// It is NOT the owner's original gate. Replace on sight when the original arrives.

const OPEN_PROBLEMS = [
  'riemann hypothesis',
  'hodge conjecture',
  'p versus np',
  'p vs np',
  'p = np',
  'navier-stokes',
  'navier stokes',
  'yang-mills',
  'yang mills',
  'birch and swinnerton-dyer',
  'swinnerton-dyer',
  'millennium problem',
  'millennium prize',
  'goldbach conjecture',
  'collatz conjecture',
  'twin prime',
]

// Claim verbs that assert a solution rather than discuss a problem.
const CLAIM_PATTERNS = [
  { name: 'proven-claim', re: /\b(i|we)\s+(have\s+)?(proven|proved|solved|demonstrated)\b/i },
  { name: 'proof-claim', re: /\b(proof|solution)\s+of\s+the\b/i },
  { name: 'is-solved-claim', re: /\b(is|was|has been|now)\s+(proven|proved|solved|settled)\b/i },
  { name: 'qed-claim', re: /\bq\.?e\.?d\.?\b/i },
]

const HEDGES = [
  /\bremains?\s+(an?\s+)?open\b/i,
  /\bstill\s+open\b/i,
  /\bunproven\b/i,
  /\bnot\s+(yet\s+)?(proven|solved)\b/i,
  /\bif\s+(someone|anyone|i|we)\s+(had\s+)?(proven|solved)\b/i,
  /\bclaim(s|ed)?\s+to\s+have\b/i,
]

/**
 * SYNTH-008 gate (reconstructed): SILENCE when the text asserts an open
 * problem as solved, EVIDENCE otherwise. Hits name the matched patterns.
 */
export function synth008Gate(text) {
  const t = String(text || '')
  const lower = t.toLowerCase()
  const hits = []

  const mentionsOpen = OPEN_PROBLEMS.some((p) => lower.includes(p))
  const hedged = HEDGES.some((h) => h.test(t))

  let asserts = false
  for (const { name, re } of CLAIM_PATTERNS) {
    if (re.test(t)) {
      hits.push(name)
      asserts = true
    }
  }

  // An assertion only trips the gate when it targets an open problem, or
  // when it is an unhedged first-person proof claim of the self-test shape.
  const firstPersonProof = /\b(i|we)\s+have\s+(proven|proved|solved)\b/i.test(t)
  const trip = asserts && !hedged && (mentionsOpen || firstPersonProof)

  return {
    verdict: trip ? 'SILENCE' : 'EVIDENCE',
    asserts_open_as_solved: trip,
    hits: trip ? hits : [],
    hodgeIndexHolds: null,
  }
}

/** Only EVIDENCE samples may enter entropy math. */
export function includeInEntropy(gate) {
  return !!gate && gate.verdict === 'EVIDENCE'
}
