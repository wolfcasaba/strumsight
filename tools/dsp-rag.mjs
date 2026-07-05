#!/usr/bin/env node
// Tiny BM25-ish retrieval over docs/rag/chunks — zero dependencies.
//   node tools/dsp-rag.mjs "onset threshold median"
//   node tools/dsp-rag.mjs --list
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const CHUNKS = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'rag', 'chunks');

const tokenize = (s) =>
  s.toLowerCase().normalize('NFKD').replace(/[^a-z0-9#+]+/g, ' ').split(/\s+/).filter((t) => t.length > 1);

const docs = readdirSync(CHUNKS).filter((f) => f.endsWith('.md')).map((f) => {
  const text = readFileSync(join(CHUNKS, f), 'utf8');
  const tokens = tokenize(text);
  const tf = new Map();
  for (const t of tokens) tf.set(t, (tf.get(t) ?? 0) + 1);
  return { file: f, text, tokens, tf, len: tokens.length };
});

const args = process.argv.slice(2);
if (!args.length || args[0] === '--list') {
  for (const d of docs) {
    const topic = d.text.match(/^topic:\s*(.+)$/m)?.[1] ?? '';
    console.log(`${d.file}  —  ${topic}`);
  }
  process.exit(0);
}

const query = tokenize(args.join(' '));
const N = docs.length;
const avgLen = docs.reduce((a, d) => a + d.len, 0) / N;
const k1 = 1.4, b = 0.6;

const scored = docs.map((d) => {
  let score = 0;
  for (const q of query) {
    const df = docs.filter((x) => x.tf.has(q)).length;
    if (!df) continue;
    const idf = Math.log(1 + (N - df + 0.5) / (df + 0.5));
    const f = d.tf.get(q) ?? 0;
    score += idf * ((f * (k1 + 1)) / (f + k1 * (1 - b + b * (d.len / avgLen))));
  }
  return { d, score };
}).filter((x) => x.score > 0).sort((a, b2) => b2.score - a.score);

if (!scored.length) { console.log('no hits'); process.exit(0); }
for (const { d, score } of scored.slice(0, 3)) {
  const topic = d.text.match(/^topic:\s*(.+)$/m)?.[1] ?? '';
  console.log(`\n=== ${d.file}  (score ${score.toFixed(2)})  ${topic} ===`);
  // print the body (past frontmatter), trimmed
  const body = d.text.split('---').slice(2).join('---').trim();
  console.log(body.length > 1600 ? body.slice(0, 1600) + '\n…' : body);
}
