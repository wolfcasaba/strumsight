# ADR 0389 — Jutalom-postaláda és ünneplés-koordinátor: caller-fed megszakítás-tilalom és összevonás

- **Státusz:** elfogadva (E08-R22 pre-flight)
- **Dátum:** 2026-08-21
- **Kör:** `E08-R22` — Jutalom-postaláda és ünneplés-koordinátor
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0301`](0301-reward-ledger-append-only-idempotency.md),
  [`0333`](0333-activity-outbox-reliable-processing.md),
  [`0353`](0353-caller-fed-compassionate-streak-v2-presentation.md),
  [`0377`](0377-achievement-evaluator-ledger-projection-and-bounded-backfill.md)

> **Számozási megjegyzés:** a kör-brief `0316`-ot nevezte meg előre kiosztott
> ADR-számként (2026-08-18-i írás állapota), de `docs/adr/` mára `0388`-ig
> tart — a `0316` egy korábbi, független kör alatt régen elkelt. A kötelező
> `tools/round-slots.py reserve-adr --round E08-R22` futás ezért `0389`-et
> adott; a foglaló mért eredménye az irányadó (§0.0 brief-revízió rögzíti).

## Kontextus

A `reward_policy_engine.dart` és a mögötte álló kiértékelők
(`achievement_evaluator.dart`, `daily_challenge_service.dart`,
`mastery_evaluator.dart`, `profile_projector.dart`) MA is önállóan írnak a
`RewardLedgerRepository`-ba (`appendIfAbsent`), mihelyt egy aktivitás
jogosultságot szerez — ez a jutalom **jóváírása**, és teljesen független attól,
hogy a felhasználó LÁTJA-e. Ez a kör nem ezt a jóváírást építi, hanem az
utána következő, **tisztán megjelenítési** lépést: mikor és hogyan kapja meg a
felhasználó a visszajelzést anélkül, hogy megszakítaná a hangszeres
gyakorlást (a termék magja).

Az `ADR 0290` §1/§2 már kimondta: a széria/beváltás nem büntet és nem
sürget, a beváltás idempotens. Az `ADR 0301` ugyanezt az elvet az append-only
ledgerre vitte át. Az `E08-R20` (Quest/Challenge UI) volt az első
felhasználó-szembeni felület, ami ezt betartatta — ez a kör a második, és az
egyetlen, ami emellett egy ÚJ, önálló szabályt is kikényszerít: aktív
gyakorlás közben SEMMILYEN ünneplés nem szakíthatja meg a felhasználót
(§5.1). A mért tény (pre-flight, §0.0): a gyakorlási aktivitás
(`PracticeSessionState.isActive`), az átlépett szintek listája
(`ProfileProjection.crossedLevels`) és a reduced-motion jelzés
(`MediaQuery.disableAnimationsOf`) mind létező, olvasható bemenetek — de a
haptika/hang-beállítás MA nem létezik éles providerként (Kör 27 dolga). Az
`ADR 0353` „caller-fed compassionate" mintája (a Streak V2 prezentáció a
döntést a hívótól kapja, nem maga számol) pontosan erre a hiányra ad kész
választ: a koordinátor típusos bemenetként kapja, amit még nem lehet éles
providerből olvasni.

## Döntés

1. **A koordinátor nem ír a ledgerbe, és nem dönt jogosultságról.** A
   `CelebrationCoordinator` bemenete egy már **jóváírt** jutalom-esemény
   (a hívó — evaluator/ledger bridge — felelőssége, hogy a
   `RewardLedgerEntry`/szint-/mérföldkő-/quest-jóváírás megelőzze a
   koordinátor hívását). A koordinátor típusai között nem szerepelhet
   `RewardLedgerRepository` vagy bármilyen írási felület — csak olvasott,
   már véglegesített bejegyzések.

2. **Aktív gyakorlás közben a felugró abszolút tilos — nincs „kis toast"
   kivétel.** A koordinátor az aktív-session jelzést (`isActive`-ekvivalens
   bool) **caller-fed** bemenetként kapja, Riverpod-import nélkül (pure
   Dart application-réteg, a többi gamification application-fájl mintáját
   követve). Amíg ez a jelzés igaz, minden keletkező jutalom a postaládába
   kerül, függetlenül a mennyiségtől vagy a fajtájától; a session VÉGE
   (szintén caller-fed esemény) váltja ki az összevont megjelenítést.

3. **Az összevonás session-szintű és determinisztikus, küszöb-vezérelt.** A
   `celebrationBatchWindow` időablakon belül keletkező jutalmak EGY
   összefoglalóba kerülnek; az ablak **inkluzív** (a pontosan
   `celebrationBatchWindow` időkülönbség még összevonva számít, a
   `celebrationBatchWindow + 1` már különválik — §6.1 „rajta" sora). A
   prioritási sorrend explicit, tesztelt rangsoron alapul (pl. mérföldkő >
   szintlépés > quest/challenge > napi jutalom), **nem** egy `Map` bejárási
   sorrendjén.

4. **A postaláda értesítési felület, nem beváltás — nincs lejárat, nincs
   „Begyűjtés" gomb.** A `RewardInboxItem` nem hordoz lejárati mezőt, és a
   `reward_inbox_screen.dart` nem ad műveletet, ami a jutalom státuszát
   módosítaná. A megnyitás/megtekintés (seen/unseen) csak megjelenítési
   állapot, nem beváltási előfeltétel — ez az `ADR 0290` §5.2-nek a
   gamification UI-ra vitt megfelelője.

5. **Reduced motion: az információ megmarad, csak az animáció esik ki.** A
   `reward_summary_sheet.dart` a meglévő precedenst követi
   (`MediaQuery.disableAnimationsOf(context)`, ld.
   `streak_status_card.dart:16`): `disableAnimations == true` esetén a
   composit ugyanazt a szöveges/numerikus tartalmat statikusan rendereli.
   Tilos ág: reduced motion → az ünneplés (és az információ) teljes
   elhagyása.

6. **Haptika/hang: caller-fed bool, nem élő settings-provider.** Mivel MA
   nincs élő haptika/hang-beállítás provider (`lib/features/settings/`), a
   koordinátor/összefoglaló ezeket explicit bool paraméterként
   (`hapticsEnabled`, `soundEnabled`) fogadja a hívótól — az éles
   settings-wiring Kör 27 dolga. A hiányzó élő bemenet emiatt nem válik
   csendes lista-tágítássá: a teszt a koordinátor viselkedését a paraméter
   mindkét értékére méri, a valódi forrást a jövőbeli kör köti be.

## Következmények

A jutalom jóváírása és a felhasználó felé való megjelenítése két, egymástól
független időpontban történhet — ez szándékos: egy háttérben vagy bezárt
folyamatban szerzett jutalom (§6 A5) attól még azonnal a ledgerben van, csak
a postaláda mutatja meg később. A koordinátor pure-Dart, tesztelhető marad
(nincs Flutter-/Riverpod-függés), a Flutter-specifikus olvasás
(`MediaQuery`, a jövőbeli settings-providerek) a prezentációs rétegben
marad — ugyanaz a réteg-határ, amit a többi gamification application-fájl
(pl. `reward_policy_engine.dart`) is tart.

A haptika/hang caller-fed modellezésének ára, hogy Kör 27-ig a valós
alkalmazásban ezek a paraméterek egy konkrét (pl. mindkettő "bekapcsolva")
alapértéken futnak a hívó oldalon — ez a jövőbeli kör tartozása, nem e kör
rése, és a §0.0 brief-revízió ezt dokumentálja.

## Mérce

Az E08-R22 brief §6/§6.1 cellái (A1–A8): a megszakítás-mátrix (aktív
gyakorlás → SOSE felugró, még kis toast formájában sem); az összevonási
küszöb-hármas (alatt/rajta/fölött, a `celebrationBatchWindow`-n); a
sorrend-cella (jutalom a ledgerben MIELŐTT a postaládába kerül); a
lejárat-/begyűjtés-mentesség; a determinisztikus prioritás-mátrix; a
reduced-motion ekvivalencia-próba; a tartósság app-újraindítás után. A §6.1
kötelező valódi-sértés próba (engedd meg a felugrót aktív gyakorlás közben →
az A1 cellának pirosra kell váltania → állítsd vissza) a 2. döntés gépi őre.
