# ADR 0351 — Streak V2: read-only legacy migráció és tiszta policy

- **Státusz:** elfogadva
- **Dátum:** 2026-08-20
- **Kör:** `E08-R10` (Chapter 9, Kör 10)
- **Kapcsolódó:** [`0085`](0085-learn-migration-and-progress-merge.md),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0344`](0344-gamification-storage-schema-versioned-documents-and-layer-purity.md),
  [`0350`](0350-legacy-practice-backfill-identity-zero-xp-and-checkpoint.md)

## Kontextus

A shipping streak domain öt értéket tárol: `current`, `longest`,
`lastPracticeDay`, `freezes`, `totalDays`. A wire-nevek rendre `current`,
`longest`, `last`, `freezes`, `total`. A tiszta `StreakLogic.applyPractice`
óra és IO nélkül kezeli az első napot, azonos/visszafelé mozdult napot, a
gap 1 és gap 2 ágakat, a resetet, továbbá minden hetedik qualified nap után
freeze-t ad legfeljebb háromig.

A pre-flight egy fontos storage-ütközést mért. A core v22 storage migration a
`practice_streak_v1` raw JSON-t `ss.streak.state` envelope-ba költözteti, majd
törli a régi kulcsot. Ez már merge-elt viselkedés. Az R10 brief korábbi
szövege ezzel szemben kizárólag a legacy kulcsból kért migrációt, miközben a
legacy kulcs megőrzését is előírta. Egy új V2 gamification storage-kulcs sem
vezethető be a migrátor fájljában: az ADR 0344 szerint minden ilyen kulcs a
központi gamification séma tulajdona, amely nem része az implementer scope-jának.

## Döntés

1. **A V2 domain az SDD §8.10 nevét használja, az értéket nem változtatja.**
   `lastPracticeDay` → `lastQualifiedDay`, `totalDays` →
   `totalQualifiedDays`; a másik három mező neve változatlan. A
   `policyVersion` induló értéke `1`, a `graceState` semleges alapállapotú,
   a `plannedRestDays` üres, másolás ellen védett halmaz.

2. **A policy tiszta és óra-mentes.** A hívó adja a qualified epoch-napot.
   A policy nem importál Fluttert, Riverpodot vagy storage-t, és nem hív
   `DateTime.now()`-t. A policy a teljes legacy átmeneti mátrixot reprodukálja,
   beleértve az első napot, clock-skew no-opot, freeze-awardot és a capet.

3. **Minden policy-hívás állapotot és indok-kódot ad.** Az azonos nap és a
   visszafelé mozdult nap külön indok, noha mindkettő változatlan állapotot
   eredményez. Így a Kör 11 az óra-anomáliát találgatás nélkül kezeli.

4. **A legacy migrátor read-only forrásadapter.** Elsőként a
   `ss.streak.state` envelope-ot olvassa; ha nincs, a `practice_streak_v1`
   raw JSON-t. Egyiket sem írja vagy törli. Ugyanaz a store kétszer ugyanazt a
   V2 értéket adja. Ismeretlen legacy mező figyelmen kívül marad, a shipping
   öt mező validációja megmarad. Sérült vagy jövőbeli envelope nem válik
   csendes üres streakké: explicit hibát ad.

5. **Ebben a körben nincs V2 persistence wiring.** A migrátor előállítja a
   verziózott V2 domain-értéket, de új kulcsot nem talál ki. A tartós V2
   repository és a feature-hívók átállítása külön, explicit wiring-kör tárgya.
   Ez additív és rollbackelhető, az ADR 0085 migrációs mintájával összhangban.

6. **A legacy projekció feature-semleges DTO.** A gamification domain nem
   importálhatja a `lib/features/streak/` belső `StreakData` típusát. A
   `LegacyStreakProjection` az öt legacy értéket hordozza; a jelenlegi
   `StreakBadge`/provider bekötése változatlan marad.

7. **A qualified-day policy küszöbe még nincs itt.** Az R10 policy kizárólag
   egy már qualified nap streak-hatását kezeli. A minimum duration, planned
   rest, recovery, grace és weekly consistency a Kör 11 kötött feladata;
   ezeket az R10 nem hardcode-olja előre.

## Következmények

**Pozitív.** Nincs streak-adatvesztés, a régi útvonal érintetlen, a teljes
shipping logika determinisztikusan tesztelhető, és a már lefutott core
storage migration után is van migrációs forrás.

**Ár.** A V2 állapot e kör után domain contract, még nem a shipping widget
perzisztens forrása. Ez tudatosan elválasztja a szemantikát a későbbi wiringtól.

**Tiltott.** `DateTime.now()` vagy IO a policyben; a `longest` újraszámítása;
forráskulcs törlése; új storage-kulcs a migrátorban; cross-feature belső
`StreakData` import; a Kör 11 küszöbeinek előre kitalálása.

## Mérce

Az E08-R10 brief A1–A10 cellái és a teljes legacy átmeneti mátrix. Kötelező
mutációs próba: a `gap == 2 && freezes > 0` ág eltávolítása az A4 freeze-cellát
pirosra váltja, majd visszaállítás után a teljes kör-gate zöld.
