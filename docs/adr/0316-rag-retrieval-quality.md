# ADR 0316 — Visszakeresés-minőség: súlyozott fúzió, dokumentum-korlát, hiányzó korpuszok és mérhető rangsor

- **Státusz:** elfogadva (2026-08-18)
- **Kontextus-ADR:** [`0312`](0312-knowledge-rag.md) (tudás-index)

## 1. Probléma — MÉRVE éles használatban

Az ADR 0312 indexe működik (18 547 chunk), és ma két körnél is döntést
változtatott. De ugyanezen a napon **el is bukott egy valós feladaton**, és a
bukás reprodukálható.

**(a) A hibrid rangsor lenyomja az erős lexikai találatot.** Az E99-R21 brief
írásakor a „flaky" osztályra kerestem:

| futtatás | L142 helyezése |
|---|---|
| `--bm25 --corpus lessons "flaky"` | **1.** |
| `--corpus lessons "flaky teszt zöld újrafuttatásra kapu lépés bukás"` | 4. |
| `--top 12` (teljes korpusz, ugyanaz a kérdés) | **6.** |

A brief írásakor `--top 4`-gyel dolgoztam, tehát **a RAG nem adta vissza a
döntő leckét** — `grep -i flaky docs/LESSONS.md` adta. A top-5-öt olyan
review-szakaszok foglalták el, amelyek CÍME sablon („Gate — független
újrafuttatás", „Biztonsági review — Futtatott ellenőrzés", „Megjegyzés a
futásról"), tehát minden kérdésre gyengén illeszkednek, és **darabszámmal**
nyernek. Az RRF a két ágnak egyenlő súlyt ad, így a ritka, egyértelmű
domain-terminus (flaky, H8, tmux, win32) lexikai előnye elvész.

**(b) Nincs dokumentum-szintű korlát.** Egy másik lekérdezés első négy
találata **ugyanannak a briefnek** (`e99-r15`) négy szakasza volt — négy hely a
találati listán, egyetlen forrásból.

**(c) Hiányzó korpusz.** A `HANDOFF.md` (3 059 sor) és a
`docs/handoff-archive.md` (9 034 sor) — összesen **12 093 sor operatív
történet** — egyáltalán nincs indexelve. Eközben a `halts` korpusz mindössze
24 chunk, mert a `.pipeline/halted-*.txt` rekordokból csak 5 él a lemezen (a
többi archiválva). Vagyis épp az a tudás hiányzik, amit az önjavító ág kérdez.

**(d) A `--corpus` egyetlen nevet fogad** (`flags.corpus === name`), tehát a
„lessons + halts + adr" szűkítés — a pre-flight természetes szűrése — ma nem
kifejezhető.

**(e) A rangsor változása nem mérhető.** Nincs visszakeresési fixture, így
minden hangolás ízlés kérdése maradna.

## 2. Döntés

1. **Mérce először:** `tools/rag-eval.tsv` — (kérdés, elvárt chunk-azonosító,
   elvárt helyezés) hármasok, és egy futtató, ami jelenti a találati arányt. A
   rangsort érintő minden további változás ezen mérve.
2. **Súlyozott fúzió:** a lexikai és a szemantikus ág külön súlyt kap
   (`RAG_W_BM25`, `RAG_W_EMB`). Az alapértelmezés a lexikai ág javára billen,
   mert a mért hibaosztály pontosan az volt, hogy egy ritka domain-terminus
   erős lexikai jelét a szemantikus ág hígította.
3. **Dokumentum-korlát:** egy forrásfájlból legfeljebb kettő chunk kerülhet a
   találati listára; a többi kiesik, hogy a lista forrásban is változatos legyen.
4. **Új `handoff` korpusz:** `HANDOFF.md` + `docs/handoff-archive.md`.
5. **Több korpusz egy hívásban:** `--corpus lessons,halts,adr`.

## 3. Amit ez a döntés NEM tesz

- Nem cserél embedding-modellt és nem épít újra nulláról indexet: a `--reindex`
  inkrementális marad, a súlyozás és a korlát **lekérdezés-idejű**.
- Nem nyúl a kulcs-politikához (ADR 0312): a kulcs kizárólag a RAG-é.
- Nem tesz a visszakeresésből kaput: a rangsor-mérce jelentés, nem gate-lépés.

## 4. Következmények

- A `handoff` korpusz a legnagyobb egyszeri tartalmi bővítés az index élete
  során; az első `--reindex` ezért hosszabb lesz (a szokásos néhány száz chunk
  helyett több ezer).
- A dokumentum-korlát elrejthet jogos, sok szakaszos találatot. Ellenszer: a
  korlát a listára vonatkozik, nem az indexre, és a `--json` alak megmutatja a
  kiesett forrásokat.
