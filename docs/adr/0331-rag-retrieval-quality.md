# ADR 0331 — Visszakeresés-minőség: mérce először, pontszám-alapú fúzió, rekord-tudatos dokumentum-korlát, hiányzó korpuszok

- **Státusz:** elfogadva (2026-08-19)
- **Kontextus-ADR:** [`0312`](0312-knowledge-rag.md) (tudás-index)
- **Előzmény:** a `gov/rag-retrieval-quality` ágon készült, be nem olvasztott
  **0316-os tervezet**. Annak sorszáma ÜTKÖZÖTT: a `0316` a
  `docs/execution/pipeline-queue.tsv`-ben az **E08-R22** körnek van kiosztva.
  A szám ezért a foglalóból jött (`.pipeline/inflight/adr`, 0330 volt a max).
  Tartalmilag ez az ADR a tervezet **helyébe lép**, két ponton MÉRT
  korrekcióval — lásd §3.

## 1. Probléma — MÉRVE éles használatban

Az ADR 0312 indexe működik (18 998 chunk), de a rangsora **méretlen** volt:
nem lehetett megmondani, hogy egy hangolás javít vagy ront.

**(a) A hibrid rangsor lenyomja a döntő találatot.** A „flaky" osztályra:

| futtatás | L142 helyezése |
|---|---|
| `--bm25 --corpus lessons "flaky"` | **1.** |
| `--corpus lessons` (mondatos kérdés) | 4. |
| `--top 12` (teljes korpusz) | **be sem kerül** |

A brief írásakor `--top 4`-gyel dolgoztunk, tehát a RAG **nem adta vissza** a
döntő leckét — `grep` adta.

**(b) Nincs dokumentum-szintű korlát.** Egy lekérdezés első helyeit ugyanannak
a briefnek (`e99-r21`) négy szakasza foglalta: 1., 2., 3. és 8. hely, egyetlen
forrásból.

**(c) Hiányzó korpusz.** A `HANDOFF.md` (3 059 sor) és a
`docs/handoff-archive.md` (9 034 sor) — **12 093 sor operatív történet** —
egyáltalán nem volt indexelve. Épp az a tudás, amit az önjavító ág kérdez.

**(d) A `--corpus` egyetlen nevet fogadott**, tehát a „lessons + halts + adr"
szűkítés nem volt kifejezhető.

**(e) A kiírt „score" nem hordozott relevanciát.** Tiszta RRF rang-érték volt
(`1/(60+rang)`): ugyanaz a **0,0164** jött ki egy értelmes és egy értelmetlen
kérdésre is, mert mindkettő az adott ág 1. helyezettje volt.

## 2. Döntés

1. **Mérce először.** `tools/rag-eval.tsv` — (kérdés, elvárt találat, elvárt
   helyezés, korpusz) sorok; futtató: `--eval`, jelenti a találati arányt és az
   MRR-t. Minden további rangsor-változás EZEN mérve.
   Két kikötés, hogy a mérce ne legyen önigazoló:
   - a kérdések **parafrázisok**, nem a találat címének visszamásolásai;
   - a sorok **több korpuszt** fognak át, tehát egyetlen korpusz felnyomásával
     nem javítható (ami az egyiken nyer, a másikon veszít).
2. **Pontszám-alapú fúzió** (`RAG_FUSION=score`, alapértelmezés): ágon BELÜL
   min-max normalizálás [0,1]-re, majd súlyozott összeadás. A rang-alapú RRF
   megmarad (`RAG_FUSION=rank`), hogy a két mód összemérhető legyen.
3. **Súlyok a szemantikus ág javára:** `RAG_W_BM25=1`, `RAG_W_EMB=2`.
4. **Rekord-tudatos dokumentum-korlát:** egy forrásból legfeljebb kettő chunk
   a listára — DE azokban a korpuszokban, ahol egy fájl önálló rekordok
   GYŰJTEMÉNYE (`lessons`, `halts`, `notes`), a csoportosítási egység a chunk,
   nem a fájl.
5. **Új `handoff` korpusz:** `HANDOFF.md` + `docs/handoff-archive.md`.
6. **Több korpusz egy hívásban:** `--corpus lessons,halts,adr`.
7. **Diagnosztika:** a találat kiírja az ÁGANKÉNTI helyezést (`bm25#3 emb#11`),
   a `--explain` a fúzió súlyait és a korlát miatt kiesett forrásokat.

## 3. Amit a mérés MEGCÁFOLT a 0316-os tervezetből

A tervezet két előírása MÉRVE rossz volt. Ezt azért rögzítjük, mert mindkettő
hihető hipotézis volt, és mérce nélkül mindkettő beépült volna.

**(1) „A dokumentum-korlát fájl-alapú."** A `docs/LESSONS.md` mind a 346
leckéje ugyanaz a `file`, tehát a fájl-alapú korlát az EGÉSZ lessons-korpuszt
két találatra vágta:

| változat | találat | MRR |
|---|---|---|
| korlát nélkül | 7/13 (53,8%) | 0,438 |
| naiv, fájl-alapú korlát | **5/13 (38,5%)** | 0,308 |

A döntő leckék (L142, L143, L323) kiestek a top-20-ból. Innen a §2.4
rekord-tudatos alak. Mutáció-próbával igazolva: a `RECORD_CORPORA` kiürítése
a regressziós tesztet PIROSRA váltja.

**(2) „Az alapértelmezés a LEXIKAI ág javára billen."** A tervezet indoklása
az volt, hogy a ritka domain-terminus erős lexikai jelét hígítja a szemantikus
ág. Mérve ez fordítva igaz:

| fúzió | súlyok | találat | MRR |
|---|---|---|---|
| rank | bm25×2 emb×1 | 7/19 (36,8%) | 0,254 |
| rank | bm25×1 emb×2 | 10/19 (52,6%) | 0,491 |
| rank | bm25×1 emb×4 | 10/19 (52,6%) | 0,500 |
| **score** | **bm25×1 emb×2** | **11/19 (57,9%)** | **0,537** |

A feltevés egyetlen anekdotán állt: a szó szerint beírt „flaky" szón. A valós
használat PARAFRÁZIS, ahol nincs közös ritka szó — ugyanarra a kérdésre L142 a
BM25 top-40-ben SINCS benne, a szemantikus ágon viszont #11.

**Miért lett pontszám-alapú a fúzió:** a §2.7 rang-kijelzés mutatta meg, hogy a
fúzió utáni lista `bm25#1, emb#1, bm25#2, emb#2 …` mintát ad, vagyis a két ág
találatai szinte teljesen DISZJUNKTAK. Ilyenkor az RRF nem rangsorol, csak
összefésül, mert a rang nem hordozza, hogy egy találat erős-e vagy csak a
gyengék legjobbja. A rang-ág a súlyok emelésével sem érte utol (plafon: MRR
0,500), tehát nem hangolási kérdés volt.

## 4. Amit ez a döntés NEM tesz

- Nem cserél embedding-modellt és nem épít újra nulláról indexet: a súlyozás,
  a normalizálás és a korlát **lekérdezés-idejű**.
- Nem nyúl a kulcs-politikához (ADR 0312): a kulcs kizárólag a RAG-é.
- Nem tesz a visszakeresésből kaput: a rangsor-mérce jelentés, nem gate-lépés.
- **Nem oldja meg a teljes korpuszos keresést.** MÉRVE: szűkített korpuszon
  11/15, teljes korpuszon **0/4**. A szemantikus ág a döntő leckét ~#11-re
  teszi 18 998 chunk között, és ezen a fúzió nem segít. A gyakorlati kar a
  `--corpus` szűkítés.

## 5. Következmények

- **A hangolás innentől mért.** Aki a rangsorhoz nyúl, előbb `--eval`
  baseline-t vesz, és a változást a két számmal (találat, MRR) indokolja.
- A `--eval` OpenAI-kulcsot igényel, tehát **CI-ben nem fut**. Ezért a mért
  alapértelmezéseket forrás-szintű teszt őrzi (`test_the_default_fusion_is_the_measured_one`).
- A `handoff` korpusz a legnagyobb egyszeri tartalmi bővítés az index élete
  során; az első `--reindex` ezért hosszabb. A driver merge után magától
  újraindexel (`round-pipeline.sh:2337`), tehát külön teendő nincs.
- A dokumentum-korlát elrejthet jogos, sok szakaszos találatot. Ellenszer: a
  korlát a LISTÁRA vonatkozik, nem az indexre, és a `--explain` megmutatja a
  kiesett forrásokat.
- **A fixture 19 soros és kézzel írt.** Ennél tovább hangolni már a fixture-re
  illesztés lenne, nem javítás. Bővítése valós használatból történjen.
