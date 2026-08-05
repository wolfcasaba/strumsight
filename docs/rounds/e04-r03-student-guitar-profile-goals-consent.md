# E04-R03 — Student profile, guitar profile, goals és consent

- **Státusz:** PLANNING (pre-flight 2026-08-05, kód olvasva: main @ `52bf072`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 3; §35
- **Branch:** `codex/e04-r03-student-guitar-profile-goals-consent`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/student_profile.dart",
  "lib/features/ai_tutor/domain/models/guitar_profile.dart",
  "lib/features/ai_tutor/domain/models/learning_goal.dart",
  "lib/features/ai_tutor/domain/models/tutor_consent.dart",
  "lib/features/ai_tutor/data/local/tutor_profile_codec.dart",
  "test/features/ai_tutor/domain/student_profile_test.dart",
  "test/features/ai_tutor/domain/tutor_consent_test.dart",
  "test/features/ai_tutor/data/tutor_profile_codec_test.dart",
  "docs/rounds/e04-r03-student-guitar-profile-goals-consent.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R01 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR — a §5 a R01 **0132**
> (privacy/consent) + **0134** (memory) ADR-re hivatkozik; igazold a végleges
> számokat. `rg`: domain-purity őr + R02 ID-készlet mai alakja. PREPARED→PLANNING,
> brief commit a kör-branchre az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract/ellentmondó
acceptance → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió (2026-08-05, orchestrátor)

**Baseline:** `main @ 52bf072` (origin/main == local HEAD). Előfeltétel teljesül:
E04-R01 (`814388a`, #124) és E04-R02 (`db778c4`, #125) merge-elve.

**ADR-döntés — NINCS új ADR.** Ez a kör az R01-ben elfogadott policyt *realizálja*
domain-modellként, nem hoz új normatív döntést, ezért új ADR-szám kiosztása
szám-infláció lenne. A kötő ADR-ek MÉRTEN léteznek és fedik a kört:
- **ADR 0132** (`docs/adr/0132-…`) §3: a consent **három független tengely** —
  (a) model-use, (b) tartós szerveroldali tárolás, (c) evaluation redakcióval;
  „az egyik megadása nem vonja [a másikat]". Ez a §5.1 forrása.
- **ADR 0134** (`docs/adr/0134-…`): local-first, megtekinthető, szerkeszthető/
  törölhető memory, dokumentált retention; „nem lazítható azért, hogy egy teszt
  zöld legyen". A §5.2 (immutable, verziózott) + §9 retention forrása.

**Mért §1.1 (elérhetetlen cél-státusz):** N/A — nincs reducer/állapotgép ebben a
körben; a `TutorConsent` value-object három **független** tengellyel, a
grant/revoke tiszta value-transzformáció. A cél-„státuszt" (adott tengely
engedélyezett/tiltott) közvetlenül az érték produkálja, nincs félrevezető
átmenettábla.

**Mért §1.2 (erőforrás-tulajdonlás):** N/A — tiszta domain, nincs
lease/lock/handle/subscription. (`rg "\.acquire\(" lib/features/ai_tutor` = 0.)

**REVÍZIÓ 1 — engedélyezett-lista SZŰKÍTÉSE (`public.dart` eltávolítva).**
Mérés: az R02 commitolt egy **kényszerített üres-boundary invariánst** —
`test/features/ai_tutor/ai_tutor_boundary_test.dart` (NINCS az engedélyezett
listán) azt állítja, hogy `lib/features/ai_tutor/public.dart` **nulla**
import/export direktívát tartalmaz. „Additív export" hozzáadása ezt a
scope-on-kívüli tesztet pirosra váltaná (tilos zóna, H3-kockázat), és **egyetlen
acceptance criterion sem** igényel külső elérhetőséget ebben a körben (a tesztek
közvetlenül a modellfájlokból importálnak). Ezért a `public.dart` kikerül az
engedélyezett listáról; a boundary-export a fogyasztót bevezető későbbi kör
dolga. Ez a §2 (ADR 0087) szerinti autonóm **lista-szűkítés**, nem tágítás.

**REVÍZIÓ 2 — teszt-fájl leképezés rögzítése.** Négy új modell (Student/Guitar/
Learning/Consent), de az engedélyezett domain-tesztlista csak `student_profile_test.dart`
és `tutor_consent_test.dart`. A `GuitarProfile` és `LearningGoal` ≥90% coverage-ét
a `student_profile_test.dart`-ban **csoportosítva** kell elérni; ÚJ tesztfájl
létrehozása (pl. `guitar_profile_test.dart`) tilos-zóna → `stopped`.

**Mért precedens-készlet (a briefben hivatkozott mai alakok):**
- ID/validáció-minta: `tutor_ids.dart` — `TutorIdValidationException._(code)`,
  stabil `TutorIdValidationCode` konstansok, `Object.hash` value-equality.
- Codec-minta: `tutor_conversation_codec.dart` — `supportedSchemaVersion = 1`,
  stabil `…CodecErrorCode` konstansok, `schemaVersion.missing/unknown`,
  `field.missing/invalid` policy, determinisztikus kulcssorrend, UTF-8 JSON.

## 1. Cél

A személyre szabás és az adatvédelmi döntések explicit, **megtekinthető**
domainjének létrehozása — a consent szerkezetileg elkülönített tengelyekkel.

## 2. Jelenlegi állapot

- `lib/features/ai_tutor/domain/` ma csak az R02 conversation/message modelleket
  tartalmazza; profil/goal/consent nincs (greenfield).
- A `SongMetadata`/`PracticeSessionConfig` value-equal, validált, immutable domain
  a követendő precedens (E03-R02 / E02-R03).
- Consent-precedens az appban nincs tutor-specifikusan — ez a kör vezeti be.

## 3. Scope

**Benne:** `StudentProfile` (szint/preferenciák/avoid-lista), `GuitarProfile`
(hangszer/tuning/capo referencia), `LearningGoal` (aktív célok), `TutorConsent`
(model-use / storage / evaluation **külön** tengely), verziózott codec.

**Kívül — TILOS:** UI (R22), repository/storage-írás (R17), cloud-hívás, provider-SDK.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/student_profile.dart` | ÚJ | tanulói profil |
| `.../domain/models/guitar_profile.dart` | ÚJ | hangszerprofil |
| `.../domain/models/learning_goal.dart` | ÚJ | célmodell |
| `.../domain/models/tutor_consent.dart` | ÚJ | granular consent |
| `.../data/local/tutor_profile_codec.dart` | ÚJ | verziózott codec |
| ~~`lib/features/ai_tutor/public.dart`~~ | **TÖRÖLVE** (§0.0 Rev.1) | boundary-export ütközik az R02 üres-boundary teszttel |
| `test/features/ai_tutor/domain/student_profile_test.dart` | ÚJ | profil + GuitarProfile + LearningGoal (grouped) |
| `test/features/ai_tutor/domain/tutor_consent_test.dart` | ÚJ | consent-tengelyek |
| `test/features/ai_tutor/data/tutor_profile_codec_test.dart` | ÚJ | codec round-trip |
| `docs/rounds/e04-r03-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A **consent három független tengely** (model-use / storage / evaluation) — egyik
   engedélyezése soha nem implikálja a másikat (ADR 0132). **NEM elfogadható:**
   egyetlen összevont „AI engedélyezve" boolean.
2. Minden modell immutable, value-equal, validált, verziózott codec-cel (ADR 0134).
3. A domain Flutter-/provider-SDK-mentes (purity-őr).
4. Nyers audio/PII-mező nincs a profilban.

## 6. Acceptance criteria

- [ ] `TutorConsent` a három tengelyt külön reprezentálja és round-tripeli; a
      grant/revoke minden tengelyre függetlenül tesztelt (mind a 3 kombináció-él).
- [ ] `StudentProfile`/`GuitarProfile`/`LearningGoal` validáció + value-equality +
      immutabilitás literálisan tesztelt (stabil validációs kódkészlet).
- [ ] Codec round-trip bit-stabil; ismeretlen/hiányzó mező policy dokumentált+tesztelt.
- [ ] Domain purity-őr zöld; **≥90% coverage** az új domainen.

A reviewer a consent-függetlenséget eldobható mutációval (egy tengely implikálja a
másikat) pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED consent-tengely + validációs tesztek.
2. Modellek + codec.
3. Gate. (NINCS `public.dart` export — §0.0 Rev.1.)

Javasolt commit: `feat(ai-tutor-domain): add student profile goals and granular consent`.

## 9. Kockázatok

- A consent-tengelyek összemosása csábító a UI-kényelemért — a domain szinten TILOS.
- Retention-mező itt csak modellezhető; a tényleges érvényesítés R17/R22.

**STOP:** összevont consent, provider-SDK import vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r03-student-guitar-profile-goals-consent-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
