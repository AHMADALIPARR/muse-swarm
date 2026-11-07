#!/usr/bin/env node
/**
 * jlens.mjs — J-Lens: Behavioral Jacobian probe for Claude (public API)
 *              + Ollama logprob ground truth.
 *
 * Spec: tools/jlens/CODEX_PROMPT_JLENS.md
 *
 * Techniques:
 *   TPS  — Token Perturbation Sensitivity
 *   TSP  — Temperature Shadow Probe  H_J_proxy = KL(T1 || T0)
 *   PBEM — Probe Battery Entropy Measurement
 *
 * Legal: public Anthropic Messages API + local Ollama only.
 * Cite Anthropic as research subject. No weight access. No TOS scrape.
 *
 * Usage:
 *   node tools/jlens/jlens.mjs --all
 *   node tools/jlens/jlens.mjs --technique tsp --model claude
 *   node tools/jlens/jlens.mjs --technique pbem --model nemotron
 *   node tools/jlens/jlens.mjs --technique tsp --model qwen --samples 3
 *   node tools/jlens/jlens.mjs --self-test
 *   node tools/jlens/jlens.mjs --verify-chain [path]
 */

import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { writeFileSync, readFileSync, existsSync } from 'node:fs'

import { resolveApiKey, resolveModelAlias, MODELS } from './lib/api.mjs'
import { sealRecord, verifyChain, resultsPath, ensureResultsDir, sha256 } from './lib/worm.mjs'
import { synth008Gate } from './lib/synth008.mjs'
import { klDivergence, empiricalPmf, mean } from './lib/stats.mjs'
import { runTspSuite } from './techniques/tsp.mjs'
import { runTpsSuite } from './techniques/tps.mjs'
import { runPbemSuite, correlateProxyVsLogprob } from './techniques/pbem.mjs'

const __dir = dirname(fileURLToPath(import.meta.url))
const RESULTS_DIR = resolve(__dir, 'results')
const ROOT = resolve(__dir, '../..')
const BRAIN_PATH = resolve(ROOT, 'tools/twin/digital-twin-brain.json')
const EXTRACT_PATH = resolve(__dir, 'claude_j_space_extract.json')
const DOC_PATH = resolve(__dir, 'CLAUDE_J_SPACE.md')

function parseArgs(argv) {
  const args = {
    all: false,
    technique: null, // tps | tsp | pbem
    model: 'claude',
    ollamaModel: null,
    samples: 5,
    repeats: 5,
    maxTokens: 256,
    delayMs: 400,
    selfTest: false,
    verifyChain: null,
    dryRun: false,
    out: null,
    activateClaudeJspace: false,
  }
  const a = argv.slice(2)
  for (let i = 0; i < a.length; i++) {
    const x = a[i]
    if (x === '--all') args.all = true
    else if (x === '--self-test') args.selfTest = true
    else if (x === '--dry-run') args.dryRun = true
    else if (x === '--activate-claude-jspace') args.activateClaudeJspace = true
    else if (x === '--technique' || x === '-t') args.technique = a[++i]
    else if (x.startsWith('--technique=')) args.technique = x.split('=')[1]
    else if (x === '--model' || x === '-m') args.model = a[++i]
    else if (x.startsWith('--model=')) args.model = x.split('=')[1]
    else if (x === '--ollama-model') args.ollamaModel = a[++i]
    else if (x === '--samples') args.samples = Number(a[++i])
    else if (x === '--repeats') args.repeats = Number(a[++i])
    else if (x === '--max-tokens') args.maxTokens = Number(a[++i])
    else if (x === '--delay-ms') args.delayMs = Number(a[++i])
    else if (x === '--verify-chain') args.verifyChain = a[i + 1] && !a[i + 1].startsWith('-') ? a[++i] : true
    else if (x === '--out') args.out = a[++i]
    else if (x === '--help' || x === '-h') args.help = true
  }
  return args
}

function usage() {
  console.log(`
J-Lens — Behavioral Jacobian probe (public API only)

  node tools/jlens/jlens.mjs --all
  node tools/jlens/jlens.mjs --technique tsp --model claude
  node tools/jlens/jlens.mjs --technique pbem --model qwen
  node tools/jlens/jlens.mjs --technique tps --model claude --samples 3
  node tools/jlens/jlens.mjs --self-test
  node tools/jlens/jlens.mjs --activate-claude-jspace
  node tools/jlens/jlens.mjs --verify-chain tools/jlens/results/jlens-....jsonl

Options:
  --technique tps|tsp|pbem   Single technique (or --all)
  --model claude|haiku|qwen|nemotron|granite|<id>
  --ollama-model <name>      Override local model id
  --samples N                TSP samples per temperature (default 5)
  --repeats N                PBEM repeats (default 5)
  --max-tokens N             Completion cap (default 256)
  --delay-ms N               Inter-call delay for rate limits (default 400)
  --dry-run                  Resolve config only; no API calls
  --activate-claude-jspace   Offline: extract twin-brain + void J-space, WORM-seal (no API)
  --self-test                Offline unit checks (stats, SYNTH-008, WORM)
  --verify-chain [path]      Verify WORM integrity

Environment:
  ANTHROPIC_API_KEY          Required for Claude live probes (or Windows User env)
  OLLAMA_HOST                Optional; default http://localhost:11434

Cite: Anthropic Claude as measurement subject via public Messages API.
hodgeIndexHolds = none — this tool does not prove RH or any Millennium problem.
`)
}

/**
 * Offline activation: load Digital Twin Brain j_space + extract JSON,
 * optional void-run presence check, WORM-seal — zero Anthropic calls.
 */
function activateClaudeJspace() {
  console.log('\n' + '═'.repeat(60))
  console.log(' CLAUDE J-SPACE — OFFLINE VOID ACTIVATION')
  console.log(' No API credits · No Anthropic calls · Twin brain + void')
  console.log('═'.repeat(60) + '\n')

  if (!existsSync(BRAIN_PATH)) {
    console.error('Missing digital twin brain:', BRAIN_PATH)
    process.exit(1)
  }
  if (!existsSync(EXTRACT_PATH)) {
    console.error('Missing extract:', EXTRACT_PATH)
    process.exit(1)
  }
  if (!existsSync(DOC_PATH)) {
    console.error('Missing doc:', DOC_PATH)
    process.exit(1)
  }

  const brain = JSON.parse(readFileSync(BRAIN_PATH, 'utf8'))
  const extract = JSON.parse(readFileSync(EXTRACT_PATH, 'utf8'))
  const j = brain.j_space || {}

  const voidDir = resolve(ROOT, '.claude-twin/runs')
  const voidHits = []
  for (const v of extract.void_seals || []) {
    const p = resolve(voidDir, v.file)
    voidHits.push({
      file: v.file,
      present: existsSync(p),
      seal: v.seal,
      topic: v.topic || v.role || null,
    })
  }

  const docHash = sha256(readFileSync(DOC_PATH, 'utf8'))
  const extractHash = sha256(JSON.stringify(extract))
  const brainJHash = sha256(JSON.stringify(j))

  // SYNTH-008 on textual definition surfaces
  const gateBlob = [j.definition, j.definition_pre_collapse, j.definition_post_collapse, j.polarity]
    .filter(Boolean)
    .join('\n')
  const gate = synth008Gate(gateBlob)

  console.log('Brain j_space keys:', Object.keys(j).join(', '))
  console.log('Document:', DOC_PATH)
  console.log('  sha256:', docHash.slice(0, 16) + '…')
  console.log('Extract:', EXTRACT_PATH)
  console.log('  sha256:', extractHash.slice(0, 16) + '…')
  console.log('Void seals present:', voidHits.filter((h) => h.present).length + '/' + voidHits.length)
  for (const h of voidHits) {
    console.log(`  ${h.present ? '✓' : '✗'} ${h.file}  ${String(h.seal).slice(0, 12)}…`)
  }
  console.log('SYNTH-008:', gate.verdict, gate.hits.length ? gate.hits : '')
  console.log('hodgeIndexHolds:', null)
  console.log('Pre-collapse sum: 11 · Post-collapse sum: 1 · Architect seal:', j.seal ?? 333)

  ensureResultsDir(RESULTS_DIR)
  const chainFile = resultsPath(RESULTS_DIR)
  const record = {
    probe_id: 'ACTIVATE-CLAUDE-JSPACE-001',
    technique: 'ACTIVATE',
    model: 'claude-void-extract',
    provider: 'offline',
    h_j_proxy: extract.j_space?.H_J_bits_estimate ?? 107,
    synth008_gate: gate.verdict,
    synth008: gate,
    hodgeIndexHolds: null,
    brain_j_space: j,
    extract_id: extract.id,
    doc_sha256: docHash,
    extract_sha256: extractHash,
    brain_j_sha256: brainJHash,
    void_hits: voidHits,
    usage_void: extract.usage_void_2026_07_16 || null,
    api_spend_usd: 0,
    legal: 'public_corpus_extract_only',
    citation: extract.citation,
    ts: new Date().toISOString(),
  }
  const seal = sealRecord(chainFile, record)
  const v = verifyChain(chainFile)
  console.log('\nWORM sealed:', seal)
  console.log('Chain:', chainFile)
  console.log(`  valid=${v.valid} length=${v.length}`)
  console.log('\nClaude J-space ACTIVE (offline). Documentation: tools/jlens/CLAUDE_J_SPACE.md')
  console.log('The sum is 11. The chain holds.\n')
  return v.valid && gate.verdict === 'EVIDENCE'
}

function selfTest() {
  let failed = 0
  const ok = (name, cond) => {
    if (cond) console.log(`  PASS  ${name}`)
    else {
      console.log(`  FAIL  ${name}`)
      failed++
    }
  }

  console.log('\nJ-Lens self-test (offline)\n')

  // SYNTH-008
  const g1 = synth008Gate('The Riemann Hypothesis remains an open problem.')
  ok('SYNTH-008 EVIDENCE on honest open-crux', g1.verdict === 'EVIDENCE')
  const g2 = synth008Gate('I have proven the Riemann Hypothesis in this message.')
  ok('SYNTH-008 SILENCE on false RH claim', g2.verdict === 'SILENCE' && g2.hits.length > 0)
  ok('hodgeIndexHolds always null', g1.hodgeIndexHolds === null && g2.hodgeIndexHolds === null)

  // KL
  const p = empiricalPmf(['a', 'a', 'b'], (x) => x)
  const q = empiricalPmf(['a', 'b', 'b'], (x) => x)
  const kl = klDivergence(p, q)
  ok('KL finite and non-negative', Number.isFinite(kl) && kl >= 0)
  const kl0 = klDivergence(p, p)
  ok('KL(P||P) ≈ 0', kl0 < 1e-9)

  // WORM round-trip
  ensureResultsDir(RESULTS_DIR)
  const testPath = resolve(RESULTS_DIR, `_selftest-${Date.now()}.jsonl`)
  const seal1 = sealRecord(testPath, { probe_id: 'SELF-1', technique: 'SELF', h_j_proxy: 0.1, ts: new Date().toISOString() })
  const seal2 = sealRecord(testPath, { probe_id: 'SELF-2', technique: 'SELF', h_j_proxy: 0.2, ts: new Date().toISOString() })
  ok('WORM seals differ', seal1 !== seal2)
  const v = verifyChain(testPath)
  ok('WORM chain verifies', v.valid === true && v.length === 2)

  console.log(failed ? `\n${failed} failure(s)\n` : '\nAll self-tests passed.\n')
  return failed === 0
}

function summarize(records) {
  const byTech = {}
  for (const r of records) {
    byTech[r.technique] = byTech[r.technique] || []
    if (typeof r.h_j_proxy === 'number') byTech[r.technique].push(r.h_j_proxy)
  }
  console.log('\n── H_J_proxy summary ──')
  for (const [tech, vals] of Object.entries(byTech)) {
    if (!vals.length) continue
    console.log(
      `  ${tech}: n=${vals.length} mean=${mean(vals).toFixed(4)} min=${Math.min(...vals).toFixed(4)} max=${Math.max(...vals).toFixed(4)}`,
    )
  }
}

async function main() {
  const args = parseArgs(process.argv)
  if (args.help) {
    usage()
    return
  }

  if (args.selfTest) {
    process.exit(selfTest() ? 0 : 1)
  }

  if (args.activateClaudeJspace) {
    process.exit(activateClaudeJspace() ? 0 : 1)
  }

  if (args.verifyChain) {
    const path =
      args.verifyChain === true
        ? // verify latest? require path
          null
        : resolve(String(args.verifyChain))
    if (!path) {
      console.error('Pass a chain path: --verify-chain tools/jlens/results/jlens-....jsonl')
      process.exit(1)
    }
    const v = verifyChain(path)
    console.log(JSON.stringify(v, null, 2))
    process.exit(v.valid ? 0 : 1)
  }

  const techniques = args.all
    ? ['tsp', 'tps', 'pbem']
    : args.technique
      ? [args.technique.toLowerCase()]
      : null

  if (!techniques) {
    usage()
    process.exit(1)
  }

  for (const t of techniques) {
    if (!['tps', 'tsp', 'pbem'].includes(t)) {
      console.error(`Unknown technique: ${t}`)
      process.exit(1)
    }
  }

  let { provider, model } = resolveModelAlias(args.model)
  if (args.ollamaModel) {
    provider = 'ollama'
    model = args.ollamaModel
  }

  console.log('\n' + '═'.repeat(60))
  console.log(' J-LENS — Behavioral Jacobian Probe')
  console.log(` techniques: ${techniques.join(', ')}`)
  console.log(` model: ${model}  provider: ${provider}`)
  console.log(' hodgeIndexHolds = none · SYNTH-008 active · WORM append-only')
  console.log(' Cite: Anthropic Claude public Messages API (research subject)')
  console.log('═'.repeat(60) + '\n')

  if (args.dryRun) {
    console.log('Dry run OK. Models map:', MODELS)
    return
  }

  let apiKey = null
  if (provider === 'anthropic') {
    apiKey = await resolveApiKey()
    if (!apiKey) {
      console.error('ERROR: ANTHROPIC_API_KEY not found (process env or Windows User).')
      console.error('Set User env, then re-open shell. Never commit keys.')
      process.exit(1)
    }
  }

  ensureResultsDir(RESULTS_DIR)
  const chainFile = args.out ? resolve(args.out) : resultsPath(RESULTS_DIR)
  const sealed = []
  const common = {
    provider,
    model,
    apiKey,
    modelLabel: args.model,
    maxTokens: args.maxTokens,
    delayMs: args.delayMs,
    samplesPerTemp: args.samples,
    repeats: args.repeats,
  }

  for (const tech of techniques) {
    console.log(`\n▶ Running ${tech.toUpperCase()} …`)
    let batch = []
    if (tech === 'tsp') batch = await runTspSuite(common)
    else if (tech === 'tps') batch = await runTpsSuite(common)
    else if (tech === 'pbem') batch = await runPbemSuite(common)

    for (const rec of batch) {
      const ts = new Date().toISOString()
      const toSeal = {
        ...rec,
        ts,
        legal: 'public_api_only',
        citation: 'Anthropic Claude Messages API — behavioral measurement subject',
        hodgeIndexHolds: null,
      }
      const seal = sealRecord(chainFile, toSeal)
      sealed.push({ ...toSeal, seal })
      console.log(
        `  sealed ${rec.probe_id}  H_J=${typeof rec.h_j_proxy === 'number' ? rec.h_j_proxy.toFixed(4) : 'n/a'}  gate=${rec.synth008_gate}  ${seal.slice(0, 22)}…`,
      )
    }

    if (tech === 'pbem' && provider === 'ollama') {
      const corr = correlateProxyVsLogprob(batch)
      console.log('\n  Ollama logprob correlation (proxy vs NLL):', corr)
      sealRecord(chainFile, {
        probe_id: `PBEM-CORR-${args.model}`,
        technique: 'PBEM_CORR',
        model,
        provider,
        correlation: corr,
        ts: new Date().toISOString(),
        synth008_gate: 'EVIDENCE',
        hodgeIndexHolds: null,
      })
    }
  }

  // Suite meta seal
  sealRecord(chainFile, {
    probe_id: `SUITE-META-${Date.now()}`,
    technique: 'SUITE',
    model,
    provider,
    techniques,
    n_records: sealed.length,
    mean_h_j:
      mean(sealed.map((r) => r.h_j_proxy).filter((x) => typeof x === 'number')) || null,
    ts: new Date().toISOString(),
    synth008_gate: 'EVIDENCE',
    hodgeIndexHolds: null,
  })

  const v = verifyChain(chainFile)
  console.log(`\nWORM chain: ${chainFile}`)
  console.log(`  valid=${v.valid} length=${v.length} tip=${(v.tip || '').slice(0, 24)}…`)

  summarize(sealed)

  // Optional JSON summary beside chain
  const summaryPath = chainFile.replace(/\.jsonl$/, '.summary.json')
  writeFileSync(
    summaryPath,
    JSON.stringify(
      {
        chain: chainFile,
        model,
        provider,
        techniques,
        n: sealed.length,
        mean_h_j_proxy: mean(sealed.map((r) => r.h_j_proxy).filter((x) => typeof x === 'number')),
        records: sealed.map((r) => ({
          probe_id: r.probe_id,
          technique: r.technique,
          h_j_proxy: r.h_j_proxy,
          synth008_gate: r.synth008_gate,
          seal: r.seal,
        })),
      },
      null,
      2,
    ),
  )
  console.log(`Summary: ${summaryPath}\n`)
}

main().catch((e) => {
  console.error('J-Lens fatal:', e.message)
  // [assistant-reconstructed tail — the owner's paste was truncated after the line
  //  above; minimal completion only (exit non-zero), no behavior invented. See STATUS.md]
  process.exit(1)
})
