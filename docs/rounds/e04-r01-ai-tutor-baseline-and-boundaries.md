# E04-R01 — AI Tutor baseline, ADR-ek és feature flagek

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 1; §35
- **Branch:** `codex/e04-r01-ai-tutor-baseline-and-boundaries`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "lib/features/ai_tutor/public.dart",
  "docs/baseline/epic-04-ai-tutor-start.md",
  "test/features/ai_tutor/ai_tutor_boundary_test.dart",
  "test/app/feature_flags_test.dart",
  "docs/rounds/e04-r01-ai-tutor-baseline-and-boundaries.md",
]
gate_tests = [
  "test/features/ai_tutor",
  "test/app/feature_flags_test.dart",
  "test/app/offline_network_guard_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main`-t és
> Epic 3 (E03-R22) merge-jét; olvasd újra az `AGENTS.md`-t, Chapter 1/5-öt,
> `HANDOFF.md`-t, a `docs/LESSONS.md`-t. **ADR-reconcile:** `ls docs/adr/ | sort
> | tail` — a batch 0131–0134-et oszt R01-re, de E03-R21/R22 elfogyaszthatja a
> 0129/0130-at; ha a next-free nem 0131, **told el az egész Epic 4 ADR-blokkot**
> és javítsd a §5-öt + a batch-indexet. `rg`-vel igazold: `lib/features/ai_tutor/`
> ma nem létezik (greenfield), a `FeatureFlags` mezőkészletét
> (`lib/app/config/feature_flags.dart`), és az `offline_network_guard` teszt
> mai alakját. PREPARED→PLANNING, dátum/sha frissítés, brief commit a
> kör-branchre az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol,
nem nyit PR-t. Listán kívüli fájl, hiányzó contract, ellentmondó acceptance vagy
megkülönböztetésre alkalmatlan teszt esetén `stopped`; nincs néma scope-tágítás
vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki** (baseline `main` @
akkori sha). Előre kiosztott ADR: **0131** (provider-boundary), **0132**
(privacy-and-consent), **0133** (tool-confirmation), **0134** (memory-policy) —
mind a NÉGY ADR-fájlt a **Claude/orchestrátor** írja a pre-flightban, NEM
implementer-diff és NEM a TOML `allowed_paths`-on (a §4 tábla jelöli). Az
E03-R21/R22 általi ADR-eltolódást a pre-flight kezeli.

## 1. Cél

A jelenlegi coaching-, progress-, Analyze-, Practice- és Song Trainer
adatforrások leltárba vétele, az AI Tutor biztonságos rollout-határainak és üres
feature-boundaryjának létrehozása **funkcionális változtatás nélkül**, flag mögött.

## 2. Jelenlegi állapot

- **Greenfield:** `lib/features/ai_tutor/` nem létezik (mérve — a könyvtár hiányzik).
- **Flagek:** `lib/app/config/feature_flags.dart` `FeatureFlags` osztálya ma
  `accountEnabled`, `diagnosticsEnabled`, `migratedLearnEnabled`,
  `practiceDetailedHistoryEnabled` mezőket hordoz — Epic 4 ide ad additívan
  `aiTutorEnabled` + `aiTutorCloudEnabled` mezőt, default **OFF**.
- **Újrahasznált public API-k** (a későbbi körök fogyasztják, most csak leltár):
  `lib/features/{practice,song_trainer,analyze,progress,streak,settings,learn,
  library,live}/public.dart`.
- **Offline-garancia:** `test/app/offline_network_guard_test.dart` őrzi a
  0-request kijelentkezett/offline utat (E01-R16) — flag OFF nem törheti.
- **Deterministic coaching baseline:** a Practice `PracticeCoach`→`PracticeInsight`
  (ADR 0084) a legacy determinisztikus visszajelzés — a baseline-dokumentum
  fixture-snapshotot rögzít róla (nem másolja a viselkedést).

## 3. Scope

**Benne:**
- `aiTutorEnabled` + `aiTutorCloudEnabled` flag, default OFF, additív mező.
- Üres `lib/features/ai_tutor/public.dart` boundary (nem importál más feature
  belső fájlt).
- `docs/baseline/epic-04-ai-tutor-start.md`: adatforrás-leltár (mért tény /
  számított aggregátum / UI-only megkülönböztetés), deterministic coaching
  fixture-snapshot, „nyers audio nem része a tutor contextnek" kimondás,
  rollout+rollback terv.

**Kívül — ebben a körben TILOS:**
- bármely tutor domain/model/UI/gateway (R02+),
- új route vagy hálózati kérés,
- bármely meglévő viselkedés megváltoztatása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/app/config/feature_flags.dart` | meglévő | additív `aiTutorEnabled`+`aiTutorCloudEnabled`, default OFF |
| `lib/features/ai_tutor/public.dart` | ÚJ | üres feature-boundary |
| `docs/baseline/epic-04-ai-tutor-start.md` | ÚJ | adatforrás-leltár + rollout/rollback |
| `test/features/ai_tutor/ai_tutor_boundary_test.dart` | ÚJ | boundary nem importál idegen belsőt |
| `test/app/feature_flags_test.dart` | meglévő/ÚJ | flag default OFF regresszió |
| `docs/rounds/e04-r01-ai-tutor-baseline-and-boundaries.md` | meglévő | §10 handoff |
| `docs/adr/0131…0134-*.md` | ÚJ (pre-flight, **orchestrátor** — NEM implementer-diff, NEM TOML `allowed_paths`) | provider/privacy/tool/memory döntések |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje,
a `docs/rag` fejlesztői DSP-korpusz, és minden viselkedésváltozás flag OFF mellett.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0131 — provider boundary:** a tutor providerfüggetlen; model-provider SDK
   típus soha nem szivárog a domainbe/kliensbe (a cloud a StrumSight backenden át, R14).
2. **ADR 0132 — privacy & consent:** cloud AI explicit consent; nyers audio soha
   nem kerül tutor requestbe; model-use / storage / evaluation consent külön.
3. **ADR 0133 — tool confirmation:** write/launch action kétlépcsős user-megerősítést
   igényel (R11).
4. **ADR 0134 — memory policy:** minden tutor-adat local-first, megtekinthető,
   szerkeszthető, törölhető; retention dokumentált.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] `FeatureFlags` additívan hordozza `aiTutorEnabled`+`aiTutorCloudEnabled`-et,
      default **OFF** — `test/app/feature_flags_test.dart` bizonyítja mindkét
      default-értéket (nem elég az egyiket).
- [ ] Flag OFF ⇒ **nincs új route** és **nincs hálózati kérés**:
      `test/app/offline_network_guard_test.dart` változatlanul zöld; a boundary-teszt
      igazolja, hogy `ai_tutor/public.dart` semmit sem exportál, ami route-ot regisztrál.
- [ ] `ai_tutor_boundary_test.dart`: a `public.dart` nem importál más feature
      belső (`/domain/`, `/data/`, `/application/`, `/presentation/`) fájlt —
      **NEM elfogadható** gyengítés: „csak egy belső importot enged".
- [ ] A teljes meglévő Flutter suite + backend suite változatlanul zöld (CI).
- [ ] A baseline-dokumentum minden adatforráshoz megjelöli: mért tény / számított
      aggregátum / UI-only; és fixture-snapshotot rögzít a deterministic coachingról.

A reviewer legalább egy központi invariánst (flag-default VAGY boundary-import
tiltás) eldobható mutációval pirosra vált; bemásolt zöld output nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor test/app/feature_flags_test.dart test/app/offline_network_guard_test.dart
```

Egyetlen lokális záró gate: format → analyze → célzott test → architecture külön
processzekben; nincs `&&`, pipe, `tail` vagy csonkítás. Full suite + randomizált
property + APK CI = orchestrátor exact-SHA dispatch.

## 8. Implementációs sorrend

1. Írd a RED flag-default és boundary-import tesztet.
2. Add a két flaget additívan, default OFF; készítsd az üres `public.dart`-ot.
3. Írd a baseline-leltárt + coaching fixture-snapshotot + rollout/rollback tervet.
4. Futtasd a gate-et; igazold a 0-request offline utat.

Javasolt commit: `chore(ai-tutor): establish Epic 4 baseline and safety boundaries`.

## 9. Kockázatok

- Flag-hozzáadás elronthatja a `FeatureFlags` konstruktor-hívóhelyeit — a
  pre-flight `rg`-zze az összes `FeatureFlags(` hívást; új mező default-tal, hívó nem tör.
- A baseline-dokumentum „viselkedés-leírás" helyett fixture-t rögzítsen, különben
  a coaching-parity későbbi köre (R08) nem tud rá hivatkozni.

**STOP:** listán kívüli javítás, viselkedésváltozás flag OFF mellett, vagy idegen
belső import helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

_(üres — a Codex tölti)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r01-ai-tutor-baseline-and-boundaries-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
