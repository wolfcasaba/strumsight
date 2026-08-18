# E99-R23 (GOV-17) — Visszakeresés-minőség: mérce, súlyozott fúzió, dokumentum-korlát, hiányzó korpuszok

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ b38c22f2`)
- **Típus:** **governance-kör** — a lánc SAJÁT tudás-visszakeresése
- **Kör-azonosító:** `E99-R23`. Emberi neve **GOV-17**.
- **Előfeltétel:** nincs (a `tools/knowledge-rag.mjs` fájlhalmaza diszjunkt az E99-R14…R22 köröktől)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0316`](../adr/0316-rag-retrieval-quality.md) — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tools/knowledge-rag.mjs",
  "tools/rag-eval.tsv",
  "tools/tests/test_rag_retrieval_quality.py",
  "docs/execution/pipeline-orchestrator-prompt.md",
  ".github/workflows/router-ci.yml",
  "docs/rounds/e99-r23-gov-17-rag-retrieval-quality.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = normal, indoklás:** a diff egy visszakereső eszközt és annak
> mércéjét érinti. Nem nyúl a kapuhoz, a lánc vezérléséhez, a merge-úthoz,
> sem futásidejű alkalmazás-viselkedéshez. A rossz találat félrevezet, de nem
> gyengíti a mércét — a kapu és a review változatlan.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 0.1 Visszakeresett előzmény (tudás-index, ADR 0312 §4.1)

Ez a kör a visszakeresésről szól, ezért az előzményt magával az eszközzel
mértem, és a mérés a bukását mutatta:

| futtatás | `lessons/L142` helyezése |
|---|---|
| `--bm25 --corpus lessons "flaky"` | **1.** |
| `--corpus lessons "flaky teszt zöld újrafuttatásra kapu lépés bukás"` | 4. |
| `--top 12`, teljes korpusz, ugyanaz a kérdés | **6.** |

Az **`adr/0312`** (tudás-index) a döntési előzmény: hibrid BM25 + embedding,
RRF fúzió, korpuszonkénti chunkolás. **Nincs releváns előzmény** viszont a
rangsor MÉRÉSÉRE: visszakeresési fixture ma nem létezik, ezért az ADR 0316 §2
a mércét teszi az első feladattá.

## 1. Cél

Az index él és hasznos, de éles feladaton mérve **nem adta vissza a döntő
leckét** (§0.1): a top-5-öt sablon-című review-szakaszok foglalták el, és a
döntő találatot végül `grep` hozta. Egy magabiztos, de rosszul rangsoroló
visszakeresés rosszabb, mint a semmi — ugyanaz a hibaosztály, amit az ADR 0312
az elavult indexnél már kimondott.

## 2. Jelenlegi állapot — mérve a kódban

- `tools/knowledge-rag.mjs`: hibrid BM25 + embedding, RRF fúzió **egyenlő
  súllyal**; dokumentum-szintű korlát nincs; `flags.corpus === name` — egyetlen
  korpusz-név fogadható.
- Korpuszok: `lessons` 328, `adr` 949, `rounds` 3674, `reviews` 1972,
  `sdd` 3822, `dsp` 130, `plan` 3386, `halts` 24, `notes` 112, `code` 3955.
- `HANDOFF.md` (3 059 sor) és `docs/handoff-archive.md` (9 034 sor)
  **nincs indexelve**.
- A `.pipeline/halted-*.txt` rekordokból 5 él a lemezen; a `halts` korpusz 24 chunk.

## 3. Feladatok

### D1 — Mérce először: `tools/rag-eval.tsv` és `--eval`

- TSV oszlopok: `query`, `expect_id`, `expect_rank`, `corpus` (üres = mind).
- Kezdő sorok (a §0.1 mért esete + a §2-ből levezethető ellenpróbák):
  `flaky teszt zöld újrafuttatásra` → `lessons/L142` ≤ 3;
  `H8 rebase konfliktus` → `lessons/L77` ≤ 3;
  `tmux slot-zár szivárgás` → `lessons/L312` ≤ 3;
  `ambiens PIPELINE_ env override` → `lessons/L313` ≤ 3.
- `node tools/knowledge-rag.mjs --eval [--file <tsv>]`: soronként lefuttatja a
  kérdést, jelenti a tényleges helyezést és a teljesítés arányát.
- Kilépési kód **mindig 0** (jelentés, nem kapu — ADR 0316 §3). Ha nincs
  API-kulcs, a futtató BM25-módban fut és ezt KIÍRJA.

### D2 — Súlyozott fúzió

- `RAG_W_BM25` és `RAG_W_EMB` környezeti változó, az RRF-hozzájárulás szorzója.
- Alapértelmezés: a lexikai ág javára billen (a §0.1 mért oka).
- A súlyok a `--json` alakban is megjelennek, hogy a mérés reprodukálható legyen.

### D3 — Dokumentum-korlát

- Egy forrásfájlból legfeljebb **kettő** chunk kerülhet a találati listára.
- A kiesett forrásokat a `--json` alak külön mezőben felsorolja.
- A korlát a LISTÁRA vonatkozik, az indexre nem.

### D4 — `handoff` korpusz

- Új korpusz: `HANDOFF.md` + `docs/handoff-archive.md`, a meglévő
  `chunkMarkdownSections` szakasz-bontóval.
- A `--stat` kimenet sorolja fel az új korpuszt is.

### D5 — Több korpusz egy hívásban

- `--corpus lessons,halts,adr` — vesszős lista; egyetlen név változatlanul működik.
- Ismeretlen korpusz-név → hibaüzenet a lehetséges nevekkel, kilépési kód 2.

### D6 — Az orchesztrátor-prompt szűkítsen

A pre-flight visszakeresés (§4.9) mondja ki: a kör témájára először
`--corpus lessons,halts,adr` szűkítéssel keress, és csak utána a teljes
korpuszon. Indoklás: a sablon-című review- és brief-szakaszok darabszámmal
nyernek (§0.1).

### D7 — CI-szűrő

`.github/workflows/router-ci.yml` `paths:` fedje le a `tools/rag-eval.tsv` és
`tools/tests/test_rag_retrieval_quality.py` fájlokat. A fedés **nő, sosem
szűkül** (mérve: PR #309 piros CI-kapuja).

## 4. Mérce-mátrix (`tools/tests/test_rag_retrieval_quality.py`)

Hermetikus: kicsi, kézzel írt chunk-halmazon (injektált index), **API-hívás
nélkül**, BM25-ágon és álszemantikus ágon (rögzített vektorokkal).

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| dokumentum-korlát | egy forrásfájl 5 illeszkedő szakasza | a listán legfeljebb 2 marad belőle |
| korlát nem vág le mást | 5 találat 5 KÜLÖNBÖZŐ fájlból | mind az 5 marad |
| súly hat | ugyanaz a kérdés `RAG_W_BM25=1` és `=5` mellett | az erős lexikai találat helyezése JAVUL |
| több korpusz | `--corpus lessons,adr` | csak e két korpusz találatai jönnek |
| ismeretlen korpusz | `--corpus nincsilyen` | hibaüzenet + kilépési kód 2 |
| `handoff` korpusz | fixture `HANDOFF.md` | a `--stat` felsorolja, a keresés megtalálja |
| `--eval` jelentés | 2 soros fixture-TSV, egyik teljesül, másik nem | jelentés 1/2, kilépési kód **0** |

**Súly-hármas** (a D2 alapértelmezésének két oldala és maga az alapérték):

| cella | `RAG_W_BM25` | elvárt |
|---|---|---|
| az alapérték **alatt** | a lexikai ág súlya kisebb az alapértéknél | az erős lexikai találat helyezése ROMLIK vagy változatlan |
| az alapértéken (**rajta**) | az alapérték | a fixture-találat a §4 „súly hat" cellája szerinti helyen |
| az alapérték **fölött** | nagyobb súly | a helyezés nem romlik |

**Falszifikációs cellák (kötelezők):**

1. A D3 dokumentum-korlát kiszedése → a „dokumentum-korlát" cella **PIROS**
   (5 szakasz ugyanabból a fájlból) → visszaállítás után zöld.
2. A D2 súly figyelmen kívül hagyása (a szorzó bekötése nélkül) → a „súly hat"
   cella **PIROS** → visszaállítás után zöld.

## 5. Tilos zóna — amit ez a kör NEM tesz

- **Nem cserél embedding-modellt**, és nem épít indexet nulláról: a súlyozás és
  a korlát **lekérdezés-idejű**, a `--reindex` inkrementális marad.
- **Nem nyúl a kulcs-politikához** (ADR 0312): a kulcs kizárólag a RAG-é, motor
  hitelesítésére TILOS.
- Nem tesz a visszakeresésből kaput: az `--eval` jelentés, kilépési kódja 0.
- Nem módosítja a `tools/round-pipeline.sh`-t, a kaput és a landolót — így nem
  ütközik az E99-R14…R22 körökkel.
- Fájlok: `docs/adr/**`, `.ai/router.toml`, `.pipeline/**`, `docs/LESSONS.md`,
  Dart források — tilos.

## 6. Definition of Done

1. D1–D7 kész; egyetlen korpusz-név és kulcs nélküli futás változatlanul működik.
2. `tools/tests/test_rag_retrieval_quality.py` lefedi a §4 mind a hét celláját
   és a súly-hármast, API-hívás nélkül.
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate-lépések külön processzben futnak; a csonkítatlan kimenet a bizonyíték.
A teljes suite + property gate a CI-ban fut (ADR 0053).
