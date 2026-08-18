#!/usr/bin/env node
/**
 * StrumSight knowledge RAG — a TELJES fejlesztési tudás egy indexben.
 *
 *   node tools/knowledge-rag.mjs "PIPELINE_ORCH_SWAP_ENGINE szivárgás"
 *   node tools/knowledge-rag.mjs --corpus lessons --top 5 "gate csonkítás"
 *   node tools/knowledge-rag.mjs --reindex            # inkrementális újraindexelés
 *   node tools/knowledge-rag.mjs --stat               # index kora, mérete, frissessége
 *   node tools/knowledge-rag.mjs --json "…"           # gépi kimenet (brief-lint, self-heal)
 *
 * MIÉRT külön tool a `tools/rag.mjs` mellett: az előbbi ELŐRE chunkolt
 * kézi korpuszokat (dsp, plan) kezel, fájl = chunk alapon. Itt a bemenet a
 * repó ÉLŐ tudása, amit gépileg kell darabolni: 193 ADR, 322 lecke (~200k
 * token egyetlen fájlban), 257 brief, 244 review, 918 Dart + 689 teszt +
 * 111 tooling fájl. Mérve (2026-08-18): a régi kód-index 168 fájlt ismert a
 * 918-ból, és három hete állt — a `lib/features/{practice_generator,ai_tutor,
 * vision}` egyáltalán nem volt benne.
 *
 * Korpuszok:
 *   lessons  docs/LESSONS.md          leckénként (`## L<n>`) — a MÉRT kudarcok
 *   adr      docs/adr/*.md            szekciónként — a kötelező döntések
 *   rounds   docs/rounds/*.md         szekciónként — a kör-briefek
 *   reviews  docs/reviews/*.md        szekciónként — a független review-k
 *   sdd      docs/sdd/*.md            szekciónként — a specifikáció
 *   dsp      docs/rag/chunks/*.md     a mért DSP-igazság (fájl = chunk)
 *   plan     docs/plans/gpt/*.md      terv-kivonatok (fájl = chunk)
 *   code     lib|test|tools|tool      szimbólum-közeli ablakok
 *
 * Az index a repón KÍVÜL él (`~/.local/state/strumsight-rag/`), mert minden
 * kör külön munkapéldányban dolgozik: így egyszer épül és mindenki használja.
 *
 * Beágyazás: OpenAI `text-embedding-3-small` (kulcs: OPENAI_API_KEY vagy a
 * `~/Recipewiser/.env.local`). Kulcs nélkül a keresés BM25-re esik vissza —
 * degradál, de nem hal meg.
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { homedir } from 'node:os';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const INDEX_DIR = process.env.RAG_INDEX_DIR || join(homedir(), '.local', 'state', 'strumsight-rag');
const INDEX_FILE = join(INDEX_DIR, 'index.json');
// MÉRVE (2026-08-18): 18 110 chunk × 1536 float JSON-ban 359 MB — a lekérdezés
// minden hívásnál beolvasná és parse-olná. A vektorok ezért bináris
// oldalfájlba mennek (Float32, rekordonként dim*4 bájt ≈ 110 MB), az
// `index.json` csak a metaadatot és a rekord-eltolást tartja.
const VECTOR_FILE = join(INDEX_DIR, 'vectors.f32');
const EMBED_MODEL = process.env.RAG_EMBED_MODEL || 'text-embedding-3-small';
const EMBED_BATCH = Number(process.env.RAG_EMBED_BATCH || 96);
const EMBED_DELAY_MS = Number(process.env.RAG_EMBED_DELAY_MS || 900);
const MAX_CHUNK_CHARS = Number(process.env.RAG_MAX_CHUNK_CHARS || 6000);
// MÉRVE (2026-08-18): az embeddings végpont bemenetenként 8192 TOKEN-t enged,
// és a magyar próza + kód ~2 karakter/token sűrűségű — egy 24k karakteres
// bemenet elhasalt (`maximum input length is 8192 tokens`). A kemény vágás a
// darabolóban van, nem a hívásnál: így a chunk-azonosító és a tárolt szöveg is
// azt tükrözi, amit tényleg beágyaztunk.
const HARD_CHUNK_CHARS = Number(process.env.RAG_HARD_CHUNK_CHARS || 12000);
const CODE_WINDOW_LINES = 120;
const CODE_OVERLAP_LINES = 20;

// ---------- kulcs (sosem logoljuk) ----------
function loadEnvFile(path) {
  if (!existsSync(path)) return;
  for (const raw of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) val = val.slice(1, -1);
    if (!(key in process.env) && val) process.env[key] = val;
  }
}
// USER-DÖNTÉS (2026-08-18): „az openait ne használjuk csak a rag adatbázishoz".
// Ezért a kulcs SAJÁT nevet kap (`RAG_OPENAI_API_KEY`) és saját fájlt
// (`~/.rag-openai.env`, 0600): egy `OPENAI_API_KEY`-t kereső session — például
// egy önjavító kör, ami a Codex-hitelesítést akarja helyreállítani — nem
// találja meg, és nem tudja motor-hívásra fordítani. Mérve 2026-08-18: pontosan
// ez történt, amikor a kulcs még `OPENAI_API_KEY` néven, `~/.openai.env`-ben állt.
loadEnvFile(join(homedir(), '.rag-openai.env'));
const OPENAI_KEY = process.env.RAG_OPENAI_API_KEY || '';

// ---------- CLI ----------
const argv = process.argv.slice(2);
const flags = { corpus: null, top: 8, reindex: false, json: false, stat: false, bm25: false };
const words = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--corpus') flags.corpus = argv[++i];
  else if (a === '--top') flags.top = Number(argv[++i]);
  else if (a === '--reindex') flags.reindex = true;
  else if (a === '--json') flags.json = true;
  else if (a === '--stat') flags.stat = true;
  else if (a === '--bm25') flags.bm25 = true;
  else words.push(a);
}
const query = words.join(' ').trim();

// ---------- chunkolók ----------
const sha = (s) => createHash('sha1').update(s).digest('hex').slice(0, 12);

function splitOversized(text, id, title, extra) {
  // A szekció-alapú darabolás után maradó túl hosszú blokk: bekezdés-határon
  // vágunk, hogy a chunk önmagában értelmes maradjon.
  if (text.length <= MAX_CHUNK_CHARS) return [{ id, title, text, ...extra }];
  const parts = [];
  let buffer = '';
  let n = 1;
  const flush = () => {
    if (!buffer) return;
    // Kemény vágás: egy bekezdés önmagában is lehet hosszabb a limitnél
    // (nagy táblázat, kódblokk) — ilyenkor karakter-határon szeleteljük.
    for (let at = 0; at < buffer.length; at += HARD_CHUNK_CHARS) {
      parts.push({ id: `${id}#${n}`, title: `${title} (${n}.)`, text: buffer.slice(at, at + HARD_CHUNK_CHARS), ...extra });
      n += 1;
    }
    buffer = '';
  };
  for (const paragraph of text.split(/\n\n+/)) {
    if (buffer.length + paragraph.length > MAX_CHUNK_CHARS && buffer) flush();
    buffer += (buffer ? '\n\n' : '') + paragraph;
  }
  flush();
  return parts;
}

function chunkMarkdownSections(text, idPrefix, file) {
  // `## ` szintű szekciók: egy ADR/brief/review döntése vagy szakasza egy chunk.
  const lines = text.split('\n');
  const headingAt = [];
  lines.forEach((line, i) => { if (/^##\s+\S/.test(line)) headingAt.push(i); });
  const title0 = (lines.find((l) => /^#\s+\S/.test(l)) || file).replace(/^#\s+/, '').trim();
  if (!headingAt.length) return splitOversized(text, idPrefix, title0, { file });
  const out = [];
  const preamble = lines.slice(0, headingAt[0]).join('\n').trim();
  if (preamble) out.push(...splitOversized(preamble, `${idPrefix}#0`, `${title0} — fejléc`, { file }));
  headingAt.forEach((start, k) => {
    const end = k + 1 < headingAt.length ? headingAt[k + 1] : lines.length;
    const body = lines.slice(start, end).join('\n').trim();
    if (!body) return;
    const heading = lines[start].replace(/^##\s+/, '').trim();
    out.push(...splitOversized(body, `${idPrefix}#${k + 1}`, `${title0} — ${heading}`, { file }));
  });
  return out;
}

function chunkLessons(text) {
  // Egy lecke = egy chunk. A `## L<n> — <cím>` marker a repó saját, kivétel
  // nélküli konvenciója (322 lecke, mérve).
  const out = [];
  const re = /^## (L\d+)\s*[—-]?\s*(.*)$/gm;
  const marks = [...text.matchAll(re)];
  marks.forEach((m, i) => {
    const start = m.index;
    const end = i + 1 < marks.length ? marks[i + 1].index : text.length;
    const body = text.slice(start, end).trim();
    out.push(...splitOversized(body, `lessons/${m[1]}`, `${m[1]} — ${m[2].slice(0, 120)}`, { file: 'docs/LESSONS.md' }));
  });
  return out;
}

const CODE_SYMBOL = /^(?:\s*)(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+)*(?:class|mixin|enum|extension|typedef|def|function|async def)\s+([A-Za-z_][\w]*)/;

function chunkCode(text, file) {
  const lines = text.split('\n');
  const out = [];
  for (let start = 0; start < lines.length; start += CODE_WINDOW_LINES - CODE_OVERLAP_LINES) {
    const window = lines.slice(start, start + CODE_WINDOW_LINES);
    if (!window.join('').trim()) continue;
    let symbol = '';
    for (let i = start; i >= 0; i--) {
      const m = lines[i].match(CODE_SYMBOL);
      if (m) { symbol = m[1]; break; }
    }
    out.push({
      id: `code/${file}#${start + 1}`,
      title: `${file}:${start + 1}${symbol ? ` (${symbol})` : ''}`,
      text: window.join('\n').slice(0, MAX_CHUNK_CHARS),
      file,
    });
  }
  return out;
}

function walk(dir, exts, acc = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    if (e.name.startsWith('.') || e.name === 'node_modules' || e.name === '__pycache__' || e.name === '.venv') continue;
    const full = join(dir, e.name);
    if (e.isDirectory()) walk(full, exts, acc);
    else if (exts.has(extname(e.name))) acc.push(full);
  }
  return acc;
}

function collect() {
  const chunks = [];
  const want = (name) => !flags.corpus || flags.corpus === name;

  if (want('lessons') && existsSync(join(ROOT, 'docs', 'LESSONS.md'))) {
    for (const c of chunkLessons(readFileSync(join(ROOT, 'docs', 'LESSONS.md'), 'utf8'))) chunks.push({ corpus: 'lessons', ...c });
  }
  for (const [corpus, dir] of [['adr', 'docs/adr'], ['rounds', 'docs/rounds'], ['reviews', 'docs/reviews'], ['sdd', 'docs/sdd'], ['dsp', 'docs/rag/chunks'], ['plan', 'docs/plans/gpt']]) {
    if (!want(corpus) || !existsSync(join(ROOT, dir))) continue;
    for (const path of walk(join(ROOT, dir), new Set(['.md']))) {
      const rel = relative(ROOT, path);
      for (const c of chunkMarkdownSections(readFileSync(path, 'utf8'), `${corpus}/${rel}`, rel)) chunks.push({ corpus, ...c });
    }
  }
  if (want('code')) {
    for (const dir of ['lib', 'test', 'tools', 'tool']) {
      for (const path of walk(join(ROOT, dir), new Set(['.dart', '.py', '.sh', '.mjs']))) {
        const rel = relative(ROOT, path);
        for (const c of chunkCode(readFileSync(path, 'utf8'), rel)) chunks.push({ corpus: 'code', ...c });
      }
    }
  }
  for (const c of chunks) c.hash = sha(c.text);
  return chunks;
}

// ---------- beágyazás ----------
async function embed(texts) {
  const res = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: EMBED_MODEL, input: texts.map((t) => t.slice(0, HARD_CHUNK_CHARS)) }),
  });
  if (!res.ok) {
    const error = new Error(`openai ${res.status}: ${(await res.text()).slice(0, 160).replace(/\s+/g, ' ')}`);
    error.status = res.status;
    // A 429 fejléce megmondja, mennyit kell várni — a vak backoff vagy túl
    // sokat vár, vagy azonnal újra elbukik (mérve: 28 újrapróba egy futáson).
    error.retryAfterMs = Number(res.headers.get('retry-after-ms')) ||
      Number(res.headers.get('retry-after')) * 1000 || 0;
    throw error;
  }
  const json = await res.json();
  return json.data.sort((a, b) => a.index - b.index).map((d) => d.embedding);
}

function loadIndex() {
  try { return JSON.parse(readFileSync(INDEX_FILE, 'utf8')); } catch { return { meta: {}, entries: {} }; }
}

/** A vektorok visszaolvasása: új alak (bináris oldalfájl) VAGY régi alak (JSON `vec`). */
function loadVectors(index) {
  const dim = index.meta?.dim;
  if (dim && existsSync(VECTOR_FILE)) {
    const buffer = readFileSync(VECTOR_FILE);
    return { dim, data: new Float32Array(buffer.buffer, buffer.byteOffset, Math.floor(buffer.length / 4)) };
  }
  return null; // régi alak: az entries[].vec mezőt használjuk
}

function writeIndex(index, vectors) {
  mkdirSync(INDEX_DIR, { recursive: true });
  if (vectors) {
    const dim = vectors.dim;
    const flat = new Float32Array(vectors.order.length * dim);
    vectors.order.forEach((id, i) => flat.set(vectors.byId.get(id), i * dim));
    writeFileSync(VECTOR_FILE, Buffer.from(flat.buffer));
    vectors.order.forEach((id, i) => { index.entries[id].offset = i; delete index.entries[id].vec; });
    index.meta.dim = dim;
  }
  writeFileSync(INDEX_FILE, JSON.stringify(index));
}
function headCommit() {
  try { return execSync('git -C ' + ROOT + ' rev-parse HEAD', { encoding: 'utf8' }).trim(); } catch { return ''; }
}

async function reindex() {
  if (!OPENAI_KEY) { console.error('nincs OPENAI_API_KEY — az index nem építhető (a keresés BM25-tel megy)'); process.exit(2); }
  const chunks = collect();
  const index = loadIndex();
  if (index.meta?.model !== EMBED_MODEL) index.entries = {};
  const vectorStore = { dim: null, byId: new Map(), order: [] };
  const existing = loadVectors(index);
  for (const [id, entry] of Object.entries(index.entries)) {
    if (entry.vec) { vectorStore.byId.set(id, Float32Array.from(entry.vec)); vectorStore.dim ??= entry.vec.length; }
    else if (existing && Number.isInteger(entry.offset)) {
      vectorStore.byId.set(id, existing.data.subarray(entry.offset * existing.dim, (entry.offset + 1) * existing.dim));
      vectorStore.dim ??= existing.dim;
    }
  }
  const missing = chunks.filter((c) => index.entries[c.id]?.hash !== c.hash || !vectorStore.byId.has(c.id));
  process.stderr.write(`[knowledge-rag] ${chunks.length} chunk, ebből ${missing.length} új/változott\n`);
  // A köteget NEM a darabszám, hanem a KARAKTER-költségvetés zárja: az
  // embeddings végpont kérésenkénti token-limitje mérve elhasal 96 darab
  // ~6000 tokenes chunkon (400 invalid_request). Egy köteg legfeljebb
  // RAG_EMBED_CHARS karakter (~1/4 token) vagy EMBED_BATCH darab.
  const CHAR_BUDGET = Number(process.env.RAG_EMBED_CHARS || 60000);
  const batches = [];
  let current = [];
  let currentChars = 0;
  for (const chunk of missing) {
    const size = Math.min(chunk.text.length + chunk.title.length, HARD_CHUNK_CHARS);
    if (current.length && (current.length >= EMBED_BATCH || currentChars + size > CHAR_BUDGET)) {
      batches.push(current); current = []; currentChars = 0;
    }
    current.push(chunk); currentChars += size;
  }
  if (current.length) batches.push(current);
  let done = 0;
  for (const batch of batches) {
    let vectors;
    for (let attempt = 1; ; attempt++) {
      try { vectors = await embed(batch.map((c) => `${c.title}\n\n${c.text}`)); break; }
      catch (error) {
        if (attempt >= 8) throw error;
        const wait = error.retryAfterMs || Math.min(30000, 1500 * 2 ** (attempt - 1));
        process.stderr.write(`  429/hiba, várok ${Math.round(wait / 1000)}s (${attempt}/7)\n`);
        await new Promise((r) => setTimeout(r, wait + 250));
      }
    }
    batch.forEach((c, k) => {
      index.entries[c.id] = { hash: c.hash, corpus: c.corpus, title: c.title, file: c.file };
      vectorStore.byId.set(c.id, Float32Array.from(vectors[k]));
      vectorStore.dim ??= vectors[k].length;
    });
    done += batch.length;
    // Ütemezés: a kulcs percenkénti token-kerete mérve szűk (folyamatos 429).
    // Egy rövid, fix szünet olcsóbb, mint a 30 másodperces backoff-lépcsők.
    if (EMBED_DELAY_MS) await new Promise((r) => setTimeout(r, EMBED_DELAY_MS));
    if (done % (EMBED_BATCH * 10) < EMBED_BATCH) {
      process.stderr.write(`  ${done}/${missing.length}\n`);
      // Részleges mentés: a beágyazás a drága lépés; egy megszakadt futás után
      // a következő indulás csak a hiányzót kéri le újra.
      index.meta = { ...(index.meta || {}), model: EMBED_MODEL, partial: true };
      vectorStore.order = [...vectorStore.byId.keys()].filter((id) => index.entries[id]);
      writeIndex(index, vectorStore);
    }
  }
  const live = new Set(chunks.map((c) => c.id));
  for (const key of Object.keys(index.entries)) if (!live.has(key)) delete index.entries[key];
  const counts = {};
  for (const c of chunks) counts[c.corpus] = (counts[c.corpus] || 0) + 1;
  index.meta = { model: EMBED_MODEL, updatedAt: new Date().toISOString(), commit: headCommit(), counts, chunks: chunks.length };
  vectorStore.order = [...vectorStore.byId.keys()].filter((id) => index.entries[id]);
  writeIndex(index, vectorStore);
  process.stderr.write(`[knowledge-rag] kész: ${chunks.length} chunk → ${INDEX_FILE}\n`);
}

// ---------- keresés ----------
const tokenize = (s) => s.toLowerCase().normalize('NFKD').replace(/[^a-z0-9_#+.]+/g, ' ').split(/\s+/).filter((t) => t.length > 1);
const cosine = (a, b) => {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
};

function bm25(chunks, q) {
  const terms = tokenize(q);
  const N = chunks.length || 1;
  const df = new Map();
  const tfs = chunks.map((c) => {
    const tf = new Map();
    for (const t of tokenize(`${c.title} ${c.text}`)) tf.set(t, (tf.get(t) ?? 0) + 1);
    for (const t of new Set(tf.keys())) df.set(t, (df.get(t) ?? 0) + 1);
    return tf;
  });
  const avg = tfs.reduce((a, tf) => a + [...tf.values()].reduce((x, y) => x + y, 0), 0) / N;
  const k1 = 1.4, b = 0.6;
  return chunks.map((c, i) => {
    const tf = tfs[i];
    const len = [...tf.values()].reduce((x, y) => x + y, 0);
    let score = 0;
    for (const t of terms) {
      const n = df.get(t);
      if (!n) continue;
      const idf = Math.log(1 + (N - n + 0.5) / (n + 0.5));
      const f = tf.get(t) ?? 0;
      score += idf * ((f * (k1 + 1)) / (f + k1 * (1 - b + b * (len / (avg || 1)))));
    }
    return { chunk: c, score };
  }).filter((x) => x.score > 0).sort((a, b2) => b2.score - a.score);
}

function rrf(rankings, k = 60) {
  const scores = new Map();
  for (const ranking of rankings) {
    ranking.forEach((row, rank) => {
      const id = row.chunk?.id ?? row.id;
      scores.set(id, (scores.get(id) ?? 0) + 1 / (k + rank + 1));
    });
  }
  return scores;
}

async function search() {
  const index = loadIndex();
  const hasIndex = Object.keys(index.entries || {}).length > 0;
  const chunks = collect();
  const byId = new Map(chunks.map((c) => [c.id, c]));
  const lexical = bm25(chunks, query).slice(0, 50);

  let semantic = [];
  if (!flags.bm25 && OPENAI_KEY && hasIndex) {
    const [qv] = await embed([query]);
    const store = loadVectors(index);
    semantic = Object.entries(index.entries)
      .filter(([id]) => byId.has(id) && (!flags.corpus || byId.get(id).corpus === flags.corpus))
      .map(([id, e]) => {
        const vec = e.vec
          ? e.vec
          : store && Number.isInteger(e.offset)
            ? store.data.subarray(e.offset * store.dim, (e.offset + 1) * store.dim)
            : null;
        return vec ? { chunk: byId.get(id), score: cosine(qv, vec) } : null;
      })
      .filter(Boolean)
      .sort((a, b) => b.score - a.score)
      .slice(0, 50);
  }

  const fused = rrf(semantic.length ? [lexical, semantic] : [lexical]);
  const results = [...fused.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, flags.top)
    .map(([id, score]) => ({ id, score, chunk: byId.get(id) }))
    .filter((r) => r.chunk);

  if (flags.json) {
    console.log(JSON.stringify(results.map((r) => ({
      id: r.id, corpus: r.chunk.corpus, title: r.chunk.title, file: r.chunk.file,
      score: Number(r.score.toFixed(5)), excerpt: r.chunk.text.slice(0, 600),
    })), null, 2));
    return;
  }
  if (!results.length) { console.log('nincs találat'); return; }
  for (const r of results) {
    console.log(`\n=== [${r.chunk.corpus}] ${r.chunk.title}  (${r.id}, score ${r.score.toFixed(4)}) ===`);
    console.log(r.chunk.text.slice(0, 700).trim());
  }
}

function stat() {
  const index = loadIndex();
  const meta = index.meta || {};
  const head = headCommit();
  console.log(`index:      ${INDEX_FILE}${existsSync(INDEX_FILE) ? '' : '  (MÉG NEM ÉPÜLT)'}`);
  console.log(`modell:     ${meta.model || '-'}`);
  console.log(`frissítve:  ${meta.updatedAt || '-'}`);
  console.log(`commit:     ${meta.commit ? meta.commit.slice(0, 8) : '-'}  (HEAD: ${head.slice(0, 8)})`);
  if (meta.commit && head && meta.commit !== head) {
    let behind = '?';
    try { behind = execSync(`git -C ${ROOT} rev-list --count ${meta.commit}..HEAD`, { encoding: 'utf8' }).trim(); } catch {}
    console.log(`ELAVULT:    ${behind} commit-tal a HEAD mögött — futtasd: node tools/knowledge-rag.mjs --reindex`);
  }
  console.log(`chunk:      ${meta.chunks ?? 0}`);
  for (const [corpus, n] of Object.entries(meta.counts || {})) console.log(`  ${corpus.padEnd(9)} ${n}`);
}

if (flags.stat) { stat(); }
else if (flags.reindex) { await reindex(); }
else if (!query) { console.error('használat: node tools/knowledge-rag.mjs [--corpus <név>] [--top N] [--json] "<kérdés>"'); process.exit(2); }
else { await search(); }
