#!/usr/bin/env node
/**
 * StrumSight unified doc RAG — BM25 + optional semantic (Jina v3) hybrid.
 *
 *   node tools/rag.mjs "onset threshold median"              # BM25, all corpora
 *   node tools/rag.mjs --corpus dsp "chroma tuning"          # one corpus only
 *   node tools/rag.mjs --corpus plan --status active "ui"    # filter plan chunks by status
 *   node tools/rag.mjs --semantic "hogyan mérjük a strum pontosságot"  # hybrid (BM25 + embeddings, RRF)
 *   node tools/rag.mjs --reindex                             # rebuild the embedding index
 *   node tools/rag.mjs --list [--corpus plan]                # list chunks
 *
 * Corpora:
 *   dsp  → docs/rag/chunks/      MEASURED truth (params tuned on real audio). Static, wins conflicts.
 *   plan → docs/plans/gpt/       Development-plan chunks (intent, not proof). Living: frontmatter
 *                                `status:` moves as rounds land (active|done|conflicts|superseded|rejected).
 *
 * RULE: a plan chunk NEVER overrides a dsp chunk. If a plan section contradicts a measured
 * parameter/verdict, the measurement wins and the plan chunk goes to `status: conflicts`
 * with the refuting evidence — it stays in the corpus so the idea can't come back unnoticed.
 *
 * Semantic search needs an embedding key (JINA_API_KEY, read from the web repo's .env.local —
 * already present on this box). Without a key it silently degrades to pure BM25.
 * Embedding index: dev-tools/doc-rag-index.json (gitignored, hash-based incremental).
 */
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CORPORA = {
  dsp: join(ROOT, 'docs', 'rag', 'chunks'),
  plan: join(ROOT, 'docs', 'plans', 'gpt'),
};
const INDEX_FILE = join(ROOT, 'dev-tools', 'doc-rag-index.json');
const EMBED_MAX_CHARS = 8000; // jina-embeddings-v3 comfortably holds this
const TOP_K = 3;

// ---------- env (embedding key lives in the web repo's .env.local) ----------
function loadEnvFile(path) {
  if (!existsSync(path)) return;
  for (const raw of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'")))
      val = val.slice(1, -1);
    if (!(key in process.env)) process.env[key] = val;
  }
}
loadEnvFile('/home/ubuntu/Recipewiser/.env.local');
loadEnvFile(join(ROOT, '.env.local'));
const JINA_API_KEY = process.env.JINA_API_KEY;
const JINA_EMBED_MODEL = process.env.JINA_EMBED_MODEL || 'jina-embeddings-v3';

// ---------- args ----------
const argv = process.argv.slice(2);
const flags = { corpus: null, status: null, semantic: false, list: false, reindex: false };
const queryParts = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--corpus') flags.corpus = argv[++i];
  else if (a === '--status') flags.status = argv[++i];
  else if (a === '--semantic') flags.semantic = true;
  else if (a === '--list') flags.list = true;
  else if (a === '--reindex') flags.reindex = true;
  else queryParts.push(a);
}
if (flags.corpus && !CORPORA[flags.corpus]) {
  console.error(`unknown corpus "${flags.corpus}" — use: ${Object.keys(CORPORA).join(' | ')}`);
  process.exit(1);
}

// ---------- load docs ----------
function frontmatterField(text, field) {
  const m = text.match(new RegExp(`^${field}:\\s*(.+)$`, 'm'));
  return m ? m[1].trim() : '';
}
const tokenize = (s) =>
  s.toLowerCase().normalize('NFKD').replace(/[^a-z0-9#+]+/g, ' ').split(/\s+/).filter((t) => t.length > 1);

const docs = [];
for (const [corpus, dir] of Object.entries(CORPORA)) {
  if (flags.corpus && flags.corpus !== corpus) continue;
  if (!existsSync(dir)) continue;
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.md'))) {
    if (/^(README|INDEX)\.md$/i.test(f)) continue; // meta files, not chunks
    const text = readFileSync(join(dir, f), 'utf8');
    const status = frontmatterField(text, 'status');
    if (flags.status && status !== flags.status) continue;
    const tokens = tokenize(text);
    const tf = new Map();
    for (const t of tokens) tf.set(t, (tf.get(t) ?? 0) + 1);
    docs.push({
      corpus, file: f, path: join(dir, f), text, tf, len: tokens.length,
      topic: frontmatterField(text, 'topic'), status,
      hash: createHash('sha1').update(text).digest('hex').slice(0, 12),
    });
  }
}

if (flags.list) {
  for (const d of docs) {
    const st = d.status ? `  [${d.status}]` : '';
    console.log(`${d.corpus}/${d.file}${st}  —  ${d.topic}`);
  }
  process.exit(0);
}

// ---------- BM25 ----------
function bm25Rank(query) {
  const q = tokenize(query);
  const N = docs.length;
  const avgLen = docs.reduce((a, d) => a + d.len, 0) / (N || 1);
  const k1 = 1.4, b = 0.6;
  return docs
    .map((d) => {
      let score = 0;
      for (const t of q) {
        const df = docs.filter((x) => x.tf.has(t)).length;
        if (!df) continue;
        const idf = Math.log(1 + (N - df + 0.5) / (df + 0.5));
        const f = d.tf.get(t) ?? 0;
        score += idf * ((f * (k1 + 1)) / (f + k1 * (1 - b + b * (d.len / avgLen))));
      }
      return { d, score };
    })
    .filter((x) => x.score > 0)
    .sort((a, b2) => b2.score - a.score);
}

// ---------- semantic (Jina v3) ----------
async function jinaEmbed(texts, task) {
  const res = await fetch('https://api.jina.ai/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${JINA_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: JINA_EMBED_MODEL, task, input: texts.map((t) => t.slice(0, EMBED_MAX_CHARS)) }),
  });
  if (!res.ok) throw new Error(`jina ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return (await res.json()).data.map((d) => d.embedding);
}
const cosine = (a, b) => {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
};

function loadIndex() {
  try { return JSON.parse(readFileSync(INDEX_FILE, 'utf8')); } catch { return { model: JINA_EMBED_MODEL, entries: {} }; }
}
async function ensureIndex() {
  const index = loadIndex();
  if (index.model !== JINA_EMBED_MODEL) index.entries = {};
  index.model = JINA_EMBED_MODEL;
  const missing = docs.filter((d) => index.entries[`${d.corpus}/${d.file}`]?.hash !== d.hash);
  if (missing.length) {
    process.stderr.write(`embedding ${missing.length} changed chunk(s)…\n`);
    const vecs = await jinaEmbed(missing.map((d) => d.text), 'retrieval.passage');
    missing.forEach((d, i) => { index.entries[`${d.corpus}/${d.file}`] = { hash: d.hash, vec: vecs[i] }; });
    // prune deleted files
    const live = new Set(docs.map((d) => `${d.corpus}/${d.file}`));
    for (const k of Object.keys(index.entries)) if (!live.has(k)) delete index.entries[k];
    mkdirSync(dirname(INDEX_FILE), { recursive: true });
    writeFileSync(INDEX_FILE, JSON.stringify(index));
  }
  return index;
}
async function semanticRank(query, index) {
  const [qv] = await jinaEmbed([query], 'retrieval.query');
  return docs
    .map((d) => ({ d, score: cosine(qv, index.entries[`${d.corpus}/${d.file}`].vec) }))
    .sort((a, b) => b.score - a.score);
}

// ---------- RRF fusion ----------
function rrfFuse(rankings, k = 60) {
  const scores = new Map();
  for (const ranking of rankings) {
    ranking.forEach(({ d }, rank) => {
      const key = `${d.corpus}/${d.file}`;
      scores.set(key, { d, score: (scores.get(key)?.score ?? 0) + 1 / (k + rank + 1) });
    });
  }
  return [...scores.values()].sort((a, b) => b.score - a.score);
}

// ---------- main ----------
if (flags.reindex) {
  if (!JINA_API_KEY) { console.error('no JINA_API_KEY — nothing to reindex (BM25 needs no index)'); process.exit(1); }
  await ensureIndex();
  console.log('embedding index up to date:', INDEX_FILE);
  process.exit(0);
}
if (!queryParts.length) {
  console.error('usage: node tools/rag.mjs [--corpus dsp|plan] [--status active] [--semantic] "<query>"');
  process.exit(1);
}
const query = queryParts.join(' ');
let ranked;
if (flags.semantic && JINA_API_KEY) {
  const index = await ensureIndex();
  ranked = rrfFuse([bm25Rank(query), await semanticRank(query, index)]);
} else {
  if (flags.semantic) process.stderr.write('no JINA_API_KEY found — falling back to BM25\n');
  ranked = bm25Rank(query);
}
if (!ranked.length) { console.log('no hits'); process.exit(0); }
for (const { d, score } of ranked.slice(0, TOP_K)) {
  const st = d.status ? `  [${d.status}]` : '';
  console.log(`\n=== ${d.corpus}/${d.file}  (score ${score.toFixed(3)})${st}  ${d.topic} ===`);
  const body = d.text.split('---').slice(2).join('---').trim();
  console.log(body.length > 1600 ? body.slice(0, 1600) + '\n…' : body);
}
