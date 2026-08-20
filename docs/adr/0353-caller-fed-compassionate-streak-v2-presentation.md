# ADR 0353 — Hívó-adta, együttérző Streak V2 prezentáció

- **Státusz:** elfogadva
- **Dátum:** 2026-08-20
- **Kör:** `E08-R12` (Chapter 9, Kör 12)
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0351`](0351-streak-v2-read-only-legacy-migration-and-pure-policy.md),
  [`0352`](0352-qualified-day-planned-rest-and-recovery-policy.md)

## Kontextus

Az R10 `StreakState` contractja hordozza a current, longest, total qualified
days, freeze és planned-rest adatokat. Az R11 `StreakEvaluationReason`
application-projekciója különbözteti meg a qualified, insufficient, planned
rest, grace, freeze-covered, broken, recovery és clock-anomaly állapotokat,
és a `StreakService.weeklyConsistency()` külön, 0–7 közötti kész értéket ad.

A V2 felület körének scope-ja nem tartalmaz repositoryt, providert,
composition rootot vagy route-ownert. A shipping `/streak` útvonal ma a legacy
`StreakScreen`-re mutat. Emiatt a képernyő ebben a körben nem olvashat saját
állapotot és nem válthatja le a shipping route-ot; egy későbbi wiring/migrációs
kör adja majd a kész inputokat és a navigációt.

Az ADR 0290 tiltja a büntető streak-nyelvet, a fizetős visszaállítást és a
UI-oldali jutalomszámítást. Ugyanez az ADR reduced-motion mellett is megmaradó,
más modalitású visszajelzést követel.

## Döntés

1. **A V2 képernyő passzív prezentáció.** A hívó adja a `StreakState`-et, a
   `StreakEvaluationReason`-t, a kész `weeklyConsistencyDays` értéket és a
   recovery CTA callbackjét. A képernyő nem olvas órát, providert,
   repositoryt, reward ledgert vagy route-ot.
2. **A heti következetesség kész érték.** A UI csak a hívó-adta, validált
   `0..7` értéket jeleníti meg; nem vezeti le a daily streakből, dátumokból
   vagy eseményekből.
3. **A reason code vezérli a státusz-szöveget.** `plannedRest` semleges védett
   állapot, `grace` nyugodt at-risk állapot, `broken` együttérző recovery
   állapot. A broken szöveg kimondja, hogy a megszerzett tudás megmaradt;
   nincs veszteségnyelv, felkiáltójel, sürgetés vagy visszaszámláló.
4. **A recovery CTA csak a broken állapotban jelenik meg.** Egyetlen
   hívó-adta callbacket indít; a widget nem indít sessiont, nem navigál, nem
   ír állapotot és nem dönt recovery-jogosultságról.
5. **A megjelenítési visszajelzés accessibility-érzékeny.** Normál módban a
   status card finom átmenetet használhat. `MediaQuery.disableAnimations`
   mellett az átmenet időtartama nulla, de a státusz szövege, ikonja és teljes
   szemantikus címkéje megmarad. A képernyő görgethető és fix kártyamagasság
   nélküli, ezért nagy szövegskálán is hozzáférhető.
6. **A shipping `/streak` route változatlan.** Az R12 csak exportálható V2
   widgeteket szállít. A route-wiring és a V2 adatforrás bekötése a későbbi
   migrációs kör felelőssége; az R12 ezt forrásszintű regressziós cellával
   őrzi.
7. **Minden felhasználói szöveg ARB-ból jön.** Az angol és magyar új kulcsok
   párban készülnek; meglévő legacy kulcs nem változik.

## Következmények

**Pozitív.** A prezentáció determinisztikusan tesztelhető, nem duplikál
application-logikát, a legacy deep link érintetlen marad, és a későbbi wiring
egy publikus, kész UI-contractot kap.

**Ár.** A V2 képernyő e kör után még nem a shipping `/streak` célpontja. A
recovery gomb callbackje tesztelhető, de production navigációját a későbbi
wiring kör adja.

**Tiltott.** Provider/repository/clock vagy reward-számítás a widgetben;
weekly consistency levezetése; recovery eligibility kitalálása; közvetlen
navigáció a CTA-ban; shame/sürgetés/countdown; legacy route vagy legacy ARB
kulcs módosítása; a státusz-visszajelzés teljes eltüntetése reduced motionban.

## Mérce

Az E08-R12 brief A1–A8 cellái, különösen a reason-code mátrix, a broken ×
weekly-consistency kombinált állapot, a CTA egyszeri callback-próbája, az
1.0/2.0/3.0 text-scale mátrix, a reduced-motion időtartam + megmaradó
szemantika és a változatlan `/streak` route forrásőre.
