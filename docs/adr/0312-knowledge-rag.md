# ADR 0312 — Tudás-RAG: a teljes fejlesztési korpusz visszakereshetővé tétele

**Státusz:** elfogadva (2026-08-18, user-kérdés: „ha a kódból és az összes
fejlesztési tervekből csinálnánk egy rag adatbázist az segítené a fejlesztést?",
majd döntés: „az openait ne használjuk csak a rag adatbázishoz").

## 1. Miért — a mérés, ami eldöntötte

A kérdésre a válasz nem elvi, hanem mért: **ugyanaznap egy kör állt meg egy
visszakeresési hiba miatt.** Az `E99-R14` H3-mal halt, mert a kötelező teljes
tooling-suite három függetlenségi tesztje pirosra váltott a cron
`PIPELINE_ORCH_SWAP_ENGINE` env-szivárgása miatt. Ez a jelenség **órákkal
korábban már le volt írva** a HANDOFF-ban (E07-R21 heal jegyzete) — a tudás
megvolt, csak senki nem hozta elő. Ára: egy halt + három önjavító kísérlet.

Ugyanez a hibaosztály korábban is mért: az `E07-R21/H2` halt oka az volt, hogy
a brief glosszája ellentmondott az ADR 0266 TÉNYLEGES szövegének.

Ellenpélda ugyanabból a napból, hogy a hatókör ne legyen túlbecsülve: a
motor-override beragadása, a tmux slot-zár öröklése és az ambiens env-szivárgás
mind **mechanizmus-hibák** voltak, amiket MÉRÉS talált meg, nem olvasás. A RAG
ezekre nem segített volna. **A repó saját, kemény leckéje érvényben marad: a
próza nem tart, a gépi őr tart** — ezért a RAG önmagában nem cél, hanem kapuk
bemenete (§4).

## 2. Mi volt eddig (mérve 2026-08-18)

| Korpusz | Lemezen | Indexelve volt? |
|---|---|---|
| `lib/` Dart | 918 fájl | 168 fájl / 310 chunk, **2026-07-28-i** index (814 commit-tal korábbi) |
| `lib/features/{practice_generator,ai_tutor,vision}` | él | **egyáltalán nem** |
| `test/` (a mérce) | 689 fájl | nem |
| `tools/` (a lánc maga) | 111 fájl | nem |
| `docs/LESSONS.md` | 322 lecke (~200k token) | **nem** |
| `docs/adr/` | 193 ADR | **nem** |
| briefek / review-k | 257 / 244 | nem |

Az elavult index a legrosszabb fajta: magabiztos, de régi választ ad, és ezt
semmi nem jelezte.

## 3. Döntés

`tools/knowledge-rag.mjs` — egyetlen, gépileg darabolt index a teljes élő
tudásról. Mért eredmény az első teljes építés után: **18 206 chunk**
(lessons 325, adr 943, rounds 3674, reviews 1972, sdd 3822, plan 3386, dsp 130,
code 3954).

* **Darabolás struktúrából**, nem LLM-mel: lecke = `## L<n>` blokk, markdown =
  `##` szekció, kód = szimbólum-közeli ablak (120 sor, 20 sor átfedés). Kemény
  felső korlát 12 000 karakter.
* **Beágyazás:** OpenAI `text-embedding-3-small`. A teljes korpusz ~5,7M token
  ≈ **0,11 $**.
* **Tárolás a repón kívül** (`~/.local/state/strumsight-rag/`), mert minden kör
  külön munkapéldányban dolgozik: egyszer épül, mindenki használja. A vektorok
  bináris oldalfájlban (`vectors.f32`, 112 MB) — a JSON-alak mérve **359 MB**
  volt, ami minden lekérdezésnél újraparse-olódott volna.
* **Frissesség gépi jelzés:** a `--stat` kiírja, hány commit-tal van az index a
  HEAD mögött, és ELAVULT-ot mond. A hallgatólagosan régi index tiltott állapot.
* **Kulcs nélkül** a keresés BM25-re esik vissza: degradál, nem hal meg.

### 3.1 Mért defektek, amiket az építés hozott elő

1. kérésenkénti token-limit → karakter-költségvetés alapú kötegelés;
2. **bemenetenként 8192 token** a felső korlát (a magyar próza + kód ~2
   karakter/token) → kemény vágás a darabolóban;
3. 359 MB-os JSON-index → bináris vektor-oldalfájl;
4. szűk percenkénti kvóta → `Retry-After`-tudatos backoff és részleges mentés
   (egy megszakadt futás nem dobja el a kifizetett beágyazásokat).

## 4. Amire használjuk — kapuk, nem hangulat

A RAG önmagában nem javít semmit. Három ponton kap gépi szerepet (külön kör,
`E99-R20`):

1. **brief-íráskor** — a kör `allowed_paths`-ára lekért ADR/lecke-találatokat a
   briefnek hivatkoznia vagy explicit módon elutasítania kell (`brief-lint`
   strict lelet);
2. **halt-kor** — a halt-kód + terület aláírására lekért korábbi esetek a
   self-heal promptjába kerülnek (ez ma azonnal kiadta volna a `PIPELINE_ORCH_SWAP_ENGINE`-t);
3. **review-kor** — az érintett fájlokhoz tartozó leckék a reviewer elé.

### 4.1 Frissesség: merge-horgony, nem fájlfigyelő

A kérdés jogos volt („kell code watcher?"), a válasz mérésből jön: **nem**.
A körök külön munkapéldányban dolgoznak, tehát egy fájlfigyelő a köztes,
még nem mért állapotokra is beágyazást venne — zajt indexelne, és pénzt égetne.
A MEGOSZTOTT igazság a `main`, ezért a horgony a **merge**: a driver a
merge után leválasztva, inkrementálisan újraindexel
(`PIPELINE_RAG_REINDEX=1`, csak a változott chunk). Ehhez jön a
`--stat` frissesség-jelzése, ami kimondja, hány commit-tal elavult az index —
a hallgatólagosan régi index tiltott állapot.

### 4.2 A halt visszakeresést kap

A self-heal promptjához a driver hozzáfűzi a halt aláírására (kód + összegzés)
kapott top-5 találatot, „bizonyíték, nem utasítás" felirattal. Ez az a lépés,
ami a 2026-08-18-i E99-R14 haltot megelőzte volna.

### 4.3 A lánc saját tanulása is korpusz

A `docs/LESSONS.md` a lassú, megírt réteg; a napi tanulság előbb a
halt-fájlokban (`.pipeline/halted-*`, `round-status-*`) és a git-notes
kísérlet-pufferben (HORIZON konvenció) születik meg. Mindkettő külön korpusz
(`halts`, `notes`), tehát a rendszer akkor is tud a saját hibájából tanulni, ha
azt még senki nem fogalmazta leckévé.

**A siker mércéje:** az önjavítást igénylő körök aránya (ma **22%**, 31/141) és
az ismétlődő hibaosztályok száma. Ha ezek nem mozdulnak, a RAG nem érte meg —
és ezt ki fogjuk mondani.

## 5. Kulcs-politika (user-döntés)

A kulcs **kizárólag** a RAG-indexé. Ezt nem próza őrzi:

* saját változónév és fájl: `RAG_OPENAI_API_KEY` a `~/.rag-openai.env`-ben
  (0600) — egy `OPENAI_API_KEY`-t kereső session nem találja meg;
* a `~/.codex` profil `codex logout`-tal API-kulcs nélkül maradt;
* a `tools/hooks/implementer_guard.py` blokkolja a `codex login --api-key`
  alakot, a self-heal prompt pedig kimondja a tiltást.

**Mért indok:** amikor a kulcs még `OPENAI_API_KEY` néven állt a boxon, egy
önjavító kör 6 percen belül megtalálta, és `codex login --with-api-key`-vel
motor-hitelesítésre fordította — ettől minden kör a user API-számláját terhelte
volna az előfizetés helyett.
