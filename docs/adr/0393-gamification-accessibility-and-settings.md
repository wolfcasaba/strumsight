# ADR 0393 — Gamifikáció akadálymentesség és beállítások: vizuális kikapcsolás, engedély-jutalom tilalma, azonnali érvényesülés

- **Státusz:** elfogadva (E08-R27 pre-flight)
- **Dátum:** 2026-08-22
- **Kör:** `E08-R27` — Gamification accessibility és settings
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0307`](0307-pipeline-throughput-program-v2.md),
  [`0374`](0374-achievement-domain-and-catalog-contract.md),
  [`0389`](0389-reward-inbox-and-celebration-coordinator.md)

> **Számozási megjegyzés:** a kör-brief `0318`-at nevezte meg előre kiosztott
> ADR-számként (2026-08-18-i írás állapota), de az azóta elkelt egy korábbi,
> független körnél
> (`0318-song-goal-public-boundary-and-caller-fed-input.md`). A kötelező
> `tools/round-slots.py reserve-adr --round E08-R27` futás ezért `0393`-at
> adta; a foglaló mért eredménye az irányadó (§0.0 brief-revízió rögzíti).

## Kontextus

Az Epic 8 gamifikációs rétege (Kör 01–26) a haladás mérésére, jutalmazására
és megjelenítésére épült — de eddig egyetlen kör sem adott a felhasználónak
tényleges KAPCSOLÓT a réteg felett. Az `ADR 0389` §6 caller-fed bool
paraméterként (`hapticsEnabled`, `soundEnabled`) vezette be a
`reward_summary_sheet.dart` viselkedés-kapcsolóit, explicit megjegyezve, hogy
„az éles settings-wiring Kör 27 dolga". Ez a kör az, amelyik a beállítás-
modellt és a beállítás-szekciót megépíti — de a pre-flight mérése szerint
(§0.0) a `reward_summary_sheet.dart`-nak MA nincs élő hívója (`grep -rn
"RewardSummarySheet(" lib/` → 0 találat), tehát a „bekötés" ma csak egy
leképezés-szintű szerződés lehet, nem egy létező képernyő tényleges
huzalozása. Ez az ADR pontosítja az `ADR 0389` §6 ígéretét: a PROVIDER és a
leképezés e körben készül el, a képernyő-szintű integráció egy jövőbeli,
a celebration-felületet ténylegesen megjelenítő kör (feltehetően `E13-R32`,
a `docs/execution/pipeline-queue.tsv` „gamification-ui" sora) tartozása
marad.

## Döntés

1. **A kikapcsolás vizuális, a haladás-adat sosem vész el.** A gamifikációs
   réteg (ledger, széria, mastery) kiértékelése a felhasználói
   preferenciáktól FÜGGETLENÜL fut — a `GamificationPreferences` egyetlen
   mezője sem érheti el vagy állíthatja meg az `application/*_evaluator.dart`
   / `*_service.dart` réteget (ezek nincsenek is az `allowed_paths`-on). A
   preferenciák kizárólag a MEGJELENÍTŐ réteg bemenetei: mit mutat, mit
   hallat, mit rezeg — nem hogy mi történik a ledgerben. Visszakapcsoláskor
   ezért az előzményben nem keletkezhet lyuk, mert az esemény-feldolgozás
   sosem állt le (§6 A1/A2 gépi őre: valódi-sértés próba — a kikapcsolás az
   esemény-feldolgozást is leállítja → A1-nek pirosra kell váltania).

2. **Az értesítési engedély megadása nem jár jutalommal.** A
   `GamificationPreferences.notificationsEnabled` (vagy megfelelője) átállítása
   — bármelyik irányba — nem termel `RewardEvent`-et, nem ad XP-t, nem old
   fel achievementet, és nem befolyásol quest-progressziót. Ez az `ADR 0290`
   §1/§5.2 (nincs büntető/sürgető nyelv, nincs beváltási akadály) engedély-
   oldali kiterjesztése: az engedély-jutalom („kis üdvözlő bónusz")
   ugyanaz a sötét minta, mint egy mesterséges lejárat vagy egy rejtett
   beváltás-feltétel, és tiltott (§6 A3 gépi őre).

3. **A beállítás azonnal és teljesen érvényesül — nincs újraindítás-igény.**
   A preferencia-provider (Riverpod) állapotváltása szinkron, és a következő
   kiértékelt megjelenítési döntés (a leképezés-teszt szintjén) MÁR az új
   értéket olvassa. A tárolás a `settings_sync.dart` mért mintáját követi
   (lokálisan azonnal ír; egy jövőbeli felhő-szinkron csak szerver-
   megerősítés UTÁN jelölne szinkronizáltnak) — DE e kör `allowed_paths`-a
   nem tartalmazza a `settings_sync.dart`-ot, tehát a preferenciák e körben
   KIZÁRÓLAG lokálisan perzisztálnak; a felhő-bekötés nem e kör dolga (§3).

4. **Minden achievementnek van kitöltött akadálymentességi leírása — mért
   regresszió-őr, nem új mező.** Az `AchievementDefinition
   .accessibilityDescriptionKey` már az `ADR 0374`/Kör 13 óta kötelező,
   konstruktor-validált mező, és a `default_achievement_catalog.dart` mind a
   22 bejegyzéshez kitölti (`'${keyStem}Semantics'`). E kör kényszeríti ki
   GÉPI mércével (a) hogy minden katalógus-bejegyzéshez létezzen ilyen kulcs,
   ÉS (b) hogy a kulcs mindkét ARB-ban (`en`, `hu`) jelen legyen és NE legyen
   üres — egy jövőbeli, hiányosan felvett achievement így pirosra vált,
   mielőtt élesbe kerülne.

5. **A haptika/hang/intenzitás/mozgás beállítás e körben leképezés-szintű
   szerződés, nem élő UI-huzalozás (pontosítja az `ADR 0389` §6-ot).** Az
   `ADR 0389` §6 ígérete („az éles settings-wiring Kör 27 dolga") arra a
   PROVIDERRE vonatkozott, ami e körben létrejön — nem egy ma nem létező
   celebration-képernyőre. A `gamification_accessibility_test.dart` a mind
   az öt preferenciát egy tesztelt leképezési függvényen keresztül a
   megfelelő megjelenítési paraméterekre (pl. `RewardSummaryFeedback`-
   ekvivalens érték) fordítja, és ezt méri közvetlenül — a
   `reward_summary_sheet.dart` tényleges hívása (és a stale „the wiring
   lands in round 27" doc-komment javítása) egy jövőbeli, a celebration-
   felületet ténylegesen megjelenítő kör tartozása marad (nyitott tétel,
   HANDOFF §6).

6. **Az l10n-kulcsok forrása a `gamification` szegmens, nem a generált
   aggregátum (`ADR 0307` §4 alkalmazása).** Az új preferencia-szekció
   szövegei tartalmilag gamifikációs fogalmak (ünneplés-intenzitás, haptika,
   hang, mozgás, értesítés), ezért a `lib/l10n/features/gamification_en.arb`
   / `gamification_hu.arb` szegmensbe kerülnek, NEM a kézzel nem
   szerkesztendő `lib/l10n/app_{en,hu}.arb` aggregátumba — ugyanaz a fájl-
   fizikai-hely vs. tartalmi-hovatartozás elv, mint amit a brief §4 rögzít a
   beállítás-szekcióra magára (fizikailag `settings/`, tartalmilag
   gamifikáció).

## Következmények

A preferencia-modell és a megjelenítési leképezés e körben teljesen
tesztelhető pure-Dart/Riverpod-provider szinten, Flutter-widget-fa vagy élő
képernyő nélkül — ez szándékos: a tényleges celebration-UI (és annak
huzalozása a preferenciákra) egy külön, UI-fókuszú kör dolga. Ennek ára, hogy
a `reward_summary_sheet.dart` doc-kommentje egy ideig továbbra is a „Kör 27"
számra hivatkozik majd tévesen — ez dokumentált, alacsony kockázatú
tartozás (nem tesztelt állítás, nem viselkedés), amit a képernyő-szintű
bekötő kör javít ki egyúttal.

A WCAG AA kontrasztküszöb (§6 A7) a mért `L381` hibaosztály (idealizált
luminanciával átjárható, hibásan linearizált küszöbteszt) ellen két külön
bizonyítékot kényszerít ki: a below/at/above döntési hármas ÉS legalább egy
kipinnelt, nem idealizált RGB-vektor a teljes sRGB→luminancia úton
(`math.pow(x, 2.4)`, nem köbözés).

## Mérce

Az E08-R27 brief §6/§6.1 cellái (A1–A8): az adat-megőrzés valódi-sértés
próbája (A1/A2 — a kikapcsolás NEM állíthatja le az esemény-feldolgozást);
az engedély-jutalom tilalma (A3); az öt-beállítás leképezés-mátrix (A4); az
azonnali érvényesülés (A5); az achievement a11y-kitöltöttség regresszió-őre
(A6); a WCAG AA küszöb-hármas + kipinnelt vektor (A7); és a `test/features/
settings` suite változatlan zöldje (A8, a gate önmagában bizonyítja). A §6.1
kötelező valódi-sértés próba (állítsd le az esemény-feldolgozást
kikapcsoláskor → A1 pirosra vált → állítsd vissza) az 1. döntés gépi őre.
