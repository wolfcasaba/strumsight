# E07-R28 — Tutor és PlannerAssistGateway integráció

- **Státusz:** READY (pre-flight felülvizsgálva 2026-08-19, `main @ e95bd937`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 28
- **Kör-azonosító:** `E07-R28`
- **Branch:** `<motor>/e07-r28-planner-assist-gateway`
- **Előfeltétel:** `E07-R27` merge-elve (kihagyás-kezelés)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0270`](../adr/0270-planner-assist-allowlist-and-untrusted-input.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg az AI Tutor
> **tényleges** `public.dart` felületét és a `plannerAssistEnabled` flag
> állását (OFF kell legyen). Olvasd újra az ADR 0255 §2-t: **a modell javasol,
> nem hajt végre.** Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/application/port/planner_assist_gateway.dart",
  "lib/features/practice_generator/data/ai/remote_planner_assist_gateway.dart",
  "lib/features/practice_generator/data/ai/fake_planner_assist_gateway.dart",
  "lib/features/practice_generator/data/ai/planner_assist_schema.dart",
  "lib/features/practice_generator/data/adapter/tutor_plan_proposal_adapter.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/assist/planner_assist_gateway_test.dart",
  "test/features/practice_generator/assist/planner_assist_schema_test.dart",
  "test/fixtures/practice_generator/assist/",
  "docs/rounds/e07-r28-planner-assist-gateway.md",
]
gate_tests = [
  "test/features/practice_generator/assist/planner_assist_gateway_test.dart",
  "test/features/practice_generator/assist/planner_assist_schema_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Pre-flight mérés és brief-revízió (2026-08-19, `main @ e95bd937`)

**Az `ai_tutor` `public.dart` mérve ÜRES, és ez FAGYASZTOTT invariáns, nem
ideiglenes hiány.** `lib/features/ai_tutor/public.dart` ma két sor
(`library;` + doc-comment), zéró export/import — ezt egy E04-R01-ben
merge-elt regressziós teszt kényszeríti ki:
`test/features/ai_tutor/ai_tutor_boundary_test.dart` ("the empty baseline
boundary must not pull in another feature's domain, data, application, or
presentation internals"). A `crossFeatureImportsMustUsePublicApi` szabály
(`tool/check_architecture.dart`, `architectureAllowlist` már 12/12 tele) emiatt
ma NULLA reachable szimbólumot ad az `ai_tutor` felől — sem a gyökér-, sem egy
új nested `public.dart` nem oldaná (a fagyasztott boundary-teszt PONT ezt
tiltja), és mindkét fájl (`ai_tutor/**`, `tool/check_architecture.dart`)
egyszerre esik a brief tilos zónájába és az engedélyezett listán kívülre — a
feloldásuk H3 lenne, nem ennek a körnek a hatásköre.

**Ugyanez a hibaosztály HÁROMSZOR mérve, ugyanazzal a feloldással**
(`lessons/L121` E04-R12, `lessons/L133` E04-R20, `lessons/L139` E04-R23): egy
előre megírt brief additív `ai_tutor`-exportot feltételezett, a mérés mindig
üres+fagyasztott barrelt talált, és a feloldás mindháromszor
**scope-szűkítés** volt, sosem a guard módosítása. Ez a kör ugyanazt az utat
követi.

**Revízió.** A §3/§8 „a Tutor terv-vázlatának leképezése" **nem**
`lib/features/ai_tutor/domain/models/practice_plan_draft.dart` importját
jelenti (elérhetetlen — ne próbáld, a `flutter analyze`/architecture gate úgyis
pirosra váltja). A `tutor_plan_proposal_adapter.dart` egy SAJÁT, ebben a
körben definiált javaslat-típust ad ki a `planner_assist_schema.dart` validált
válaszából (mezők: allowlistelt cél-/skill-/candidate-ID hivatkozások,
rationale, blokk-vázlat) — importot csakis a practice_generator SAJÁT,
már publikus katalógus-/skill-felületéről végez
(`practice_catalog_reader.dart`, `skill_snapshot_reader.dart`,
`domain/id/planner_ids.dart` — mind a meglévő `public.dart`-on). Az allowlist
forrása ugyanez a felület. A valódi `ai_tutor` ↔ `practice_generator`
drótozás (a tényleges `PracticePlanDraft` átalakítása erre az alakra) egy
jövőbeli, hívó-táplált kör dolga marad — ugyanaz a minta, mint R23/R24/R26
(`practiceGeneratorEnabled` marad `false`, nulla production hívó). A §6 A8
cellája ("A Tutor-vázlat leképezése típusos, validált") ezzel az alakkal
teljesül és marad mérhető — a "Tutor" a javaslat TÉMÁJÁRA utal (AI-tanácsadás),
nem az `ai_tutor` feature-importra.

**`plannerAssistEnabled` mérve OFF** (`lib/app/config/feature_flags.dart:23,79`
— mindkét konstruktor-default `false`), a brief előfeltétele igaz. ADR 0255
§2 újraolvasva: a „javaslat külön, validált csatornán érkezik, a
determinisztikus tervező fogadja el vagy utasítja el" — ez a csatorna maga a
`planner_assist_schema.dart`, az elfogadás/elutasítás egy KÉSŐBBI kör dolga
(a generátor domain-rétege ennek a körnek is tilos zónája).

**Visszakeresett előzmény (RAG, `node tools/knowledge-rag.mjs`, index
`e95bd937`):** `adr/0139` (AI Tutor action proposal & confirmation — a
„javasol, nem hajt végre" mintát az AI Tutor saját rétegén belül már
alkalmazta), `adr/0141` (AI Tutor prompt-építés és injection boundary — A6
cella mintája). `--corpus lessons`: `L121`/`L133`/`L139` (fent) a döntő
találat; nincs ezekkel ütköző előzmény.

## 1. Cél

A Tutor és az **opcionális** AI-segítség biztonságos bekötése típusos
javaslatokkal és determinisztikus tartalékkal (SDD Ch8 Kör 28).

## 2. Jelenlegi állapot — mért tények

- Az ADR 0255 §2: **a modell javasol, nem hajt végre** — nincs olyan út,
  amelyen egy modell-válasz mezői közvetlenül végrehajtott terv mezőivé válnak.
- A `plannerAssistEnabled` flag **OFF** (E07-R01), külön a
  `practiceGeneratorEnabled`-től (ADR 0255 §3).
- A determinisztikus tervező (R12-R18) **modell nélkül is teljes**.

## 3. Scope

**Benne van:** strukturált kérés/válasz séma · **allowlist**: csak létező
goal-, skill- és jelölt-ID fogadható el · a Tutor terv-vázlatának leképezése
kérés/javaslat formára (**§0.0 szerint: SAJÁT javaslat-típusra, NEM
`ai_tutor`-importra**) · **determinisztikus magyarázat-tartalék** · timeout,
megszakítás és rate limit kezelése · prompt-injection és **nem megbízható
felhasználói szöveg** elkülönítése.

**NINCS benne (tilos):** a modell általi **aktiválás** · a flag `true`-ra
állítása · a determinisztikus út modell-függővé tétele · nyers modell-kimenet
beírása a tervbe · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/port/planner_assist_gateway.dart` | **ÚJ** — a port |
| `data/ai/planner_assist_schema.dart` | **ÚJ** — a séma + validáció |
| `data/ai/remote_planner_assist_gateway.dart` | **ÚJ** |
| `data/ai/fake_planner_assist_gateway.dart` | **ÚJ** — teszt/offline |
| `data/adapter/tutor_plan_proposal_adapter.dart` | **ÚJ** |
| `public.dart` | a barrel bővítése |
| `test/…/assist/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r28-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor domain-
rétege · `lib/features/ai_tutor/**` tartalma · `docs/adr/**` · `tools/**`.

## 5. Kötött architekturális döntések (ADR 0270)

### 5.1 A modell SOHA nem aktivál tervet

A javaslat a determinisztikus validátoron megy át (ADR 0263), és az aktiválás
felhasználói megerősítéshez kötött (R21 §5.1). **Nincs** olyan út, ahol a
modell kimenete közvetlenül végrehajtott tervvé válik.

### 5.2 Csak ALLOWLISTELT azonosító fogadható el

A modell csak **létező** goal-, skill- és jelölt-ID-t hivatkozhat. Ismeretlen
vagy kitalált azonosító → a javaslat elutasítva, nem „legjobb egyezés".

**NEM elfogadható gyengítés:** fuzzy illesztés a modell által kitalált névre.
Az kitalált tartalmat engedne a tervbe (ADR 0262 §1 rokona).

### 5.3 A felhasználói szabad szöveg NEM MEGBÍZHATÓ bemenet

A tanuló megjegyzése adat, nem utasítás. A prompt-szerkezetnek el kell
különítenie, és a modellnek adott instrukció nem írható felül belőle.

### 5.4 AI NÉLKÜL minden alapfunkció működik

Timeout, hálózati hiba, rate limit, kikapcsolt flag → a tervezés zavartalanul
fut, determinisztikus magyarázattal. A felhő hibája **nem veszíthet draftot**.

### 5.5 A séma-sértés ELUTASÍTÁS, nem javítgatás

Ha a válasz nem illeszkedik a sémára, elutasítjuk. Nincs „megpróbáljuk
kiolvasni belőle, ami használható".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A modell javaslata NEM aktivál tervet | `planner_assist_gateway_test.dart` |
| A2 | Ismeretlen/kitalált ID → elutasítás, nem fuzzy egyezés | `planner_assist_schema_test.dart` |
| A3 | Séma-sértő válasz elutasítva, nem részlegesen felhasználva | ugyanott |
| A4 | Timeout / rate limit / hálózati hiba → determinisztikus tartalék | `planner_assist_gateway_test.dart` |
| A5 | Felhő-hiba nem veszít draftot | ugyanott |
| A6 | Prompt-injection kísérlet a felhasználói szövegben hatástalan | `planner_assist_schema_test.dart` |
| A7 | `plannerAssistEnabled = false` mellett minden alapfunkció megy | `planner_assist_gateway_test.dart` |
| A8 | A Tutor-vázlat leképezése típusos, validált | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A javaslat közvetlenül aktiválható | **A1** |
| Fuzzy illesztés kitalált ID-ra | **A2** |
| A séma-sértő válaszból „ami használható" kiolvasva | **A3** |
| Timeout esetén hiba a tartalék helyett | A4 |
| A felhasználói szöveg utasításként a promptban | **A6** |
| A flag OFF állapotában a tervezés elakad | **A7** |

**A javaslat-érvényesség három kötelező cellája** (a küszöb: a séma + allowlist):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | séma-sértő vagy ismeretlen ID | **elutasítva**, determinisztikus tartalék |
| rajta (a küszöbön) | séma-helyes, **minden** ID allowlisten | elfogadva **javaslatként** — aktiválás nélkül |
| a küszöb fölött | séma-helyes, de a tanuló elutasítja | nem lép életbe, auditálható (R26 §5.3) |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedj fuzzy
ID-illesztést → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/assist/planner_assist_gateway_test.dart test/features/practice_generator/assist/planner_assist_schema_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `planner_assist_schema.dart` — séma + allowlist-validáció.
2. `planner_assist_gateway.dart` port + `fake_planner_assist_gateway.dart`.
3. `remote_planner_assist_gateway.dart` — timeout, rate limit, megszakítás.
4. `tutor_plan_proposal_adapter.dart` — típusos leképezés a §0.0 szerinti
   SAJÁT javaslat-típusra (NEM `ai_tutor` import — az elérhetetlen, ne
   próbáld).
5. Tesztek a §6.1 három érvényesség-cellájával, prompt-injection fixture-rel.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „segítőkész" fuzzy illesztés.** A modell kitalál egy gyakorlatnevet, a
  rendszer megkeresi a leghasonlóbbat — és a tanuló mást gyakorol, mint amit
  bárki eldöntött (A2).
- **A prompt-injection.** A tanuló megjegyzése a promptba kerülve utasítássá
  válhat (A6).
- **Az AI mint feltétel.** Ha a tervezés elakad a modell nélkül, az egész
  offline-first ígéret elveszik (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
