# E09-R05 — Flutter Community domain és public API

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 5
- **Kör-azonosító:** `E09-R05`
- **Branch:** `<motor>/e09-r05-flutter-community-domain-and-public-api`
- **Előfeltétel:** `E09-R04` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0399` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `tool/check_architecture.dart` `_isSharedDomain()` hardcode-olt listáját — a `lib/features/community/domain/` NINCS rajta (ugyanaz a mért hiányosság, mint E08-R02-ben), ezért a domain-purity guard a bevált, önálló teszt-csoportos mintát követi, nem a checker bővítését. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/domain/entities/community_profile.dart",
  "lib/features/community/domain/entities/community_post.dart",
  "lib/features/community/domain/entities/community_comment.dart",
  "lib/features/community/domain/entities/community_reaction.dart",
  "lib/features/community/domain/entities/community_challenge.dart",
  "lib/features/community/domain/entities/community_club.dart",
  "lib/features/community/domain/entities/notification_item.dart",
  "lib/features/community/domain/entities/moderation_state.dart",
  "lib/features/community/domain/value_objects/public_user_id.dart",
  "lib/features/community/domain/value_objects/community_handle.dart",
  "lib/features/community/domain/value_objects/audience.dart",
  "lib/features/community/domain/value_objects/cursor_page.dart",
  "lib/features/community/domain/value_objects/content_id.dart",
  "lib/features/community/domain/repositories/",
  "lib/features/community/public.dart",
  "test/features/community/domain/community_domain_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e09-r05-flutter-community-domain-and-public-api.md",
]
gate_tests = [
  "test/features/community/domain/community_domain_test.dart",
  "test/core/architecture_dependency_test.dart"
]
native_gate = false
```

> **Kockázat = high, indoklás:** a `public.dart` a Community feature
> KIZÁRÓLAGOS belépője — a Kör 6-tól épülő `data/`/`presentation/` réteg és
> minden jövőbeli fogyasztó erre a felületre köt, tehát egy itt elkövetett
> hiba (hiányzó export, rossz típusalak, `CommunityAudience` duplikálása a
> már létező Kör 4 policy-enum mellett) sok jövőbeli kört érintene. A
> `docs/adr/0399` és a domain-purity guard ezt a felületet rögzíti.

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-22, `main @ e77e9b06`)

**S7 (brief-lint):** a fenti `**Kockázat = high, indoklás:**` sor pótolva.

**S8 (brief-lint) — visszakeresés:**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "Flutter
community domain public API value objects entities"` és `--corpus
lessons,halts --top 5 "wire enum unknown value handling cursor page opaque
value object"` (majd kiegészítésként a teljes korpuszon). Találatok:
ADR 0057 (shared-domain `public.dart` konvenció, `package:meta` kontra
Flutter `@immutable` kérdés — ld. lent D1), ADR 0339 (generált-barrel
registry, pilot: `practice_generator` — ld. lent D2). **Nincs közvetlenül
alkalmazandó lecke** a cursor/enum témára (L349 egy KÖVETKEZŐ kör — Kör 6+,
a repository-fogyasztó lapozó hurokja — kockázata, ide csak annyiban tartozik,
hogy a `CursorPage` value objectnek A4 szerint **nem szabad** a kezdő,
üres-oldal `cursor == null` állapotot és a "lapozás elakadt" hibát ugyanazzal
az alakkal jelölnie — ezt a döntést a `CursorPage` API-ja explicit
kell hordozza, nem a jövőbeli fogyasztóra hárítva).

**D1 — nincs változás:** a §5.1 (`final` mezők + `const` konstruktor, se
Flutter, se `package:meta` `@immutable`) mérve helyes — a Gamification
domain (E08-R02) sem használ `@immutable`-t egyáltalán, tehát a bevett
minta a teljes hiány, nem a `package:meta`-s csere. Lásd `docs/adr/0399`
1. döntés.

**D2 — nincs változás, csak megerősítés:** a `public.dart` ebben a körben
KÉZZEL ÍRT, hagyományos barrel — a `tool/gen_public_barrel.dart` +
`docs/adr/0339` generált-barrel regisztrációja jelenleg EGYETLEN pilot
bejegyzést tartalmaz (`practice_generator`), és az ADR kifejezetten
kimondja: "a nem regisztrált feature gyökér `public.dart` továbbra is teljes
ütközési felület." A Community generált-barrel migrációja NEM ennek a
körnek a tárgya. Lásd `docs/adr/0399` 3. döntés.

**D3 — ÚJ tisztázás (a brief eredeti szövege nem tért ki rá):**
`lib/features/community/domain/policies/community_audience.dart` (Kör 4)
MÁR definiálja a `ProfileVisibility`/`CommunityAudience` wire-enumokat
(3 érték: `public`/`followers`/`private`). Ez a fájl **nincs** ezen a
körön az `allowed_paths`-on — szerkesztése tilos zóna, de OLVASÁSA
(import) nem `allowed_paths`-sértés. A SDD Ch10 §9.1 egy korábbi,
4-értékű vázlatot mutat (`onlyMe, followers, club, public`) — ez ADR
0398-cal FELÜLÍRÓDOTT (a club-domain Kör 24-re halasztva,
`is_club_member` ma `False`-default, fenntartott mező). A Kör 5
`domain/value_objects/audience.dart` fájlja **nem definiálhat új
`CommunityAudience`-t vagy `ProfileVisibility`-t, és nem árnyékolhatja**
a Kör 4 típusait — importálja őket. A value object feladata: kontrollált,
sosem dobó dekódolás ismeretlen wire-stringre (A3 — a Kör 4 fájl saját
doc-kommentje szerint a JSON-kötés "egy jövőbeli körben" landol; ez a
felelősség itt landol, nem a policy fájlban), és stabil, `public.dart`-on
át exportálható típusfelület a Kör 5 entitásoknak (poszt/komment audience
mezője). Részletek: `docs/adr/0399` 4. döntés.

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

Hozd létre a Flutter-oldali, framework-független Community domaint és a stabil feature boundaryt. Ez a kör NEM ad hálózati implementációt vagy teljes UI-t — csak típusokat és repository-interfészeket.

## 2. Jelenlegi állapot — mért tények

- `lib/features/community/` **nem létezik** a Flutter oldalon (a Kör 2-4 kizárólag backend munka volt)
- `lib/features/community/domain/policies/community_audience.dart` (Kör 4) MÁR LÉTEZIK — ez a kör a köré építi a teljes domain-fát
- `test/core/architecture_dependency_test.dart` a bevált E07-R02/E08-R02 mintát hordozza: önálló, feature-gyökeret közvetlenül beolvasó teszt-csoport a domain-purity mérésére (nem a checker bővítése)
- a projekt konvenciója: 21+ feature mind EGY `public.dart` barrelen át importálható

## 3. Scope

**Benne van:** a Chapter 10 §7.1 mappastruktúra (`domain/{entities,value_objects,repositories,policies}`) · public ID, handle, audience, profile summary, relationship és cursor page value object · repository interfészek: profile, social graph, feed, post, challenge, club, notification · immutable state, explicit `copyWith`/equality · `public.dart` barrel kizárólag stabil típusokkal · architektúra-guard bejegyzés az önálló teszt-csoport mintájával.

**NINCS benne (tilos):**

- Hálózati (Dio) implementáció — Kör 6-tól kezdve, repositoryként.
- Bármely UI/widget/screen — Kör 6-tól.
- Más feature importálása (a Community még senkinek nem fogyasztója és nem is fogyasztja őket).
- `docs/adr/**` — az ADR 0399-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/domain/entities/community_profile.dart` | ÚJ |
| `lib/features/community/domain/entities/community_post.dart` | ÚJ |
| `lib/features/community/domain/entities/community_comment.dart` | ÚJ |
| `lib/features/community/domain/entities/community_reaction.dart` | ÚJ |
| `lib/features/community/domain/entities/community_challenge.dart` | ÚJ |
| `lib/features/community/domain/entities/community_club.dart` | ÚJ |
| `lib/features/community/domain/entities/notification_item.dart` | ÚJ |
| `lib/features/community/domain/entities/moderation_state.dart` | ÚJ |
| `lib/features/community/domain/value_objects/public_user_id.dart` | ÚJ |
| `lib/features/community/domain/value_objects/community_handle.dart` | ÚJ |
| `lib/features/community/domain/value_objects/audience.dart` | ÚJ |
| `lib/features/community/domain/value_objects/cursor_page.dart` | ÚJ |
| `lib/features/community/domain/value_objects/content_id.dart` | ÚJ |
| `lib/features/community/domain/repositories/` | ÚJ — a hét repository-interfész |
| `lib/features/community/public.dart` | ÚJ — az EGYETLEN belépő |
| `test/features/community/domain/community_domain_test.dart` | ÚJ — a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az új feature-gyökér határa |

**Tilos zóna:** `lib/features/` MINDEN más feature-je · `lib/features/community/application/**` · `lib/features/community/data/**` · `lib/features/community/presentation/**` (ezek Kör 6-tól) · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0399)

### 5.1 A domain TISZTA Dart — nincs Flutter, Riverpod, storage vagy Dio import

A Kör 5 domain-fája framework-független, teljesen unit-tesztelhető, mert erre épül a Kör 6-tól minden repository-implementáció.

**NEM elfogadható gyengítés:** `package:flutter/foundation.dart` behúzása `@immutable` kedvéért — az immutabilitást `final` mezők és `const` konstruktor adja, ugyanaz a minta, mint a Gamification domainben (E08-R02).

### 5.2 Domain-purity guard önálló teszt-csoporttal, NEM a checker bővítésével

`tool/check_architecture.dart` NINCS az `allowed_paths` listán, ezért a `lib/features/community/domain/` framework-mentességét a bevált E07-R02/E08-R02 mintát követve, `architecture_dependency_test.dart` önálló csoportjával mérjük — a cross-feature-import szabály (A7-ekvivalens) viszont automatikus, mert generikusan fut minden `lib/features/*` fára.

### 5.3 EGY belépő: `public.dart`

A Community kizárólag a `public.dart`-on át importálható. Ez a 21+ meglévő feature konvenciója, és a Kör 6-tól kezdve minden fogyasztó erre a felületre épít.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A domain nem importál Fluttert, Dio-t vagy SharedPreferences-t | `architecture_dependency_test.dart` |
| A2 | Minden value object immutable és validált (üres handle, negatív cursor stb. elutasítva) | `community_domain_test.dart` |
| A3 | Minden wire enum ismeretlen értéket kontrolláltan kezel | `community_domain_test.dart` |
| A4 | A cursor page opaque (a kliens nem értelmezi a belső tartalmát) | `community_domain_test.dart` |
| A5 | A feature EGYETLEN `public.dart`-ból importálható | `architecture_dependency_test.dart` |
| A6 | Más feature ma nem importálja a Communityt, és a Community sem importál más feature-t | `architecture_dependency_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `package:flutter/foundation.dart` importálva `@immutable` miatt | A1 |
| Egy value object mezői utólag írhatók (nincs `final`) | A2 |
| Egy ismeretlen wire-enum érték kivételt dob dekódoláskor ahelyett, hogy kontrolláltan `unknown` ágra futna | A3 |
| A cursor egy nyers, kliens által értelmezhető JSON objektum | A4 |
| Egy belső fájl közvetlenül importálható a barrel megkerülésével | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** importálj `package:flutter/foundation.dart`-ot a `community_profile.dart`-ba egy `@immutable` annotációhoz, futtasd a gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/domain/community_domain_test.dart test/core/architecture_dependency_test.dart
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

1. A value objectek (`public_user_id`, `community_handle`, `audience`, `cursor_page`, `content_id`).
2. Az entitások (`community_profile`, `..._post`, `..._comment`, `..._reaction`, `..._challenge`, `..._club`, `notification_item`, `moderation_state`).
3. A hét repository-interfész (`domain/repositories/`).
4. `public.dart` — az egyetlen belépő.
5. Az architektúra-guard bejegyzése az E07-R02/E08-R02 mintával (önálló teszt-csoport).
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `flutter/foundation.dart` behúzása.** Egyetlen `@immutable` kedvéért, és a domain tesztelhetősége/újrafelhasználhatósága elvész (A1).
- **A checker bővítésének kísértése.** `tool/check_architecture.dart` NINCS ezen a listán — a bővítés elérhetetlen cél ebben a körben (§0.0 mérés kötelező a pre-flightban, mint E08-R02-ben).
- **A hét entitás "majd később" hozzáadása.** A `public.dart` barrel Kör 6-tól fix felület — az utólagos bővítés minden fogyasztót érint.

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Fájlonkénti összegzés

A Kör 5 minden engedélyezett fájlja új (Kör 5 hozta létre), kivéve a
`test/core/architecture_dependency_test.dart` bővítését.

#### Value objectek (`lib/features/community/domain/value_objects/`)

- **`public_user_id.dart`** — `final class PublicUserId` opac string,
  factory validáció (`isEmpty`, hossz ≤ 128, `@`-tiltás az e-mail-shape
  ellen), `==` + `hashCode`.
- **`community_handle.dart`** — `final class CommunityHandle`,
  NFKC/casefold helyett `.trim().toLowerCase()` (structural pre-check
  only — a backend `handle_policy.normalize` a kanonikus forrás),
  explicit `^[\w][\w\-]{1,22}[\w]$|^[\w]$` regex a Kör 3 backend
  mintájára, equality a normalizált alakon.
- **`audience.dart`** — NEM redefiniálja a Kör 4 wire-enumokat (D3, ADR
  0399 4. döntés), importálja a `policies/community_audience.dart`-ot,
  és adja a `profileVisibilityFromWire`, `communityAudienceFromWire`,
  `profileVisibilityToWire`, `communityAudienceToWire` hidakat
  (sosem dobók — null az ismeretlenre, A3).
- **`cursor_page.dart`** — `final class CursorPage` opac, három
  explicit állapottal: `CursorPage.initial()`, `CursorPage.continued(String)`
  és `CursorPage.haltedAfterRequest()`. A `null` cursor-t megkülönbözteti
  a soha-nem-lapozott és a leállt esetek közt (L349 footprint fix).
- **`content_id.dart`** — `final class ContentId` post/comment/
  artifact-azonosítókhoz, factory-validáció.

#### Entitások (`lib/features/community/domain/entities/`)

- **`community_profile.dart`** — `final class CommunityProfile` +
  `enum CommunityRelationshipToViewer` (8 állapot, lefedi a `blockedBy`
  tükör-esetet is). Factory-validáció: `displayName` 1–40, `bio` ≤
  500, `skillInterests` ≤ 16, `badges` ≤ 32.
- **`community_post.dart`** — `CommunityPost` + `CommunityPostCounts`
  + `CommunityViewerPostState` + abstract `CommunityShareArtifact` +
  `UnfilledCommunityShareArtifact` placeholder (Kör 10-re vár a
  konkrét altípusokra). Body cap 2000, editedAt ≥ createdAt, count
  non-negative.
- **`community_comment.dart`** — `final class CommunityComment`,
  factory-validáció (test ≤ 1000, editedAt ≥ createdAt, opcionális
  `parentCommentId` + `deletedAt` soft-delete).
- **`community_reaction.dart`** — `enum ReactionKind` (support /
  celebrate / inspiring / helpful — SDD §14.1 allowlist),
  `reactionKindFromWire` (null ismeretlenre, A3), és
  `CommunityReaction.fromWire` factory.
- **`community_challenge.dart`** — `CommunityChallengeDefinition` +
  `CommunityChallengeParticipantState` + `ChallengeType` /
  `ChallengeInviteState` enumok és fromWire dekóderek.
- **`community_club.dart`** — `enum ClubVisibility` /
  `enum ClubRole` + `final class CommunityClub` (name 1–60,
  description ≤ 2000, tags ≤ 10 (1–24 char/db), memberCount
  ≥ 1, ≤ 500).
- **`notification_item.dart`** — `enum CommunityNotificationKind`
  (10 típus) + `final class CommunityNotificationItem` (titleKey /
  bodyKey ARB lowerCamelCase-regex ellenőrzés).
- **`moderation_state.dart`** — `enum ModerationState` (visible /
  limited / pendingReview / removed / authorOnly).

#### Repository interfészek (`lib/features/community/domain/repositories/`)

- **`community_page.dart`** — `final class CommunityPage<T>` generic
  envelope, items + opaque cursor. Az `isHaltedAfterRequest` helper a
  `CursorPage.haltedAfterRequest()`-típust mutatja.
- **`community_profile_repository.dart`** — 4 metódus: `fetchMyProfile`,
  `fetchById`, `fetchByHandle`, `searchProfiles` (cursor-paged).
- **`social_graph_repository.dart`** — 11 metódus (following/followers
  page, follow/unfollow/remove-follower/accept/decline, block/unblock,
  mute/unmute), mind idempotency-key paraméteres.
- **`feed_repository.dart`** — 3 paged metódus: `followingFeed`,
  `profilePosts`, `clubPinned` (utóbbi Kör 24-ig `UnsupportedError`).
- **`post_repository.dart`** — 10 metódus: `createPost`, `fetchPost`,
  `updatePost`, `deletePost`, `setReaction`, `setBookmark`, `comments`,
  `createComment`, `updateComment`, `deleteComment`.
- **`challenge_repository.dart`** — 9 metódus: `listChallenges`,
  `fetchDefinition`, `fetchMyParticipation`, `invite`/`acceptInvite`/
  `declineInvite`/`cancelInvite`, `submitResult`, `leaderboard`.
- **`club_repository.dart`** — 10 metódus: `listClubs`, `fetchClub`,
  `createClub`, `updateClub`, `requestJoin`, `invite`, `leave`,
  `removeMember`, `transferOwnership`.
- **`notification_repository.dart`** — 5 metódus: `inboxPage`,
  `markRead`, `markAllReadUpTo`, `preferences`, `updatePreference`.

#### Public API

- **`lib/features/community/public.dart`** — kézzel írt barrel
  (ADR 0399 3. döntés — `tool/gen_public_barrel.dart` registry-t nem
  bővítettük). 17 export-sor: a Kör 4 wire-enum policy, mind az 5
  value object, mind a 8 entitás, mind a 7 repository interfész, és
  a `CommunityPage` envelope.

#### Architecture guard bővítés (`test/core/architecture_dependency_test.dart`)

Három új `group` a meglévő E07-R02 / E08-R02 mintára:

- **`'community domain stays framework-free (E09-R05)'`** — rekurzív
  scan a `lib/features/community/domain/` fán, ugyanaz a
  `_withoutTrivia`-alapú szűrő, ami a gamification csoportot védi
  (A1).
- **`'community is reachable only through public.dart (E09-R05)'`** —
  `lib/` rekurzív scan, ahol minden NEM-`features/community/` fájl
  community-importját nézi, és a `community/public.dart` barrel-t
  kivéve mindent jelöl (A5). Az elfogadás és az elutasítás is benne
  van explicit unit-teszttel.
- **`'community does not import other features (E09-R05)'`** —
  `lib/features/community/` rekurzív scan, minden más feature
  belső importját jelöli (A6).

A meglévő generikus `_forbiddenGamificationInternalImports` /
`_isCrossFeatureInternalImport` segédfüggvények kiegészülnek a
`_forbiddenCommunityDomainMarkerOffenders`,
`_forbiddenCommunityInternalImports` és
`_forbiddenCommunityOtherFeatureImports` függvényekkel.

#### Domain tests (`test/features/community/domain/community_domain_test.dart`)

6 `group`, 41 `test` (mind a 41-re kiterjedő lefedettség):

- **A2 — value object validation (17 eset)**: üres/e-mail/id/handle
  elutasítás, hossz-sértések, separator-alsó/felső, post/comments/
  notification/challenge/club factory-túlcsordulások.
- **A3 — wire enum handling (12 eset)**: 7 wire-enum
  (`ReactionKind`, `ProfileVisibility`, `CommunityAudience`,
  `ChallengeInviteState`, `ChallengeType`,
  `CommunityNotificationKind`, `ClubVisibility`) mind null-t ad
  ismeretlenre; round-trip-pozitív esetek; a `CommunityReaction
  .fromWire` a mérce-mátrix egyenes cellája (null ismeretlenre).
- **A4 — cursor page opacity (7 eset)**: a három explicit állapot,
  az initial-vs-halted disztinkció fennmarad equality-n (az L349 fix),
  `CommunityPage<T>.isHaltedAfterRequest` helper.
- **D3 — audience wire contract (3 eset)**: `wireValue` byte-identity
  a Kör 4 felé, és a 3-értékűség pin-jét (nincs `club` audience — a
  4-értékű vázlat felülírva ADR 0398-cal).
- **A5 + A6 — public.dart barrel surface (2 eset)**: a barrelből
  re-exportált szimbólumok neve, és egy működő konstrukció a
  barrel-en át.

### 10.2 Acceptance pontok — tényleges futtatott bizonyíték

A gate parancs (`tools/round-gate.sh test/features/community/domain/community_domain_test.dart test/core/architecture_dependency_test.dart`) a §10.4-ben látható, minden lépés zöld.

| # | Cell | Bizonyíték |
|---|---|---|
| **A1** | A domain nem importál Fluttert, Dio-t vagy SharedPreferences-t | `community domain stays framework-free (E09-R05)` group, `flutter test test/core/architecture_dependency_test.dart --plain-name 'community domain stays framework-free'` ZÖLD (3/3) |
| **A2** | Minden value object immutable és validált | 17 eset a `value object validation (A2)` group-ban, `flutter test community_domain_test.dart` ZÖLD (17/17) |
| **A3** | Minden wire enum ismeretlen értéket kontrolláltan kezel | 12 eset a `wire enum handling (A3)` group-ban, ideértve a `CommunityReaction.fromWire` mérce-cellát (ZÖLD 12/12) |
| **A4** | A cursor page opaque (a kliens nem értelmezi a belső tartalmát) | 7 eset a `cursor page opacity (A4)` group-ban; a `CursorPage.initial() != CursorPage.haltedAfterRequest()` cella explicit módon védi a L349 regressziót |
| **A5** | A feature EGYETLEN `public.dart`-ból importálható | `community is reachable only through public.dart (E09-R05)` group, 3/3 ZÖLD: a barrel-en átmenő import elfogadva, a közvetlen domain/internal import elutasítva |
| **A6** | Más feature ma nem importálja a Communityt, és a Community sem importál más feature-t | `community does not import other features (E09-R05)` group, 1/1 ZÖLD a ma tiszta fán; a `community_domain_test.dart` `public.dart barrel surface (A5 + A6)` csoport is állítja |

### 10.3 Valódi-sértés próba — bizonyíték

A §6.1 mérce-mátrix kötelező valódi-sértés próbája: ideiglenesen
hozzáadtam egy `import 'package:flutter/foundation.dart';` + egy
`@immutable` annotációt a `community_profile.dart`-hoz, és
futtattam a `community domain stays framework-free` csoportot.

**A1 a sértéssel PIROS (kilépési kód 1):**

```
00:00 +0: community domain stays framework-free (E09-R05) no framework, storage, wall-clock, or random source in the domain
00:00 +0 -1: community domain stays framework-free (E09-R05) no framework, storage, wall-clock, or random source in the domain [E]
  Expected: empty
    Actual: [
              'lib/features/community/domain/entities/community_profile.dart contains "package:flutter/"'
            ]
```

A kódot visszaállítottam (a `final class CommunityProfile` újra
`@immutable` nélkül, az extra `import` törölve).

**A1 a visszaállítással ZÖLD:**

```
00:00 +0: community domain stays framework-free (E09-R05) no framework, storage, wall-clock, or random source in the domain
00:00 +1: community domain stays framework-free (E09-R05) the boundary detector flags a direct Flutter import
00:00 +2: community domain stays framework-free (E09-R05) the boundary detector flags a direct DateTime.now() call
00:00 +3: All tests passed!
```

### 10.4 Futtatott parancs és teljes kimenete

```bash
ROUND_GATE_SLEEP_SECONDS=0 \
  tools/round-gate.sh \
    test/features/community/domain/community_domain_test.dart \
    test/core/architecture_dependency_test.dart
```

A gate 7 lépése, mind zöld:

| Lépés | Parancs (kivonat) | Eredmény |
|---|---|---|
| 1. format | `dart format --output=none --set-exit-if-changed lib test tool` | ZÖLD — `Formatted 1838 files (0 changed)` |
| 2. analyze | `flutter analyze lib/ test/ tool/` | ZÖLD — `No issues found! (ran in 5.2s)` |
| 3. test community_domain | `flutter test test/features/community/domain/community_domain_test.dart` | ZÖLD — `+41: All tests passed!` |
| 4. test architecture | `flutter test test/core/architecture_dependency_test.dart` | ZÖLD — `+44: All tests passed!` |
| 5. architecture | `dart run tool/check_architecture.dart` | ZÖLD — `Architecture dependencies OK (12 allowlisted deviation(s))` |
| 6. secrets | `dart run tool/ci/check_secrets.dart` | ZÖLD — `Secret scan OK (3340 file(s) scanned, 0 finding(s))` |
| 7. l10n | `dart run tool/ci/check_l10n_parity.dart` | ZÖLD — `L10n parity OK (en → hu, 1663 message(s))` |

A gate kimenete az `end_summary` sorral zárult:

```
MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### 10.5 `git diff --stat` (pre-flight `770f25cc` → HEAD)

24 fájl, 3002 sor hozzáadva (0 törölt):

```
 .../domain/entities/community_challenge.dart       | 284 +++++++++++
 .../community/domain/entities/community_club.dart  | 198 ++++++++
 .../domain/entities/community_comment.dart         | 149 ++++++
 .../community/domain/entities/community_post.dart  | 298 +++++++++++
 .../community/domain/entities/community_profile.dart         | 193 ++++++++
 .../domain/entities/community_reaction.dart        |  90 ++++
 .../domain/entities/moderation_state.dart          |  10 +
 .../domain/entities/notification_item.dart         | 149 ++++++
 .../domain/repositories/challenge_repository.dart  |  79 +++
 .../domain/repositories/club_repository.dart       |  85 ++++
 .../domain/repositories/community_page.dart        |  52 ++
 .../repositories/community_profile_repository.dart |  40 ++
 .../domain/repositories/feed_repository.dart       |  43 ++
 .../repositories/notification_repository.dart      |  48 ++
 .../domain/repositories/post_repository.dart       |  96 ++++
 .../domain/repositories/social_graph_repository.dart      |  88 ++++
 .../community/domain/value_objects/audience.dart   |  51 ++
 .../domain/value_objects/community_handle.dart     |  88 ++++
 .../community/domain/value_objects/content_id.dart |  39 ++
 .../domain/value_objects/cursor_page.dart          |  65 ++++
 .../domain/value_objects/public_user_id.dart       |  52 ++
 lib/features/community/public.dart                 |  53 ++
 test/core/architecture_dependency_test.dart        | 202 ++++++++
 .../community/domain/community_domain_test.dart    | 550 +++++++++++++++++++++
 24 files changed, 3002 insertions(+)
```

A commit-sorozat (kumulatív):

```
0551b26f fix(community): drop unused CursorPage._, make UnfilledCommunityShareArtifact non-const (...)
956c6639 test(community): A2/A3/A4 acceptance cells + D3 wire-enum pin + A5/A6 barrel surface
1d83ff1a feat(community): add public.dart barrel + architecture guard groups (E09-R05)
b51484c6 feat(community): add 7 abstract repository interfaces + community page envelope
03692085 feat(community): add domain entities (profile, post, comment, reaction, challenge, club, notification, moderation)
b02c00b7 feat(community): add immutable value objects (public id, handle, audience, cursor, content id)
```

### 10.6 Eltérések a brief specifikációitól

Nincs eltérés a `allowed_paths` listától, és nincs scope-sértés.
A specifikációhoz képest a következő mérnöki döntések születtek:

1. **`community_page.dart` a `repositories/` mappa alatt.** A brief
   `value_objects/` listája 5 fájlt nevez meg, és nem hoz létre új
   `CommunityPage<T>` envelope-ot. Mivel minden repository-interfésznek
   szüksége van rá, és nem tiszta value-object (a lista + cursor
   kombinációja), a `repositories/` alá tettem (ahol a
   `repositories/`-be az új fájlok engedélyezettek voltak). A típus
   neve, szerkezete és az `isHaltedAfterRequest` helper egy az egyben
   lefedi a §6.1 A4 cellát.

2. **`UnfilledCommunityShareArtifact` factory, nem `const`.** A
   `DateTime.utc` Dart-ban factory, nem const konstruktor, ezért a
   `super(createdAt: _epoch)` hívás nem mehet `const` kontextusba.
   A `dart format` és a `dart analyze` ezt a `Invalid constant value`
   hibát jelezte; a megoldás egy factory + egy `DateTime.utc(1970, 1, 1)`
   literál lett. A `CommunityPost` mezője továbbra is a
   `CommunityShareArtifact` típust várja, tehát a Kör 10
   altípus-bevezetése egy-az-egyben cserélhető.

3. **A `final class ExperiencePoints` mintát követtem** a
   `copyWith` megvalósításnál. A Gamification domain (E08-R02)
   referenciája alapján a `factory + private const + copyWith` a
   projekt stílusa. A copyWith *nem* revalidál — a factory az
   egyetlen structural guard; ez a Kör 6+ alkalmazásrétegnek egy
   explicit döntése (új poszt nyilván factory-n át megy, nem
   copyWith-on).

4. **A `priority`-os stringek a notification entity-n ARB key
   formátumúak.** A `titleKey` / `bodyKey` a `r'^[a-z][A-Za-z0-9_]*$'`
   regexszel ellenőrzött, így a Kör 6+ UI kizárólag
   `AppLocalizations` felé tud mutatni (AGENTS.md §7).

A fenti döntések egyike sem változtatja a §6 acceptance cellákat —
minden futó teszt zöld maradt.

### 10.7 Javító kör 1 — F1 (ModerationState A3 wire decoder)

A review (`docs/reviews/e09-r05-review.md`, `b545ef3b`) egy MAJOR
leletet (F1) jelzett: `ModerationState` volt az egyetlen A3
wire-enum testvér, amelyik nem kapott `xFromWire(String?)` dekódert
+ a teszt-csoportból kimaradt. Javítás:

#### Mit javítottam

- **`lib/features/community/domain/entities/moderation_state.dart`**
  — a plain enum átalakítása enhanced enummá (`wireValue` mező,
  snake_case: `pendingReview` → `"pending_review"`, `authorOnly` →
  `"author_only"`), és hozzáadva a `moderationStateFromWire` /
  `moderationStateToWire` függvényeket a testvér-dekóderek
  mintájára (sosem dob, `null` ismeretlenre — A3).
- **`test/features/community/domain/community_domain_test.dart`** —
  három új cella a `'wire enum handling (A3)'` csoportban
  (`+29/+30/+31`):
  1. ismeretlen + üres + `null` wire-string → `null`,
  2. minden `ModerationState.values` roundtrip
     (`moderationStateFromWire(moderationStateToWire(v)) == v`),
  3. a snake_case wire-form pin (`pendingReview.wireValue ==
     "pending_review"`, `authorOnly.wireValue == "author_only"` —
     ez véd a `state.name` véletlen használata ellen);
  és `'moderationStateFromWire'` + `'moderationStateToWire'` a
  `'public.dart barrel surface (A5 + A6)'` `exportedNames`
  listájába véve.
- **`lib/features/community/public.dart`** — nem módosult: a
  barrel már file-level exportálja
  `domain/entities/moderation_state.dart` (40. sor), tehát az új
  szimbólumok automatikusan látszanak a barrel-en át. A teszt fájl
  `package:strumsight/features/community/public.dart` importja +
  a tesztekben való tényleges használat (`ModerationState` /
  `moderationStateFromWire` / `moderationStateToWire` referenciák
  a 105/129/150/327-329/334-335/351-355. sorokon) egyúttal a
  compile-time pin a barrel-exportra — ha a barrel eldobná a
  szimbólumot, a tesztek le se fordulnának.

#### Wire-string formátum — mérnöki döntés

A backend oldalon (`backend/app/community/`) nincs élő
`ModerationState` enum, így a wire-form a Dart-oldali alapértelmezés
lett snake_case, ahogy a brief §1 F1 javasolta (`pendingReview` →
`"pending_review"`, `authorOnly` → `"author_only"`). Ha egy jövőbeli
backend kör bevezet egy `ModerationState`-jellegű enumot, annak
`.value`-ját byte-identical kell tartani a `wireValue`-val — ezt a
3. cella (`'ModerationState wire form is snake_case'`) explicit
módon őrzi.

#### Gate — teljes kimenet

```bash
ROUND_GATE_SLEEP_SECONDS=0 \
  tools/round-gate.sh \
    test/features/community/domain/community_domain_test.dart \
    test/core/architecture_dependency_test.dart
```

| Lépés | Eredmény |
|---|---|
| 1. format | ZÖLD — `Formatted 1838 files (0 changed) in 7.34 seconds.` |
| 2. analyze | ZÖLD — `No issues found! (ran in 5.3s)` |
| 3. test `community_domain_test.dart` | ZÖLD — `+44: All tests passed!` (3 új cella: +29/+30/+31, a meglévő 41 megmaradt) |
| 4. test `architecture_dependency_test.dart` | ZÖLD — `+44: All tests passed!` |
| 5. architecture | ZÖLD — `Architecture dependencies OK (12 allowlisted deviation(s))` |
| 6. secrets | ZÖLD — `Secret scan OK (3341 file(s) scanned, 0 finding(s))` |
| 7. l10n | ZÖLD — `L10n parity OK (en → hu, 1663 message(s))` |

A gate `end_summary` sorral zárult: `MINDEN GATE ZÖLD`.

Az új A3 cellák kimenete a targeted futtatásból:

```
00:00 +12: wire enum handling (A3) ModerationState decoder returns null for unknown wire value
00:00 +13: wire enum handling (A3) ModerationState decoder roundtrips every allowed state
00:00 +14: wire enum handling (A3) ModerationState wire form is snake_case (pendingReview / authorOnly)
00:00 +15: All tests passed!
```

A `round-auditor` alügynök (szinkron, §8.4.2 kötelező önellenőrzés)
a `done` jelzés ELŐTT futott, scope / acceptance / truthfulness
mindhárom tengelyen `PASS` (jelentés: scope = 2 fájl, mind a
`allowed_paths` §1 listáján; acceptance = mind a 3 A3 cella + az
A5 barrel-pin név megvan és zöld; truthfulness = minden állítás
mögött van konkrétan lefuttatott parancs).

#### `git diff --stat b545ef3b..HEAD`

```
 .../domain/entities/moderation_state.dart          | 39 +++++++++++++++++++++-
 .../community/domain/community_domain_test.dart    | 37 ++++++++++++++++++++
 2 files changed, 75 insertions(+), 1 deletion(-)
```

Commit: `d52a10c5 fix(community): add ModerationState wire decoder
+ A3 cells (E09-R05 F1)` — a review commit `b545ef3b` fölé,
a branchen (`minimax/e09-r05-flutter-community-domain-and-public-api`).

A javító kör scope-sértés nélkül, kizárólag az F1-et érintő fájlokon
dolgozott — `public.dart` módosítása a file-level export miatt nem
volt szükséges.

## 11. Review — a Claude tölti ki
