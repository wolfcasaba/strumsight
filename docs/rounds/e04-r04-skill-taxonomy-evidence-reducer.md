# E04-R04 — Skill taxonomy, evidence és reducer

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 4; §35
- **Branch:** `codex/e04-r04-skill-taxonomy-evidence-reducer`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/skill_node.dart",
  "lib/features/ai_tutor/domain/models/skill_evidence.dart",
  "lib/features/ai_tutor/domain/models/skill_estimate.dart",
  "lib/features/ai_tutor/domain/services/skill_evidence_reducer.dart",
  "test/features/ai_tutor/domain/skill_taxonomy_test.dart",
  "test/features/ai_tutor/domain/skill_evidence_reducer_test.dart",
  "docs/rounds/e04-r04-skill-taxonomy-evidence-reducer.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R01 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0131 bővítése).
> `rg`: domain-purity őr; a Practice/Song eredménymodellek **public** felülete
> (`lib/features/{practice,song_trainer}/public.dart`) — a reducer csak a
> később (R05) adaptált, redaktált evidence-t fogyasztja, NEM a source feature
> belső típusait. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió (2026-08-05, orchestrátor)

**Baseline:** `main @ 3dc7f5a` (origin/main == local HEAD, mérve). Előfeltétel
teljesül: E04-R01 (`814388a`, #124), E04-R02 (`db778c4`, #125) és E04-R03
(`06ae3f7`, #126) merge-elve.

**ADR-döntés — NINCS új ADR.** Ez a kör az E04-R01-ben elfogadott policyt
*realizálja* domain-modellként, nem hoz új normatív döntést, ezért új ADR-szám
kiosztása szám-infláció lenne (az R02/R03 precedens szerint). A kötő ADR mérten
létezik és fedi a kört: **ADR 0131** (`docs/adr/0131-ai-tutor-provider-boundary.md`)
§Döntés 1–3 — a tutor domain **providerfüggetlen**, determinisztikus on-device
coachingból dolgozik; a §5.1 (pure, determinisztikus reducer, stable tie-break)
és a §9 (source-belső import tilalma) forrása.

**Mért §1.1 (elérhetetlen cél-státusz):** a reducer EGY becslés-státuszt produkál
(`insufficient` vs. redukált trend-becslés). Nincs meglévő állapotgép/átmenettábla
grep-elni (a `skill_*` fájlok ÚJak; `grep -rn "SkillEstimate\|SkillEvidence" lib/`
= 0). Az acceptance által kötött input→státusz leképezés: **0 vagy 1** összehasonlítható
evidence-group → `insufficient`; **≥2** group → trend-becslés. A státuszt tehát
közvetlenül az input-count produkálja, félrevezető átmeneti-él nélkül. A reviewer
a 0/1/2-group mátrixszal méri (§6).

**Mért §1.2 (erőforrás-tulajdonlás):** N/A — tiszta domain, nincs
lease/lock/handle/subscription (`grep -rn "\.acquire(" lib/features/ai_tutor` = 0).

**REVÍZIÓ 1 — engedélyezett-lista SZŰKÍTÉSE (`public.dart` eltávolítva).**
Mérés: az E04-R01 commitolt egy **kényszerített üres-boundary invariánst** —
`test/features/ai_tutor/ai_tutor_boundary_test.dart` (LEZÁRT kör, NINCS az
engedélyezett listán) azt állítja, hogy `lib/features/ai_tutor/public.dart`
**nulla** import/export direktívát tartalmaz. „Additív export" hozzáadása ezt a
scope-on-kívüli, lezárt-kör tesztet pirosra váltaná (H2/H3-kockázat), és **egyetlen
acceptance criterion sem** igényel külső elérhetőséget (a tesztek közvetlenül a
modell-/service-fájlokból importálnak). Ezért a `public.dart` **kikerül** az
engedélyezett listáról és **ÜRES MARAD**; a boundary-export a fogyasztót bevezető
későbbi kör (R05+) dolga. Ez a §2 (ADR 0087) szerinti autonóm **lista-szűkítés**,
nem tágítás. Az R02/R03 azonos revíziót hozott.

**Az engedélyezett fájllista a §0.0 után (6 írható út):**
- `lib/features/ai_tutor/domain/models/skill_node.dart` (ÚJ)
- `lib/features/ai_tutor/domain/models/skill_evidence.dart` (ÚJ)
- `lib/features/ai_tutor/domain/models/skill_estimate.dart` (ÚJ)
- `lib/features/ai_tutor/domain/services/skill_evidence_reducer.dart` (ÚJ)
- `test/features/ai_tutor/domain/skill_taxonomy_test.dart` (ÚJ)
- `test/features/ai_tutor/domain/skill_evidence_reducer_test.dart` (ÚJ)
- `docs/rounds/e04-r04-skill-taxonomy-evidence-reducer.md` (§10 handoff)

`lib/features/ai_tutor/public.dart` → **tilos zóna** (üres marad). Minden más fájl,
más feature belső contractja, `tool/check_architecture.dart`, `docs/rag` → tilos.

**Mért precedens-készlet (a briefben hivatkozott mai alakok):**
- Value-object / stabil hibakód: `tutor_ids.dart` — `…ValidationException._(code)`,
  `abstract final class …ValidationCode` stabil string-konstansokkal, `Object.hash`
  value-equality.
- Domain-purity őr: **kör-lokális** `group('Domain purity')` scanner a tesztben
  (a song_trainer/E03-R02 + E04-R02 precedens szerint); a `tool/check_architecture.dart`
  NEM fedi az `ai_tutor`-t és **tilos zóna**.

## 1. Cél

Egységes **skill graph** és **készségbizonyíték-modell** létrehozása, amely a
szórt progress-adatot determinisztikus, forrásjelölt skill-becsléssé redukálja.

## 2. Jelenlegi állapot

- Nincs egységes skill graph vagy evidence-modell (SDD §3.2/4).
- A progress-adat több feature-ben, eltérő formában él (Practice/Song/Analyze/
  Progress/Streak) — public barrelen át elérhető, de nem egységes.
- A reducernek **tiszta függvénynek** kell lennie (E02-R10 scorer-precedens:
  belül egész-aritmetika, kifelé normalizált érték; lebegőpont-akkumuláció tilos).

## 3. Scope

**Benne:** `SkillNode` (taxonómia), `SkillEvidence` (forrásjelölt bizonyíték-elem
provenance + scorer/schema version-nel), `SkillEstimate` (redukált becslés +
bizonyosság), `SkillEvidenceReducer` (pure, determinisztikus, stable-order).

**Kívül — TILOS:** context-assembly (R05), UI, cloud, provider-SDK, source feature
belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/skill_node.dart` | ÚJ | skill taxonómia |
| `.../domain/models/skill_evidence.dart` | ÚJ | forrásjelölt bizonyíték |
| `.../domain/models/skill_estimate.dart` | ÚJ | redukált becslés |
| `.../domain/services/skill_evidence_reducer.dart` | ÚJ | pure reducer |
| `lib/features/ai_tutor/public.dart` | ~~additív export~~ **TÖRÖLVE (§0.0 REVÍZIÓ 1)** | üres marad — a lezárt E04-R01 boundary-invariáns pirosra váltana |
| `test/features/ai_tutor/domain/*` | ÚJ | taxonómia + reducer tesztek |
| `docs/rounds/e04-r04-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A reducer **pure és determinisztikus** — azonos evidence-halmazra bit-azonos
   becslés, stable tie-break (ADR 0131). **NEM elfogadható:** rendezéstől függő
   vagy lebegőpont-akkumulált eredmény.
2. Minden `SkillEvidence` **provenance + scorer/schema version**-t hordoz — verzió
   nélküli bizonyíték nem kerülhet a becslésbe.
3. Két összehasonlítható evidence-group kell trend-becsléshez (SDD DoD: trend ≥ 2 group).
4. A domain Flutter-/provider-SDK-mentes.

## 6. Acceptance criteria

- [ ] A reducer determinisztikus: shuffle-elt evidence-sorrendre azonos becslés
      (property-teszt seeddel); stable tie-break literálisan tesztelt.
- [ ] Trend csak **≥2** összehasonlítható groupból; 1 groupnál a becslés
      „insufficient" — **mátrix:** 0 / 1 / 2 evidence-group.
- [ ] Verzió nélküli evidence elutasított (fail-loud), nem néma befogadás.
- [ ] Domain purity-őr zöld; **≥90% coverage**.

A reviewer a determinizmust független reference-számítással vagy shuffle-mutációval
pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED determinizmus + trend-mátrix + verzió-reject tesztek.
2. Taxonómia + evidence + estimate modellek.
3. Pure reducer.
4. Additív export; gate.

Javasolt commit: `feat(ai-tutor-domain): add skill taxonomy evidence and reducer`.

## 9. Kockázatok

- A reducer csábítható source-feature belső típusra hivatkozni — TILOS; csak a
  R05 adaptált, redaktált evidence a bemenet.
- Lebegőpont-akkumuláció determinizmus-törés — egész/normalizált aritmetika.

**STOP:** source-belső import, nem-determinisztikus becslés vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Módosított fájlok

- `lib/features/ai_tutor/domain/models/skill_node.dart` — immutable, v1-es
  kezdeti taxonómia (`SkillId`, `SkillNode`, prerequisite-validáció és
  cycle-őr).
- `lib/features/ai_tutor/domain/models/skill_evidence.dart` — provenance-os,
  schema- és scorer-verziót fail-loud módon validáló evidence value object;
  egész súlyokkal a közvetlen méréshez, self-reporthoz és tutor assessmenthez.
- `lib/features/ai_tutor/domain/models/skill_estimate.dart` — immutable
  `insufficient`/`trend` output, külön normalized confidence-szal és stabil
  value equalityvel.
- `lib/features/ai_tutor/domain/services/skill_evidence_reducer.dart` — tiszta,
  integer-aritmetikás reducer: ID-idempotencia, comparable partition/group
  kiválasztás, UTC + lexikális tie-break, 0/1/2-group küszöb és explicit trend.
- `test/features/ai_tutor/domain/skill_taxonomy_test.dart` — initial manifest,
  prerequisite graph/cycle, immutability és a kör-lokális purity scanner.
- `test/features/ai_tutor/domain/skill_evidence_reducer_test.dart` —
  version-reject, 0/1/2 matrix, literal tie-break, seedelt shuffle-property,
  source-weight, duplicate conflict/idempotencia és output-validáció.

`public.dart`, a lezárt boundary-teszt és minden más feature contract érintetlen.

### Futtatott ellenőrzések

- RED: `/home/ubuntu/flutter/bin/flutter test
  test/features/ai_tutor/domain/skill_taxonomy_test.dart
  test/features/ai_tutor/domain/skill_evidence_reducer_test.dart` — a négy még
  nem létező domain-contract importja miatt várt compile failure.
- GREEN: ugyanez a két tesztfájl — **27 passed**.
- `/home/ubuntu/flutter/bin/flutter test --coverage
  test/features/ai_tutor/domain` — **75 passed**; az új domain fájlok összesen
  **300/304 sor, 98.68%** line coverage.
- `tools/round-gate.sh test/features/ai_tutor/domain` — **ZÖLD**: format (889
  fájl, 0 változás), analyze (`No issues found!`), domain tesztek (75 passed),
  architecture.
- `/home/ubuntu/flutter/bin/dart run tool/check_architecture.dart` —
  `Architecture dependencies OK (12 allowlisted deviation(s)).`
- `git diff --check` — hiba nélkül.

### Nem futtatott ellenőrzések

- A teljes Flutter suite, friss randomizált property gate és release APK a
  kör-branch CI-dispatchének/orchestrátorának kötelezettsége; implementerként
  nem futtattam `gh`-t, nem pusholtam és nem nyitottam PR-t.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r04-skill-taxonomy-evidence-reducer-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
