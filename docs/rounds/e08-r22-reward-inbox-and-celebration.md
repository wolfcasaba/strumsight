# E08-R22 — Jutalom-postaláda és ünneplés-koordinátor

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 22
- **Kör-azonosító:** `E08-R22`
- **Branch:** `<motor>/e08-r22-reward-inbox-and-celebration`
- **Előfeltétel:** `E08-R21` merge-elve (mastery kiértékelő)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0316` — STALE, lásd §0.0 (a foglaló a tényleges
  szabad számot, `ADR 0389`-et adta). Az ADR-t a Claude írja meg a kör
  indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R07 „átlépett szintek listája” kimenetét (a több szintlépés összevonása erre épül) és a `lib/features/live/` gyakorlás-közbeni állapotjelzését — a „zenélés közben nincs felugró” szabály ezt kérdezi. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/profile/reward_inbox_item.dart",
  "lib/features/gamification/application/celebration_coordinator.dart",
  "lib/features/gamification/presentation/screens/reward_inbox_screen.dart",
  "lib/features/gamification/presentation/widgets/reward_summary_sheet.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "tool/gen_l10n_segments.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/application/celebration_coordinator_test.dart",
  "docs/rounds/e08-r22-reward-inbox-and-celebration.md",
]
gate_tests = [
  "test/features/gamification/application/celebration_coordinator_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (Claude, 2026-08-21)

**ADR-szám csere.** Az előre kiosztott `ADR 0316` a foglaló szerint már
elfogyott — `docs/adr/` a `0388`-ig tart, a `0316` egy korábbi, független kör
alatt régen elkelt (ugyanaz a mintázat, mint az E08-R21/H0-nál, ahol a
`0315` bizonyult ütközőnek). `tools/round-slots.py reserve-adr --round
E08-R22` a tényleges szabad számot adta: **`ADR 0389`**. A brief további
részében és a §11 review-ban az `ADR 0316` hivatkozás mindenütt `ADR 0389`-re
értendő; az ADR fájl `docs/adr/0389-reward-inbox-and-celebration-coordinator.md`
néven készül.

**1. Elérhetetlen cél-státusz — mért bemenetek:**

- **„Aktív gyakorlás" bemenet MÉRVE reachable.** `PracticeSessionState.isActive`
  (`lib/features/practice/domain/model/practice_session_state.dart`) igaz
  `countIn`/`running`/`paused`/`finishing` státuszra, exportálva a
  `practice/public.dart`-ban (`PracticeSessionState`, `PracticeSessionStatus`).
  A koordinátor ezt **caller-fed** bemenetként kapja (bool vagy a típus
  maga), NEM importálja a Riverpod providert — az application-réteg
  (`celebration_coordinator.dart`) a többi gamification application-fájl
  mintáját követi (pure Dart, Flutter-mentes, ld. `reward_policy_engine.dart`,
  `profile_projector.dart`).
- **R07 „átlépett szintek" lista MÉRVE reachable.**
  `ProfileProjection.crossedLevels` (`profile_projector.dart:104`, típus
  `List<LevelDefinition>`) — a §5.3 összevonás ezen a listán dolgozik.
- **Reduced motion MÉRVE reachable, meglévő precedenssel.** Nincs külön
  domain-szintű settings-provider; a meglévő minta
  (`lib/features/gamification/presentation/widgets/streak_status_card.dart:16`)
  közvetlenül `MediaQuery.disableAnimationsOf(context)`-tal olvassa a
  widget-rétegben — a `reward_summary_sheet.dart`/`reward_inbox_screen.dart`
  ugyanezt a mintát követi.
- **Haptika/hang beállítás NEM reachable ma — brief-rés, feloldva.**
  `grep -rln "haptic\|Haptic\|soundEnabled" lib/features/settings/` **0
  találat**: nincs élő, olvasható haptika/hang-beállítás provider (a
  beállítások képernyő maga Kör 27, a brief §3 szerint is jövőbeli). A §5.4
  „a haptika és a hang külön kapcsolható" ezért **caller-fed bool
  paraméterként** (`hapticsEnabled`, `soundEnabled`) modellezendő a
  koordinátoron/összefoglalón — a valódi settings-wiring Kör 27 dolga, nem
  ennek a körnek a rése. Ez ugyanaz a caller-fed minta, mint az ADR 0353
  „caller-fed compassionate" streak-előírás.

**2. Erőforrás-tulajdonlás — MÉRVE.** A jutalom főkönyvi írása
(`RewardLedgerRepository.appendIfAbsent`) MA is a kiértékelőkben történik
(`grep -rln "appendIfAbsent" lib/features/gamification/` →
`achievement_evaluator.dart`, `daily_challenge_service.dart` — az
alkalmazás-réteg evaluatorai, NEM a koordinátor). A §5.2/A3 tehát nem azt
követeli meg, hogy a koordinátor írjon a főkönyvbe, hanem hogy a
postaláda-elem sose előzze meg a HÍVÓ oldali, már megtörtént főkönyvi írást —
a koordinátor ezt egy már-jóváírt jutalom-eseményt hordozó, típusos bemeneten
méri, nem saját IO-val.

**Visszakeresett előzmény** (ADR 0312, szűkített korpusszal előbb):
`halts/E08-R20` (Quest/Challenge UI — „no-claim, no popup-spam" ugyanabban a
family-ben, valódi-sértés próbával igazolt A1-mintájú megszakítás-mátrix),
`halts/E08-R19` (Challenge V2 — idempotens jutalom, katalógus-verzió pin),
`halts/E07-R08` (Practice capability adapter — precedens a gyakorlási állapot
public contracton át olvasására), `adr/0290` (Együttérző széria és idempotens
beváltás — a §5.2 „nincs beváltás" szabály forrása), `adr/0301` (Reward
ledger append-only idempotency), `adr/0377` (Achievement evaluator: ledgerhez
kötött projekció), `adr/0333` (Activity outbox: megbízható, korlátos
feldolgozás — caller-fed minta precedense), és a SDD-forrás
`docs/sdd/09-epic-08-gamification.md:2905` (Kör 22 eredeti terve). Nem talált
a fentiekkel ellentétes elfogadott döntést.

**Kockázat = high, indoklás:** a `risk = "high"` a brief eredeti besorolása
szerint marad, bár egyik `allowed_paths` sem egyezik a router
`high_risk_path_fragments` listájával (auth, credential, crypto, migration,
payment, secret, upload, vision, …). Az indok tartalmi: ez a kör az ADR 0290
§1/§5.2 (nincs sürgető/lejáró szöveg, nincs beváltás-gomb) MÁSODIK
felhasználó-szembeni kirakata a Quest/Challenge UI (E08-R20) után, ÉS az
egyetlen felület, ami a hangszeres gyakorlás MEGSZAKÍTÁSÁNAK tilalmát (§5.1)
kényszeríti ki — egy visszacsúszó „csak egy kis toast" vagy egy „Begyűjtés"
gomb nem csak UI-kozmetika, hanem a termék magját (a zavartalan gyakorlást) vagy
a mért compassionate-UX szerződést törné el. Ezt kizárólag a §6.1 kötelező
valódi-sértés próba (A1-re) és a küszöb-hármas cella fogja meg gépi mércével.

### §0.0.1 l10n-fragment scope (mid-round revízió, Claude, 2026-08-21, mérve)

Az E08-R20 §0.0.1-es analóg revízióját (L396) követve: a `lib/l10n/app_en.arb`
és `app_hu.arb` a PR #343 (ADR 0307 §4) óta **GENERÁLT aggregátum**, nem
kézzel szerkesztett forrás. A tényleges forrásfájl a gamification feature-höz a
`lib/l10n/features/gamification_en.arb` és `gamification_hu.arb`
(`tool/gen_l10n_segments.dart` egyesíti a `lib/l10n/base/` + `lib/l10n/features/`
szegmenseket → `lib/l10n/app_<locale>.arb` → `flutter gen-l10n` →
`lib/l10n/app_localizations_<locale>.dart`). Az első implementer-futás a kulcsokat
a generált aggregátumba írta (rossz hely), a gate-fix commit eltávolította
onnan (mert a `flutter gen-l10n` mindig újraírja), de a tényleges forrás
(`features/gamification_*.arb`) üres maradt → `analyze` 11 undefined-getter
hibát dobott a `rewardInbox*`/`rewardSummary*` getterekre. A javító kör az új
kulcsokat a **`lib/l10n/features/gamification_{en,hu}.arb`**-be írja, majd a
meglévő aggregátort a `tool/gen_l10n_segments.dart --write` → `flutter gen-l10n`
szekvenciával szinkronizálja. Az `allowed_paths` és a §4 tábla ezen §0.0.1
revízióval végleges.

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

A jutalmakat **nem zavaró**, összevont és akadálymentes módon jelenítsd meg. A
postaláda **nem beváltás-mechanika**: a jutalom már jóvá van írva, mire ide kerül.

## 2. Jelenlegi állapot — mért tények

- Az R07 az átlépett szintek listáját adja; az R03 főkönyve a jutalmakat.
- `reward_inbox_item.dart` és a koordinátor **nem létezik**.
- A `lib/features/live/` és `lib/features/practice/` aktív gyakorlási állapotot jelez — ez a felugró tiltásának bemenete.
- Az `ADR 0290` §2: a beváltás idempotens, a felület nem számol jutalmat.

## 3. Scope

**Benne van:** a session jutalmainak prioritizálása és **összevonása** · több szintlépés EGY
összefoglalóban · **nincs felugró zenélés közben** · háttérben vagy bezárt folyamatban
keletkezett jutalom a postaládába · a postaláda NEM beváltás · reduced motion, haptika és
hang beállítás tiszteletben tartása.

**NINCS benne (tilos):**

- Beváltás-mechanika a postaládában (§5.2) — abszolút tilos.
- Jutalom-számítás a felületen (ADR 0290 §2).
- A beállítások képernyő (Kör 27) — itt csak a meglévő beállítások OLVASÁSA történik.
- `docs/adr/**` — az ADR 0389-et (§0.0) a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/profile/reward_inbox_item.dart` | **ÚJ** — a postaláda-elem |
| `lib/features/gamification/application/celebration_coordinator.dart` | **ÚJ** — prioritás, összevonás, megszakítás-politika |
| `lib/features/gamification/presentation/screens/reward_inbox_screen.dart` | **ÚJ** — a postaláda |
| `lib/features/gamification/presentation/widgets/reward_summary_sheet.dart` | **ÚJ** — az összevont összefoglaló |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/features/gamification_en.arb` | **ÚJ kulcsok forrása** (lásd §0.0.1) |
| `lib/l10n/features/gamification_hu.arb` | az ÚJ kulcsok magyar forrása |
| `tool/gen_l10n_segments.dart` | az aggregátor-generátor (ADR 0307 §4) — opcionális, ha a szegmens-tartalom változik |
| `lib/l10n/app_en.arb` | GENERÁLT aggregátum — a szegmens-forrásból `tool/gen_l10n_segments.dart --write` állítja elő |
| `lib/l10n/app_hu.arb` | GENERÁLT aggregátum — ua. |
| `test/features/gamification/application/celebration_coordinator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0389, §0.0)

### 5.1 ZENÉLÉS KÖZBEN NINCS FELUGRÓ — soha

Aktív gyakorlási vagy felvételi állapotban semmilyen ünneplés nem szakítja meg a
felhasználót. A jutalom a postaládába kerül, és a session VÉGÉN jelenik meg összevontan.

**NEM elfogadható gyengítés:** „csak egy kis toast”. A hangszeres gyakorlás megszakítása a
termék magját rontja el — és a jutalom amúgy is jóvá van írva.

### 5.2 A POSTALÁDA NEM BEVÁLTÁS — a jutalom már jóvá van írva

A postaláda **értesítési** felület: megmutatja, mi történt. A megnyitása nem
feltétele semminek, és a nem megnyitott elem nem jár le.

**NEM elfogadható gyengítés:** „Begyűjtés” gomb vagy lejáró postaláda-elem.

### 5.3 ÖSSZEVONÁS: több szintlépés EGY összefoglaló

Egy session során átlépett három szint egyetlen összefoglalóban jelenik meg, nem
három egymás utáni animációban. A prioritási sorrend **tesztelt** és determinisztikus.

### 5.4 REDUCED MOTION: a visszajelzés CSÖKKEN, nem tűnik el

Csökkentett mozgás beállítás mellett az ünneplés statikus, de **teljes értékű**:
ugyanaz az információ, animáció nélkül. A haptika és a hang külön kapcsolható.

**NEM elfogadható gyengítés:** reduced motion esetén az ünneplés teljes elhagyása — az
információt is elvenné.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Aktív gyakorlás közben SEMMILYEN ünneplés nem jelenik meg | `celebration_coordinator_test.dart` — megszakítás-mátrix |
| A2 | A session végén a jutalmak ÖSSZEVONTAN jelennek meg (három szintlépés → egy összefoglaló) | `celebration_coordinator_test.dart` |
| A3 | A jutalom a főkönyvben van, MIELŐTT a postaládába kerül | `celebration_coordinator_test.dart` — sorrend-cella |
| A4 | A postaláda-elem NEM jár le, és nincs begyűjtés-gomb | `celebration_coordinator_test.dart` |
| A5 | Háttérben/bezárt folyamatban keletkezett jutalom a postaládában megjelenik | `celebration_coordinator_test.dart` |
| A6 | A prioritási sorrend determinisztikus és tesztelt | `celebration_coordinator_test.dart` — prioritás-mátrix |
| A7 | Reduced motion mellett az ünneplés statikus, de UGYANAZT az információt adja | `celebration_coordinator_test.dart` |
| A8 | A postaláda tartós: app-újraindítás után is megvan | `celebration_coordinator_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Toast jelenik meg gyakorlás közben | **A1** |
| Három szintlépés három animáció | **A2** |
| A postaláda-elem a jutalom jóváírása ELŐTT jön létre | **A3** |
| Begyűjtés-gomb a postaládában | **A4** |
| Reduced motion esetén az ünneplés elmarad | **A7** |
| A prioritás a `Map` bejárási sorrendjéből | **A6** |

**A küszöb három kötelező cellája** (az összevonási ablak (`celebrationBatchWindow`) — meddig várunk további jutalomra összevonás előtt):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | két jutalom `celebrationBatchWindow - 1` időkülönbséggel | **ÖSSZEVONVA** — egy összefoglaló |
| **rajta** (a küszöbön) | pontosan `celebrationBatchWindow` időkülönbség | **MÉG ÖSSZEVONVA** — az ablak az ÖSSZEVONÓ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `celebrationBatchWindow + 1` időkülönbség | **KÜLÖN** összefoglaló; a második a postaládába kerül, ha közben gyakorlás indult |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd meg a felugrót aktív gyakorlás közben, futtasd a gate-et → az **A1**
megszakítás-mátrix cellájának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/celebration_coordinator_test.dart
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

1. `reward_inbox_item.dart` — a postaláda-elem (lejárat NÉLKÜL).
2. `celebration_coordinator.dart` — prioritás, összevonás, megszakítás-politika.
3. A gyakorlási állapot lekérdezése (public contracton át) és a felugró tiltása.
4. `reward_summary_sheet.dart` — az összevont összefoglaló.
5. `reward_inbox_screen.dart` — a postaláda, begyűjtés nélkül.
6. Reduced motion / haptika / hang beállítás tiszteletben tartása.
7. Az ARB-kulcsok; a `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „csak egy kis toast”.** A legkisebb engedmény is megszakítja a hangszeres gyakorlást (A1).
- **A begyűjtés-mechanika.** A postaláda felület ránézésre kínálja; az ADR 0290 §2 tiltja (A4).
- **A reduced motion „kikapcsolásként” értelmezése.** Az információt is elveszi, nem csak a mozgást (A7).

## 10. Implementation handoff — az implementer tölti ki

**Round:** `E08-R22` · **Engine:** MiniMax M3 (autonomous) · **Branch:** `minimax/e08-r22-reward-inbox-and-celebration` · **Commit tip:** a §8 szerinti sorrendben, fájlonkénti commitok (4 db production-commit + 1 teszt-commit + 1 gate-fix-commit + a §0.0.1 mid-round revízióhoz kapcsolódó 2 javító-commit: forrás-fragment + aggregátum-regen). A gate utolsó futása a JAVÍTÓ KÖRBEN: `tools/round-gate.sh test/features/gamification/application/celebration_coordinator_test.dart` (előtérben, csonkítatlanul, 2026-08-21) — minden lépés zöld:

```
═══ [1] format                                            zöld  (Formatted 1791 files, 0 changed)
═══ [2] analyze                                           zöld  (No issues found!)
═══ [3] test test/features/gamification/application/celebration_coordinator_test.dart   zöld  (18/18 All tests passed!)
═══ [4] architecture                                      zöld  (Architecture dependencies OK)
═══ [5] secrets                                           zöld  (3210 file(s) scanned, 0 finding(s))
═══ [6] l10n                                              zöld  (parity OK, en → hu, 1584 message(s))
MINDEN GATE ZÖLD.
```

### §6 / §6.1 cellák → mérő tesztek (L09 — csak LEFUTTATOTT bizonyíték)

| Cell | Bizonyíték (test név + fájl) | Parancs |
|---|---|---|
| **A1** megszakítás-mátrix | `A1 — active session: no celebration, ever (§5.1)` × 3 + `A1 — szigorú megszakítás-mátrix (valódi-sértés próba)` | `flutter test test/features/gamification/application/celebration_coordinator_test.dart` (lásd lent) |
| **A2** összevonás | `A2 — session end: multiple rewards consolidate into ONE summary` | ua. |
| **A3** sorrend-cella | `A3 — reward must already be in the ledger before it reaches the coordinator` × 2 | ua. |
| **A4** nincs lejárat/begyűjtés | `A4 — no expiry, no claim field on RewardInboxItem (§5.2)` (a `RewardInboxItem.toJson()` kulcsai között nincs `expiresAt`/`claimedAt`/`claimState`) | ua. |
| **A5** háttér/bezárt folyamat | `A5 — background / closed-app rewards still surface in the inbox` | ua. |
| **A6** determinisztikus prioritás | `A6 — deterministic priority order (§5.3)` × 2 (mindkét beszúrási irányból azonos eredmény) | ua. |
| **A7** reduced motion | `A7 — reduced motion: information preserved, animation dropped (§5.4)` (a `CelebrationSummary.events` minden mezőt tartalmaz, nincs csonkítás) | ua. |
| **A8** postaláda tartós | `A8 — inbox survives app restart via JSON round-trip` × 2 | ua. |
| §6.1 **alatt** (window-1) | `alatt (window - 1): the two events are CONSOLIDATED into one summary` | ua. |
| §6.1 **rajta** (pontosan window) | `rajta (exactly window): the boundary belongs to ÖSSZEVONÁS (inclusive)` | ua. |
| §6.1 **fölött** (window+1) | `fölött (window + 1): the two events become SEPARATE summaries` | ua. |
| §6.1 **fölött + gyakorlás indult** | `fölött + közben gyakorlás indult: the second event goes to the INBOX` | ua. |

**Végső futás (JAVÍTÓ KÖR, LEFUTTATVA):** `tools/round-gate.sh test/features/gamification/application/celebration_coordinator_test.dart` — `MINDEN GATE ZÖLD` — 18/18 teszt zöld (`All tests passed!`), analyze 0 issues (`No issues found!`), l10n parity OK (en → hu, **1584 message** — az előző, hamis futás 1572-es számához képest +12, a forrás-fragmentumba írt 12 új kulccsal konzisztens). A gate kimenete a jelen §10 „Gate utolsó futása" kó-blokkban szó szerint idézve; a parancs a §7-nek megfelelően előtérben, csonkítatlanul futott.

### §6.1 valódi-sértés próba (KÖTELEZŐ) — LEFUTTATVA

A brief §6.1 előírja, hogy a §10-ben dokumentáljam egy „engedd meg a felugrót aktív gyakorlás közben” típusú szándékos regresszió tényleges, gépi bizonyítékát. A próba menete:

1. **Mentés** az eredeti koordinátorról: `cp lib/.../celebration_coordinator.dart /tmp/cc-original.dart`.
2. **Mutáció** (sed-del): `if (isActiveSession)` → `if (false)` a 215. soron. Ez a `CelebrationCoordinator.apply` aktív-session-specifikus ágát deaktiválja — az aktív gyakorlás közben bejövő jutalom a továbbiakban az inaktív ágra esik, és batch-be gyűlik, ahonnan a drain summary-t csinál.
3. **Gate futtatás**: a `format` lépés zöld maradt, az **`analyze` lépés PIROS (dead_code warning, `celebration_coordinator.dart:215:16`)** — a gépi elemző maga jelzi, hogy az aktív-session-ág elérhetetlenné vált. Ezzel a lépéssel a gate már itt megáll, de a `flutter test` egyedüli futtatása (ami a §6.1 szövege szerint a „futtasd a gate-et” mércéje) az alábbi A1-cellákat váltotta PIROSRA:
   - `A1: active session routes the reward to the inbox, not a summary` — `Expected: an object with length of <1> · Actual: []`
   - `A1: ten sequential events during an active session all stay in the inbox` — `Expected: an object with length of <10> · Actual: []`
   - `A1: switching from active → inactive during a session starts a fresh batch` — `Expected: an object with length of <1> · Actual: []`
   - `A1 — szigorú megszakítás-mátrix (valódi-sértés próba) A1 real-violation: strict contract — active session produces zero summaries` — `Expected: empty · Actual: [Instance of 'CelebrationSummary']`
   - 3 kaszkád A3/A8/§6.1 fölött+session failure (mert az aktív-session-ág a megszakítás nélküli `pendingBatch` zárást is elbukta).
4. **Visszaállítás**: `cp /tmp/cc-original.dart lib/.../celebration_coordinator.dart` → `if (isActiveSession)` ismét a helyén (215. sor).
5. **Gate újrafuttatás**: `MINDEN GATE ZÖLD`, 18/18 teszt zöld.

A lépéssor a fenti táblázat `A1 megszakítás-mátrix` sorában van dokumentálva — a mutáció NEM maradt a fán (`git status` tiszta, az utolsó commit `63c38abb E08-R22: gate fix — celebration_coordinator closes pending batch when session becomes active; l10n segment regen`).

### Implementált scope (a §4 engedélyezett listán)

- `lib/features/gamification/domain/profile/reward_inbox_item.dart` — domain: `RewardKind`, `RewardEvent`, `RewardInboxItem` (nincs expiry/claim, `seen` csak megjelenítési állapot), `rewardPriorityIndex`, JSON round-trip.
- `lib/features/gamification/application/celebration_coordinator.dart` — application: `CelebrationCoordinator` (caller-fed `isActiveSession`, inkluzív `batchWindow`), `CelebrationState` (immutable, `copyWith`), `CelebrationSummary` (priority-sorted), `RoutedInboxEntry`, `CelebrationSideEffects`, `CelebrationRouting`.
- `lib/features/gamification/presentation/widgets/reward_summary_sheet.dart` — `RewardSummarySheet` + `RewardSummaryFeedback` (caller-fed `hapticsEnabled`/`soundEnabled`); reduced-motion esetén `AnimatedSize(duration: Duration.zero)`, tartalom nem csonkolt.
- `lib/features/gamification/presentation/screens/reward_inbox_screen.dart` — postaláda lista; `seen` flag állítása koppintásra, NINCS „Begyűjtés” gomb, NINCS lejárat.
- `lib/features/gamification/public.dart` — 3 új export-sor (`celebration_coordinator.dart`, `reward_inbox_item.dart`, `reward_summary_sheet.dart`, `reward_inbox_screen.dart`).
- `lib/l10n/app_en.arb` + `lib/l10n/app_hu.arb` — 12 új kulcs (`rewardInboxTitle`, `rewardInboxEmptyTitle/Body`, `rewardInboxSeen/UnseenLabel`, `rewardInboxCountSemantics`, `rewardInboxEarnedXpLabel`, `rewardInboxEntrySemantics`, `rewardSummaryTitle`, `rewardSummaryConsolidatedLabel/Semantics`, `rewardSummaryEntrySemantics`) + magyar párjaik, placeholder-defs a parity-check-hez.
- `test/features/gamification/application/celebration_coordinator_test.dart` — 18 teszt, minden §6/§6.1 cellát fed.

### Szándékosan NEM tettem (a brief „NINCS benne” listája + a §0.0 rögzített brief-rés)

- Nem nyúltam a `RewardLedgerRepository.appendIfAbsent`-hez — az ADR 0389 §1 / §0.0 rögzíti, hogy a koordinátor nem ír a főkönyvbe.
- Nem hoztam létre `Begyűjtés` gombot vagy lejárat-mezőt (ADR 0290 §2 tiltja).
- Nem implementáltam settings providert a haptikához/handhez — caller-fed bool a §0.0 rögzítés szerint (Kör 27-é a wiring).
- Nem módosítottam `docs/adr/0389-…md` — az ADR TILOS ZÓNA, a §0.0 szerinti szöveggel készült.
- Nem bővítettem az `allowed_paths` listát — minden új fájl azon belül van.
- **A JAVÍTÓ KÖRBEN (a §0.0.1 mid-round revízió nyomán):** az előző implementer-futás a 12 új kulcsot a generált `lib/l10n/app_{en,hu}.arb` aggregátumba írta (rossz hely — a `flutter gen-l10n` mindig újraírja, így a kulcsok eltűntek, és az `analyze` 11 undefined-getter hibát dobott a `rewardInbox*`/`rewardSummary*` getterekre). A javító kör a kulcsokat a tényleges FORRÁSBA, a `lib/l10n/features/gamification_{en,hu}.arb` szegmensbe írja, majd a `tool/gen_l10n_segments.dart --write` + `bash tools/prepare-flutter-generated.sh` sorrenddel szinkronizálja az aggregátumot és a generált `app_localizations_*.dart` fájlokat. A §10 „Végső futás” sorában az üzenetszám 1572-ről 1584-re javítva (a +12 a forrás-fragmentumba írt kulcsok száma).

### Reviewer-prioritás

1. A `CelebrationCoordinator.apply` aktív-session-ág: itt érvényesül az A1 megszakítás-mátrix, és itt zárja be az új implementation a korábbi inaktív batch-et (a §6.1 „fölött + közben gyakorlás indult” cella kiszolgálója).
2. A `rewardPriorityIndex` + `_priorityCompare` — az A6 prioritás-mátrix kizárólagos forrása.
3. A `RewardInboxItem` API surface — A4 lejárat/begyűjtés-mentesség; a `toJson` kulcsait lefedi az A4 teszt.
4. A `reward_summary_sheet.dart` reduced-motion ága — A7 statikus render.


## 11. Review — a Claude tölti ki
