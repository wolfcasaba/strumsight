# E12-R36 — Program completion report és következő roadmap

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 36 — a fejezet ZÁRÓ köre
- **Kör-azonosító:** `E12-R36`
- **Branch:** `<motor>/e12-r36-program-completion-and-next-roadmap`
- **Előfeltétel:** `E12-R35` merge-elve (és a Chapter 12 minden korábbi köre)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — záró/riport-kör.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "program completion report roadmap chapter matrix handoff"` → a `halts/round-status-E07-R30`, `E07-R23`, `E08-R26` merge-elt ZÁRÓ körök — a repóban van bevált minta az epic-záró completion reportra (`docs/sdd/epic-0X-completion-report.md`). Ez a kör azt a mintát emeli PROGRAM-szintre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd a Kör 2 `tool/check_sdd_index.dart` ellenőrzőjét, és mérd meg minden fejezet TÉNYLEGES kör-státuszát a `docs/execution/pipeline-queue.tsv`-ből. A completion matrix ebből a KÉT forrásból készül, nem emlékezetből.

## 0.0 A záró kör őszinteségi feltétele

A program-riport akkor ér valamit, ha a NEM elkészült részeket is pontosan nevezi meg. A megíráskor MÉRT állapot szerint az Epic 10 (Offline AI) sáv `hold`-on, a Chapter 14 sáv `prepared` státuszban áll, és a Chapter 12 rounds 27–33 emberi kapuja külön jelölendő. A riport ezeket NEM írhatja késznek.

## 0.0.A Pre-flight revízió (orchestrátor, 2026-09-02, `main @ 9da6d2f3`)

A brief 2026-08-27-én, `main @ 9ca4a0dc`-n készült. Az alábbi hét pont a MAI
mérés, és a brief §2/§6 megfelelő állításait **felülírja**. A mérés forrásai:
`docs/execution/pipeline-queue.tsv`, `docs/sdd/00-index.md`, `ls docs/sdd/`,
`tool/check_sdd_index.dart`.

**Visszakeresés (ADR 0312):** `--corpus lessons,halts,adr` →
`lessons/L118` (az őr tesztje ne a valódi repóra mutasson: az ambiens engedély
NÉMÁN 20 állítást fordított zöldre rossz okból), `lessons/L577` (az őr a
SZÁMOT védte, a szám INDOKLÁSÁT nem), `lessons/L133` (előre megírt brief mért
állítása avulhat → a feloldás scope-SZŰKÍTÉS, nem tágítás). A teljes korpuszon
saját magán kívül csak a Ch12 SDD-fejezet fájllistája jött vissza — új
információ nélkül. A P5 pont közvetlenül az L118 + L577 ellenszere.

### P1 — A fejezet ↔ queue-előtag leképezés NEM azonosság, és a queue NEM teljes kör-nyilvántartás

MÉRVE:

- **Chapter 1**-nek nincs köre (az index „Fejlesztési körök" cellája `—`).
- **Chapter 2–11 = Epic 1–10**, queue-előtag `E01`–`E10`. Az **`E01` előtagra
  NULLA queue-sor van** (`grep -c "^E01" … → 0`): az Epic 1 a queue létrejötte
  ELŐTT zárult, bizonyítéka az `epic-01-completion-report.md` (zárókör
  `E01-R16`), nem queue-sor.
- Az **`E02` sorai `R12`-nél kezdődnek** (10 sor: R12–R21), miközben az Epic 2
  20+1 kört futott — a queue az epic KÖZEPÉN jött létre.
  **Következmény:** a completion matrix „körök" oszlopa NEM a queue-sorok
  száma. A kör-szám forrása a fejezet-fájl / `00-index.md`; a queue-ból MÉRT
  szám külön, `queue-sorok` néven nevezett oszlop.
- **Chapter 12/13/14 = `E12`/`E13`/`E14`** — a szám a FEJEZETET jelöli, nem
  epicet.
- **Két sávnak NINCS SDD-fejezetfájlja:** `E15` (Ch15 — UI-migráció,
  user-döntés 2026-08-28) és `E16` (Ch16 — kompozíció és rollout, user-döntés
  2026-09-02). Rajtuk kívül az `E99` a governance-pszeudoepic.
  **A riportnak MINDHÁRMAT fel kell sorolnia mért, nyitott sávként, és ki kell
  mondania, hogy `docs/sdd/`-ben nincs fejezetfájljuk.** A hallgatólagos
  kihagyásuk a matrixot hamis „a program kész" állítássá tenné — ez pontosan a
  §9 első kockázata.

### P2 — A MÉRT queue-állapot előtagonként (2026-09-02)

| Előtag | Fejezet | done | pending | prepared | hold |
|---|---|---:|---:|---:|---:|
| `E01` | Ch2 / Epic 1 | — (nincs sor) | — | — | — |
| `E02` | Ch3 / Epic 2 | 10 | 0 | 0 | 0 |
| `E03` | Ch4 / Epic 3 | 22 | 0 | 0 | 0 |
| `E04` | Ch5 / Epic 4 | 24 | 0 | 0 | 0 |
| `E05` | Ch6 / Epic 5 | 30 | 0 | 0 | 0 |
| `E06` | Ch7 / Epic 6 | 30 | 0 | 0 | 0 |
| `E07` | Ch8 / Epic 7 | 30 | 0 | 0 | 0 |
| `E08` | Ch9 / Epic 8 | 29 | 0 | 0 | **1** (`E08-R29`) |
| `E09` | Ch10 / Epic 9 | 27 | 0 | 0 | **5** (`E09-R28…R32`) |
| `E10` | Ch11 / Epic 10 | **0** | 0 | 0 | **32** (a TELJES sáv) |
| `E12` | Ch12 | 35 | 1 (ez a kör) | 0 | 0 |
| `E13` | Ch13 | 36 | 0 | 0 | 0 |
| `E14` | Ch14 | 1 | 0 | **18** | 0 |
| `E15` | Ch15 (nincs fejezetfájl) | 8 | **6** | 0 | 0 |
| `E16` | Ch16 (nincs fejezetfájl) | **0** | **5** | 0 | 0 |
| `E99` | governance | 18 | 0 | 0 | **2** (`E99-R21`, `E99-R23`) |

Reprodukció:
`awk -F'\t' '$1 ~ /^E[0-9]/ {split($1,a,"-"); print a[1]"\t"$NF}' docs/execution/pipeline-queue.tsv | sort | uniq -c`

A Ch14 sáv **42 kört** tervez, de ma csak **19 sor** létezik (R01 `done` +
R02–R19 `prepared`) — az R20–R42 briefjei MEG SEM ÍRÓDTAK (queue-komment,
2026-09-02). A riport ezt a különbséget nevezze meg.

### P3 — A §2 completion-report felsorolása elavult

MÉRVE (`ls docs/sdd/`): **nyolc** zárójelentés létezik —
`epic-01`…`epic-08-completion-report.md` —, nem a §2-ben írt négy
(`0{1,2,3,6}`). A §2 megfelelő mondata ezzel a mért listával olvasandó.

### P4 — A `done` queue-sor NEM bizonyítéka annak, hogy az emberi művelet megtörtént

MÉRVE: az `E12-R27`…`E12-R33` mind a hét sora `done`. Ezek a körök a
zárt/nyílt béta, a produkciós deploy, a szakaszos rollout és a GA
**artefaktumait és eszközeit** szállították — a user-oldali TÉNYLEGES műveletek
(valódi Play Console béta, valódi rollout, valódi GA) és a **valódi gitáros
APK-teszt** NEM történtek meg. Az A5 tehát megköveteli, hogy a riport
**megkülönböztesse** a „kör `done`" és az „emberi kapu NYITOTT" állítást; a
`done` sort emberi kapu teljesítéseként feltüntetni a §5.3 tiltott gyengítése.

### P5 — A §6 őr KÖTELEZŐ szigorítása: tartalom-paraméteres, RED-bizonyító cellák

Az L118 és az L577 ugyanazt a hibaosztályt méri: a valódi fára mutató őr
zöld lehet **rossz okból**, mert nem tud olyan bemenetet előállítani, amit a
valódi fa nem produkál. A `test/tooling/program_completion_test.dart` ezért
NEM állhat csak a valódi fán zöld cellákból. Kötelező szerkezet — az E12-R35
`check_deprecations.dart` bevált mintája szerint:

1. **Tiszta függvények, tartalom-paraméterrel.** A queue-parszolás, a
   riport-parszolás és az összevetés `String` (queue-szöveg, riport-szöveg,
   roadmap-szöveg) paramétert vevő, tiszta függvény legyen; a valódi fát mérő
   cellák ezek **vékony burkolói**. Mivel a brief a `tool/`-t TILTJA, ezek a
   függvények magában a teszt-fájlban élnek — ez a scope-on BELÜL van, és ez az
   EGYETLEN út a (2) ponthoz scope-tágítás nélkül.
2. **Acceptance-pontonként legalább egy RED-bizonyító cella**, kézzel épített,
   a valódi fa által elő nem állítható bemeneten:
   - **A1** — szintetikus queue, amelyben egy előtag státusza eltér a riportban
     jelölttől → a cellának PIROSNAK kell lennie;
   - **A2** — szintetikus riport, amely a `hold`-on álló `E10`-et késznek
     jelöli → PIROS;
   - **A3** — szintetikus riport, amely nem létező fájlra hivatkozik → PIROS;
   - **A4** — szintetikus roadmap-tétel mérőszám nélkül, illetve olyan tétel,
     amelynek tartalma csak kör-azonosítók felsorolása (`E\d\d-R\d\d`) → PIROS;
   - **A5** — szintetikus riport, amely egy emberi kaput elvégzett lépésként
     tüntet fel → PIROS.
3. A valódi fát mérő cellák ezután ugyanezekkel a függvényekkel mérik a
   TÉNYLEGES `docs/execution/pipeline-queue.tsv`-t és a megírt riportot.

### P5.1 — Az A4 gépi alakja (különben nem mérhető)

„Mérhető outcome" gépileg csak akkor ellenőrizhető, ha kötött alakja van. A
`docs/roadmap/next-six-months.md` minden tétele tartalmazzon:

- egy `**Outcome:**` sort (a felhasználói/terméki eredmény mondata),
- egy `**Mérőszám:**` sort, amelyben van **szám** (küszöb vagy célérték),
- egy `**Forrás:**` sort, amely megnevezi, MI méri (fájl, teszt, eszköz vagy
  dokumentált manuális mérés).

Az A4 cella ezt a három sort és a számot ellenőrzi tételenként, továbbá
elutasítja azt a tételt, amelynek törzse pusztán kör-azonosítók listája.

### P6 — ADR: NINCS, és ez a pre-flight döntése

A brief §0/§5 ADR-mentes záró körként definiálja magát, és a `docs/adr/**` a
**tilos zónában** van. Egy új ADR az `allowed_paths` **tágítását** kívánná, ami
az ADR 0087 §2 szerint NEM orchestrátori hatáskör (a hatáskör a lista
SZŰKÍTÉSE). Precedens: **E12-R35** ugyanezzel az indoklással zárult ADR nélkül,
és merge-elve van. A `reserve-adr` foglalót ezért nem hívjuk.

### P7 — A `00-index.md` frissítés HATÁRA (az A6 miatt)

A `tool/check_sdd_index.dart` a „Fejlesztési körök" cellát a fejezet-fájlok
`# Kör N` / `## Kör N` fejléceiből méri, és ellenőrzi a fájl- és
zárójelentés-linkeket. A státusz-frissítés ezért **kizárólag** a `Státusz` és
az `Implementation progress` oszlop szövegét érintheti; a körszám-cellákat, a
fájl-linkeket és a zárójelentés-linkeket **nem szabad módosítani**. A Ch15/Ch16
sávnak nincs fejezetfájlja, ezért **nem kap sort** a `## Fejezetek` táblában —
őket a program-riport nevezi meg (P1). Az A6-ot a
`test/tooling/sdd_index_guard_test.dart` méri a §7 gate-ben.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/sdd/program-completion-report.md",
  "docs/roadmap/next-six-months.md",
  "docs/sdd/00-index.md",
  "HANDOFF.md",
  "test/tooling/program_completion_test.dart",
  "docs/rounds/e12-r36-program-completion-and-next-roadmap.md",
]
gate_tests = [
  "test/tooling/program_completion_test.dart",
  "test/tooling/sdd_index_guard_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a completion matrix egy fejezet státuszához nem talál bizonyítékot (queue-sor, completion report vagy merge-elt PR), a kimenet a `stopped` jelzés — becsült státusz nem kerülhet a riportba.

## 1. Cél

A program állapotának átadható, bizonyíték-alapú lezárása és egy termékmetrikákból induló, outcome-alapú következő roadmap.

## 2. Jelenlegi állapot — mért tények

- `docs/sdd/`: fejezet-fájlok 01–14, `epic-0{1,2,3,6}-completion-report.md` — a completion report MÉRT mintája.
- `docs/execution/pipeline-queue.tsv`: körönként egy sor, `prepared | pending | running | done | halted | hold` státusszal — ez a státusz EGYETLEN gépi forrása.
- `docs/roadmap/` **nem létezik**.
- `HANDOFF.md` a mindenkori pillanatkép — a kör a záró bejegyzést írja bele.
- A `00-index.md` a Kör 2 óta gépileg ellenőrzött.

## 3. Scope

**Benne van:** `docs/sdd/program-completion-report.md` (fejezetenként: kör-szám, `done`/nyitott sorok, bizonyíték-hivatkozás, fő tanulságok, eltérések a tervtől) · `docs/roadmap/next-six-months.md` (outcome-alapú célok termékmetrikákkal, NEM feature-lista) · a `00-index.md` státusz-oszlopának frissítése a MÉRT queue-állapotra · `HANDOFF.md` záró bejegyzés · `test/tooling/program_completion_test.dart` (a riport minden fejezet-státusza egyezik a queue-val; minden hivatkozott fájl létezik; nyitott sáv nem jelölhető késznek).

**NINCS benne (tilos):**

- Bármely `lib/`, `backend/`, `tool/` kód módosítása.
- Fejezet-fájl tartalmának átírása.
- A `pipeline-queue.tsv` módosítása (olvasni kell, nem igazítani).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/program-completion-report.md` | ÚJ — a program-szintű zárójelentés |
| `docs/roadmap/next-six-months.md` | ÚJ — outcome-alapú roadmap |
| `docs/sdd/00-index.md` | státusz-oszlop frissítés a MÉRT állapotra |
| `HANDOFF.md` | záró bejegyzés |
| `test/tooling/program_completion_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `tool/**` · `docs/sdd/0*.md` és `1[1-4]*.md` · `docs/execution/pipeline-queue.tsv` · `docs/adr/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A státusz FORRÁSA a queue, nem a riport

**NEM elfogadható gyengítés:** a riportban „kész" jelölés olyan sávra, amelynek queue-sorai `hold` vagy `prepared` státuszúak (a megíráskor: Epic 10 és Chapter 14).

### 5.2 A roadmap OUTCOME-alapú

Minden tétel egy mérhető felhasználói/terméki eredményt nevez meg, nem funkciót. **NEM elfogadható gyengítés:** a hátralévő SDD-körök átmásolása feature-listaként.

### 5.3 Az emberi kapuk NEVESÍTVE maradnak

A Kör 27–33 user-műveletei és a valós gitáros APK-teszt a riportban EXPLICIT emberi kapuként szerepelnek. **NEM elfogadható gyengítés:** ezek „elvégzett lépésként" való feltüntetése.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A completion matrix minden fejezet-státusza egyezik a `pipeline-queue.tsv` MÉRT állapotával | `program_completion_test.dart` |
| A2 | Nyitott (`hold`/`prepared`) sávot a riport NEM jelöl késznek | `program_completion_test.dart` |
| A3 | Minden hivatkozott dokumentum létezik | `program_completion_test.dart` |
| A4 | A roadmap minden tétele mérhető outcome-ot nevez meg | `program_completion_test.dart` szerkezeti cellája |
| A5 | Az emberi kapuk (Kör 27–33, valós APK-teszt) explicit jelöléssel szerepelnek | a riport + a teszt cellája |
| A6 | A `00-index.md` a Kör 2 ellenőrzőjével továbbra is valid | `sdd_index_guard_test.dart` a §7 gate-ben |

> **A §0.0.A P5 KÖTELEZŐ:** az A1–A5 cellák nem állhatnak csak a valódi fán
> zöld állításokból — acceptance-pontonként legalább egy RED-bizonyító, kézzel
> épített bemenetű cella kell, tartalom-paraméteres tiszta függvényeken. Az A4
> gépi alakját a §0.0.A P5.1 rögzíti.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A riport az Epic 10-et késznek jelöli, miközben a sorai `hold`-on állnak | A1/A2 |
| A roadmap a hátralévő SDD-körök feature-listája | A4 |
| Az emberi kapuk elvégzett lépésként szerepelnek | A5 |
| Az index-frissítés elrontja a körszám-egyezést | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írd át a riportban az Epic 10 státuszát „kész"-re, futtasd a §7 gate-et → az **A1**/**A2** cellának PIROSNAK kell lennie → állítsd vissza a MÉRT állapotra.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/program_completion_test.dart test/tooling/sdd_index_guard_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: queue-státuszok fejezetenként + a meglévő completion reportok.
2. `docs/sdd/program-completion-report.md`.
3. `test/tooling/program_completion_test.dart`.
4. `docs/sdd/00-index.md` státusz-frissítés.
5. `docs/roadmap/next-six-months.md`.
6. `HANDOFF.md` záró bejegyzés + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Kozmetikai zárójelentés.** A legnagyobb kockázat, hogy a riport késznek mutat egy el sem indult sávot (A2).
- **Feature-lista roadmap.** A SDD folytatása outcome helyett (A4).
- **Index-drift.** A státusz-oszlop frissítése elronthatja a Kör 2 gépi egyezését (A6).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`), folytató futás (az előző futás a
kvótakorlát miatt jelzés nélkül szakadt meg 23:42 UTC-kor; a §−1 leírja a
folytatás kiindulását).

**Szállítva (a §4 engedélyezett fájllista mind az öt eleme + a brief maga):**

- `docs/sdd/program-completion-report.md` — a completion matrix (§3), a
  fejezet↔queue-előtag leképezés magyarázata (§2), az eltérések (§4), az
  emberi kapuk táblája (§5), a fő tanulságok (§6) és a bizonyíték-lista (§7).
  A meglévő draftot ellenőriztem a §0.0.A P1–P4 mérésével (`awk` reprodukció
  megismételve, ld. alább) — pontos egyezést találtam, nem kellett javítani.
- `docs/roadmap/next-six-months.md` — 7 outcome-tétel, mindegyik
  `**Outcome:**`/`**Mérőszám:**`/`**Forrás:**` hármassal. Szintén ellenőrizve,
  változtatás nélkül elfogadva.
- `test/tooling/program_completion_test.dart` (ÚJ, 20 cella) — a §5 szerinti
  őr: tartalom-paraméteres tiszta függvények (`parseQueueCounts`,
  `parseCompletionMatrix`, `compareMatrixToQueue`, `findOpenLaneMarkedClosed`,
  `parseEvidencePaths`/`findMissingEvidence`, `findHumanGatesMarkedDone`,
  `parseRoadmapItems`/`validateRoadmapItem`) + acceptance-pontonként (A1–A5)
  legalább egy kézzel épített RED-bizonyító cella, majd ugyanazokkal a
  függvényekkel a valódi fát mérő cellák.
- `docs/sdd/00-index.md` — **kizárólag** a Chapter 5–14 sorok Státusz és
  Implementation progress cellái frissültek a §0.0.A P2 mért állapotra (a
  Chapter 1–4 sorok már pontosak voltak, nem nyúltam hozzájuk; a
  „Fejlesztési körök"/„Fájl"/„Zárójelentés" oszlopokat és a Chapter 15/16
  hiányát — P7 szerint — nem érintettem).
- `HANDOFF.md` — záró bejegyzés (lásd a git history-ban ezzel egy időben).

**Mérési újra-ellenőrzés (§0.0.A P2 reprodukció, 2026-09-02):**
`awk -F'\t' '$1 ~ /^E[0-9]/ {split($1,a,"-"); print a[1]"\t"$NF}'
docs/execution/pipeline-queue.tsv | sort | uniq -c` — a kimenet BYTE szinten
egyezik a brief táblájával; a queue azóta nem változott.

**Döntések:**

- A `_extractLabelValue` (roadmap A4 parser) belső hibát mértem és javítottam
  fejlesztés közben: az első verzió `[A-Za-zÀ-ÿ ]+` karakterosztályt
  használt a `**Label:**` határ felismerésére, ami a magyar "ő" (U+0151)
  betűnél (a `Mérőszám` szóban) elbukott — a Latin-1 Supplement tartomány nem
  tartalmazza. Emiatt a nem-mohó capture átnyelte a következő teljes szakaszt
  is. Javítás: `\p{L}` Unicode betű-osztály (`unicode: true` flaggel) — a
  teszt ezt a hibát az A4 "csak kör-azonosítók felsorolása" RED-cellája fogta
  meg fejlesztés közben (a cella előbb hamisan zöld volt).
- ADR-t nem foglaltam (a brief §0.0.A P6 és a precedens `E12-R35` szerint).

**A KÖTELEZŐ valódi-sértés próba (§6.1/§10), két formában:**

1. **Automatizált, a gate részeként fut** (`program_completion_test.dart`,
   "(a)"/"(b)" cellák): (a) csak a Riport-státusz szöveg átírása "lezárva,
   minden kör kész"-re (a számok érintetlenek) → A2 PIROS, A1 zöld marad;
   (b) csak a számok átírása (a 32 hold-ot done-ba mozgatva, a szöveg
   érintetlen) → A1 PIROS a valódi mért queue ellen, A2 zöld marad. Mindkettő
   dokumentálja, hogy A1 és A2 EGYMÁSTÓL FÜGGETLENÜL fog hibát.
2. **Kézi, a fájlon (KÖTELEZŐ, a brief §10 szerint):** a
   `docs/sdd/program-completion-report.md` Ch11/E10 sorának
   Riport-státusz celláját "nyitva (hold: a TELJES sáv, mind a 32 kör)"-ról
   "lezárva, minden kör kész"-re írtam, futtattam a §9 gate-sort szó szerint
   (`tools/round-gate.sh test/tooling/program_completion_test.dart
   test/tooling/sdd_index_guard_test.dart`) → **kilépési kód 10, a [3] `test
   test/tooling/program_completion_test.dart` lépés PIROS**, a konkrét bukó
   cella: `the real tree (...) A2 — no open lane is marked closed`, üzenet:
   `Ch11 (E10): open lane (openCount=32) but report-status claims closure:
   "lezárva, minden kör kész"`. Ezután visszaállítottam a MÉRT szöveget, és a
   gate-et újra futtattam: **mind a 7 lépés (format, analyze, mindkét teszt,
   architecture, secrets, l10n) ZÖLD** — "MINDEN GATE ZÖLD" záró sorral.

**Gate (végleges, a MÉRT állapoton):** `tools/round-gate.sh
test/tooling/program_completion_test.dart test/tooling/sdd_index_guard_test.dart`
→ mind a 7 lépés zöld (format, analyze, a két megnevezett teszt fájl 20+36
cellával, architecture 12 allowlisted deviation, secrets 0 finding, l10n
2298 üzenet en→hu párban).

**Amit a következő körnek/orchestrátornak tudnia kell:** a riport és a
roadmap tartalmilag a 2026-08-27-es draft volt, amit csak a §0.0.A mérésével
kellett igazolni, nem újraírni — az egyetlen új munka az őr-teszt és a
`00-index.md` státusz-frissítés volt. A Chapter 14 42-tervezett/19-létező
kör közötti rés (R20–R42 briefjei meg sem íródtak) a program legnagyobb,
még meg sem tervezett hátraléka — ezt a roadmap 5. tétele nevesíti.

**fix1 (javító kör, MAJOR-1 + MINOR-1, `docs/reviews/e12-r36-review.md`):**

- **MAJOR-1 javítva** — az őr eddig csak a riportban JELEN LÉVŐ sorokat
  ellenőrizte; egy teljesen kihagyott nyitott sáv vagy emberi kapu minden
  cellán zöld maradt (a reviewer PROBE1–PROBE3 mérése). Két új
  lefedettség-ellenőrzés `test/tooling/program_completion_test.dart`-ban,
  ugyanazzal a tartalom-paraméteres tiszta függvény + RED-bizonyító cella
  mintával:
  - `findLanesMissingFromMatrix(queueCounts, rows)` — a `parseQueueCounts`
    minden queue-előtagjának legyen sora a completion matrixban (a `—`
    Ch1-előtag sosem lehet queue-kulcs, nincs szükség kivételre). RED-cella:
    szintetikus `E15` queue-előtag, aminek nincs sora a szintetikus
    riportban → piros; a valódi fán zöld (mind a 15 előtag — E01–E16, E99 —
    kap sort).
  - `findMissingHumanGates(expectedGateRefs, rows)` a `parseHumanGateRows`
    (a korábbi `findHumanGatesMarkedDone` belső parseréből kiemelve, a
    viselkedése változatlan) fölött — a hét `E12-R27`…`E12-R33` és a valódi
    gitáros APK-teszt sora mind jelen van-e a §5 táblában
    (`humanGateCoverageExpectedRefs`, 8 elem). Két RED-cella (egy kör-sor
    törölve, ill. a névtelen APK-teszt sor törölve) → mindkettő piros; a
    valódi fán zöld.
  - Mindkét új cella az ÚJ `the real tree (...)` csoportban is fut a valódi
    `pipeline-queue.tsv` / `program-completion-report.md` ellen — zöld,
    tehát a MAI riport lefedettsége teljes; a MÁJOR a regresszió elleni őr
    hiányát javította, nem egy tartalmi hibát.
- **MINOR-1 javítva ((b) ág)** — `parseEvidencePaths` doc-commentje eddig
  azt állította, hogy a bulleteket "a riport evidence-sources
  szakaszából" gyűjti; a mintázat valójában a TELJES dokumentumon fut,
  szakasz-határ nélkül. A doc-comment pontosítva arra, amit a függvény
  ténylegesen tesz (a §7 lista egyezése ma a prózaszerkezet
  mellékterméke, nem invariáns) — kódváltozás nem történt.
- **Gate (fix1, MÉRT):** `tools/round-gate.sh
  test/tooling/program_completion_test.dart
  test/tooling/sdd_index_guard_test.dart` → mind a 7 lépés zöld; a célfájl
  cellaszáma 20 → 27 (7 új: 2 RED + 1 zöld-kontroll lane-coverage-höz, 3
  RED/zöld-kontroll human-gate-coverage-hez, 2 új valódi-fa cella).
- Nem nyúltam a riport/roadmap TARTALMÁHOZ, a `docs/reviews/e12-r36-review.md`
  fájlhoz, sem a §4 engedélyezett listán kívüli más fájlhoz (`NOTE-1`-t
  szándékosan nem érintettem — opcionális, a brief §4 szerint nem blokkol).

## 11. Review — a Claude tölti ki
