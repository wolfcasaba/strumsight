# E08-R11 — Qualified day, tervezett pihenőnap és visszatérés-politika

- **Státusz:** IN PROGRESS (pre-flight: 2026-08-20, `main @ 915c4529`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 11
- **Kör-azonosító:** `E08-R11`
- **Branch:** `<motor>/e08-r11-qualified-day-planned-rest-and-recovery`
- **Előfeltétel:** `E08-R10` merge-elve (Streak V2 domain)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0352` — a számot a foglaló kiosztotta. Az ADR-t az orchestrátor írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R10 `streak_policy.dart` és `streak_transition.dart` TÉNYLEGES felületét, valamint a `lib/features/practice_generator/` terv-szerződését (a tervezett pihenőnap onnan jön) — ha a mező neve eltér, §0.0 revízió. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió — 2026-08-20

1. **ADR-szám:** a briefben előre szereplő `0309` már foglalt
   (`docs/adr/0309-implementer-machine-guards.md`). A kötelező
   `tools/round-slots.py reserve-adr --round E08-R11` mérés `0352`-t adott;
   ez a kör kizárólag az ADR 0352-t használja.
2. **R10 szerződés:** a tényleges `StreakPolicy.applyQualifiedDay` a hívótól
   kapott epoch-napot kezeli, és már külön reason code-ot ad az azonos napra,
   clock rollbackre, freeze-re és resetre. A perzisztált
   `StreakGraceState` ma csak `none`; mivel a domain fájlok nincsenek az
   engedélyezett listán, az R11 a grace / planned-rest / broken állapotot az
   application-szintű, típusos napi átmeneti projekcióban adja vissza. A
   `StreakState.graceState` és a storage wiring változatlan marad; ez nem
   rejtett domain-módosítás.
3. **Pihenőnap tényleges útja:** a Practice Generator publikus contractja
   exportálja a `WeeklyScheduleDecision.dayDecisions` listát. A pihenőnapot a
   `ScheduleDecisionReason.restDay.code` (`schedule.decision.restDay`) jelöli;
   a streak service ezt a publikus contractot olvassa, a generator belső
   fájlját nem importálja és nem módosítja. A mért hívási lánc nem szerez
   lease-t, lockot vagy handle-t (`rg -n "\\.acquire\\("` → nincs találat az
   érintett két feature-ben).
4. **Küszöbök:** az SDD §8.10 példáját rögzítjük standard policyként:
   `minQualifiedDuration = 120s`, explicit recovery módban
   `minRecoveryDuration = 60s`. A kötelező határcellák a
   `python3 -c` mérés szerint `119s / 120s / 121s`; recoverynél
   `59s / 60s / 61s`. Mindkettő ugyanabban a konfigurációban él.
5. **Weekly consistency:** külön projekció, amely a hívó által átadott
   qualified epoch-napokból számolja az inkluzív, lekérdezési nappal záródó
   hétnapos ablak egyedi napjait. Nem olvassa és nem vezeti le a daily
   `current` streakből.
6. **Visszakeresett előzmény:** `adr/0351` rögzíti, hogy az R10 policy csak a
   már minősített nap streak-hatását kezeli; `adr/0299` a publikus, reason
   code-os rest-day contract forrása; `adr/0290` tiltja a büntetést és a
   negatív XP-t; `lessons/L302` előírja, hogy egy hiányzó alacsonyabb szintű
   contract miatt csak akkor legyen H3, ha a meglévő publikus típusokkal és az
   engedélyezett fájlokon belül sem teljesíthető az invariáns. A szűkített és
   teljes korpuszos RAG-lekérdezések ezeket hozták fel; további releváns
   előzmény nem került elő.

**Kockázat = high, indoklás:** a kör a felhasználó hosszú távú streak
állapotát, a freeze-fogyasztást és egy másik feature publikus terv-contractját
kapcsolja össze. Hibás napkonverzió vagy reason code pénzben nem mérhető, de
tartós motivációs állapotot ronthat; ezért correctness és külön security /
abuse review is kötelező.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/streak_service.dart",
  "lib/features/gamification/infrastructure/default_streak_policy.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/streak_service_test.dart",
  "docs/rounds/e08-r11-qualified-day-planned-rest-and-recovery.md",
]
gate_tests = [
  "test/features/gamification/application/streak_service_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Kösd a szériát **valódi gyakorláshoz** és rugalmas visszatéréshez: egy véletlen
pendítés ne minősítsen napot, a tervezett pihenőnap ne törje meg a ritmust, és az
óra-anomália se ne növelje, se ne törje automatikusan a szériát.

## 2. Jelenlegi állapot — mért tények

- Az R10 szállította a tiszta, óra-mentes `StreakPolicy`-t és az indok-kódos átmenetet.
- A mai `streak_logic.dart` **bármely** gyakorlási eseményt napnak minősít — nincs minimum-küszöb. Ez a kör vezeti be a qualified-day szabályt.
- A `lib/features/practice_generator/` (Epic 7) terv-szerződése tartalmazza a heti ütemezést — a tervezett pihenőnap innen származik.
- Az `ADR 0290` §1: nincs büntető vagy bűntudatkeltő széria-nyelv; a pihenőnap és a türelmi idő NORMÁLIS állapot.

## 3. Scope

**Benne van:** a minimum érvényes tevékenység (qualified day) és a visszatérő (recovery) session
szabálya · a tervezett pihenőnap integrálása a Practice Generator szerződéséből · a freeze /
grace / broken átmenetek · az egy napon belüli többszörös esemény idempotens kezelése · a heti
következetesség (weekly consistency) projekciója a napi szériától KÜLÖN · óra-anomália
kezelése.

**NINCS benne (tilos):**

- A `lib/features/streak/**` és a `lib/features/practice_generator/**` bármely fájljának módosítása.
- UI (Kör 12) — ez a kör az application-réteg.
- Büntető XP-vesztés bevezetése (ADR 0290) — abszolút tilos.
- `docs/adr/**` — az ADR 0309-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/streak_service.dart` | **ÚJ** — az átmenetek vezérlése |
| `lib/features/gamification/infrastructure/default_streak_policy.dart` | **ÚJ** — a küszöbök EGY konfigurációban |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/streak_service_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/streak/**` · `lib/features/practice_generator/**`

## 5. Kötött architekturális döntések (ADR 0352)

### 5.1 Egy véletlen pendítés NEM minősít napot

A qualified day küszöbhöz kötött: minimum érvényes időtartam VAGY minimum
érdemi tevékenység. A küszöb a konfigurációban él, nem a szolgáltatásba égetve.

A standard konfiguráció `120s` minimumot használ. A rövid recovery út csak
explicit `recoveryEligible` bemenettel nyílik meg, és akkor is legalább `60s`
valid aktivitást követel; pusztán az esemény típusa vagy egy strum nem elegendő.

**NEM elfogadható gyengítés:** „bármilyen esemény számít, mert az is elkötelezettség”.
Akkor a széria a hitelességét veszti el — és az ADR 0289 szellemében a mérőszám a
részvételt sem méri, csak az app megnyitását.

### 5.2 A tervezett pihenőnap MEGVÉDI a ritmust, nem tör

Ha a terv szerint aznap pihenőnap van, a kihagyás nem broken átmenet, hanem
védett állapot — és ez a felületen is látszik (Kör 12). Ez az ADR 0290 §1 közvetlen
alkalmazása.

**NEM elfogadható gyengítés:** a pihenőnap freeze-ként való elköltése. A freeze véges
erőforrás; a tervezett pihenő nem az.

### 5.3 Az egy napon belüli többszörös esemény IDEMPOTENS

Öt gyakorlás egy napon ugyanazt az állapotot adja, mint egy: a nap egyszer
minősül. Ez a mai `applyPractice` viselkedése (`today <= lastPracticeDay` → változatlan),
és a V2 megtartja.

### 5.4 ÓRA-ANOMÁLIA: se ne növelj, se ne törj automatikusan

Ha a mai epoch-nap KISEBB, mint az utolsó gyakorlás napja (visszaállított óra,
időzóna-váltás), a szolgáltatás **nem** növeli és **nem** töri a szériát: az állapot
változatlan marad, és az átmenet indok-kódja jelzi az anomáliát.

**NEM elfogadható gyengítés:** a szériát megtörni „mert az adat gyanús”. A felhasználó
nem hibás az óra állapotáért, és a büntetés az ADR 0290 tiltólistáján van.

### 5.5 A heti következetesség KÜLÖN mérőszám

A weekly consistency (hány minősített nap volt a héten) nem a napi szériából
származtatott érték, hanem önálló projekció. A kettő összekeverése azt jelentené, hogy egy
megszakadt széria eltünteti a heti teljesítményt is.

### 5.6 A napi állapot-projekció application contract, nem storage-migráció

Az R11 visszatérési értéke típusosan megkülönbözteti a qualified,
insufficient-activity, planned-rest, grace, freeze-covered, broken,
already-qualified és clock-anomaly ágakat. A `StreakState` V2 perzisztált
`graceState` enumját ez a kör nem bővíti és nem írja storage-ba. **Nem
elfogadható gyengítés:** string reason code, vagy a domain enum scope-on kívüli
módosítása.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A küszöb alatti tevékenység NEM minősít napot; a küszöbön MÁR igen | `streak_service_test.dart` — küszöb-hármas |
| A2 | A tervezett pihenőnap NEM tör szériát, és NEM költ freeze-t | `streak_service_test.dart` |
| A3 | Öt esemény egy napon ugyanazt az állapotot adja, mint egy | `streak_service_test.dart` — idempotencia-cella |
| A4 | Visszafelé állított óra esetén az állapot VÁLTOZATLAN, indok-kóddal | `streak_service_test.dart` — anomália-cella |
| A5 | A heti következetesség KÜLÖN lekérdezhető, és megszakadt széria mellett is helyes | `streak_service_test.dart` |
| A6 | Minden átmenet indok-kóddal tér vissza (freeze / grace / broken / anomália / pihenőnap) | `streak_service_test.dart` — átmenet-mátrix |
| A7 | **Nincs büntető XP-vesztés** semmilyen átmenetnél | `streak_service_test.dart` — a főkönyv egyenlege nem csökken |
| A8 | A küszöbök EGYETLEN konfigurációból jönnek (a konfiguráció módosítása átüt) | `streak_service_test.dart` |
| A9 | A rövid recovery session csak explicit engedéllyel és a recovery-küszöbtől minősít | `streak_service_test.dart` — recovery `59s / 60s / 61s` + engedély nélküli cella |
| A10 | A pihenőnap kizárólag a Practice Generator publikus reason code-jából jön; belső import nincs | `streak_service_test.dart` — valódi `WeeklyScheduleDecision` fixture + forrás-audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Bármely esemény napot minősít | **A1** (a küszöb alatti cella) |
| A pihenőnap freeze-t költ | **A2** |
| A napon belüli második esemény újra léptet | **A3** |
| Visszaállított óránál a széria törik | **A4** |
| A heti következetesség a napi szériából származik | **A5** (megszakadt széria mellett nullát ad) |
| A broken átmenet XP-t von le | **A7** — az ADR 0290 megsértése |
| A recovery bármely rövid eventet elfogad | **A9** (59s és explicit-engedély nélküli 60s cella) |
| A service stringből találja ki a pihenőnapot vagy belső fájlt importál | **A10** (publikus decision fixture + import-audit) |

**A küszöb három kötelező cellája** (a qualified day minimum érvényes időtartama (`minQualifiedDuration`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `minQualifiedDuration - 1s` gyakorlás | a nap **NEM minősül** — a széria nem lép, indok-kód: nem elégséges tevékenység |
| **rajta** (a küszöbön) | pontosan `minQualifiedDuration` | a nap **MÁR minősül** — a küszöb a MINŐSÍTŐ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `minQualifiedDuration + 1s` | a nap minősül |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Recovery-küszöb hármas:** `59s` → nem minősül · `60s` → explicit recovery
engedéllyel minősül · `61s` → explicit recovery engedéllyel minősül. Ugyanaz
a `60s` engedély nélkül továbbra sem minősül, mert a normál `120s` küszöb alatt
van.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a qualified-day ellenőrzést úgy, hogy bármely esemény minősítsen napot,
futtasd a gate-et → az **A1** küszöb alatti cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/streak_service_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `default_streak_policy.dart` — a küszöbök és a pihenőnap-szabály EGY konfigurációban.
2. `streak_service.dart` — qualified day kiértékelés, indok-kóddal.
3. A tervezett pihenőnap beolvasása a terv-szerződésből (freeze-költés NÉLKÜL).
4. A freeze / grace / broken átmenetek, mind indok-kóddal.
5. Napon belüli idempotencia.
6. Óra-anomália: változatlan állapot + indok-kód.
7. Heti következetesség külön projekcióként.
8. A valódi-sértés próba §10-be; `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „minden számít” küszöb.** Megengedőnek tűnik, és a széria hitelességét viszi el (A1).
- **Az óra-anomália „gyanúsként” kezelése.** A büntetés a felhasználót éri az eszköz állapotáért — az ADR 0290 tiltólistáján (A4).
- **A heti mérőszám származtatása a napi szériából.** Egyszerűbb kód, és egy megszakadt széria eltünteti a valós heti teljesítményt (A5).

## 10. Implementation handoff — az implementer tölti ki

### Fájlonkénti összefoglaló

- `lib/features/gamification/infrastructure/default_streak_policy.dart` — új,
  immutable és validált qualified/recovery threshold-konfiguráció (120s/60s),
  valamint a Practice Generator publikus, típusos rest-day decisionjének
  shipping `StreakLogic`-kal egyező, helyi-éjféli epoch-day projekciója
  rendszeróra-olvasás nélkül.
- `lib/features/gamification/application/streak_service.dart` — tiszta,
  caller-supplied napi evaluation typed application reasonnel; planned rest,
  grace, freeze, broken, clock anomaly, idempotencia és külön, inkluzív
  seven-day weekly consistency projekció.
- `lib/features/gamification/public.dart` — a két új nyilvános contract
  exportja.
- `test/features/gamification/application/streak_service_test.dart` — A1–A10
  bizonyíték: `119/120/121s`, explicit recovery `59/60/61s`, valós
  `WeeklyScheduleDecision` rest fixture, öt-event idempotencia, clock no-op,
  grace/freeze/broken reason-mátrix, independent weekly projection, no-XP és
  public-import audit; F1 regressziós cella a shipping helyi-éjféli request
  epoch-nappal ugyanarra a typed rest napra `plannedRest`-et vár.

### Futtatott ellenőrzések

- `flutter test test/features/gamification/application/streak_service_test.dart`
  — **11/11 passed**.
- Valódi-sértés próba: a `DefaultStreakPolicy.qualifies` ideiglenesen
  `activity != null`-t adott vissza. A
  `ROUND_GATE_SLEEP_SECONDS=0 tools/round-gate.sh test/features/gamification/application/streak_service_test.dart`
  futásban az A1 119s cella piros volt (`Expected: <0>`, `Actual: <1>`),
  továbbá a konfigurációs és recovery-alatti cellák is pirosak lettek. A
  küszöb-logika visszaállítása után:
  `ROUND_GATE_SLEEP_SECONDS=0 tools/round-gate.sh test/features/gamification/application/streak_service_test.dart`
  — **zöld**: format, analyze, célzott 11 teszt, architecture, secrets, l10n.
  A `ROUND_GATE_SLEEP_SECONDS=0` kizárólag a gate saját lépések közötti
  várakozását nullázta a harness időkorlátja miatt; egy ellenőrző lépést vagy
  küszöböt sem hagyott ki.
- F1 timezone-javítás után `dart format
  lib/features/gamification/infrastructure/default_streak_policy.dart
  test/features/gamification/application/streak_service_test.dart` — **2 fájl,
  0 változás**.
- F1 timezone-javítás után `TZ=Europe/Budapest flutter test
  test/features/gamification/application/streak_service_test.dart` — **12/12
  passed**, a shipping helyi-éjféli epoch-day regressziós cellával együtt.
- F1 timezone-javítás után `tools/round-gate.sh
  test/features/gamification/application/streak_service_test.dart` — **zöld**:
  format (1723 fájl, 0 változás), analyze (no issues), célzott 12 teszt,
  architecture (12 allowlisted deviation), secrets és l10n.

### Eltérések és nem futtatott ellenőrzések

- CI-dispatch, `gh`, PR és merge nem futott — a brief szerint az
  orchestrátor/reviewer feladata.
- Nem volt scope-tágítás, domain/storage/ledger írás vagy XP-módosítás.

## 11. Review — a Claude tölti ki
