// ASSISTANT-RECONSTRUCTED (2026-11-06) — the original lib/api.mjs lives in the
// owner's private foundry-intel repo and has not been received. Built only from
// the contracts exercised by the received code:
//   resolveModelAlias(alias) -> { provider, model }
//   resolveApiKey() -> key string or null (env only; keys are never stored)
//   MODELS (map printed on --dry-run)
//   callClaude({ apiKey, prompt, model, temperature, maxTokens }) -> { text }
//   callOllama({ prompt, model, temperature, maxTokens, logprobs })
//     -> { text, entropy_nats|null }
//   roughTokens(prompt) -> token-ish string pieces (techniques/tps.mjs)
// It is NOT the owner's original. Replace on sight when the original arrives.

export const MODELS = {
  claude: { provider: 'anthropic', model: 'claude-sonnet-5' },
  opus: { provider: 'anthropic', model: 'claude-opus-5-5' },
  haiku: { provider: 'anthropic', model: 'claude-haiku-4-5' },
  qwen: { provider: 'ollama', model: 'qwen3' },
  nemotron: { provider: 'ollama', model: 'nemotron-super' },
  granite: { provider: 'ollama', model: 'granite3' },
}

export function resolveModelAlias(alias) {
  const key = String(alias || 'claude').toLowerCase()
  if (MODELS[key]) return { ...MODELS[key] }
  // Unknown alias: treat as a raw Ollama model id.
  return { provider: 'ollama', model: String(alias) }
}

export async function resolveApiKey() {
  return process.env.ANTHROPIC_API_KEY || null
}

function ollamaHost() {
  return process.env.OLLAMA_HOST || 'http://localhost:11434'
}

export async function callClaude({ apiKey, prompt, model, temperature = 0.7, maxTokens = 256 }) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      temperature,
      messages: [{ role: 'user', content: prompt }],
    }),
  })
  if (!res.ok) throw new Error(`Anthropic API ${res.status}: ${await res.text()}`)
  const data = await res.json()
  const text = (data.content || [])
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('')
  return { text, entropy_nats: null }
}

export async function callOllama({ prompt, model, temperature = 0.7, maxTokens = 256, logprobs = false }) {
  const res = await fetch(`${ollamaHost()}/api/generate`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      prompt,
      stream: false,
      options: { temperature, num_predict: maxTokens },
    }),
  })
  if (!res.ok) throw new Error(`Ollama ${res.status}: ${await res.text()}`)
  const data = await res.json()
  // Ollama's public API does not reliably expose per-token logprobs; the
  // ground-truth field stays null and PBEM correlation reports n<2 honestly.
  return { text: data.response || '', entropy_nats: null }
}

/** Rough tokenization: word pieces and single punctuation marks. */
export function roughTokens(text) {
  return String(text).match(/[A-Za-z0-9']+|[^\sA-Za-z0-9']/g) || []
}
