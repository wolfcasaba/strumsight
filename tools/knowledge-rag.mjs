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
const flags = {
  corpus: null, top: 8, reindex: false, json: false, stat: false, bm25: false,
  emb: false, eval: false, maxPerDoc: null, explain: false,
};
const words = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  // ADR 0316 §2.5: több korpusz egy hívásban — `--corpus lessons,halts,adr`.
  if (a === '--corpus') flags.corpus = parseCorpusList(argv[++i]);
  else if (a === '--top') flags.top = Number(argv[++i]);
  else if (a === '--reindex') flags.reindex = true;
  else if (a === '--json') flags.json = true;
  else if (a === '--stat') flags.stat = true;
  else if (a === '--bm25') flags.bm25 = true;
  else if (a === '--emb') flags.emb = true;
  else if (a === '--eval') flags.eval = true;
  else if (a === '--explain') flags.explain = true;
  else if (a === '--max-per-doc') flags.maxPerDoc = Number(argv[++i]);
  else words.push(a);
}
const query = words.join(' ').trim();

/** `--corpus lessons,halts` → Set{lessons,halts}; üres/hiányzó → null (mind). */
function parseCorpusList(raw) {
  if (!raw) return null;
  const names = String(raw).split(',').map((s) => s.trim()).filter(Boolean);
  return names.length ? new Set(names) : null;
}

/** Egy chunk beleesik-e a kért korpusz-szűrőbe. */
const inCorpus = (name) => !flags.corpus || flags.corpus.has(name);

// ADR 0316 §2.2 — SÚLYOZOTT fúzió, `RAG_W_BM25` / `RAG_W_EMB` felülírja.
//
// Az ADR eredeti előírása az volt, hogy az alapértelmezés a LEXIKAI ág javára
// billenjen: a feltevés szerint egy ritka domain-terminus (flaky, H8, tmux,
// win32) erős lexikai jelét hígította a szemantikus ág. MÉRVE a
// `tools/rag-eval.tsv` mércén ez az irány ROMLIK: bm25×2 → 36,8% (MRR 0,254),
// míg emb×2 → 52,6% (MRR 0,491).
//
// A feltevés azért dőlt meg, mert egyetlen anekdotán állt: a szó szerint
// beírt „flaky" szón. A valós használat PARAFRÁZIS („miért bukik el néha a
// property gate…"), ahol nincs közös ritka szó, tehát a BM25-ág vak — mérve
// ugyanerre a kérdésre L142 a BM25 top-40-ben SINCS benne, a szemantikus ágon
// viszont #11. Ezért az alapértelmezés a szemantikus ág javára billen.
const W_BM25 = Number(process.env.RAG_W_BM25 ?? 1.0);
const W_EMB = Number(process.env.RAG_W_EMB ?? 2.0);
// ADR 0316 §2.3 — dokumentum-korlát: egy forrásfájlból legfeljebb ennyi chunk
// kerülhet a LISTÁRA (az indexet nem érinti). 0 = korlátozás nélkül.
const MAX_PER_DOC = Number(flags.maxPerDoc ?? process.env.RAG_MAX_PER_DOC ?? 2);

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
  const want = inCorpus;

  if (want('lessons') && existsSync(join(ROOT, 'docs', 'LESSONS.md'))) {
    for (const c of chunkLessons(readFileSync(join(ROOT, 'docs', 'LESSONS.md'), 'utf8'))) chunks.push({ corpus: 'lessons', ...c });
  }
  // ADR 0316 §2.4 — `handoff` korpusz. MÉRVE: a HANDOFF.md (3 059 sor) és a
  // docs/handoff-archive.md (9 034 sor) — együtt 12 093 sor OPERATÍV történet —
  // egyáltalán nem volt indexelve, miközben épp ezt kérdezi az önjavító ág.
  if (want('handoff')) {
    for (const rel of ['HANDOFF.md', 'docs/handoff-archive.md']) {
      const path = join(ROOT, rel);
      if (!existsSync(path)) continue;
      for (const c of chunkMarkdownSections(readFileSync(path, 'utf8'), `handoff/${rel}`, rel)) {
        chunks.push({ corpus: 'handoff', ...c });
      }
    }
  }
  for (const [corpus, dir] of [['adr', 'docs/adr'], ['rounds', 'docs/rounds'], ['reviews', 'docs/reviews'], ['sdd', 'docs/sdd'], ['dsp', 'docs/rag/chunks'], ['plan', 'docs/plans/gpt']]) {
    if (!want(corpus) || !existsSync(join(ROOT, dir))) continue;
    for (const path of walk(join(ROOT, dir), new Set(['.md']))) {
      const rel = relative(ROOT, path);
      for (const c of chunkMarkdownSections(readFileSync(path, 'utf8'), `${corpus}/${rel}`, rel)) chunks.push({ corpus, ...c });
    }
  }
  // A LÁNC SAJÁT TANULÁSA (ADR 0312 §4.3): a `docs/LESSONS.md` a lassú, írott
  // réteg, de a napi tanulság előbb a halt-fájlokban és a git-notes
  // kísérlet-pufferben (HORIZON konvenció) születik meg. Ezek nélkül a
  // visszakeresés csak azt látja, amit valaki már megfogalmazott.
  if (want('halts')) {
    // A `.pipeline/` a HUB-ban él (gitignore-olt), a körök viszont külön
    // munkapéldányból futnak — ezért a hub állapotkönyvtárát is megnézzük.
    const candidates = [process.env.PIPELINE_STATE_DIR, join(ROOT, '.pipeline'), join(homedir(), 'music-theory', '.pipeline')];
    const dir = candidates.find((c) => c && existsSync(c)) || join(ROOT, '.pipeline');
    if (existsSync(dir)) {
      for (const name of readdirSync(dir).filter((f) => /^(halted-|round-status-|heal-status)/.test(f))) {
        const path = join(dir, name);
        try {
          if (!statSync(path).isFile()) continue;
          const body = readFileSync(path, 'utf8').trim();
          if (!body) continue;
          const round = (body.match(/^round=(\S+)/m) || [])[1] || name;
          const code = (body.match(/^halt=(\S+)/m) || [])[1] || (body.match(/^outcome=(\S+)/m) || [])[1] || '';
          for (const c of splitOversized(body, `halts/${name}`, `${round} ${code}`.trim(), { file: `.pipeline/${name}` })) {
            chunks.push({ corpus: 'halts', ...c });
          }
        } catch { /* egy olvashatatlan állapotfájl nem buktathatja az indexet */ }
      }
    }
  }
  if (want('notes')) {
    try {
      const raw = execSync(`git -C ${ROOT} log --notes=* --pretty=format:%H%x1f%s%x1f%N%x1e -n 400`, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
      for (const record of raw.split('\x1e')) {
        const [hash, subject, note] = record.split('\x1f');
        if (!note || !note.trim()) continue;
        chunks.push({
          corpus: 'notes',
          id: `notes/${(hash || '').trim().slice(0, 12)}`,
          title: `git-note: ${(subject || '').trim().slice(0, 120)}`,
          text: `${(subject || '').trim()}\n\n${note.trim()}`,
          file: 'git-notes',
        });
      }
    } catch { /* notes nélküli klón: nem hiba */ }
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

/**
 * Súlyozott RRF (ADR 0316 §2.2).
 *
 * `rankings`: [{ rows, weight, label }] — ágakként a rendezett találatlista.
 * A visszaadott térkép id → { score, ranks } , ahol a `ranks` ágankénti
 * 1-alapú helyezést tart. A helyezés MEGJELENÍTÉSE szándékos: a puszta RRF-
 * pontszám (1/(k+rang)) rang-információ, nem relevancia — a felhasználó abból
 * nem tudja megítélni, hogy erős vagy gyenge találatot lát.
 */
function rrf(rankings, k = 60) {
  const out = new Map();
  for (const { rows, weight, label } of rankings) {
    rows.forEach((row, rank) => {
      const id = row.chunk?.id ?? row.id;
      const cur = out.get(id) ?? { score: 0, ranks: {} };
      cur.score += weight / (k + rank + 1);
      cur.ranks[label] = rank + 1;
      out.set(id, cur);
    });
  }
  return out;
}

/**
 * Dokumentum-korlát (ADR 0316 §2.3): egy forrásfájlból legfeljebb `max` chunk
 * kerülhet a listára. MÉRVE: egy lekérdezés első négy helyét ugyanannak a
 * briefnek négy szakasza foglalta el. A korlát a LISTÁRA vonatkozik, nem az
 * indexre; a kiszorított forrásokat a `--explain` megmutatja.
 */
/**
 * Korpuszok, amelyekben EGY fájl önálló rekordok GYŰJTEMÉNYE, nem egyetlen
 * összefüggő dokumentum. Itt a „dokumentum" rossz csoportosítási egység:
 * a `docs/LESSONS.md` 346 leckéje mind ugyanaz a `file`, tehát a korlát az
 * egész korpuszt két találatra vágná.
 *
 * MÉRVE: naiv fájl-alapú korláttal a mérce 53,8% → 38,5%-ra ROMLOTT, és a
 * döntő leckék (L142, L143, L323) teljesen kiestek a top-20-ból.
 */
const RECORD_CORPORA = new Set(['lessons', 'halts', 'notes']);

const groupKey = (chunk, id) =>
  RECORD_CORPORA.has(chunk?.corpus) ? id : (chunk?.file ?? id);

function capPerDocument(rows, max) {
  if (!max || max <= 0) return { kept: rows, dropped: [] };
  const seen = new Map();
  const kept = [];
  const dropped = [];
  for (const r of rows) {
    const key = groupKey(r.chunk, r.id);
    const n = seen.get(key) ?? 0;
    if (n >= max) { dropped.push(r); continue; }
    seen.set(key, n + 1);
    kept.push(r);
  }
  return { kept, dropped };
}

/**
 * A KÖZÖS rangsorolás — a keresés és a mérce ugyanezt hívja, hogy a mérce
 * tényleg azt mérje, amit a felhasználó kap (ADR 0316 §2.1).
 * Visszaad: { kept, dropped } — a dokumentum-korláttal szűrt, rendezett lista.
 */
async function rankAll(q) {
  const index = loadIndex();
  const hasIndex = Object.keys(index.entries || {}).length > 0;
  const chunks = collect();
  const byId = new Map(chunks.map((c) => [c.id, c]));
  const lexical = flags.emb ? [] : bm25(chunks, q).slice(0, 50);

  let semantic = [];
  if (!flags.bm25 && OPENAI_KEY && hasIndex) {
    const [qv] = await embed([q]);
    const store = loadVectors(index);
    semantic = Object.entries(index.entries)
      .filter(([id]) => byId.has(id) && inCorpus(byId.get(id).corpus))
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

  const branches = [];
  if (lexical.length) branches.push({ rows: lexical, weight: W_BM25, label: 'bm25' });
  if (semantic.length) branches.push({ rows: semantic, weight: W_EMB, label: 'emb' });

  const fused = rrf(branches);
  const ordered = [...fused.entries()]
    .sort((a, b) => b[1].score - a[1].score)
    .map(([id, v]) => ({ id, score: v.score, ranks: v.ranks, chunk: byId.get(id) }))
    .filter((r) => r.chunk);

  // A korlát a RENDEZETT listára megy, és CSAK utána vágunk `--top`-ra —
  // különben a kiszorított helyeket nem töltené fel a következő forrás.
  return capPerDocument(ordered, MAX_PER_DOC);
}

/** A mérce ezt hívja: a végleges, korlátozott sorrend. */
async function rankFor(q) {
  const { kept } = await rankAll(q);
  return kept;
}

async function search() {
  const { kept, dropped } = await rankAll(query);
  const results = kept.slice(0, flags.top);

  if (flags.json) {
    console.log(JSON.stringify(results.map((r) => ({
      id: r.id, corpus: r.chunk.corpus, title: r.chunk.title, file: r.chunk.file,
      score: Number(r.score.toFixed(5)), ranks: r.ranks, excerpt: r.chunk.text.slice(0, 600),
    })), null, 2));
    return;
  }
  if (!results.length) { console.log('nincs találat'); return; }
  for (const r of results) {
    const where = Object.entries(r.ranks).map(([k, v]) => `${k}#${v}`).join(' ') || '—';
    console.log(`\n=== [${r.chunk.corpus}] ${r.chunk.title}  (${r.id}, score ${r.score.toFixed(4)}, ${where}) ===`);
    console.log(r.chunk.text.slice(0, 700).trim());
  }
  if (flags.explain) {
    console.log(`\n--- fúzió: bm25×${W_BM25} emb×${W_EMB}, dok-korlát ${MAX_PER_DOC || 'nincs'} ---`);
    const bySource = new Map();
    for (const d of dropped.slice(0, 40)) bySource.set(d.chunk.file, (bySource.get(d.chunk.file) ?? 0) + 1);
    if (bySource.size) {
      console.log('a dokumentum-korlát miatt kiesett:');
      for (const [file, n] of bySource) console.log(`  ${file}  (${n} további szakasz)`);
    }
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

/**
 * Visszakeresési MÉRCE (ADR 0316 §2.1).
 *
 * `tools/rag-eval.tsv`: kérdés ⇥ elvárt chunk-azonosító ⇥ elvárt legrosszabb
 * helyezés ⇥ korpusz-szűrő (opcionális). Jelenti a találati arányt és az
 * átlagos reciprok helyezést (MRR), hogy a rangsor hangolása MÉRT legyen,
 * ne ízlés kérdése.
 */
async function runEval() {
  const evalFile = join(ROOT, 'tools', 'rag-eval.tsv');
  if (!existsSync(evalFile)) {
    console.error(`nincs mérce-fájl: ${evalFile}`);
    process.exit(2);
  }
  const rows = readFileSync(evalFile, 'utf8').split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'))
    .map((l) => l.split('\t').map((s) => s.trim()));

  let hits = 0;
  let mrr = 0;
  const failures = [];
  for (const [q, expectedId, wantRankRaw, corpusRaw] of rows) {
    const wantRank = Number(wantRankRaw || 5);
    flags.corpus = parseCorpusList(corpusRaw);
    flags.top = Math.max(wantRank, 20);
    const ranked = await rankFor(q);
    // Az elvárt oszlop `|`-lal ALTERNATÍVÁKAT sorolhat: egy kérdésre több
    // dokumentum is jogosan válaszolhat (mérve: a pengetés-irány kérdésre a
    // `006-strum-direction` és a `015-strum-direction-ml` egyaránt helyes).
    // A találat SZAKASZ-szinten is számít: ha a jó dokumentum másik szakasza
    // jön vissza, az is a jó helyre mutat.
    const wanted = expectedId.split('|').map((s) => s.trim()).filter(Boolean);
    const matches = (r) => wanted.some((e) =>
      r.id === e || r.id.startsWith(`${e}#`) || r.chunk.title.startsWith(e));
    const pos = ranked.findIndex(matches);
    const rank = pos < 0 ? 0 : pos + 1;
    if (rank && rank <= wantRank) { hits++; mrr += 1 / rank; }
    else failures.push({ q, expectedId, wantRank, rank: rank || '—' });
    const mark = rank && rank <= wantRank ? 'OK ' : 'HIB';
    console.log(`${mark} ${String(rank || '—').padStart(3)}/${String(wantRank).padEnd(2)}  ${expectedId.padEnd(10)} ${q.slice(0, 62)}`);
  }
  const pct = rows.length ? (100 * hits / rows.length).toFixed(1) : '0.0';
  console.log(`\ntalálat: ${hits}/${rows.length} (${pct}%)   MRR: ${(mrr / (rows.length || 1)).toFixed(3)}`);
  console.log(`fúzió:   bm25×${W_BM25} emb×${W_EMB}   dok-korlát: ${MAX_PER_DOC || 'nincs'}`);
  if (failures.length) process.exitCode = 1;
}

if (flags.stat) { stat(); }
else if (flags.reindex) { await reindex(); }
else if (flags.eval) { await runEval(); }
else if (!query) {
  console.error('használat: node tools/knowledge-rag.mjs [--corpus a,b] [--top N] [--json] [--explain] "<kérdés>"');
  console.error('           node tools/knowledge-rag.mjs --eval     # visszakeresési mérce');
  process.exit(2);
}
else { await search(); }
