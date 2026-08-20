# ADR 0352 — Qualified day, planned rest és recovery policy

- **Státusz:** elfogadva
- **Dátum:** 2026-08-20
- **Kör:** `E08-R11` (Chapter 9, Kör 11)
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0299`](0299-weekly-scheduler-contract.md),
  [`0351`](0351-streak-v2-read-only-legacy-migration-and-pure-policy.md)

## Kontextus

Az R10 tiszta `StreakPolicy`-ja csak egy, a hívó által már minősítettnek
tekintett epoch-nap streak-hatását kezeli. A canonical learning event viszont
időtartamot és epoch-napot hordoz, a Practice Generator pedig a publikus
`WeeklyScheduleDecision` reason code-jaival jelöli a tervezett pihenőnapot.
Az R11-nek e két contract között kell determinisztikus, óra- és IO-mentes
application policyt adnia anélkül, hogy a legacy streak feature-t vagy a
Practice Generator belső kódját módosítaná.

A pre-flight megmérte, hogy a V2 `StreakGraceState` enum ma csak a semleges
`none` értéket tartalmazza. A kör engedélyezett fájljai nem tartalmazzák a
domain- vagy storage-contractot; ezért a grace/broken/rest napi állapot e
körben application-szintű, típusos projekció, nem perzisztált séma-bővítés.

## Döntés

1. **Egyetlen konfiguráció birtokol minden küszöböt.** A standard qualified
   minimum 120 másodperc valid aktivitás. Explicit recovery módban 60
   másodperc a minimum. A határok inkluzívak; negatív vagy egymásnak
   ellentmondó konfiguráció fail-closed.
2. **Recovery csak explicit engedéllyel rövidíthet.** Egy esemény típusa,
   score-ja vagy puszta létezése nem nyitja meg a recovery utat. Engedély
   nélkül a normál 120 másodperces küszöb érvényes.
3. **A napi evaluation tiszta application service.** A hívó adja az előző
   `StreakState`-et, a vizsgált epoch-napot és az opcionális canonical
   activityt. A service nem olvas órát, repositoryt vagy reward ledgert, és
   nem ír XP-t.
4. **A tervezett pihenőnap egyetlen hiteles forrása a Practice Generator
   publikus contractja.** A service a `WeeklyScheduleDecision.dayDecisions`
   listában a `ScheduleDecisionReason.restDay.code` értéket olvassa. A local
   dátum epoch-nappá alakítása naptári komponensekből történik; nincs belső
   generator-import és nincs string-literalból kitalált alternatív jel.
5. **A pihenőnap semleges.** Nem növeli a daily streaket, nem töri meg, és nem
   költ freeze-t. A következő qualified nap gap-számítása az intervening
   planned-rest napokat nem tekinti kihagyott napnak.
6. **Minden evaluation típusos reason code-ot ad.** Külön ág a qualified,
   insufficient activity, already qualified, clock anomaly, planned rest,
   grace, freeze-covered, broken és recovery. A transient grace/broken/rest
   állapot az application transition része; a `StreakState.graceState`
   perzisztált enum és a storage wiring ebben a körben változatlan.
7. **A heti következetesség önálló projekció.** Az inkluzív, lekérdezési nappal
   záródó hétnapos ablak egyedi qualified napjait számolja a hívó által adott
   naplistából. A daily streak `current` értékét nem olvassa.
8. **Nincs büntetés.** Egyetlen ág sem von le XP-t, nem csökkenti a longest vagy
   total qualified days történeti értékét, és a clock rollback no-op marad.
9. **A meglévő tiszta domain policy marad az alap.** A service az R10
   `StreakPolicy` átmeneteit használja, ahol azok szemantikája egyezik; a
   planned-rest és recovery orchestráció application felelősség.

## Következmények

**Pozitív.** Egy véletlen strum nem minősít napot; a recovery út explicit és
tesztelhető; a terv szerinti pihenés nem fogyaszt véges freeze-erőforrást; a
weekly consistency túléli a daily streak megszakadását.

**Ár.** A napi grace/rest projekció ebben a körben nem kerül perzisztált
`StreakGraceState` értékbe. Ha később storage-szintű helyreállítás kell, az
külön domain+migrációs kör és policy-version emelés.

**Tiltott.** `DateTime.now()` vagy repository-hívás a service-ben; belső
Practice Generator import; string reason code; implicit recovery; negatív XP;
planned rest freeze-ként; weekly consistency levezetése a daily streakből.

## Mérce

Az E08-R11 brief A1–A10 cellái, különösen a `119/120/121` és `59/60/61`
másodperces határhármasok, a valódi `WeeklyScheduleDecision` rest-day fixture,
az idempotencia/clock-skew mátrix és a kötelező „bármely event minősít”
mutációs próba.
