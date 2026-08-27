# E13-R33 — Community profil, feed, keresés és poszt UI

- **Státusz:** READY (pre-flight elvégezve 2026-08-27, `main @ d2c96253` — lásd §0.0.B;
  előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 33
- **Kör-azonosító:** `E13-R33`
- **Branch:** `<motor>/e13-r33-community-feed-and-posts`
- **Előfeltétel:** `E13-R32` merge-elve (gamifikáció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0291`](../adr/0291-community-is-optional-and-private-by-default.md)
  — **MÁR MERGE-ELVE (`5b32bd8e`, 2026-08-15): a kör ADR-t NEM ír, a `docs/adr/`
  TILOS zóna, módosítása H1.** Lásd §0.0.B/B2.

> ✅ **Pre-flight ELVÉGEZVE (2026-08-27, orchestrátor).** A brief fejléce a
> TÉNYLEGES közösségi domain és a poszt-küldés idempotencia-kulcsának mérését
> írta elő: **mindkettő a fán van** — a kulcsot a `PostComposerController`
> generálja EGYSZER és minden további mentésnél ÚJRAHASZNÁLJA
> (`post_composer_controller.dart:352–366`), a felület sosem generál újat. A
> mért típusok, sorszámok és a belőlük következő kötelező mércék a §0.0.B-ben.
> Az `allowed_paths` a MÉRT `presentation/` rétegre mutat (B1) — a brief
> eredeti `profile/`, `feed/`, `posts/` előtagjai a fán NEM léteznek.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/presentation/screens/bookmarks_screen.dart",
  "lib/features/community/presentation/screens/comments_screen.dart",
  "lib/features/community/presentation/screens/community_gate_screen.dart",
  "lib/features/community/presentation/screens/community_search_screen.dart",
  "lib/features/community/presentation/screens/edit_profile_screen.dart",
  "lib/features/community/presentation/screens/followers_screen.dart",
  "lib/features/community/presentation/screens/following_feed_screen.dart",
  "lib/features/community/presentation/screens/post_composer_screen.dart",
  "lib/features/community/presentation/widgets/",
  "lib/features/community/presentation/dialogs/",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/community/community_gate_test.dart",
  "test/features/community/composer_audience_test.dart",
  "test/features/community/offline_publish_retry_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/features/community/presentation/comments_screen_test.dart",
  "test/features/community/presentation/community_gate_test.dart",
  "test/features/community/presentation/community_media_player_test.dart",
  "test/features/community/presentation/community_search_test.dart",
  "test/features/community/presentation/following_feed_test.dart",
  "test/features/community/presentation/profile_onboarding_test.dart",
  "test/features/community/presentation/report_content_sheet_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r33-community-feed-and-posts.md",
]
gate_tests = [
  "test/features/community/community_gate_test.dart",
  "test/features/community/composer_audience_test.dart",
  "test/features/community/offline_publish_retry_test.dart",
  "test/features/community/block_mute_test.dart",
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

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a közösségi feed IDEGEN felhasználók tartalmát rendereli — prompt-injection és megbízhatatlan-tartalom felület.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/community/profile/`, `lib/features/community/feed/`, `lib/features/community/posts/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

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
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/community/feed/`, `lib/features/community/posts/`, `lib/features/community/profile/` könyvtár-előtag
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

## 0.0.B — PRE-FLIGHT MÉRÉS, 2026-08-27 (`main @ d2c96253`, orchestrátor Claude)

Az alábbi leletek a kör INDÍTÁSA előtt, a fán MÉRVE keletkeztek. A `brief-lint`
`S13` lelete a B1-ben oldódik fel; a többi a §1.1 két kötelező mérési szabálya
(elérhetetlen cél-státusz, erőforrás-tulajdonlás) és a merge-elt precedens
ütköztetése.

**Visszakeresett előzmény** (ADR 0312, `tools/knowledge-rag.mjs`, szűkítve →
teljes korpusz): [L497](../LESSONS.md#l497) (nem létező `allowed_paths`
KÖNYVTÁR-előtag — ez a kör lelete is), [L478](../LESSONS.md#l478) (a pre-flight
csak SZŰKÍTHET, a tágítás H3), [L516](../LESSONS.md#l516) (**az E13-R32 tegnapi
leckéje**: a szomszéd kör §7 gate-sorának öröklése némán ROSSZ gépet mérő
golden-kaput telepít), [L493](../LESSONS.md#l493)/[L486](../LESSONS.md#l486) +
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) (golden
CSAK x86-on), [L397](../LESSONS.md#l397)/[L377](../LESSONS.md#l377) (a
`ui_inventory` egzakt bázisvonala CI-only lelet), [E13-R28/H3
heal-status](../execution/) (a fogyasztót megállító határszabály feloldása a
szolgáltató barreljében van), [ADR 0273](../adr/0273-design-system-token-source-of-truth.md)
(a design system EGYETLEN belépője a `public.dart`; belső fájl importja kívülről
tilos — ez a kör tényleges munkája, lásd B4).

### B1 — a három `allowed_paths` előtag a fán NEM létezik → a MÉRT `presentation/` rétegre mutatnak (`S13` feloldva)

Mérve: `find lib/features/community -type f` → a feature a Epic-9 által
lefektetett **réteges** szerkezetben él (`application/`, `data/`, `domain/`,
`presentation/`); `profile/`, `feed/`, `posts/` gyerek **nincs**. A három
előtag tehát NULLA verziókövetett fájlt fedett — a lista néma ellentmondás volt.

Ezt a `docs/execution/pipeline-queue.tsv` Epic-9 blokkja **előre kimondta**
(2026-08-22): *„az `E13-R33` `allowed_paths`-a ma egy egyszerűsített
`lib/features/community/{profile,feed,posts}/` elrendezést feltételez, nem az
itt lefektetett `domain/application/data/presentation` réteges szerkezetet"* —
és a feloldást kifejezetten a kör SAJÁT pre-flightjára bízta.

**A feloldás nem a `presentation/` fa egészének felvétele**, hanem a §3
scope-jához tartozó, TÉTELESEN felsorolt nyolc képernyő + a két megosztott
alkönyvtár. A kimaradó öt képernyő a **szomszéd E13-R34** köré tartozik
(`clubs/*`, `community_challenges_screen.dart`, `leaderboard_screen.dart`,
`safety_relationships_screen.dart`, `community_notifications_screen.dart`), és
szándékosan NEM kerül erre a listára — a két kör fájlhalmaza így diszjunkt marad.

| SDD | Route | MÉRT fájl (a listán) |
|---|---|---|
| UI-53 | `/profile/community/setup` | `community_gate_screen.dart` + `edit_profile_screen.dart` |
| UI-54 | `/community` | `following_feed_screen.dart` |
| UI-55 | `/community/search` | `community_search_screen.dart` |
| UI-56 | `/community/users/:userId` | `followers_screen.dart` + `bookmarks_screen.dart` (lásd B9) |
| UI-57 | `/community/posts/new` | `post_composer_screen.dart` |
| UI-58 | `/community/posts/:postId` | `comments_screen.dart` |

A `widgets/` (`feed_card_registry.dart`, `reaction_bar.dart`,
`community_media_player.dart`) és a `dialogs/` (`report_content_sheet.dart`)
KÖNYVTÁR-előtagként kerül fel, mert a migráció közös komponenst (pl. egy
`CommunityThemeScope`) hozhat létre — a merge-elt E13-R32 precedens is így tett
(`GamificationThemeScope`).

### B2 — a kiosztott ADR `0291` MÁR MERGE-ELVE VAN: a kör ADR-t NEM ír

Mérve: `docs/adr/0291-community-is-optional-and-private-by-default.md` a fán
van, `git log` → `5b32bd8e` („docs(ch13): E13-R30..R36 briefek + ADR 0288-0292",
2026-08-15). A `docs/adr/` tilos zóna; módosítása **H1**.

Ez a sávon a **tizenhatodik** ADR nélküli kör egymás után (E13-R17…R33). Új
döntés nincs, ezért `tools/round-slots.py reserve-adr` **nem futott** — nem
égetünk el egy szabad sorszámot olyan körre, amelyik nem ír ADR-t. A §5 kötött
döntései a MÁR MERGE-ELT ADR 0291 §1–§6-jával szó szerint egyeznek.

### B3 — a §0.0/R2 „nincs ilyen" MÉRÉSE ÉRVÉNYTELEN VOLT: hét élő widget-teszt áll a kör képernyőire (FELVÉVE)

A batch pre-flight (2026-08-25) az R2 cellát a **nem létező** `profile/`,
`feed/`, `posts/` előtagok ellen mérte, ezért „nincs ilyen"-t írt. A MÉRT
`presentation/` rétegen viszont hét ma zöld widget-teszt áll közvetlenül a kör
képernyőire (`grep -rln "features/community/presentation" test/`):

| Teszt | Melyik listás képernyőt pinneli |
|---|---|
| `presentation/community_gate_test.dart` | `community_gate_screen.dart` |
| `presentation/profile_onboarding_test.dart` | `edit_profile_screen.dart` |
| `presentation/following_feed_test.dart` | `following_feed_screen.dart` |
| `presentation/community_search_test.dart` | `community_search_screen.dart` |
| `presentation/comments_screen_test.dart` | `comments_screen.dart` |
| `presentation/report_content_sheet_test.dart` | `dialogs/report_content_sheet.dart` |
| `presentation/community_media_player_test.dart` | `widgets/community_media_player.dart` |

Ez pontosan az a halt-osztály (`blocked`), amit az R2 el akart kerülni, csak a
rossz fán mérve. A hét fájl ezért FELKERÜL az `allowed_paths`-ra.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS**.

A maradék hat presentation-teszt (`clubs/*`, `community_challenges_test.dart`,
`community_notifications_test.dart`, `leaderboard_screen_test.dart`,
`screens/safety_relationships_screen_test.dart`) **NEM** kerül a listára — az
E13-R34 fájlhalmaza. A `gate_tests` viszont a TELJES
`test/features/community/presentation/` könyvtárat futtatja, tehát ha a kör
diffje mégis elmozdítaná őket, az a kör SAJÁT kapujában bukik, nem a CI-ban.

### B4 — a nyolc képernyőnek NULLA design-system importja van: EZ a kör tényleges munkája

```
grep -rn "design_system" lib/features/community/presentation/   → 0 találat
```

A migráció tehát valódi: a képernyők ma közvetlenül `material.dart`-ot
használnak. A cél az [ADR 0273 §1](../adr/0273-design-system-token-source-of-truth.md)
szerinti EGYETLEN belépő — `package:strumsight/core/design_system/public.dart`
—, a `foundations/**` közvetlen importja **TILOS**, és ezt a `gate_tests`-ben
futó `test/core/architecture_dependency_test.dart` méri (S12). Mért precedens
ugyanerre a hibaosztályra: **E13-R16/F8**, 11 sértés, javító kör árán.

### B5 — §1.1/1. szabály: a `private` alapértelmezett közönség a fán ELÉRHETETLEN — a MÉRT alapérték `followers`

Nem az átmenettáblát, hanem a **tényleges inputot** mértem:

| Felület | MÉRT fájl:sor | Alapérték |
|---|---|---|
| poszt-szerkesztő | `post_composer_controller.dart:87` | `CommunityAudience.followers` |
| profil-láthatóság | `edit_profile_screen.dart:89` | `ProfileVisibility.followers` |
| szerver-oldali profil-default | `relationship_repository_impl.dart:468` | `ProfileVisibility.followers` |

A `private` alapértéket tehát **egyetlen input sem produkálja**, és az
átállítása egy LEZÁRT kör (E09-R12 szerkesztő, E09-R04 láthatóság) viselkedését
változtatná meg — az **H2**.

**A kötő norma a MERGE-ELT [ADR 0291 §2](../adr/0291-community-is-optional-and-private-by-default.md):**
*„Az alapértelmezett közönség **nem nyilvános** — sem a profil, sem a poszt."*
A `followers` ezt kielégíti. A brief §6.1 első cellája („privát — ez az
alapérték") SZIGORÚBB volt a merge-elt ADR-nél és a fánál is; a §6.1
cellahármasa ezért a mért értékekre mutat (lásd az ott átírt táblát).

**A mérce NEM lazul:** az A2 kötő predikátuma
`audience != CommunityAudience.public` **ÉS** `visibility != ProfileVisibility.public`,
azaz pontosan az, amit az ADR 0291 §2 tilt és a §9 kockázata leír. A
valódi-sértés próba (§6.1) ettől változatlanul működik: a `public` alapértékre
állítás az A2-t PIROSRA váltja.

### B6 — §1.1/2. szabály (erőforrás-tulajdonlás): az idempotencia-kulcsot az `application/` réteg birtokolja, a felület sosem generál újat

Mérve a TÉNYLEGES hívási láncon, nem réteg-diagramból:

| Réteg | Mért artefaktum | Szerep |
|---|---|---|
| `application/controllers/post_composer_controller.dart:352–366` | `existingKey = current.idempotencyKey` → ha van, ÚJRAHASZNÁLJA | a kulcs EGYSZER születik |
| ugyanott `:367–373` | `CommunityDraft.fresh(...)` | az EGYETLEN kulcs-generáló hívás a poszt-úton |
| `application/outbox/community_outbox.dart:318–330` | `_pending.where((r) => r.idempotencyKey == key)` | azonos kulcsú rekord → **nem** kerül be másodszor |
| `application/outbox/community_outbox.dart:366–374` | `acknowledged.add(record.idempotencyKey)` | a drain kulcs szerint nyugtáz |

`grep -rn "idempotencyKey" lib/features/community/presentation/` → **12
találat, mind a listán KÍVÜLI, E13-R34-es képernyőkön** (`clubs/*`,
`safety_relationships_screen.dart`) + a `dialogs/report_content_sheet.dart`, és
**egyik sem rendereli** a kulcsot: mindegyik átadja egy repository-hívásnak.

**Ebből a kör KÖTELEZŐ mércéje:**

- a nyolc listás képernyő a kulcsot **nem generálja és nem rendereli** — az
  újrapróbálkozás a `PostComposerController` MÁR MEGLÉVŐ kulcsával megy;
- az **A6** cellája ezért KÉT publikálási kísérlet UGYANAZZAL a
  `PostComposerState.idempotencyKey`-vel, és **pontosan 1** függő rekord az
  outboxban — falszifikációs őr az „új kulcs minden gombnyomásra" hibára;
- a kulcs a `Text`/`Semantics` fába nem kerülhet (ADR 0291 §5, §3 tilalom).

### B7 — A3/A4: a megosztás tartalmát a `SharePreview` ÖT opt-in kapcsolója írja le; a nyers hang ABSZENCIÁVAL van kizárva

Mérve — `lib/features/community/domain/entities/share_artifact.dart:839–846`:

```dart
const SharePreview({
  this.includeChordTimeline = false,
  this.includeStrumPattern  = false,
  this.includeTempo         = false,
  this.includeStreakDays    = false,
  this.includeBestScore     = false,
});
```

Mind az öt **alapból `false`**, és a típusban **nincs** nyers hangra vagy
hullámformára mutató mező. A `practice_share_mapper.dart:14` doc-commentje ezt
szó szerint kimondja: *„raw audio / waveform / landmark" row is enforced by
ABSENCE*.

**Következmény a mércére:**

- **A3** = a szerkesztő tételesen felsorolja ezt az ÖT sort, és a felirat a
  tényleges `SharePreview` mezőértékből jön (nem beégetett szövegből);
- **A4** NEM kapcsoló-teszt, hanem **strukturális absztinencia-cella**: a
  `SharePreview` mezőkészlete pontosan az öt fenti, és a szerkesztő
  alapállapotában mind `false` — azaz alapból SEMMI nem megy ki. Ha egy jövőbeli
  kör nyers-hang mezőt vezetne be, ez a cella pirosra vált.

### B8 — A7: a `ModerationState.removed` LÉTEZŐ enum-érték, a helyőrző a felület dolga

`lib/features/community/domain/entities/moderation_state.dart:20–24` →
`enum ModerationState { …, removed('removed'), … }`, a doc-comment szerint a
backend read-path ezt használja placeholder-triggerként. A helyőrző tehát
NEM új domain-fogalom: a kör dolga, hogy a `comments_screen.dart` és a
`following_feed_screen.dart` a `removed` állapotot LÁTHATÓ helyőrzővel
rendelje, ne kihagyással. Az **A7** ezt méri.

### B9 — a kör NEM hoz létre új képernyőt és NEM nyúl a routerhez; `ui_inventory` bázisvonal = 94

Mérve:

- `find lib/features -name '*_screen.dart' | wc -l` → **94**;
  `test/ui/ui_inventory_test.dart:22` → `hasLength(94)` — a kettő EGYEZIK;
- `grep -n "community" lib/app/routing/app_router.dart` → **0 találat**: a
  közösségi képernyők ma NINCSENEK a routerben, egymásból `Navigator.push`-sal
  érhetők el (`community_gate_screen.dart:120,230`);
- `grep -rln "features/community/presentation" test/app/` → **0 találat**: az
  `app_router_test.dart` egyetlen közösségi képernyő-típust sem pinnel (az
  E13-R32-vel ellentétben — ezért NEM kerül erre a listára).

**Ebből két kötelező következmény:**

1. **A router TILOS zóna** (`lib/app/routing/**` nincs az `allowed_paths`-on) —
   egy új, csak route-tal elérhető képernyő ezért H3 lenne. A **UI-56** felülete
   a MEGLÉVŐ `followers_screen.dart` / `bookmarks_screen.dart` képernyőkön és a
   feed kártyáiról nyíló `Navigator.push`-on áll elő; új `*_screen.dart` fájl
   **nem szükséges**, és az alap-eset a **változatlan 94**.
2. Ha a kör mégis új `*_screen.dart`-ot hozna a listás könyvtárak alá, a
   `test/ui/ui_inventory_test.dart` `hasLength(...)` értékét UGYANABBAN a
   commitban a tényleges számra kell emelni (§0.0/R4). A jogosultság PONTOSAN a
   szám emelése; kerülőút (átnevezés, a `tool/ui_inventory.dart` lazítása)
   TILOS.

### B10 — l10n: a `community` fragmentum LÉTEZIK (173 kulcs, en/hu paritásban), új fragmentum NEM készül

`lib/l10n/features/community_{en,hu}.arb` → **173–173** kulcs, azaz paritásban.
A kör szövegei ide mennek, majd `dart run tool/gen_l10n_segments.dart --write`
regenerálja a `lib/l10n/app_{en,hu}.arb` aggregátumot — az aggregátumot **kézzel
írni TILOS** (§0.0/R1). A `test/l10n/arb_parity_test.dart` beégetett
szegmens-listáját nem kell bővíteni.

### B11 — a golden-útvonal NEM kerül a lokális `gate_tests`-be (L516, ADR 0426)

Az E13-R32 **tegnap mérte ki** ([L516](../LESSONS.md#l516)), hogy a szomszéd kör
§7 gate-sorának öröklése némán olyan kaput telepít, ami ezen az aarch64 boxon a
ROSSZ gépet méri: a `golden` cellák lokálisan pirosak, x86-on zöldek. A brief
eredeti `gate_tests` tömbje és §7 sora pontosan ezt az öröklést tartalmazta —
**mindkettőből KIKERÜLT** a golden-útvonal, a rögzítés/ellenőrzés pedig a
`tools/golden-x86.sh`-ra vált (§7).

**A mérce NEM lazul:** a golden-cellákat továbbra is KETTŐ méri — lokálisan a
`tools/golden-x86.sh check` (kötelező, a §7 alatti parancspár), a kapuban pedig
az exact-SHA `full-gate.yml` teljes suite-ja, mindkettő x86_64-en, változatlan
nulla toleranciájú komparátorral. Egy cella sincs törölve vagy `skip`-elve.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-53–UI-58 **opcionális** közösségi felületei: belépő, feed, felfedezés,
profil, szerkesztő és beszélgetés (SDD Ch13 Kör 33).

## 2. Jelenlegi állapot — mért tények

- A közösségi funkció **opcionális**: a termék magja nélküle is teljes.
- Az R13 megerősítés-rendszere és az R12 provenance-badge-ei készen állnak.
- A gyakorlási adat a felhasználó legszemélyesebb tartalma — a megosztása
  soha nem lehet implicit.

## 3. Scope

**Benne van:** a közösségi belépő és a nyilvános profil beállítása
**alapból priváttal** · a feed tartalmi / offline / eltávolított / moderációs
állapotai · keresés és felfedezés, nyilvános profil kapcsolat- és
biztonsági akcióival · a poszt-szerkesztő közönség-, csatolmány-,
gyakorlás-megosztás és offline sor felülete · a poszt részletnézete, reakciók,
kommentek, szál-állapotok · a tiltás/némítás **azonnali helyi szűrése**.

**NINCS benne (tilos):** a moderációs vagy a backend-logika módosítása · az
idempotencia-kulcs megjelenítése a felületen · a közösség kötelezővé tétele ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `presentation/screens/community_gate_screen.dart` + `edit_profile_screen.dart` | UI-53 belépő és profil-beállítás (§0.0.B/B1) |
| `presentation/screens/following_feed_screen.dart` | UI-54 feed |
| `presentation/screens/community_search_screen.dart` | UI-55 keresés és felfedezés |
| `presentation/screens/followers_screen.dart` + `bookmarks_screen.dart` | UI-56 nyilvános profil felülete (§0.0.B/B9 — új képernyő NEM kell) |
| `presentation/screens/post_composer_screen.dart` | UI-57 szerkesztő |
| `presentation/screens/comments_screen.dart` | UI-58 poszt-részlet és beszélgetés |
| `presentation/widgets/` · `presentation/dialogs/` | a migráció közös komponensei (feed-kártya, reakciósáv, médialejátszó, jelentés-lap) |
| `lib/l10n/features/community_{en,hu}.arb` | **FORRÁS** — a közösségi szövegek (`community` MÁR migrált feature, 173 kulcs, §0.0.B/B10) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/community/*_test.dart` (4) | a §6 cellái |
| `test/features/community/presentation/*_test.dart` (7) | a kör képernyőire ma zölden álló widget-tesztek, az ÚJ widgetekre ráállítva (§0.0.B/B3) |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4, §0.0.B/B9) |
| `docs/rounds/e13-r33-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a fenti tételes listán kívül — **ideértve a
`community/` `application/`, `data/`, `domain/` rétegét és az E13-R34 öt
képernyőjét** (`clubs/*`, `community_challenges_screen.dart`,
`leaderboard_screen.dart`, `safety_relationships_screen.dart`,
`community_notifications_screen.dart`) · `lib/app/routing/**` (§0.0.B/B9) ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0291)

### 5.1 A termék magja közösség NÉLKÜL is teljes

Semmilyen alapfunkció nem követel fiókot vagy nyilvános profilt. A belépő
elutasítása nem zár ki semmit.

### 5.2 Az alapértelmezett közönség NEM nyilvános

Sem a profil, sem a poszt. A nyilvánosságot a felhasználó választja, tudatosan.

**NEM elfogadható gyengítés:** a „Nyilvános" előre kiválasztott közönség „mert
úgyis azt akarják". Ez visszavonhatatlan megosztást eredményez félrekattintásból.

### 5.3 A nyers gyakorlási adat NEM megy implicit módon

Ha egy poszt gyakorlási eredményt oszt meg, a felület megmutatja, **pontosan
mi** kerül ki, és a nyers hang alapból nem tartozik bele.

### 5.4 A tiltás AZONNAL hat, helyben is

Nem kell megvárni a szerver megerősítését ahhoz, hogy a tartalom eltűnjön a
felhasználó képernyőjéről.

### 5.5 Az újrapróbálkozás NEM duplikál posztot vagy kommentet

Az offline sor idempotencia-kulcsot használ. A kulcs a **transzportban** él, a
felületen nem jelenik meg.

**NEM elfogadható gyengítés:** „a felhasználó úgyis látja, ha kétszer ment el".
Egy duplikált poszt nyilvános és kínos, egy duplikált komment zajos.

### 5.6 Az eltávolított tartalom HELYŐRZŐT kap

Nem tűnik el némán a szálból — a beszélgetés érthető marad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A termék magja közösség nélkül teljesen működik | `community_gate_test.dart` |
| A2 | Az alapértelmezett közönség nem nyilvános (profil és poszt) | `composer_audience_test.dart` |
| A3 | A gyakorlás-megosztás megmutatja, pontosan mi kerül ki | ugyanott |
| A4 | A nyers hang alapból nem része a megosztásnak | ugyanott |
| A5 | A tiltás/némítás azonnal, helyben is hat | `block_mute_test.dart` |
| A6 | Az újrapróbálkozás nem duplikál posztot vagy kommentet | `offline_publish_retry_test.dart` |
| A7 | Az eltávolított tartalom helyőrzőt kap | `community_gate_test.dart` |
| A8 | A felhasználónév-validáció hibás bevitelt nem enged tovább | ugyanott |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r33_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A „Nyilvános" előre kiválasztva | **A2** |
| A gyakorlás-megosztás nem sorolja fel a tartalmat | **A3** |
| A nyers hang alapból csatolva | **A4** |
| A tiltás csak szerver-válasz után hat | **A5** |
| Az offline sor kulcs nélkül próbálkozik újra | **A6** |
| Az eltávolított komment némán eltűnik | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A közönség-alapérték három kötelező cellája** (a küszöb: a láthatóság szintje;
a MÉRT alapérték `followers`, NEM `private` — §0.0.B/B5, a kötő norma az
[ADR 0291 §2](../adr/0291-community-is-optional-and-private-by-default.md)
„nem nyilvános" predikátuma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | új felhasználó, nincs választás | `followers` — **nem nyilvános** |
| rajta (a küszöbön) | a felhasználó „követők" közönséget választ | a választás érvényesül és látszik a küldés előtt |
| a küszöb fölött | a felhasználó „nyilvános"-t választ | **kimondott megerősítés** a visszavonhatatlanságról |

Az első cella MÉRT forrása: `post_composer_controller.dart:87`
(`CommunityAudience.followers`) és `edit_profile_screen.dart:89`
(`ProfileVisibility.followers`).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az
alapértelmezett közönséget nyilvánosra → az **A2** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/community_gate_test.dart test/features/community/composer_audience_test.dart test/features/community/offline_publish_retry_test.dart test/features/community/block_mute_test.dart test/features/community/presentation/ test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r33_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r33_screens_golden_test.dart
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
> hívás. Minta: `test/ui/goldens/e13_r32_screens_golden_test.dart`.

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

> **Review-megjegyzés:** ez a kör nyilvános megosztást és felhasználói adatot
> érint, ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A közösségi belépő — a mag működése nélküle is.
2. A nyilvános profil beállítása, alapból priváttal + a három közönség-cella.
3. A feed állapotai, eltávolított tartalom helyőrzővel.
4. A poszt-szerkesztő: közönség, csatolmány, gyakorlás-megosztás tételesen.
5. Az offline sor idempotencia-kulccsal (a felületen nem látszik).
6. A tiltás/némítás azonnali helyi szűrése.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az előre kiválasztott nyilvános közönség.** Egyetlen félrekattintásból
  visszavonhatatlan megosztás lesz (A2).
- **A duplikált poszt.** Az offline sor legkézenfekvőbb hibája, és nyilvánosan
  látszik (A6).
- **A késleltetett tiltás.** A felhasználó továbbra is látja azt, akitől épp
  védekezni próbál (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
