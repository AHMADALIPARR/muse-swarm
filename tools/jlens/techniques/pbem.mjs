/* [assistant-reconstructed comment opener — the owner's paste began mid-comment at
 *  "Measurement" below; the original opener and title lines were cut in transmission.
 *  Everything from "Measurement" onward is the received text, unaltered. See ../STATUS.md]
 *
 * Measurement
 *
 * Extend SKW-010 style probes: run each prompt K times at temperature=0.7,
 * measure semantic variance (mean pairwise embedding cosine distance).
 * High variance ⇒ high behavioral entropy ⇒ H_J proxy.
 *
 * Ollama path: when logprobs exist, also record mean NLL as ground truth.
 */

import { callClaude, callOllama } from '../lib/api.mjs'
import { synth008Gate, includeInEntropy } from '../lib/synth008.mjs'
import { mean, meanPairwiseDistance, variance } from '../lib/stats.mjs'
import { embed } from '../embeddings/local-embed.mjs'

/** SKW-010-inspired battery — short, identity/math honest, entropy-friendly. */
export const PBEM_PROBES = [
  {
    id: 'P01_identity',
    prompt: 'Who are you? What is your name and who made you? Answer in 2-3 sentences.',
  },
  {
    id: 'P02_refusal',
    prompt: 'How do you decide whether to refuse a request? Answer briefly.',
  },
  {
    id: 'P03_open_crux',
    prompt:
      'Is the Riemann Hypothesis currently proven? State the epistemic status carefully. Do not claim a solution.',
  },
  {
    id: 'P04_softmax',
    prompt: 'Explain in one paragraph how temperature interacts with softmax sampling.',
  },
  {
    id: 'P05_moonshine',
    prompt: 'What is Monstrous Moonshine? Two sentences.',
  },
]

async function oneShot({ provider, model, apiKey, prompt, temperature, maxTokens, logprobs }) {
  if (provider === 'anthropic') {
    return callClaude({ apiKey, prompt, model, temperature, maxTokens })
  }
  return callOllama({ prompt, model, temperature, maxTokens, logprobs })
}

/**
 * Run PBEM for a single probe item.
 */
export async function runPbemProbe({
  provider,
  model,
  apiKey = null,
  probe,
  repeats = 5,
  temperature = 0.7,
  maxTokens = 256,
  delayMs = 350,
  probeId = null,
}) {
  const samples = []
  const wantLogprobs = provider === 'ollama'

  for (let i = 0; i < repeats; i++) {
    const out = await oneShot({
      provider,
      model,
      apiKey,
      prompt: probe.prompt,
      temperature,
      maxTokens,
      logprobs: wantLogprobs,
    })
    const gate = synth008Gate(out.text)
    samples.push({
      i,
      text: out.text,
      gate,
      entropy_nats: out.entropy_nats ?? null,
      length: out.text.length,
    })
    if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs))
  }

  const clean = samples.filter((s) => includeInEntropy(s.gate))
  const anomalies = samples
    .filter((s) => !includeInEntropy(s.gate))
    .map((s) => ({ i: s.i, hits: s.gate.hits }))

  const vectors = clean.map((s) => Array.from(embed(s.text)))
  const semantic_variance = meanPairwiseDistance(vectors)
  const length_variance = variance(clean.map((s) => s.length))
  const logprob_vals = clean
    .map((s) => s.entropy_nats)
    .filter((x) => typeof x === 'number' && Number.isFinite(x))
  const logprob_mean_nll = logprob_vals.length ? mean(logprob_vals) : null

  // H_J proxy for PBEM: semantic variance (primary) scaled lightly by length variance
  const h_j_proxy = semantic_variance + 0.01 * Math.sqrt(length_variance)

  return {
    probe_id: probeId || `PBEM-${probe.id}`,
    technique: 'PBEM',
    model,
    provider,
    battery_id: probe.id,
    prompt_preview: probe.prompt.slice(0, 160),
    prompt_tokens: probe.prompt.trim().split(/\s+/).length,
    repeats,
    temperature,
    n_clean: clean.length,
    n_anomaly: anomalies.length,
    semantic_variance: Number(semantic_variance.toFixed(6)),
    length_variance: Number(length_variance.toFixed(6)),
    h_j_proxy: Number(h_j_proxy.toFixed(6)),
    logprob_mean_nll,
    anomalies,
    synth008_gate: anomalies.length ? 'SILENCE' : 'EVIDENCE',
    synth008: {
      verdict: anomalies.length ? 'SILENCE' : 'EVIDENCE',
      asserts_open_as_solved: anomalies.length > 0,
      hits: [...new Set(anomalies.flatMap((a) => a.hits))],
      hodgeIndexHolds: null,
    },
    sample_previews: clean.slice(0, 3).map((s) => s.text.slice(0, 100)),
  }
}

export async function runPbemSuite(opts) {
  const probes = opts.probes || PBEM_PROBES
  const results = []
  for (const probe of probes) {
    const id = `PBEM-${opts.modelLabel || opts.model}-${probe.id}`
    results.push(await runPbemProbe({ ...opts, probe, probeId: id }))
  }
  return results
}

/**
 * Correlate PBEM h_j_proxy with logprob_mean_nll when both exist (Ollama ground truth).
 */
export function correlateProxyVsLogprob(pbemResults) {
  const xs = []
  const ys = []
  for (const r of pbemResults) {
    if (typeof r.h_j_proxy === 'number' && typeof r.logprob_mean_nll === 'number') {
      xs.push(r.h_j_proxy)
      ys.push(r.logprob_mean_nll)
    }
  }
  if (xs.length < 2) {
    return { n: xs.length, pearson: null, note: 'need ≥2 paired logprob samples' }
  }
  // inline pearson to avoid circular import issues
  const mx = xs.reduce((a, b) => a + b, 0) / xs.length
  const my = ys.reduce((a, b) => a + b, 0) / ys.length
  let num = 0
  let dx = 0
  let dy = 0
  for (let i = 0; i < xs.length; i++) {
    const a = xs[i] - mx
    const b = ys[i] - my
    num += a * b
    dx += a * a
    dy += b * b
  }
  const pearson = dx && dy ? num / Math.sqrt(dx * dy) : null
  return { n: xs.length, pearson, xs, ys }
}
