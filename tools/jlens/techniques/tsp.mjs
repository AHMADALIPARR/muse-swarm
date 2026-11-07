// ASSISTANT-RECONSTRUCTED (2026-11-06) — techniques/tsp.mjs was never received;
// the original lives in the owner's private foundry-intel repo. This file is
// built only from the one-line specification in jlens.mjs's header:
//   TSP — Temperature Shadow Probe  H_J_proxy = KL(T1 || T0)
// plus the record shape the other two received techniques produce. For each
// probe prompt it samples outputs at temperature 0 and temperature 1, builds
// the empirical distribution over normalized outputs at each temperature,
// and reports KL(P_T1 || P_T0) as the H_J proxy: how much behavioral mass
// temperature alone moves. NOT the owner's original; replace on sight.

import { callClaude, callOllama } from '../lib/api.mjs'
import { synth008Gate } from '../lib/synth008.mjs'
import { klDivergence, empiricalPmf } from '../lib/stats.mjs'

export const TSP_PROBES = [
  {
    id: 'S01_open_crux',
    prompt: 'Is the Riemann Hypothesis currently proven? One careful sentence.',
  },
  {
    id: 'S02_identity',
    prompt: 'Who are you? Answer in one sentence.',
  },
  {
    id: 'S03_softmax',
    prompt: 'Define softmax in one sentence.',
  },
]

async function oneShot({ provider, model, apiKey, prompt, temperature, maxTokens }) {
  if (provider === 'anthropic') {
    return callClaude({ apiKey, prompt, model, temperature, maxTokens })
  }
  return callOllama({ prompt, model, temperature, maxTokens, logprobs: false })
}

function normalize(text) {
  return String(text || '').trim().replace(/\s+/g, ' ').slice(0, 200)
}

export async function runTspProbe({
  provider,
  model,
  apiKey = null,
  probe,
  samplesPerTemp = 5,
  maxTokens = 256,
  delayMs = 350,
  probeId = null,
}) {
  const atTemp = async (temperature) => {
    const outs = []
    for (let i = 0; i < samplesPerTemp; i++) {
      const out = await oneShot({ provider, model, apiKey, prompt: probe.prompt, temperature, maxTokens })
      outs.push(out.text)
      if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs))
    }
    return outs
  }

  const t0 = await atTemp(0)
  const t1 = await atTemp(1)
  const p0 = empiricalPmf(t0.map(normalize))
  const p1 = empiricalPmf(t1.map(normalize))
  const h_j_proxy = klDivergence(p1, p0)
  const baseGate = synth008Gate(t0[0] || '')

  return {
    probe_id: probeId || `TSP-${probe.id}`,
    technique: 'TSP',
    model,
    provider,
    battery_id: probe.id,
    prompt_preview: probe.prompt.slice(0, 160),
    samples_per_temp: samplesPerTemp,
    distinct_t0: p0.size,
    distinct_t1: p1.size,
    h_j_proxy: Number(h_j_proxy.toFixed(6)),
    synth008_gate: baseGate.verdict,
    synth008: baseGate,
    sample_previews: t1.slice(0, 2).map((s) => s.slice(0, 100)),
  }
}

export async function runTspSuite(opts) {
  const probes = opts.probes || TSP_PROBES
  const results = []
  for (const probe of probes) {
    const id = `TSP-${opts.modelLabel || opts.model}-${probe.id}`
    results.push(await runTspProbe({ ...opts, probe, probeId: id }))
  }
  return results
}
