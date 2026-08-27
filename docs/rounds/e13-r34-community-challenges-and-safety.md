# E13-R34 — Community challenges, clubs, notifications és safety UI

- **Státusz:** READY (pre-flight elvégezve 2026-08-27, `main @ 9b63c3ce` — lásd §0.0.B;
  előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 34
- **Kör-azonosító:** `E13-R34`
- **Branch:** `<motor>/e13-r34-community-challenges-and-safety`
- **Előfeltétel:** `E13-R33` merge-elve (közösségi feed és posztok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a MÁR MERGE-ELT
  [`0291`](../adr/0291-community-is-optional-and-private-by-default.md),
  [`0399`](../adr/0399-flutter-community-domain-and-public-api.md),
  [`0414`](../adr/0414-notification-inbox-and-push-abstraction.md) és
  [`0418`](../adr/0418-leaderboards-and-opt-in-competition.md) érvényes. **A kör
  ADR-t NEM ír, a `docs/adr/` TILOS zóna, módosítása H1** (§0.0.B/B2).

> ✅ **Pre-flight ELVÉGEZVE (2026-08-27, orchestrátor Claude Opus 5).** A brief
> fejléce a TÉNYLEGES kihívás- és moderációs szerződések mérését írta elő,
> kiemelten a „függő" vs. „ellenőrzött" megkülönböztetést: **mindkettő a fán
> van, de MÁS alakban, mint a brief feltételezte** — a küszöb a
> `CommunityChallengeParticipantState.bestMetricValue == null`, a ranglista
> pedig `verified`-only projekció (B6). A `brief-lint` `S13` lelete a B1-ben
> oldódik fel; az `allowed_paths` a MÉRT `presentation/` rétegre mutat — a
> brief eredeti `challenges/`, `clubs/`, `safety/` előtagjai a fán NEM léteznek.
> **A §0.0/R1–R4 cellái ugyanezekből a nem létező előtagokból lettek levezetve,
> ezért MIND újramérve a B1–B11-ben ([L518](../LESSONS.md#l518)).**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/presentation/screens/community_challenges_screen.dart",
  "lib/features/community/presentation/screens/community_notifications_screen.dart",
  "lib/features/community/presentation/screens/leaderboard_screen.dart",
  "lib/features/community/presentation/screens/safety_relationships_screen.dart",
  "lib/features/community/presentation/screens/clubs/club_detail_screen.dart",
  "lib/features/community/presentation/screens/clubs/club_list_screen.dart",
  "lib/features/community/presentation/screens/clubs/club_member_management_screen.dart",
  "lib/features/community/presentation/widgets/",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/community/challenge_join_test.dart",
  "test/features/community/leaderboard_optin_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/features/community/notification_deeplink_test.dart",
  "test/features/community/presentation/community_challenges_test.dart",
  "test/features/community/presentation/community_notifications_test.dart",
  "test/features/community/presentation/leaderboard_screen_test.dart",
  "test/features/community/presentation/clubs/club_detail_screen_test.dart",
  "test/features/community/presentation/clubs/club_list_screen_test.dart",
  "test/features/community/presentation/screens/safety_relationships_screen_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r34-community-challenges-and-safety.md",
]
gate_tests = [
  "test/features/community/challenge_join_test.dart",
  "test/features/community/leaderboard_optin_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/features/community/notification_deeplink_test.dart",
  "test/features/community/presentation/",
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

> ⚠ **FELÜLÍRVA a §0.0.B-ben (2026-08-27, indítási pre-flight).** Az alábbi
> R1–R4 cellák MIND a `lib/features/community/{challenges,clubs,safety}/`
> előtagokból lettek levezetve, amelyek a fán **nem léteznek** — a `brief-lint`
> `S13` lelete. [L518](../LESSONS.md#l518) mért tanulsága szerint egy `S13`
> lelet nem egy sort, hanem **minden belőle levezetett cellát** érvénytelenít.
> Az R1 „a képernyőket ez a kör hozza létre" állítása HAMIS (mind a hét
> képernyő a fán van, B1), az R2 „nincs ilyen"-je HAMIS (hat pinnelő teszt,
> B3), az R4 „a szám elmozdul"-ja HAMIS (nincs új képernyő, a bázisvonal
> változatlan 94, B9). **Ütközés esetén a §0.0.B a mérvadó.** Az R1
> ARB-feloldása (a `features/community_*.arb` FORRÁS + a generált aggregátum)
> és az S12 őr-blokk viszont ÉRVÉNYBEN MARAD — azok nem a hibás előtagokból
> jöttek.

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a challenge/klub/safety felületek moderációs és jelentési műveleteket indítanak idegen tartalom felett.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/community/challenges/`, `lib/features/community/clubs/`, `lib/features/community/safety/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `community` → a MÁR LÉTEZŐ `features/community_*.arb` fragmentum

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/community/challenges/`, `lib/features/community/clubs/`, `lib/features/community/safety/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0.B — PRE-FLIGHT MÉRÉS, 2026-08-27 (`main @ 9b63c3ce`, orchestrátor Claude Opus 5)

Az alábbi leletek a kör INDÍTÁSA előtt, a fán MÉRVE keletkeztek. A `brief-lint`
`S13` lelete a B1-ben oldódik fel; a többi a §1.1 két kötelező mérési szabálya
(elérhetetlen cél-státusz, erőforrás-tulajdonlás) és a merge-elt precedens
ütköztetése.

**Visszakeresett előzmény** (ADR 0312, `tools/knowledge-rag.mjs`, szűkítve →
teljes korpusz): [L518](../LESSONS.md#l518) (**az E13-R33 tegnapi leckéje, ami
NÉVEN NEVEZI ezt a kört**: egy `S13` lelet MINDEN §0.0 cellát érvénytelenít,
amit ugyanabból az előtagból vezettek le — a hat érintett tesztfájlt a HANDOFF
nevesítve adta át, lásd B3), [L519](../LESSONS.md#l519) (**szintén E13-R33,
MAJOR-1**: ARB-kulcs + vele bájtra azonos beégetett Dart-konstans = locale-hiba;
ez a kör 46 ilyen konstansot ÖRÖKÖL, lásd B10), [L497](../LESSONS.md#l497) /
[L503](../LESSONS.md#l503) (nem létező `allowed_paths` KÖNYVTÁR-előtag; az S13
elfedhet mélyebb hibát is — itt NEM fedett: egyetlen community-fa van),
[L478](../LESSONS.md#l478) (a pre-flight csak SZŰKÍTHET, a tágítás H3),
[L516](../LESSONS.md#l516) + [L517](../LESSONS.md#l517) +
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) (a
golden-útvonal NEM kerül a lokális ARM `gate_tests`-be; `tools/golden-x86.sh`),
[L397](../LESSONS.md#l397) / [L377](../LESSONS.md#l377) (a `ui_inventory`
egzakt bázisvonala CI-only lelet),
[ADR 0273](../adr/0273-design-system-token-source-of-truth.md) (a design system
EGYETLEN belépője a `public.dart` — ez a kör tényleges munkája, B4),
[ADR 0277](../adr/0277-failure-presentation-model.md) (a felület hibakódot kap,
az offline nem hiba-stílus).

### B1 — a három `allowed_paths` előtag a fán NEM létezik → a MÉRT `presentation/` rétegre mutatnak (`S13` feloldva)

Mérve: `find lib/features/community -type d` → a feature az Epic-9 által
lefektetett **réteges** szerkezetben él (`application/`, `data/`, `domain/`,
`presentation/`); `challenges/`, `clubs/`, `safety/` gyerek a feature GYÖKERE
alatt **nincs** (a `clubs/` a `presentation/screens/` ALATT él). A három előtag
tehát NULLA verziókövetett fájlt fedett.

**A feloldás nem a `presentation/` fa egészének felvétele**, hanem a §3
scope-jához tartozó, TÉTELESEN felsorolt hét képernyő. A halmaz PONTOSAN az,
amit a merge-elt **E13-R33 §0.0.B/B1 kifejezetten ennek a körnek tartott fenn**
(„a kimaradó öt képernyő a **szomszéd E13-R34** köré tartozik") — a két kör
fájlhalmaza így bizonyítottan diszjunkt, és a lista SZŰKEBB a szomszéd kör
user-jóváhagyott listájánál (7 képernyő + 1 megosztott könyvtár vs. 8 képernyő
+ 2 megosztott könyvtár), azaz nincs tágítás ([L478](../LESSONS.md#l478)).

| SDD | Felület | MÉRT fájl (a listán) |
|---|---|---|
| UI-59 | kihívás lista + részlet + csatlakozás | `community_challenges_screen.dart` |
| UI-59 | ranglista | `leaderboard_screen.dart` |
| UI-60 | klubok: lista / részlet / tagkezelés | `clubs/club_list_screen.dart`, `clubs/club_detail_screen.dart`, `clubs/club_member_management_screen.dart` |
| UI-61 | értesítés-postafiók + beállítások | `community_notifications_screen.dart` |
| UI-61 | Biztonsági központ (tiltott/némított) | `safety_relationships_screen.dart` |

A `presentation/widgets/` KÖNYVTÁR-előtagként kerül fel (a merge-elt E13-R33 és
E13-R32 precedens is így tett), mert a migráció közös komponenst hozhat létre és
mert a kör az ott MÁR merge-elt `CommunityThemeScope`-ot használja. A
`presentation/dialogs/` **NEM** kerül fel: mérve, a `report_content_sheet.dart`
az E13-R33-ban MÁR design-system-migrált (`grep -l design_system` találat), ezt
a kör VÁLTOZATLANUL hívja — ez a §5.6 bizonyítéka, nem a szerkesztéséé.

### B2 — a kör ADR-t NEM ír; a §5 normái MÁR MERGE-ELT ADR-ekből jönnek

Mérve: `docs/adr/` → `0291-community-is-optional-and-private-by-default.md`,
`0399-flutter-community-domain-and-public-api.md`,
`0414-notification-inbox-and-push-abstraction.md`,
`0418-leaderboards-and-opt-in-competition.md` mind a fán van.

| Brief §5 | A KÖTŐ, MÁR MERGE-ELT norma |
|---|---|
| 5.1 ranglista opt-in | ADR 0418 (E09-R23) |
| 5.2 függő ≠ ellenőrzött | ADR 0417 / 0418 (`verified`-only projekció) |
| 5.3 privát klub nem szivárog | ADR 0399 + SDD §16.2–16.3 |
| 5.4 mély hivatkozás validált | ADR 0414 |
| 5.5–5.6 semleges microcopy, elérhető biztonsági akció | ADR 0291 §5–§6 |

Ez a sávon a **tizenhetedik** ADR nélküli kör egymás után (E13-R17…R34). Új
normatív döntés nincs, ezért `tools/round-slots.py reserve-adr` **nem futott** —
nem égetünk el szabad sorszámot olyan körre, amelyik nem ír ADR-t. Egy
merge-elt ADR szövegének újraírása **H1**.

### B3 — a §0.0/R2 „nincs ilyen" MÉRÉSE ÉRVÉNYTELEN VOLT: hat élő widget-teszt áll a kör képernyőire (FELVÉVE)

A batch pre-flight (2026-08-25) az R2 cellát a **nem létező** `challenges/`,
`clubs/`, `safety/` előtagok ellen mérte, ezért „nincs ilyen"-t írt — pontosan
az [L518](../LESSONS.md#l518) hibaosztálya. A MÉRT `presentation/` rétegen:

```
grep -rln "…_screen" test/   → 6 fájl áll közvetlenül a kör hét képernyőjére
```

| Teszt | Melyik listás képernyőt pinneli |
|---|---|
| `presentation/community_challenges_test.dart` | `community_challenges_screen.dart` |
| `presentation/leaderboard_screen_test.dart` | `leaderboard_screen.dart` |
| `presentation/community_notifications_test.dart` | `community_notifications_screen.dart` |
| `presentation/screens/safety_relationships_screen_test.dart` | `safety_relationships_screen.dart` |
| `presentation/clubs/club_detail_screen_test.dart` | `clubs/club_detail_screen.dart` |
| `presentation/clubs/club_list_screen_test.dart` | `clubs/club_list_screen.dart` |

A hetedik képernyőnek (`clubs/club_member_management_screen.dart`) **nincs**
saját widget-tesztje — ez MÉRT tény, nem feltételezés; a migrációját az A9
golden-felvétel és a `club_detail_screen_test.dart` push-útja fedi.

A hat fájl FELKERÜL az `allowed_paths`-ra. **A jogosultság szűk:** a teszteket
az ÚJ widgetekre kell ráállítani. A lefedett viselkedést gyengíteni, cellát
törölni vagy `skip`-elni **TILOS** — az a mérce meggyengítése, amit a
gate-guard emberhez eszkalál.

### B4 — a hét képernyőnek NULLA design-system importja van: EZ a kör tényleges munkája

```
grep -rn "design_system" <a hét képernyő>   → 0 találat
```

Ugyanez a `presentation/` fa MÁS ágain (az E13-R33 nyolc képernyője + a
`widgets/` + a `dialogs/`) **13 fájlban** MÁR migrált — a kontraszt a mérés.

A cél az [ADR 0273 §1](../adr/0273-design-system-token-source-of-truth.md)
szerinti EGYETLEN belépő — `package:strumsight/core/design_system/public.dart`
—, a `foundations/**` közvetlen importja **TILOS**, és ezt a `gate_tests`-ben
futó `test/core/architecture_dependency_test.dart` méri. Mért precedens
ugyanerre a hibaosztályra: **E13-R16/F8**, 11 sértés, javító kör árán.

### B5 — §1.1/1. szabály (elérhetetlen cél-státusz): a ranglista opt-in kapcsolója a KLIENSEN NEM LÉTEZIK — szerver-oldali projekció

Nem az átmenettáblát, hanem a **tényleges inputot** mértem:

```
grep -rn "optIn|OptIn|opt_in|showOnLeaderboard|leaderboardVisib" lib/features/community/
   → 0 találat
```

A `leaderboard_screen.dart:1–10` doc-commentje kimondja, hogy a nézet „a Kör 23
endpoint (D6)" projekcióját rendereli, ami *„verified-only (A1 / D1), **opt-in
(A3 / D2)**"* — azaz az opt-in a **szerver** tulajdona
([ADR 0418](../adr/0418-leaderboards-and-opt-in-competition.md), E09-R23), és a
`CommunityChallengeRepository.leaderboard()` egy KÉSZ, már szűrt lapot ad vissza.
A kliensnek nincs kapcsolója, amit a kör bekapcsolhatna — és egy ilyen kapcsoló
bevezetése egy LEZÁRT kör (E09-R23) szerződését változtatná meg: **H2**.

**Ebből a kör KÖTELEZŐ, mérhető A1 predikátuma** (a felület felőli
falszifikáció, nem a szerver újramérése):

- a csatlakozási út (`acceptInvite` / `requestJoin`) **egyetlen** ranglista-írási
  vagy -beiratkozási hívást sem indít, és **nem** szintetizál lokális
  ranglista-sort a felhasználóra;
- a ranglista sorai KIZÁRÓLAG a `leaderboard()` lapjából származnak;
- a csatlakozás megerősítő szövege **nem** ígér ranglistára kerülést.

**Falszifikáció:** ha a csatlakozás után a felhasználó sora megjelenik a
ranglistán anélkül, hogy a repository lapja tartalmazná, az **A1** PIROS.

### B6 — §1.1/1. szabály: a „függő" vs. „ellenőrzött" küszöb MÉRT alakja `bestMetricValue == null`, és a ranglista `verified`-only

| Mért artefaktum | Fájl:sor | Jelentés |
|---|---|---|
| `CommunityChallengeParticipantState.bestMetricValue` | `community_challenge.dart:126–128` | `null` ⇔ *„the participant has not yet submitted a **verified** result (SDD §15.5)"* |
| `LeaderboardEntry.verifiedBadge` | `challenge_repository.dart:86–89` | *„Always `true` for rows in the **verified-only** projection (§A1)"* |
| `submitResult()` | `challenge_repository.dart:161–170` | *„the client never sends a `verified: true` field"* — a szerver dönt |
| `ChallengeInviteState` | `community_challenge.dart:21–32` | `draft, sent, accepted, declined, expired, cancelled, active, completed, forfeited` — **`pending`/`verified` érték NINCS benne** |

**Két következmény a mércére:**

1. az **A2** küszöbe a `bestMetricValue` NULL-ságán áll, NEM egy nem létező
   `pending` enum-értéken. A felület a `null` esetben „még nincs ellenőrzött
   eredményed" alakú, **nem véglegesként** olvasható állapotot mutat;
2. az **A2** második fele a ranglista-soron mérhető: a `verifiedBadge` a
   `Semantics`-be és a látható sorba is bekerül (a `leaderboard_screen.dart`
   doc-commentje szerint a rang-sor egyetlen `Semantics` csomópont, amelynek
   címkéje a jelvény meglétét is felolvassa) — a jelvény nélküli sor tehát
   szerkezetileg nem kerülhet a `verified`-only listára.

### B7 — §1.1/2. szabály (erőforrás-tulajdonlás): a klub-láthatóságot a REPOSITORY birtokolja, a felület csak rendereli — és a „függő kérelem" a fán NEM ábrázolható

Mérve a TÉNYLEGES hívási láncon:

| Réteg | Mért artefaktum | Szerep |
|---|---|---|
| `domain/repositories/club_repository.dart:16–19` | `listClubs()` — *„combines the visibility filter — `private` only for members"* | a szűrés a szerveré |
| ugyanott `:24–26` | `fetchClub()` — *„visibility-aware (returns a **SUMMARY placeholder** for non-members of a private club)"* | a nem-tag SOSEM kap tartalmat |
| ugyanott `:4–7` | *„the server-side permission matrix (SDD §16.3) is enforced on the backend and **never re-derived here**"* | a kliens nem dönt jogosultságot |
| `clubs/club_detail_screen.dart:234–236` | `role = club.myRole; canJoin = role == null && club.visibility != ClubVisibility.private` | a felület MA ezt a küszöböt használja |

**A brief §6.1 középső cellája („függő csatlakozási kérelem") a fán NEM
ábrázolható:** `ClubRole` = `{owner, moderator, member}` — nincs `pending`
érték, a `requestJoin()` `Future<void>`, és a `CommunityClub` entitásnak nincs
kérelem-állapot mezője. (A `pendingRequestOutgoing/Incoming` a
`community_profile.dart:33–34`-ben él, az a **követés**, nem a klub.) Egy ilyen
állapot bevezetése domain-változás, azaz LEZÁRT kör (E09-R24) átírása: **H2**.

A cellahármas ezért a MÉRT küszöbre — `myRole` + `ClubVisibility` — kerül át
(§6.1 átírt tábla). A mérce NEM lazul: a „semmilyen tartalom nem-tagnak"
invariáns mindkét alsó cellában él, csak a középső bemenete változik a fán
LÉTEZŐ `discoverable` fokra.

### B8 — §5.4 / A4: az értesítés-koppintás MA nem navigál, és a közösségi képernyők NINCSENEK a routerben → az A4 SZERKEZETI ABSZTINENCIA-cella

Mérve:

- `community_notifications_screen.dart:213–215` → `onTap: … notifier.markRead(item.id)` — **más művelet nincs**, holott a fájl doc-commentje (`:9–12`) „deep-links the user to the entity"-t állít. A doc és a kód szétcsúszott; a kód a mérés;
- `CommunityNotificationItem` mezői (`notification_item.dart:89–100`):
  `id, kind, titleKey, bodyKey, createdAt, isRead, relatedContentId` — **route,
  URL vagy deep-link mező NINCS**;
- `grep -c "community" lib/app/routing/app_router.dart` → **0**: a közösségi
  képernyők nincsenek a routerben (`Navigator.push`-sal érhetők el), és a
  `lib/app/routing/**` a kör TILOS zónája.

Egy valódi külső mély-hivatkozási út bevezetése tehát új router-bejegyzést
kívánna, ami **H3** — a kör ezt NEM teheti. Az A4 ezért a merge-elt E13-R33
`B7`-cellájának mintájára **strukturális absztinencia-cella**:

- az értesítés-sor látható és `Semantics` felülete KIZÁRÓLAG a `titleKey` /
  `bodyKey` / `kind` / `isRead` mezőkből áll elő — a `relatedContentId`-ből
  levezetett tartalom (klub- vagy poszt-payload) **nem** kerülhet bele;
- ha a kör bármilyen koppintás-navigációt vezet be egy klub- vagy
  kihívás-felületre, az a `fetchClub()` / `fetchDefinition()` **eredményét
  bevárja**, és a tagság-hiányra a SUMMARY-nézetet mutatja — nem tartalmat.

**Falszifikáció:** ha a sor a `relatedContentId`-hez tartozó klub NEVÉT vagy
tartalmát rendereli nem-tagnak, az **A4** és az **A3** is PIROS.

### B9 — a kör NEM hoz létre új képernyőt; `ui_inventory` bázisvonal = 94

Mérve:

- `find lib/features -name '*_screen.dart' | wc -l` → **94**;
  `test/ui/ui_inventory_test.dart:22` → `hasLength(94)` — a kettő EGYEZIK;
- a §3 MINDEN felülete a fán MÁR LÉTEZŐ hét képernyőn áll elő (B1 tábla) — új
  `*_screen.dart` **nem szükséges**, tehát az alap-eset a **változatlan 94**.

Ha a kör mégis új `*_screen.dart`-ot hozna a listás könyvtárak alá, a
`hasLength(...)` értékét UGYANABBAN a commitban a tényleges számra kell emelni
(§0.0/R4). A jogosultság PONTOSAN a szám emelése; kerülőút (átnevezés vagy a
`tool/ui_inventory.dart` szabályának lazítása) **TILOS**.

### B10 — l10n: a klub-ág HÁROM képernyője TELJESEN LOKALIZÁLATLAN — 46 beégetett angol konstans (L519 hibaosztály, MÉRT)

`lib/l10n/features/community_{en,hu}.arb` → **180–180** kulcs, paritásban; a
fragmentum LÉTEZIK, új fragmentum NEM készül, a
`test/l10n/arb_parity_test.dart` beégetett szegmens-listáját nem kell bővíteni.
Az aggregátumot (`lib/l10n/app_{en,hu}.arb`) **kézzel írni TILOS** — kizárólag
`dart run tool/gen_l10n_segments.dart --write` (§0.0/R1).

**A mért lelet viszont ennél súlyosabb.** `AppLocalizations`-találatok
képernyőnként:

| Képernyő | `AppLocalizations` találat | Beégetett `const String _l10n*` |
|---|---|---|
| `community_challenges_screen.dart` | 6 | 0 |
| `community_notifications_screen.dart` | 13 | 0 |
| `leaderboard_screen.dart` | 5 | 0 |
| `safety_relationships_screen.dart` | 3 | 0 |
| `clubs/club_list_screen.dart` | **0** | **14** |
| `clubs/club_detail_screen.dart` | **0** | **21** |
| `clubs/club_member_management_screen.dart` | **0** | **11** |

A három klub-képernyő tehát **egyetlen** lokalizált szöveget sem használ; 46
felhasználónak látható angol sztring él bennük `const String _l10nClub*`
alakban (pl. `club_detail_screen.dart:73` `'Manage members'`,
`club_list_screen.dart:64–66` `'Private' / 'Discoverable' / 'Public'`).

Ez PONTOSAN az [L519](../LESSONS.md#l519) hibaosztálya, csak a fordított
irányban: ott egy magyar konstans ült egy létező angol ARB-érték helyén, itt egy
angol konstans-készlet ül a lokalizáció HELYETT. Egy magyar nyelvre állított
felhasználó ma a klub-ág minden gombját és minden láthatósági címkéjét angolul
látja — köztük a `Private` / `Discoverable` / `Public` választót, ami a kör
LEGNAGYOBB következményű beállítása (§5.3, §9 első kockázata).

**Ebből a kör KÖTELEZŐ mércéje az új A10 cella** (§6): a három klub-képernyő
minden felhasználónak látható szövege az `AppLocalizations`-ből jön, és
`const String _l10nClub…` konstans **nem marad** a fájlokban. A kulcsok a
`community_{en,hu}.arb` FORRÁS-fragmentumba mennek, `en` és `hu` értékkel
egyaránt.

**A falszifikációs őr hatóköre (L519 mért tanulsága):** egy locale-specifikus
cella önmagában csak az ELLENKEZŐ nyelv beégetését fogja. Az A10 ezért
**cellapár**: `en` locale alatt az angol felirat, `hu` locale alatt a magyar
felirat állítása UGYANARRA a widgetre.

### B11 — a golden-útvonal NEM kerül a lokális `gate_tests`-be (L516, L517, ADR 0426)

A brief eredeti `gate_tests` tömbje és §7 sora a golden-útvonalat tartalmazta,
a §7 pedig `flutter test --update-goldens`-t írt elő — **mindkettő HIBÁS ezen a
boxon**, és mindkettő a szomszéd kör sorának öröklése
([L516](../LESSONS.md#l516), E13-R32, 2026-08-27; az E13-R17 két vak javító
kört, az E13-R20 egy **H5 haltot** fizetett érte). Az ARM-en rögzített pixel az
x86-os merge-kapu nulla toleranciájú komparátorán MINDIG piros
([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) §2–§3),
a golden-lépés lokális pirosa pedig a szekvenciális `round-gate.sh`-t MEGÁLLÍTJA
az `architecture` / `secrets` / `l10n` lépések ELŐTT — tehát elrejti a kör három
utolsó mércéjét.

**Mindkettő JAVÍTVA:** a golden-útvonal kikerült a `gate_tests`-ből és a §7
gate-sorából; a rögzítés/ellenőrzés `tools/golden-x86.sh record|check` (§7).

**A mérce NEM lazul:** a golden-cellákat továbbra is KETTŐ méri — lokálisan a
kötelező `tools/golden-x86.sh check`, a kapuban az exact-SHA `full-gate.yml`
teljes suite-ja —, mindkettő x86_64-en, változatlan nulla toleranciájú
komparátorral és a TELJES golden-készlettel. Egy cella sincs törölve vagy
`skip`-elve. A `textScaler 2.0` keret KÖTELEZŐ, és a felvétel közben talált,
kör ELŐTTI elrendezési hibát JAVÍTANI kell, nem bázisvonalként rögzíteni
([L517](../LESSONS.md#l517) — két egymást követő kör mérte ki, hogy ez a keret
valódi, addig láthatatlan túlcsordulást fog).

### B12 — a `gate_tests` a TELJES `test/features/community/presentation/` könyvtárat futtatja

A hat pinnelő teszt (B3) az `allowed_paths`-on TÉTELESEN van felsorolva, a
`gate_tests` viszont a teljes könyvtárat futtatja — így ha a kör diffje az
E13-R33 MÁR MERGE-ELT, **listán kívüli** tesztjeit (`comments_screen_test.dart`,
`community_gate_test.dart`, `community_media_player_test.dart`,
`community_search_test.dart`, `following_feed_test.dart`,
`profile_onboarding_test.dart`, `report_content_sheet_test.dart`) elmozdítaná,
az a kör SAJÁT kapujában bukik, nem a ~17 perces exact-SHA CI-ban. Ezek a
fájlok **NEM** szerkeszthetők: elbukásuk `blocked` jelzés és célzott
brief-revízió, nem csendes átírás.

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

> A tábla a §0.0.B/B1 MÉRÉSE szerint át van írva — a brief eredeti
> `community/{challenges,clubs,safety}/` előtagjai a fán NEM léteznek.

| Útvonal | Indok |
|---|---|
| `presentation/screens/community_challenges_screen.dart` | UI-59 — kihívás lista, részlet, csatlakozás |
| `presentation/screens/leaderboard_screen.dart` | UI-59 — ranglista |
| `presentation/screens/clubs/club_list_screen.dart` | UI-60 — klub-lista + létrehozás |
| `presentation/screens/clubs/club_detail_screen.dart` | UI-60 — klub-részlet, láthatósági küszöb |
| `presentation/screens/clubs/club_member_management_screen.dart` | UI-60 — tagok és szerepkörök |
| `presentation/screens/community_notifications_screen.dart` | UI-61 — értesítés-postafiók + beállítások |
| `presentation/screens/safety_relationships_screen.dart` | UI-61 — Biztonsági központ (tiltott/némített) |
| `presentation/widgets/` | megosztott komponensek — a kör a MÁR merge-elt `CommunityThemeScope`-ot HASZNÁLJA, és ide teheti a saját közös kártyáit (B1) |
| `lib/l10n/features/community_{en,hu}.arb` | **FORRÁS** — a szövegek (`community` MÁR migrált feature, 180–180 kulcs paritásban) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/community/{challenge_join,leaderboard_optin,private_club_leakage,notification_deeplink}_test.dart` | a §6 ÚJ cellái |
| a §0.0.B/B3 hat pinnelő tesztje | a migráció után az ÚJ widgetekre kell ráállítani; gyengíteni/`skip`-elni TILOS |
| `test/ui/goldens/` | az A9 golden-teszt + a felvett PNG-k |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a bázisvonal MÉRVE 94 és a kör alap-esetben NEM mozdítja (B9); a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r34-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/community/` a hét listás képernyőn és a
`presentation/widgets/`-en kívül — kiemelten a `presentation/dialogs/`, az
`application/`, a `data/` és a `domain/` (a klub-tagság, a kihívás-állapotgép és
az értesítés-entitás LEZÁRT körök szerződése, módosításuk **H2**) ·
`lib/features/**` egyébként · `lib/app/routing/**` (a kör nem vesz fel route-ot,
B8) · `lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**` · az E13-R33 hét, listán kívüli presentation-tesztje (B12).

## 5. Kötött architekturális döntések

### 5.1 A ranglista OPT-IN

A felhasználó nem kerül rá automatikusan azzal, hogy gyakorol. A versengés
választás, nem alapállapot (az ADR 0291 §2 kiterjesztése,
[ADR 0418](../adr/0418-leaderboards-and-opt-in-competition.md)).

**MÉRT alak (§0.0.B/B5):** a kliensen NINCS opt-in kapcsoló — az opt-in a
szerver-oldali `verified`-only projekció tulajdona, és a felület csak
rendereli. A kör mércéje ezért a felület felőli **absztinencia**: a
csatlakozási út egyetlen ranglista-beiratkozási hívást sem indít, és nem
szintetizál lokális sort. Kapcsoló bevezetése egy LEZÁRT kör (E09-R23)
szerződését írná át: **H2**.

**NEM elfogadható gyengítés:** automatikus felvétel a ranglistára a kihíváshoz
csatlakozáskor, vagy olyan megerősítő szöveg, ami ranglistára kerülést ígér.
A csatlakozás nem egyenlő a nyilvános rangsorolás vállalásával.

### 5.2 A függő bejegyzés NEM ellenőrzött

A két állapot vizuálisan és szövegesen is elkülönül. Az ellenőrizetlen eredmény
nem jelenik meg véglegesként.

**MÉRT küszöb (§0.0.B/B6):** `CommunityChallengeParticipantState.bestMetricValue
== null` ⇔ még nincs **ellenőrzött** eredmény. `pending` / `verified`
enum-érték a `ChallengeInviteState`-ben NINCS — a felület a NULL-ságot
rendereli, nem egy nem létező státuszt. A ranglista-soron a
`LeaderboardEntry.verifiedBadge` a látható sorban ÉS a `Semantics` címkében is
megjelenik.

### 5.3 A privát klub tartalma NEM szivárog

Sem előnézetben, sem értesítésben, sem mély hivatkozáson át. Ez
acceptance-cella (A3), és a kör legfontosabb invariánsa.

**NEM elfogadható gyengítés:** „a cím megjelenítése ártalmatlan az
értesítésben". A cím maga is tartalom.

**MÉRT küszöb (§0.0.B/B7):** `CommunityClub.myRole` (`null` = nem tag) +
`ClubVisibility {private, discoverable, public}`. A `fetchClub()` nem-tagnak
SUMMARY helyőrzőt ad vissza — a jogosultságot a szerver dönti el, a kliens
**nem derivál újra**. „Függő csatlakozási kérelem" állapot a fán NEM létezik
(`ClubRole` = `{owner, moderator, member}`), a bevezetése **H2**.

### 5.4 A mély hivatkozás VALIDÁLT

Az értesítésből érkező link jogosultság-ellenőrzésen megy át, mielőtt bármit
megjelenítene. Nem megbízható bemenet.

**MÉRT alak (§0.0.B/B8):** a `CommunityNotificationItem`-nek NINCS route- vagy
link-mezője (csak `relatedContentId`), a koppintás ma kizárólag `markRead`-et
hív, és a közösségi képernyők NINCSENEK a routerben — a `lib/app/routing/**`
pedig TILOS zóna, tehát új mély-hivatkozási út bevezetése **H3**. A kör mércéje
ezért **strukturális absztinencia**: az értesítés-sor látható és `Semantics`
felülete kizárólag a `titleKey` / `bodyKey` / `kind` / `isRead` mezőkből áll
elő, a `relatedContentId`-ből levezetett tartalom nem kerülhet bele; ha a kör
mégis bevezet koppintás-navigációt, az a repository tagság-feloldó válaszát
BEVÁRJA, és tagság hiányában a SUMMARY-nézetet mutatja.

### 5.5 Az integritás-vizsgálat microcopyja SEMLEGES

A vizsgálat alatt álló eredmény nem vádol csalással. A semleges szöveg tényt
közöl, nem ítéletet.

### 5.6 A biztonsági akció ELÉRHETŐ, nem elrejtett

Bejelentés, tiltás és némítás minden releváns felületről elérhető, nem csak a
beállításokból.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A ranglistára kerülés opt-in: a csatlakozási út egyetlen ranglista-beiratkozási hívást sem indít és nem szintetizál lokális sort (§0.0.B/B5) | `leaderboard_optin_test.dart` |
| A2 | A `bestMetricValue == null` (= még nincs ellenőrzött eredmény) vizuálisan és szövegesen elkülönül a `verifiedBadge`-es sortól (§0.0.B/B6) | `challenge_join_test.dart` |
| A3 | A privát klub tartalma nem szivárog (lista-előnézet, klub-részlet nem-tagként, értesítés-sor) | `private_club_leakage_test.dart` |
| A4 | Az értesítés-sor felülete kizárólag `titleKey`/`bodyKey`/`kind`/`isRead`-ből áll elő; a `relatedContentId`-ből levezetett tartalom nem kerül bele (§0.0.B/B8) | `notification_deeplink_test.dart` |
| A5 | Az integritás-/ellenőrzés-várakozás szövege semleges — nem vádol csalással (en + hu) | `challenge_join_test.dart` |
| A6 | A biztonsági akciók (bejelentés, tiltás, némítás) a releváns felületekről elérhetők, nem csak a beállításokból | `private_club_leakage_test.dart` |
| A7 | A ranglista „load more" útja idempotens: ugyanannak a lapnak az újra-beolvasása nem duplikál sort és nem ejt el sort (§0.0.B/B5) | `leaderboard_optin_test.dart` |
| A8 | A tiltás/némítás állapota a Biztonsági központ és a klub-/kihívás-felületek között egységes | ugyanott |
| A9 | A §3-ban megnevezett MIND A HÉT képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r34_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |
| **A10** | **A három klub-képernyő MINDEN felhasználónak látható szövege az `AppLocalizations`-ből jön; `const String _l10nClub…` konstans nem marad (§0.0.B/B10, [L519](../LESSONS.md#l519))** | `private_club_leakage_test.dart` — `en`/`hu` **cellapár** |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A csatlakozás automatikusan ranglista-sort ad a felhasználónak | **A1** |
| A `bestMetricValue == null` eredmény véglegesként (jelvénnyel vagy jelvény nélkül, de véglegesként) jelenik meg | **A2** |
| A privát klub neve/leírása látszik nem-tagnak a lista-előnézetben vagy a részletnézetben | **A3** |
| Az értesítés-sor a `relatedContentId`-ből levezetett klub-tartalmat rendereli | **A4** és **A3** |
| „Csalás gyanúja" / vádoló szöveg az ellenőrzés-várakozásnál | A5 |
| A „load more" újra-beolvasása megismétli az utolsó elemet | A7 |
| A klub-képernyő beégetett angol konstansot használ (`'Manage members'`, `'Private'`) | **A10** — a `hu`-cella |
| Az A10 javítása közben a fejlesztő magyar szöveget éget be az ARB-kulcs helyére | **A10** — az `en`-cella |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A klub-láthatóság három kötelező cellája** (a küszöb: `myRole` + `visibility`
— a MÉRT állapottér, §0.0.B/B7; a brief eredeti „függő csatlakozási kérelem"
középső cellája a fán NEM ábrázolható, a bevezetése H2):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | `myRole == null` + `private` | **semmilyen tartalom**, és nincs csatlakozás-gomb |
| rajta (a küszöbön) | `myRole == null` + `discoverable` | **sincs** tag-tartalom; a csatlakozási út látszik |
| a küszöb fölött | `myRole != null` (elfogadott tag) | teljes tartalom |

A „küszöb alatt" cella MÉRT forrása: `club_detail_screen.dart:236`
(`canJoin = role == null && club.visibility != ClubVisibility.private`) és
`club_repository.dart:24–26` (SUMMARY helyőrző nem-tagnak).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** rendereld a privát
klub nevét és leírását egy `myRole == null` nézetben (vagy egy értesítés-sor
alszövegében) → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

**Második valódi-sértés próba (KÖTELEZŐ, A10, L519):** írj vissza EGY beégetett
angol konstanst egy klub-képernyő feliratába → az A10 **`hu`-cellájának**
PIROSNAK kell lennie → állítsd vissza. Ha csak az `en`-cella pirosodik, az őr
rossz irányban mér — javítsd a cellapárt.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/challenge_join_test.dart test/features/community/leaderboard_optin_test.dart test/features/community/private_club_leakage_test.dart test/features/community/notification_deeplink_test.dart test/features/community/presentation/ test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ mind a HÉT képernyőre. Minta és futó precedens:
`test/ui/goldens/e13_r33_screens_golden_test.dart`. Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r34_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r34_screens_golden_test.dart
```

> **§0.0.B/B11 — a `flutter test --update-goldens` TILOS ezen a boxon, és a
> golden-útvonal NEM része a lokális `gate_tests`-nek.** Az ARM-en rögzített
> pixel az x86-os merge-kapu nulla toleranciájú komparátorán MINDIG piros
> ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) §2–§3,
> [L486](../LESSONS.md#l486), [L493](../LESSONS.md#l493): az E13-R17 két vak
> javító kört, az E13-R20 egy **H5 haltot** fizetett érte), a §7 gate-sorába
> öröklése pedig a saját gépén állítja meg a kört a későbbi lépések előtt
> ([L516](../LESSONS.md#l516), E13-R32, 2026-08-27). A `tools/golden-x86.sh` a
> CI-vel AZONOS architektúrán vesz fel és ellenőriz — a mérce (nulla tolerancia,
> ugyanaz a komparátor és golden-készlet) VÁLTOZATLAN. Kilépési kódok: `0` =
> egyezik, `10` = valódi golden-eltérés, `20` = környezeti hiba, `30` = hibás
> hívás.
>
> **A `textScaler 2.0` keret felderítő mérés is** ([L517](../LESSONS.md#l517)):
> két egymást követő kör fogott vele addig láthatatlan `RenderFlex`
> túlcsordulást, egyszer a kör ELŐTTI, merge-elt kódban. Az ilyen leletet
> JAVÍTANI kell, nem bázisvonalként rögzíteni.

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör jogosultsági határt és nyilvános adatot
> érint, ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

> **A §8 a TERVED — nincs külön task-lista.** A kör munkája a hét MÉRT képernyő
> design-system migrációja (ADR 0273: EGYETLEN belépő a `public.dart`), NEM új
> képernyők építése (§0.0.B/B4, B9).

1. **A klub-ág lokalizálása ELŐSZÖR** (A10) — a 46 beégetett `const String
   _l10nClub*` konstans ARB-kulcsokká a `community_{en,hu}.arb` FORRÁSBAN, majd
   `dart run tool/gen_l10n_segments.dart --write`. Ez a legnagyobb, legkevésbé
   kockázatos blokk, és minden további klub-munka erre épül.
2. A kihívás listája és részletnézete, csatlakozás-megerősítéssel — design-system
   komponensekre migrálva.
3. A ranglista: a `verifiedBadge`-es sor + a „load more" idempotenciája (A7).
4. A `bestMetricValue == null` (függő) / `verifiedBadge` (ellenőrzött)
   megkülönböztetés és a SEMLEGES ellenőrzés-várakozás szöveg (A2, A5).
5. A klub-állapotok + a három láthatósági cella a `myRole` × `visibility`
   küszöbön (A3).
6. Az értesítés-postafiók migrációja + az A4 absztinencia-invariáns.
7. A Biztonsági központ: tiltott/némított lista, bejelentés-státusz; a
   biztonsági akciók elérhetősége a klub- és kihívás-felületekről (A6, A8).
8. A golden-felvétel mind a hét képernyőre, két kerettel
   (`tools/golden-x86.sh record`), majd `check`.
9. A KÉT valódi-sértés próba (§6.1), §10-be dokumentálva.
10. `tools/round-gate.sh` a §7 szerint — külön processz, csonkítatlan kimenet.

## 9. Kockázatok

- **A privát klub szivárgása.** Több csatornán is előfordulhat (előnézet,
  értesítés, mély link), és mindegyiket külön kell zárni (A3).
- **Az automatikus ranglista.** Kényelmesnek látszik, és nyilvános
  összehasonlításba kényszeríti a felhasználót (A1).
- **A vádaskodó vizsgálat-szöveg.** Ártatlan felhasználót bélyegez meg egy
  automatikus jelzés miatt (A5).

## 10. Implementation handoff — az implementer tölti ki

**Státusz: KÉSZ.** Mind a hét listás képernyő (`community_challenges_screen.dart`,
`leaderboard_screen.dart`, `clubs/club_list_screen.dart`,
`clubs/club_detail_screen.dart`, `clubs/club_member_management_screen.dart`,
`community_notifications_screen.dart`, `safety_relationships_screen.dart`)
design-system-migrált (`CommunityThemeScope` + `public.dart` komponensek —
`SsButton`, `SsCard`), a klub-ág teljesen lokalizált, a négy új céltesztfájl
és a golden-készlet commitolva.

### Képernyőnkénti összegzés

- **`community_challenges_screen.dart`** — `CommunityThemeScope` + `SsButton`
  a retry-akciókon. Új: `challengeMyParticipationProvider` (lazy,
  `fetchMyParticipation`, csak az akció-lapon watch-olva — a Kör 21 pinnelt
  teszt fake-je változatlan maradhatott, mert az sosem nyitja meg a lapot).
  Az akció-lap most `_MyResultSection`-t mutat (A2: `bestMetricValue == null`
  → semleges „verification in progress" szöveg, kulcs
  `communityChallengeResultPending`; nem-null → `communityChallengeResultVerified`
  + `Icons.verified`) és két új biztonsági akciót (`Block author` /
  `Mute author`, A6/A8, ugyanaz a `socialGraphRepositoryProvider`, amit a
  Biztonsági központ olvas). A1: a csatlakozási/eredmény-megtekintési út
  bizonyítottan sosem hívja a `leaderboard()`-ot (a teszt fake-je dobna, ha
  hívnák). A sheet `SingleChildScrollView`-ba került (a bővülő tartalom
  kis viewporton túlcsordult volna — mérve, javítva).
- **`leaderboard_screen.dart`** — `CommunityThemeScope` + `SsButton` a
  „Load more" és retry gombokon (a korábbi, hibásan újrahasznosított
  „Accept" felirat helyett új `communityChallengeLoadMore` kulcs). A7:
  a „load more" mindig ugyanazt az első lapot tölti újra (nincs
  akkumuláció), ezért szerkezetileg idempotens — lásd
  `leaderboard_optin_test.dart`.
- **`clubs/club_list_screen.dart`** — mind a 14 `_l10nClub*` konstans ARB-be
  költözött; a láthatóság-címke + tagszám egyetlen sablonos kulcsba
  (`communityClubMemberCountLabel`) került, hogy a `hu` cella ne törje a
  pinnelt angol assertiont. `communityClubVisibilityLabel(...)` publikus
  segédfüggvény lett, amit a klub-részlet és a golden-fixture is
  újrahasznosít.
- **`clubs/club_detail_screen.dart`** — a MÉRT `myRole` × `visibility`
  háromsoros mátrix (§0.0.B/B7) implementálva: `_PrivateRestrictedView`
  (a küszöb alatt: SEMMI tartalom, nincs join-gomb),
  `_JoinPromptView` (a küszöbön: csak név + join CTA, nincs leírás/tab-
  tartalom), teljes `_Body` (a küszöb fölött: leírás + 4 tab). Az About tab
  most a klub leírását és láthatósági chipjét is mutatja (korábban statikus
  placeholder volt). A felső infó-blokk `ConstrainedBox` + belső görgetés
  alá került (2×-es szövegskálázásnál 805 px-es `RenderFlex` túlcsordulást
  mértem — mérve ELŐTTI, merge-elt kódban élt hiba, javítva, nem
  bázisvonalként rögzítve, L517).
- **`clubs/club_member_management_screen.dart`** — mind a 11 konstans
  ARB-be; minden sorban új „Block member" / „Mute member" akció
  (`socialGraphRepositoryProvider`, A6/A8).
- **`community_notifications_screen.dart`** — a doc-comment hazug „deep-links
  the user to the entity" állítása javítva (a kód mindig is csak
  `markRead`-et hívott — A4 doc-fix). A `hasData`-actions „Mark all as
  read" `TextButton` → `IconButton` (2×-es szövegskálázásnál 54 px-es
  AppBar-túlcsordulást mértem — mérve ELŐTTI hiba, javítva, L517).
- **`safety_relationships_screen.dart`** — `CommunityThemeScope` + `SsButton`
  az Unblock/Unmute akción, egyébként változatlan (már teljesen
  lokalizált volt).

### A KÉT kötelező valódi-sértés próba (§6.1) — MÉRT kimenet

1. **A3** — a `club_detail_screen.dart` „a küszöb alatt" ágát ideiglenesen
   `Text(club.name)`-re cseréltem (a privát klub nevét egy nem-tag nézetben
   megjelenítve). `private_club_leakage_test.dart` „the private club name…"
   cellája **PIROSRA VÁLTOTT** (`Found 1 widget with text "Secret Blues
   Club"` — várt: 0). Visszaállítva, a teszt újra zöld.
2. **A10 (`hu`-cella)** — a `club_list_screen.dart` `communityClubVisibilityLabel`
   `private` ágát ideiglenesen a beégetett `'Private'` angol literálra
   cseréltem (megkerülve az ARB-lookupot). `private_club_leakage_test.dart`
   „hu cell: …" cellája **PIROSRA VÁLTOTT** (`Found 0 widgets with text
   containing Privát` — az `en`-cella eközben változatlanul zöld maradt,
   tehát az őr a helyes irányban mér). Visszaállítva, a teszt újra zöld.

### Gate

`tools/round-gate.sh` a brief §7 pontos parancssorával (10 útvonal, külön
processz, csonkítatlan kimenet) — lásd a kör-jelzés melletti futtatási
naplót. `test/core/architecture_dependency_test.dart`,
`test/tooling/dio_factory_guard_test.dart`,
`test/tooling/preferences_plugin_import_guard_test.dart`,
`test/tooling/route_literal_guard_test.dart`, `test/ui/ui_inventory_test.dart`
mind zöld (a leltár-bázisvonal változatlan 94 — nincs új `*_screen.dart`).

### A9 — golden

Mind a hét képernyő, 412×915 compact portrait ÉS `textScaleFactor 2.0`,
`tools/golden-x86.sh record` majd `check` is zöld (14/14 teszt, exit 0
mindkét lépésben). A `check` futás megerősítette a nulla toleranciájú
determinizmust. Két, kör ELŐTTI (E13-R24/E09-R20 örökölt) `RenderFlex`
túlcsordulást a `textScaler 2.0` keret fogott meg és lett javítva (lásd
fent) — egyik sem került bázisvonalként rögzítésre.

### Nyitott pontok / kör utáni megjegyzések

- A „bejelentés" (report) biztonsági akció (A6 harmadik tagja, a tiltás/
  némítás mellett) NEM lett bedrótozva a kihívás- és klub-felületekre: a
  `showReportContentSheet` (`presentation/dialogs/report_content_sheet.dart`)
  MÁR migrált és VÁLTOZATLANUL hívható, de nincs hozzá production
  `ReportRepository`-implementáció a fán (a `data/` réteg TILOS zóna ebben a
  körben), ezért a valódi hálózati bedrótozás egy jövőbeli kör feladata. A
  tiltás/némítás (block/mute) viszont MINDKÉT felületről (kihívás-sor
  akció-lap, klub-tagkezelés) elérhető, ugyanazon `socialGraphRepositoryProvider`
  révén, mint a Biztonsági központ.
- A klub-részlet „Feed" / „Challenges" tab-jainak screen-local providerei
  (`clubFeedProvider`, `clubPinnedProvider`, `clubChallengesProvider`) MÁR
  a Kör 25 (E09-R25) óta `UnimplementedError`-t dobnak production módban — ez
  a kör nem bővítette és nem oldotta fel ezt (a `data/` réteg TILOS zóna),
  csak a golden- és a pinnelt teszt felől override-olta őket.

### Javító kör (`docs/reviews/e13-r34-review.md` §3) — leletenkénti zárás

**MAJOR-1 (A3 — a klub-LISTA előnézete szivárogtatta a privát klub nevét).**
`club_list_screen.dart` `_Body.build`-je most ugyanazt a predikátumot
alkalmazza, mint a `club_detail_screen.dart` küszöbe
(`myRole == null && visibility == private`): egy ilyen klub sor teljesen
kimarad a renderelt listából — sem a `Text`, sem a `Semantics` ág nem éri el
a nevét. Negyedik A3-cellapár került a `private_club_leakage_test.dart`-ba
(„the club-LIST preview never leaks…"), külön cellával a látható szövegre és
külön a `Semantics` labelre — a security-reviewer próbája pontosan ezt a két
csatornát mérte szivárgónak.
*Valódi-sértés próba:* a szűrést ideiglenesen kivettem (`final items =
page.items;`) → mindkét új cella **PIROSRA VÁLTOTT** (`Found 1 widget with
text "Secret Blues Club"` ill. `Found 1 widget with a semantics label
matching … "Secret Blues Club. Private · 5 members."`). Visszaállítva, a
teljes `private_club_leakage_test.dart` (15 cella) újra zöld.

**MAJOR-2 (A6/A8 — a tiltás/némítás némán bukott hálózati hibán).**
`club_member_management_screen.dart::_MemberRow._blockOrMute` és
`community_challenges_screen.dart::_ChallengeRow._blockOrMuteAuthor` most
`try { … } on AppFailure catch (failure) { … }`-ba kerültek, a
`safety_relationships_screen.dart` mintáját követve (SnackBar a
`ScaffoldMessenger`-en, `context.mounted` őrrel). A challenges-lapon a
`sheetContext` helyett a SOR SAJÁT `context`-je adja a `ScaffoldMessenger`-t
(a `sheetContext` a `pop()` után halott) — a `_formatFailure` mindkét
fájlban top-level függvénnyé lett (a klub-lapon új, a kihívás-lapon az
`_ErrorView`-ból kiemelve), hogy a hívó akció és a lista-hiba ugyanazt a
lokalizált szótárat használja. Két ÚJ ARB-kulcscsoport: `communityClubManageError{Network,SessionExpired,Forbidden,InvalidInput}`
(a klub-lapnak korábban nem volt kód-alapú hibaformázása).
Két DOBÓ-fake cella került a `private_club_leakage_test.dart`-ba (mindkét
felületre), amik `NetworkFailure`-t dobó `SocialGraphRepository`-val
igazolják, hogy (a) a hiba NEM szabadul el kezeletlenül, és (b) egy
`SnackBar` látszik.
*Valódi-sértés próba (mindkét felület, külön-külön):* a `catch`-et
ideiglenesen kivettem → mindkét új cella **PIROSRA VÁLTOTT** — a klub-lapon
`Found 0 widgets with type "SnackBar"` (a `NetworkFailure` kezeletlen
aszinkron hibaként futott le a teszt-bindingen), a kihívás-lapon ugyanez.
Mindkét `catch` visszaállítva, a teljes suite újra zöld.

**MINOR-1 (A10 — beégetett angol `Semantics` szöveg).**
`community_challenges_screen.dart:413` `semanticLabel: 'Verified'` →
`localizations.communityChallengeResultVerifiedIcon` (ARB: en „Verified",
hu „Ellenőrizve"); `club_detail_screen.dart:415` `'Role: $roleLabel'` →
`localizations.communityClubDetailRoleSemanticLabel(roleLabel)` (ARB
sablon `{role}` placeholderrel, en „Role: {role}", hu „Szerep: {role}").
Négy ÚJ A10-cella a `private_club_leakage_test.dart`-ba
(„the Semantics channel also localizes"), `tester.ensureSemantics()` +
`find.bySemanticsLabel(...)` — mindkét kulcsra en/hu pár, a meglévő
falszifikációs minta szerint (a saját nyelv jelen van, az ELLENKEZŐ nyelv
literálja hiányzik).

**ARB regenerálás.** `dart run tool/gen_l10n_segments.dart --write` +
`flutter gen-l10n` — mindkét lépés hiba nélkül, az `[15] l10n` gate-lépés
zöld.

**Golden.** Egyik javítás sem érintette a golden-fixture RENDERELT
felületét: a `club_list_screen.dart` fixture második klubja `myRole:
ClubRole.member` (nem a küszöb alatt van, tehát a szűrés nem dobja ki), a
másik két lelet kizárólag `Semantics`-csatornát / hibaágat érint (a golden
pixel-only). `tools/golden-x86.sh check` a meglévő PNG-kkel **14/14 ZÖLD**
maradt — nem kellett újra felvenni.

**Záró gate.** `tools/round-gate.sh` a brief §7 pontos 10-útvonalas
parancssorával — mind a **15/15 lépés ZÖLD** a javítások után (beleértve a
3 új falszifikációs próbát tartalmazó `private_club_leakage_test.dart`
teljes 15 cellás futását és a `presentation/` teljes suite-ot, amiben a
`club_detail_screen_test.dart` és a `community_challenges_test.dart` is
benne van).

## 11. Review — a Claude tölti ki
