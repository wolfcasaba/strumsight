# E13-R34 — Community challenges, clubs, notifications és safety UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 34
- **Kör-azonosító:** `E13-R34`
- **Branch:** `<motor>/e13-r34-community-challenges-and-safety`
- **Előfeltétel:** `E13-R33` merge-elve (közösségi feed és posztok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0291 (opcionális, alapból privát) érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES kihívás- és
> moderációs szerződéseket, kiemelten a „függő" (pending) vs. „ellenőrzött"
> (verified) állapotot — a §5.2 cella erre a mért megkülönböztetésre épül.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/challenges/",
  "lib/features/community/clubs/",
  "lib/features/community/safety/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/community/challenge_join_test.dart",
  "test/features/community/leaderboard_optin_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/features/community/notification_deeplink_test.dart",
  "docs/rounds/e13-r34-community-challenges-and-safety.md",
]
gate_tests = [
  "test/features/community/challenge_join_test.dart",
  "test/features/community/leaderboard_optin_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/features/community/notification_deeplink_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-59–UI-61 kihívás-, ranglista-, klub-, értesítés- és biztonsági felületei
(SDD Ch13 Kör 34).

## 2. Jelenlegi állapot — mért tények

- Az R33 lefektette az opcionális, alapból privát közösségi alapot — ez a kör
  ugyanezt viszi tovább a versengő felületekre.
- A kihívás-eredmény **függő** és **ellenőrzött** állapota két különböző dolog.
- A privát klub tartalma a legkönnyebben szivárgó adat (előnézet, értesítés,
  mély hivatkozás).

## 3. Scope

**Benne van:** a kihívás listája és részletnézete, csatlakozás-megerősítés,
ellenőrzés és ranglista · a klubok nyilvános / privát / csatlakozási kérelem /
tag / moderátor / archivált állapotai · az értesítések és a Biztonsági központ
lista-részlet felülete · tiltott/némított lista, bejelentés-státusz és
értesítés-beállítások · **semleges** microcopy az integritás-vizsgálathoz ·
lapozás, offline gyorsítótár, mély hivatkozás validálása és jogosultsági
tesztek.

**NINCS benne (tilos):** a moderációs vagy anti-cheat logika módosítása · a
ranglista alapértelmezett bekapcsolása · más képernyők · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `community/challenges/` | kihívás és ranglista |
| `community/clubs/` | klubok |
| `community/safety/` | értesítések és biztonsági központ |
| `lib/l10n/app_{en,hu}.arb` | a szövegek |
| `test/features/community/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r34-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/community/` a három érintett almappán kívül ·
`lib/features/**` egyébként · `lib/core/design_system/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A ranglista OPT-IN

A felhasználó nem kerül rá automatikusan azzal, hogy gyakorol. A versengés
választás, nem alapállapot (az ADR 0291 §2 kiterjesztése).

**NEM elfogadható gyengítés:** automatikus felvétel a ranglistára a kihíváshoz
csatlakozáskor. A csatlakozás nem egyenlő a nyilvános rangsorolás vállalásával.

### 5.2 A függő bejegyzés NEM ellenőrzött

A két állapot vizuálisan és szövegesen is elkülönül. Az ellenőrizetlen eredmény
nem jelenik meg véglegesként.

### 5.3 A privát klub tartalma NEM szivárog

Sem előnézetben, sem értesítésben, sem mély hivatkozáson át. Ez
acceptance-cella (A3), és a kör legfontosabb invariánsa.

**NEM elfogadható gyengítés:** „a cím megjelenítése ártalmatlan az
értesítésben". A cím maga is tartalom.

### 5.4 A mély hivatkozás VALIDÁLT

Az értesítésből érkező link jogosultság-ellenőrzésen megy át, mielőtt bármit
megjelenítene. Nem megbízható bemenet.

### 5.5 Az integritás-vizsgálat microcopyja SEMLEGES

A vizsgálat alatt álló eredmény nem vádol csalással. A semleges szöveg tényt
közöl, nem ítéletet.

### 5.6 A biztonsági akció ELÉRHETŐ, nem elrejtett

Bejelentés, tiltás és némítás minden releváns felületről elérhető, nem csak a
beállításokból.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A ranglistára kerülés opt-in, csatlakozásból nem következik | `leaderboard_optin_test.dart` |
| A2 | A függő bejegyzés vizuálisan és szövegesen elkülönül az ellenőrzöttől | `challenge_join_test.dart` |
| A3 | A privát klub tartalma nem szivárog (előnézet, értesítés, mély link) | `private_club_leakage_test.dart` |
| A4 | A mély hivatkozás jogosultság-ellenőrzésen megy át | `notification_deeplink_test.dart` |
| A5 | Az integritás-vizsgálat szövege semleges (en + hu) | `challenge_join_test.dart` |
| A6 | A biztonsági akciók a releváns felületekről elérhetők | `private_club_leakage_test.dart` |
| A7 | A ranglista lapozása stabil, nem duplikál és nem hagy ki | `leaderboard_optin_test.dart` |
| A8 | A tiltás/némítás állapota a felületek között egységes | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A csatlakozás automatikusan ranglistára tesz | **A1** |
| A függő eredmény véglegesként | **A2** |
| A privát klub címe az értesítésben | **A3** |
| A mély link ellenőrzés nélkül nyit tartalmat | **A4** |
| „Csalás gyanúja" szöveg a vizsgálatnál | A5 |
| A lapozás ismétli az utolsó elemet | A7 |

**A klub-láthatóság három kötelező cellája** (a küszöb: a felhasználó tagsága):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nem tag, privát klub | **semmilyen tartalom** — csak a létezés és a csatlakozási út |
| rajta (a küszöbön) | **függő csatlakozási kérelem** | továbbra sincs tartalom — a kérelem állapota látszik |
| a küszöb fölött | elfogadott tag | teljes tartalom |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jelenítsd meg a privát
klub címét egy értesítésben nem tagnak → az **A3** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/challenge_join_test.dart test/features/community/leaderboard_optin_test.dart test/features/community/private_club_leakage_test.dart test/features/community/notification_deeplink_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör jogosultsági határt és nyilvános adatot
> érint, ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A kihívás listája és részletnézete, csatlakozás-megerősítéssel.
2. A ranglista opt-in kapcsolója + a lapozás stabilitása.
3. A függő/ellenőrzött megkülönböztetés és a semleges vizsgálat-szöveg.
4. A klub-állapotok + a három láthatósági cella.
5. Az értesítések és a mély hivatkozás jogosultság-ellenőrzése.
6. A Biztonsági központ: tiltott/némított lista, bejelentés-státusz.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A privát klub szivárgása.** Több csatornán is előfordulhat (előnézet,
  értesítés, mély link), és mindegyiket külön kell zárni (A3).
- **Az automatikus ranglista.** Kényelmesnek látszik, és nyilvános
  összehasonlításba kényszeríti a felhasználót (A1).
- **A vádaskodó vizsgálat-szöveg.** Ártatlan felhasználót bélyegez meg egy
  automatikus jelzés miatt (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
