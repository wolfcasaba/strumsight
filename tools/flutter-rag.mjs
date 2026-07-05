#!/usr/bin/env node
/**
 * RecipeWiser MOBILE (Flutter) Semantic Code Search — local RAG over lib/.
 *
 *   node tools/flutter-rag.mjs --reindex          # build/refresh the index
 *   node tools/flutter-rag.mjs "<query>"          # search (default top 10)
 *   node tools/flutter-rag.mjs "<query>" 5        # top 5
 *
 * Storage:  dev-tools/flutter-code-index.json   (gitignored — local only)
 * Embeddings: same providers as the web code-search (jina → minimax → openai).
 *   Reads keys from the main repo's .env.local (JINA_API_KEY etc.).
 *
 * Mirrors scripts/code-search.mjs in the web repo, but Dart-tuned: scans .dart,
 * chunks by class/mixin/enum/extension/typedef + top-level functions, and tags
 * each chunk with its feature "scope" (lib/features/<scope>/…) for scope review.
 */
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { join, relative, extname, sep, posix, dirname } from 'node:path';
import { createHash } from 'node:crypto';

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
// Embedding keys live in the main web repo's .env.local.
loadEnvFile('/home/ubuntu/Recipewiser/.env.local');
loadEnvFile('.env.local');

const ROOT = '/home/ubuntu/recipewiser-mobile';
const INDEX_FILE = join(ROOT, 'dev-tools', 'flutter-code-index.json');
const SCAN_DIRS = ['lib'];
const EXTS = new Set(['.dart']);
const MAX_CHUNK_CHARS = 4000;
const BATCH_SIZE = Number(process.env.CODE_SEARCH_BATCH || 16);
const BATCH_DELAY_MS = Number(process.env.CODE_SEARCH_DELAY_MS || 2000);
const MAX_RETRIES = 6;

const JINA_API_KEY = process.env.JINA_API_KEY;
const JINA_EMBED_MODEL = process.env.JINA_EMBED_MODEL || 'jina-embeddings-v3';
const MINIMAX_API_KEY = process.env.MINIMAX_API_KEY;
const MINIMAX_API_BASE = (process.env.MINIMAX_API_BASE || 'https://api.minimax.io/v1').replace(/\/$/, '');
const MINIMAX_EMBED_MODEL = process.env.MINIMAX_EMBED_MODEL || 'embo-01';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENAI_EMBED_MODEL = process.env.OPENAI_EMBED_MODEL || 'text-embedding-3-small';
const PROVIDER = (process.env.EMBED_PROVIDER || 'jina').toLowerCase();
let activeProvider = PROVIDER === 'auto' ? (JINA_API_KEY ? 'jina' : MINIMAX_API_KEY ? 'minimax' : 'openai') : PROVIDER;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
class RateLimitError extends Error {}

function walk(dir, out = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    if (e.name.startsWith('.')) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (EXTS.has(extname(e.name))) out.push(p);
  }
  return out;
}
const toPosix = (p) => p.split(sep).join(posix.sep);
const rel = (p) => toPosix(relative(ROOT, p));

/** Feature scope from path: lib/features/<scope>/… → <scope>; lib/core/… → core. */
function scopeOf(relPath) {
  const m = relPath.match(/^lib\/features\/([^/]+)\//);
  if (m) return m[1];
  if (relPath.startsWith('lib/core/')) return 'core';
  return 'root';
}

const DART_SYMBOL_RE =
  /^(?:abstract\s+|final\s+|sealed\s+|base\s+|mixin\s+)*(class|mixin|enum|extension|typedef)\s+([A-Za-z_]\w*)/;
const DART_FUNC_RE =
  /^(?:Future<[^>]*>|Stream<[^>]*>|void|bool|int|double|String|num|Widget|[A-Z]\w*\??|List<[^>]*>)\s+([a-z_]\w*)\s*\(/;

function chunkFile(filePath) {
  const src = readFileSync(filePath, 'utf8');
  if (!src.trim()) return [];
  const lines = src.split('\n');
  const starts = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(DART_SYMBOL_RE);
    if (m) { starts.push({ line: i, name: m[2], kind: m[1] }); continue; }
    const f = lines[i].match(DART_FUNC_RE);
    if (f && !lines[i].includes('=>') ) starts.push({ line: i, name: f[1], kind: 'function' });
  }
  if (starts.length === 0)
    return [{ chunkIndex: 0, startLine: 1, endLine: lines.length, content: src.slice(0, MAX_CHUNK_CHARS), symbolName: null, symbolKind: 'file' }];
  const chunks = [];
  for (let i = 0; i < starts.length; i++) {
    const s = starts[i];
    const endLine = i + 1 < starts.length ? starts[i + 1].line - 1 : lines.length - 1;
    let content = lines.slice(s.line, endLine + 1).join('\n');
    if (content.length > MAX_CHUNK_CHARS) content = content.slice(0, MAX_CHUNK_CHARS);
    chunks.push({ chunkIndex: i, startLine: s.line + 1, endLine: endLine + 1, content, symbolName: s.name, symbolKind: s.kind });
  }
  return chunks;
}
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

async function embedJina(texts, type) {
  const task = type === 'query' ? 'retrieval.query' : 'retrieval.passage';
  const res = await fetch('https://api.jina.ai/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${JINA_API_KEY}`, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ model: JINA_EMBED_MODEL, task, input: texts }),
  });
  const t = await res.text();
  if (res.status === 429) throw new RateLimitError('Jina 429');
  if (!res.ok) throw new Error(`Jina ${res.status}: ${t.slice(0, 200)}`);
  return JSON.parse(t).data.map((d) => d.embedding);
}
async function embedMiniMax(texts, type) {
  const res = await fetch(`${MINIMAX_API_BASE}/embeddings`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${MINIMAX_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: MINIMAX_EMBED_MODEL, texts, type }),
  });
  const t = await res.text();
  const json = JSON.parse(t);
  if (res.status === 429 || json?.base_resp?.status_code === 1002) throw new RateLimitError('MiniMax RL');
  if (!res.ok) throw new Error(`MiniMax ${res.status}`);
  if (Array.isArray(json.vectors)) return json.vectors;
  return json.data.map((d) => d.embedding);
}
async function embedOpenAI(texts) {
  const res = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: OPENAI_EMBED_MODEL, input: texts }),
  });
  const t = await res.text();
  if (res.status === 429) throw new RateLimitError('OpenAI 429');
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${t.slice(0, 200)}`);
  return JSON.parse(t).data.map((d) => d.embedding);
}
function callProvider(texts, type) {
  if (activeProvider === 'jina') return embedJina(texts, type);
  if (activeProvider === 'minimax') return embedMiniMax(texts, type);
  return embedOpenAI(texts, type);
}
async function embed(texts, type) {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try { return await callProvider(texts, type); }
    catch (e) {
      if (e instanceof RateLimitError) {
        if (activeProvider === 'jina' && MINIMAX_API_KEY) { activeProvider = 'minimax'; continue; }
        if (activeProvider === 'minimax' && OPENAI_API_KEY) { activeProvider = 'openai'; continue; }
        await sleep(Math.min(60000, 4000 * 2 ** attempt)); continue;
      }
      throw e;
    }
  }
  throw new Error('Embeddings failed after retries');
}

function loadIndex() {
  if (!existsSync(INDEX_FILE)) return { meta: { dim: null }, chunks: [] };
  try { return JSON.parse(readFileSync(INDEX_FILE, 'utf8')); } catch { return { meta: { dim: null }, chunks: [] }; }
}
function saveIndex(index) { mkdirSync(dirname(INDEX_FILE), { recursive: true }); writeFileSync(INDEX_FILE, JSON.stringify(index), 'utf8'); }
function cosine(a, b) {
  let dot = 0, na = 0, nb = 0; const len = Math.min(a.length, b.length);
  for (let i = 0; i < len; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  const d = Math.sqrt(na) * Math.sqrt(nb); return d === 0 ? 0 : dot / d;
}

async function reindex() {
  const files = SCAN_DIRS.flatMap((d) => walk(join(ROOT, d)));
  console.log(`[flutter-rag] ${files.length} .dart files`);
  const index = loadIndex();
  const existing = new Map();
  for (const c of index.chunks) existing.set(`${c.file_path}|${c.chunk_index}`, c);
  const current = [];
  const seen = new Set();
  for (const f of files) {
    const fp = rel(f);
    for (const c of chunkFile(f)) {
      const key = `${fp}|${c.chunkIndex}`;
      seen.add(key);
      current.push({ key, filePath: fp, scope: scopeOf(fp), ...c, hash: sha256(c.content) });
    }
  }
  for (const k of [...existing.keys()]) if (!seen.has(k)) existing.delete(k);
  const toEmbed = current.filter((c) => existing.get(c.key)?.content_hash !== c.hash);
  console.log(`[flutter-rag] ${current.length} chunks, ${toEmbed.length} need embedding (provider=${activeProvider})`);
  for (let i = 0; i < toEmbed.length; i += BATCH_SIZE) {
    const batch = toEmbed.slice(i, i + BATCH_SIZE);
    const inputs = batch.map((b) => `${b.filePath} :: ${b.symbolName ?? ''}\n${b.content}`.slice(0, 8000));
    let vectors;
    try { vectors = await embed(inputs, 'db'); }
    catch (e) { console.error(`\n[flutter-rag] batch failed: ${e.message}; saving partial`); break; }
    if (index.meta.dim == null && vectors[0]) index.meta.dim = vectors[0].length;
    for (let j = 0; j < batch.length; j++) {
      const b = batch[j];
      existing.set(b.key, {
        file_path: b.filePath, chunk_index: b.chunkIndex, scope: b.scope,
        start_line: b.startLine, end_line: b.endLine, content: b.content,
        content_hash: b.hash, symbol_name: b.symbolName, symbol_kind: b.symbolKind, embedding: vectors[j],
      });
    }
    process.stdout.write(`\r[flutter-rag] embedded ${Math.min(i + BATCH_SIZE, toEmbed.length)}/${toEmbed.length}`);
    if ((i / BATCH_SIZE) % 10 === 9) { index.chunks = [...existing.values()]; saveIndex(index); }
    if (i + BATCH_SIZE < toEmbed.length) await sleep(BATCH_DELAY_MS);
  }
  process.stdout.write('\n');
  index.chunks = [...existing.values()];
  index.meta.updatedAt = new Date().toISOString();
  index.meta.provider = activeProvider;
  saveIndex(index);
  // Scope summary.
  const byScope = {};
  for (const c of index.chunks) byScope[c.scope] = (byScope[c.scope] || 0) + 1;
  console.log(`[flutter-rag] indexed ${index.chunks.length} chunks across ${Object.keys(byScope).length} scopes:`);
  for (const [s, n] of Object.entries(byScope).sort((a, b) => b[1] - a[1])) console.log(`  ${s.padEnd(16)} ${n}`);
}

async function search(query, topK) {
  const index = loadIndex();
  if (!index.chunks.length) { console.error('No index — run --reindex first.'); process.exit(1); }
  const [qv] = await embed([query], 'query');
  const scoped = process.env.SCOPE;
  const pool = scoped ? index.chunks.filter((c) => c.scope === scoped) : index.chunks;
  const ranked = pool.map((c) => ({ c, score: cosine(qv, c.embedding) })).sort((a, b) => b.score - a.score).slice(0, topK);
  for (const { c, score } of ranked) {
    console.log(`\n${score.toFixed(3)}  [${c.scope}] ${c.file_path}:${c.start_line}  ${c.symbol_kind} ${c.symbol_name ?? ''}`);
    console.log('  ' + c.content.split('\n').slice(0, 3).join('\n  '));
  }
}

const args = process.argv.slice(2);
if (args[0] === '--reindex') reindex();
else if (args.length) search(args[0], Number(args[1]) || 10);
else { console.log('Usage: node tools/flutter-rag.mjs --reindex | "<query>" [topK]'); process.exit(1); }
