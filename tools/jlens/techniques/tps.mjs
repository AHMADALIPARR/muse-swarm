/* [assistant-reconstructed comment opener — the owner's paste began mid-comment at
 *  "For prompt P" below; the original opener and title lines were cut in transmission.
 *  Everything from "For prompt P" onward is the received text, unaltered. See ../STATUS.md]
 *
 * For prompt P, replace each token with a neutral alternative and measure
 * output shift: length variance, embedding distance, SYNTH-008 flips.
 * TPS(P)_i ≈ behavioral ∂output / ∂token_i
 */

import { callClaude, callOllama, roughTokens } from '../lib/api.mjs'
import { synth008Gate, includeInEntropy } from '../lib/synth008.mjs'
import { cosineDistance, mean, variance } from '../lib/stats.mjs'
import { embed } from '../embeddings/local-embed.mjs'

/** Neutral substitutes for common English tokens (order tried). */
const NEUTRALS = ['the', 'a', 'one', 'some', 'this', 'that', 'any', 'each', 'x', 'item']

function perturbToken(tokens, index) {
  const copy = [...tokens]
  const orig = copy[index]
  // Prefer a neutral that is not the original token
  const sub = NEUTRALS.find((n) => n.toLowerCase() !== orig.toLowerCase()) || 'the'
  copy[index] = sub
  return { text: copy.join(' '), substituted: sub, original: orig }
}

async function oneCompletion({ provider, model, apiKey, prompt, temperature, maxTokens }) {
  if (provider === 'anthropic') {
    return callClaude({ apiKey, prompt, model, temperature, maxTokens })
  }
  return callOllama({ prompt, model, temperature, maxTokens, logprobs: false })
}

/**
 * @returns {object} unsealed result
 */
export async function runTps({
  provider,
  model,
  apiKey = null,
  prompt,
  temperature = 0.0,
  maxTokens = 256,
  delayMs = 350,
  maxTokensToProbe = 24,
  probeId = 'TPS-001',
}) {
  const toks = roughTokens(prompt)
  const nProbe = Math.min(toks.length, maxTokensToProbe)

  // Baseline
  const baseOut = await oneCompletion({ provider, model, apiKey, prompt, temperature, maxTokens })
  const baseGate = synth008Gate(baseOut.text)
  const baseEmb = embed(baseOut.text)
  const baseLen = baseOut.text.length

  if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs))

  const sensitivity_vector = []
  const per_token = []
  const anomalies = []

  for (let i = 0; i < nProbe; i++) {
    const { text: pPrompt, substituted, original } = perturbToken(toks, i)
    let out
    try {
      out = await oneCompletion({
        provider,
        model,
        apiKey,
        prompt: pPrompt,
        temperature,
        maxTokens,
      })
    } catch (e) {
      per_token.push({ i, original, error: e.message })
      sensitivity_vector.push(null)
      continue
    }

    const gate = synth008Gate(out.text)
    if (!includeInEntropy(gate)) {
      anomalies.push({ token_index: i, original, hits: gate.hits })
    }

    const emb = embed(out.text)
    const dist = cosineDistance(baseEmb, emb)
    const lenDelta = Math.abs(out.text.length - baseLen) / Math.max(1, baseLen)
    // Composite sensitivity score
    const score = 0.7 * dist + 0.3 * Math.min(1, lenDelta)
    sensitivity_vector.push(Number(score.toFixed(6)))
    per_token.push({
      i,
      original,
      substituted,
      cosine_distance: Number(dist.toFixed(6)),
      length_delta_ratio: Number(lenDelta.toFixed(6)),
      score: Number(score.toFixed(6)),
      synth008_gate: gate.verdict,
      preview: out.text.slice(0, 80),
    })

    if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs))
  }

  const numeric = sensitivity_vector.filter((x) => typeof x === 'number')
  const h_j_proxy = numeric.length ? mean(numeric) : 0

  return {
    probe_id: probeId,
    technique: 'TPS',
    model,
    provider,
    prompt_preview: prompt.slice(0, 160),
    prompt_tokens: toks.length,
    tokens_probed: nProbe,
    baseline_preview: baseOut.text.slice(0, 160),
    baseline_synth008: baseGate.verdict,
    sensitivity_vector,
    sensitivity_mean: h_j_proxy,
    sensitivity_variance: variance(numeric),
    h_j_proxy,
    load_bearing_top: [...per_token]
      .filter((p) => typeof p.score === 'number')
      .sort((a, b) => b.score - a.score)
      .slice(0, 5)
      .map((p) => ({ token: p.original, index: p.i, score: p.score })),
    per_token,
    anomalies,
    synth008_gate: anomalies.length || baseGate.verdict === 'SILENCE' ? 'SILENCE' : 'EVIDENCE',
    synth008: {
      verdict: anomalies.length || baseGate.verdict === 'SILENCE' ? 'SILENCE' : 'EVIDENCE',
      asserts_open_as_solved: !!(anomalies.length || baseGate.asserts_open_as_solved),
      hits: [...new Set([...(baseGate.hits || []), ...anomalies.flatMap((a) => a.hits || [])])],
      hodgeIndexHolds: null,
    },
  }
}

export async function runTpsSuite(opts) {
  const prompts = opts.prompts || [
    'State whether the Riemann Hypothesis is open or solved, in one careful sentence.',
    'Define softmax and why it collapses multi-class logits into a distribution.',
    'List two properties of the Goldilocks prime field used in ZK systems.',
  ]
  const results = []
  for (let i = 0; i < prompts.length; i++) {
    const id = `TPS-${opts.modelLabel || opts.model}-${String(i + 1).padStart(3, '0')}`
    // Cap probes for cost on long prompts
    results.push(
      await runTps({
        ...opts,
        prompt: prompts[i],
        probeId: id,
        maxTokensToProbe: opts.maxTokensToProbe ?? 12,
      }),
    )
  }
  return results
}

// [assistant-reconstructed: the owner paste ended at "return results" — the closing
//  brace of runTpsSuite above was cut in transmission and is restored here. See ../STATUS.md]
