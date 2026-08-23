# E09-R05 — Review

Brief: `docs/rounds/e09-r05-flutter-community-domain-and-public-api.md`
Diff: `git diff 770f25cc..8f598c28` (`minimax/e09-r05-flutter-community-domain-and-public-api`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-22
Verdikt: **APPROVED** (javító kör 1 után, `8f598c28`)

## Összegzés

BLOCKER: 0 · MAJOR: 1 (FIXED, `d52a10c5`) · MINOR: 0 · NOTE: 1 (nem blokkoló, nyitva marad follow-upként)

## Javító kör 1 lezárása (2026-08-22, `d52a10c5` + `8f598c28`)

F1 javítva: `moderation_state.dart` most `enum ModerationState` `wireValue`
mezővel + `moderationStateFromWire`/`moderationStateToWire` pár, PONTOSAN a
testvér-dekóderek mintájával (`null`/ismeretlen → `null`, sosem dob). Három
új A3-teszt (`community_domain_test.dart:326-356`: unknown/empty/null →
`null`; minden state roundtrip; a `pendingReview`/`authorOnly` snake_case
wire-alak explicit pin) + a barrel-export-pin lista bővítve
(`'moderationStateFromWire'`, `'moderationStateToWire'`, 533-534. sor). A
`public.dart`-ot NEM kellett módosítani — a meglévő `export
'domain/entities/moderation_state.dart';` sor szűrés nélküli, tehát az új
top-level függvényeket automatikusan újraexportálja.

FÜGGETLENÜL ellenőrizve, friss `/tmp/review-e09-r05-fix1` klónban
(GitHub origin, HEAD `8f598c28`):

- `python3 tools/scope-audit.py --repo ... --base b545ef3b` →
  `Legacy scope audit OK (b545ef3bb19a..8f598c286593, 3 changed path(s), 0
  generated/ignored)` — pontosan a 3 várt fájl (`moderation_state.dart`,
  `community_domain_test.dart`, a brief §10 handoff-kiegészítés).
- `tools/round-gate.sh test/features/community/domain/community_domain_test.dart
  test/core/architecture_dependency_test.dart` → mind a 7 lépés ZÖLD
  (format, analyze, mindkét célzott teszt, architecture, secrets, l10n).

Nincs újabb nyitott BLOCKER/MAJOR. N1 (a `gate_shape` regex-őr hamis
pozitívja) informatív follow-up marad, nem blokkol.

Erős, tartalmilag fegyelmezett kör: a §0.0 D3-tisztázást (audience.dart NEM
duplikálja a Kör 4 enumokat) az implementer pontosan követte és SAJÁT
teszttel is kipinnelte (`community_domain_test.dart:433`); az A4 cellánál a
brief §0.0 által idézett L349-lecke (initial ≠ halted cursor) explicit
type-state-ként (`CursorPage.initial`/`.continued`/`.haltedAfterRequest`)
került beépítésre, doc-kommentben hivatkozva a lecke számára. A §6
"valódi-sértés próba" a briefben előírt módon (import `package:flutter/
foundation.dart` → A1 piros → visszaállítás) dokumentálva és FÜGGETLENÜL
reprodukálva (lásd lent). Az egyetlen MAJOR egy tartalmi következetlenség a
saját, hét testvér-enumon bizonyítottan alkalmazott A3-mintában.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | A domain nem importál Fluttert, Dio-t vagy SharedPreferences-t | ✅ | `architecture_dependency_test.dart` `'community domain stays framework-free (E09-R05)'` csoport; valódi-sértés próba FÜGGETLENÜL reprodukálva (lásd Gate-bizonyíték) |
| A2 | Minden value object immutable és validált | ✅ | `community_domain_test.dart:35-243` (`PublicUserId`/`ContentId`/`CommunityHandle`/`CommunityPost`/`CommunityComment`/`CommunityChallengeDefinition`/`CommunityClub` — üres/túl hosszú/negatív/rossz-alakú bemenetek elutasítva) |
| A3 | Minden wire enum ismeretlen értéket kontrolláltan kezel | ❌ | 7 új wire-enumból 6-nak van tesztelt `xFromWire` dekódere (`ProfileVisibility`, `CommunityAudience`, `ReactionKind`, `ChallengeType`, `ChallengeInviteState`, `CommunityNotificationKind`, `ClubVisibility`) — **`ModerationState`-nek NINCS.** Ld. F1. |
| A4 | A cursor page opaque | ✅ | `community_domain_test.dart:340-382`; `cursor_page.dart` explicit `initial`/`continued`/`haltedAfterRequest` type-state (L349-fix) |
| A5 | A feature EGYETLEN `public.dart`-ból importálható | ✅ | `architecture_dependency_test.dart` cross-feature-import szabály (generikus, minden `lib/features/*`-ra fut) + `community_domain_test.dart:459` barrel-felület pin |
| A6 | Más feature ma nem importálja a Communityt, és a Community sem importál más feature-t | ✅ | ugyanaz a generikus cross-feature-import guard; `grep -rln "features/community" lib/features --include=*.dart | grep -v ^lib/features/community` üres |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e09-r05 --brief docs/rounds/e09-r05-flutter-community-domain-and-public-api.md --base 770f25cc402e262b1b1de95f13e47220b099e3ad`
→ **`Legacy scope audit OK (770f25cc402e..34554566721c, 25 changed path(s), 0 generated/ignored)`**

`git diff --stat 770f25cc..34554566` — 25 fájl, mind az `allowed_paths`
tételes listáján (a hét entitás, öt value object, hét repository-interfész,
`public.dart`, a két teszt fájl, a §10 handoff). Engedélyezett fájlokon
kívüli változás: **nincs**.

## Megállapítások

### F1 — MAJOR — `ModerationState` kimarad az A3 wire-enum unknown-handling mintából

- **Fájl:** `lib/features/community/domain/entities/moderation_state.dart:10`
- **Probléma:** `enum ModerationState { visible, limited, pendingReview, removed, authorOnly }`
  — plain Dart enum, dekóder/wire-bridge függvény NÉLKÜL. A fájl saját
  doc-kommentje (1-7. sor) kifejezetten wire/backend-authoritative jelként
  írja le ("a backend read-path uses to return placeholder or tombstone
  rows"), a `community_post.dart:6` és `community_comment.dart:23`
  ugyanígy hivatkozza. Eközben a kör MINDEN MÁS, hasonló természetű
  wire-enumja (`ReactionKind`, `ChallengeType`, `ChallengeInviteState`,
  `CommunityNotificationKind`, `ClubVisibility`, plusz az újrahasznosított
  `ProfileVisibility`/`CommunityAudience`) kapott egy `xFromWire(String?)
  -> X?` dekódert, ami `null`-t ad ismeretlen stringre kivétel helyett —
  ezt a `community_domain_test.dart` `'wire enum handling (A3)'` csoportja
  (239-330. sor) mind a hat esetre teszteli. `ModerationState`-re SEM
  dekóder, SEM teszt nincs — `grep -rn "moderationStateFromWire" lib/ test/`
  nulla találat.
- **Hatás:** az A3 acceptance criterion szó szerint "MINDEN wire enum"-ot
  ír elő, kivétel nélkül — ez tartalmi hiány, amit a jelenlegi zöld gate NEM
  fog meg (a `community_domain_test.dart` egyszerűen nem próbálja
  dekódolni a `ModerationState`-et ismeretlen inputból, mert nincs mit
  hívnia). Kör 6-tól, amikor a data-réteg éles JSON-t dekódol egy
  ismeretlen/jövőbeli moderation-státuszra (pl. a backend egy hetedik
  állapotot vezet be egy jövőbeli körben), nincs kontrollált fallback-pont
  — vagy egy `.byName`/`switch`-throw-os ad-hoc megoldás születik ott, épp
  az a minta, amit ez a kör A3-ként kizárni hivatott.
- **Kötelező javítás:** adj egy `moderationStateFromWire(String? wire) ->
  ModerationState?` (és szimmetria kedvéért `moderationStateToWire`) függvényt
  — ugyanabban a fájlban vagy egy hozzá tartozó helyen, a többi
  `xFromWire`-lel egyező mintával (sosem dob, `null` = ismeretlen) —, exportáld
  a `public.dart`-ból, és vedd fel a `community_domain_test.dart` A3
  csoportjába (unknown → `null`, `null` input → `null`, minden érvényes
  érték roundtrip).
- **Ellenőrzés:** `tools/round-gate.sh test/features/community/domain/community_domain_test.dart test/core/architecture_dependency_test.dart` — az új teszt zöld, a barrel-export-pin teszt (459. sor) tartalmazza a `moderationStateFromWire` nevet.
- **Státusz:** FIXED (`d52a10c5`) — ld. "Javító kör 1 lezárása" fent

### N1 — NOTE — a `gate_shape=VIOLATION` jelzés HAMIS POZITÍV, nem valódi csővezetékes gate-futtatás

- **Fájl:** `.codex-round-status` (az implementer munkapéldányában), a
  `tools/mm-round.sh` anti-hallucináció regex-őre
  (`round-gate\.sh[^\n]*(\| *(tail|head)|&&)`).
- **Megfigyelés:** a `/tmp/mm-e09-r05.log` teljes JSONL-jét gépi elemezve
  (minden Bash `tool_use` parancs, ami tartalmazza a `round-gate` szót) az
  ÖT találatból NÉGY a tényleges gate-hívás, egyenként önálló, csővezeték
  és `&&` NÉLKÜL (`ROUND_GATE_SLEEP_SECONDS=0 tools/round-gate.sh <utak>
  2>&1`); az ÖTÖDIK egy forráskód-ELOLVASÁS
  (`cat tools/round-gate.sh | head -100`), amiben a `round-gate.sh` szöveg
  ÉS egy `| head` UGYANABBAN a sorban szerepel, csak nem gate-futtatásként,
  hanem a script tartalmának megtekintéseként. A regex-őr erre a
  kombinációra is tüzel, mert csak a két minta EGYÜTT-előfordulását nézi a
  sorban, a szemantikát nem. Független `/tmp` klónban lefuttatott gate
  (lásd lent) MINDEN lépésben zöld, ami megerősíti, hogy a jelentett
  eredmény hiteles, nem egy elrejtett kilépési kódú, csonkolt kimenet.
- **Hatás:** nem blokkol — dokumentálva, hogy a jövőbeli review-k ne
  ijedjenek meg ugyanettől a mintától, és hogy a mm-round.sh regex-őr
  finomítása (a `cat`/`less`/`sed -n` jellegű OLVASÓ parancsok kizárása a
  mintából) egy jövőbeli tooling-kör follow-up jelöltje.
- **Státusz:** OPEN (follow-up, nem blokkoló)

## Gate-bizonyíték ellenőrzése

Minden az implementer állítására FÜGGETLENÜL, saját kézzel, izolált
`/tmp/review-e09-r05` klónban (GitHub origin `minimax/e09-r05-flutter-
community-domain-and-public-api`, HEAD `34554566`), csővezeték/lánc nélkül:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (`dart format --output=none --set-exit-if-changed` → 0 changed) |
| analyze | zöld | ✅ (`flutter analyze lib/ test/ tool/` → No issues found) |
| test `community_domain_test.dart` | zöld, 41 teszt | ✅ (All tests passed!) |
| test `architecture_dependency_test.dart` | zöld, 44 teszt | ✅ (All tests passed!) |
| architecture / secrets / l10n | zöld | ✅ (gate-összegzés: MINDEN GATE ZÖLD) |
| scope-audit | OK, 25 fájl, 0 generated/ignored | ✅ (`tools/scope-audit.py` önálló futtatással) |
| valódi-sértés próba (A1) | PIROS→ZÖLD | ✅ FÜGGETLENÜL reprodukálva: `@immutable` + `import 'package:flutter/foundation.dart'` a `community_profile.dart`-ba → `architecture_dependency_test.dart` PIROS (kilépési kód 1, a SAJÁT domain-purity csoport bukik, nem csak a `flutter analyze` unused-import lintje) → visszaállítás után újra teljes zöld gate |
| CI (teljes suite + property + APK) | — | Claude-oldali dispatch a review APPROVED után, `round-ci-plan.py` szerint |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge. F1 javítva és FÜGGETLENÜL ellenőrizve (`8f598c28`), nincs más nyitott
BLOCKER/MAJOR. **A review APPROVED — a CI-dispatch és a merge mehet.**
