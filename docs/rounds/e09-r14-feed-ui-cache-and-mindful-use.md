# E09-R14 — Feed UI, cache és tudatos használat

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 14
- **Kör-azonosító:** `E09-R14`
- **Branch:** `<motor>/e09-r14-feed-ui-cache-and-mindful-use`
- **Előfeltétel:** `E09-R13` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 13 cursor-szerződést és a Kör 10 artifact-típusokat — a card-registry ezekre a MEGLÉVŐ típusokra épül, ismeretlen artifact-típusra fallback-kártyát ad, nem hibázik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-23)

**Kockázat = high, indoklás:** a `risk = "high"` jogos annak
ellenére, hogy egyik `allowed_paths` elem sem tartalmazza szó szerint a
router high-risk-fragmenslistát (`auth, authorization, camera, credential,
crypto, encryption, migration, payment, privacy, secret, share, upload,
vision`) — két, egymástól független termékinvariáns forog kockán: (1) a
lokális feed-cache accountonkénti izolációja (§5.2, A2) egy privacy-osztályú
hiba (egy másik user korábbi feedjének átmeneti megjelenése account-váltás
után klasszikus adat-keveredés, ugyanaz a hibaosztály, mint egy hitelesítési
scope-hiba, csak kliens-oldalon); (2) a §5.1/§13.6 "nincs autoplay, nincs
kötelező végtelen görgetés" SDD-invariáns — ez a brief §6.1 mérce-mátrixa
szerint a legkönnyebben "visszacsúszó" minta, és egy UI-library-alapértelmezés
(automatikus infinite-scroll) csendben felülírhatja explicit kódmódosítás
nélkül is (pl. egy widget default paramétere). Mindkettő UI-rétegbeli, de a
blast radius (minden feed-fogyasztó felhasználó) és a néma-bukás jellege
(a hiba teszt nélkül észrevétlen marad) indokolja a `high` besorolást.

**Visszakeresett előzmények (S8, ADR 0312 §4.9-sorrend szerint):**
- `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "feed UI cache offline mindful use no autoplay infinite scroll"` →
  legjobb releváns találat: **ADR 0406** (Kör 13, `bm25#1 emb#1`)
  "Következmények" szakasza — a mute-szűrés ÚJ helperje kifejezetten "Kör 14
  feed UI/cache"-t nevezi meg mint egy jövőbeli fogyasztót, és a
  `FEED_CURSOR_VERSION` statikus konstans / opaque cursor kezelés a §0.0
  D5-ben leírt szerződés, amit ez a kör OPAQUE-ként kell kezeljen (nem
  dekódolhatja). Nincs korábbi lecke/halt közvetlenül a "no-autoplay" vagy
  "account-scoped cache" témára — ez az ELSŐ kör, ami mindkettőt bevezeti a
  Community modulban; a `SharePreview` "minden flag off by default" mintája
  (Kör 10, `share_artifact.dart` D5) egy analóg, konzervatív-alapérték
  precedens, de nem azonos kérdés.
- `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "user-scoped local cache bounded storage account switch mixing"` →
  nincs közvetlenül releváns lecke/halt a szűkített korpuszon; a legközelebbi
  találat a `docs/execution/` sablon-szakaszaiból jött, tartalmi egyezés
  nélkül.
- Teljes korpuszos kiegészítő lekérdezés (`"feed cache account isolation no
  autoplay infinite scroll Flutter"`) a `lib/features/community/data/local/
  community_draft_store.dart` (Kör 12 — a userId-partitionált storage-key
  minta, ld. lent) és a `lib/features/progress/data/practice_log_repository.dart`
  (a `maxEntries`-bounded `JsonCollectionStore` minta) találatokat hozta —
  mindkettő a §0.0 D1/D2 alatt konkrét mintaként be van építve.
- Ezen felül **nincs releváns előzmény**.

**D1 — A feed-cache a Kör 12 userId-partitionált storage-key mintáját
követi, nem definiál újat.** Grep-elve (`lib/features/community/data/local/
community_draft_store.dart`): a Kör 12 draft-store storage-kulcsa
`'ss.community.drafts.v2.$userId'` alakú — ez az ELSŐ user-id-partitionált
kulcs a repóban (a fájl saját dokumentációja szerint). A Kör 14 feed-cache
kulcsa kövesse ugyanezt a mintát (pl. `'ss.community.feed.v1.<userId>'`),
NEM egy globális, nem-partitionált kulcsot — az A2 acceptance cella
(account-izoláció) pontosan ezt a mintát méri.

**D2 — A "bounded" cache a Kör 7 `PracticeLogRepository.maxEntries` +
`JsonCollectionStore(maxItems: …)` mintáját követi.** Grep-elve
(`lib/features/progress/data/practice_log_repository.dart`): egy dokumentált
`static const int maxEntries` konstans + a store-primitíven átadott
`maxItems` paraméter tartja a dokumentumot korlátos méreten. A konkrét
bound-értéket az implementer választja és a §10-ben dokumentálja — a brief
nem köti meg egy konkrét számhoz, mert ez nem egy mérce-hármassal ellenőrzött
numerikus élérték, hanem egy tervezési paraméter; a szerver oldali
oldalméret-korlát (HANDOFF §6, a Kör 13 backend konstansa) egy FÜGGETLEN,
válaszonkénti korlát, a kliens-cache bound egy FÜGGETLEN, offline-megőrzési
döntés.

**D3 — Erőforrás-tulajdonlás ellenőrzés: nincs a körben lease/lock/handle/
subscription jellegű erőforrás, a §1 "2." pre-flight-szabály N/A.** A kör
egy read-modell (controller + lokális cache + UI) — a `grep -rn "\.acquire("
lib/` ellenőrzés 0 találatot ad a `lib/features/community/` fán, és a kör
nem vezet be újat.

**D4 — "Elérhetetlen cél-státusz" ellenőrzés (§1 "1." szabály): N/A, a
feed-controller állapotgépe ÚJ, nincs meglévő reducer/enum, aminek az
átmenettábláját a kód felülírná.** A brief §3 nyolc állapotot sorol fel
(initial/loading/content/refreshing/paging/offline/error/end) — ezek egyike
sem egy meglévő kódban már létező enum-érték, tehát a §1 mérési szabály
("melyik INPUT produkálja") ezen a körön nem egy meglévő táblát ellenőriz,
hanem az implementer §10 dokumentációjának kell rögzítenie, melyik átmenetet
melyik esemény váltja ki (ez NEM egy előre kimért tény, hanem a kör saját
tervezési döntése — a review ezt fogja ellenőrizni a §6.1 mérce-mátrix
mentén).

**D5 — A `CommunityFeedRepository.followingFeed` kontraktus MEGERŐSÍTVE
grep-pel, a cursor típusa `Object`, nem `String?`.** Grep-elve
(`lib/features/community/domain/repositories/feed_repository.dart`):
`Future<CommunityPage<CommunityPost>> followingFeed({required Object cursor,
required int limit})` — a hívó az ELSŐ laphoz `CursorPage.initial()`-t ad át
(nem `null`-t), a folytatáshoz a `CommunityPage.cursor` mezőt (egy
`CursorPage`) adja vissza a következő híváshoz. A `feed_controller.dart`
ezt a típus-állapotot (initial vs. continued vs. halted-after-request,
`cursor_page.dart`) kezelje, ne egy nyers nullable string cursort — a
Kör 13 backend a wire-formátumot (`<base64url(json)>.<base64url(hmac)>`)
egy `String` mezőben adja, de ezt a Flutter-oldali `CursorPage` már
becsomagolja, a kliens-domain réteg NEM dekódolja (ADR 0406 D4/D5, a fenti
S8 találat).

**D6 — Nincs `feed_repository_impl.dart` és nincs provider-wiring fájl ebben
a körben — ez a brief §4 engedélyezett-listája szerint SZÁNDÉKOS.** A
HANDOFF §6 (E09-R13 hagyatéka) megerősíti: a `feed` router MÉG NINCS
bekötve a `build_community_router`-be, és nincs `feed_repository_impl.dart`
sem. A kör négy ÚJ fájlja (`feed_cache.dart`, `feed_controller.dart`,
`feed_card_registry.dart`, `following_feed_screen.dart`) a
`CommunityFeedRepository` INTERFÉSZÉRE épül — a widget-teszt egy fake/mock
implementációt ad át, a valós HTTP-bekötés egy KÉSŐBBI kör hatásköre
(pontosan úgy, mint a `post_repository_impl.dart` hiánya is örökölt,
dokumentált tartozás). Ez NEM hiányzó scope, hanem a brief §1 cél
("Reszponzív, hozzáférhető feed... — ez a kör az első UI-fogyasztója")
tudatos határa.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/application/controllers/feed_controller.dart",
  "lib/features/community/data/local/feed_cache.dart",
  "lib/features/community/presentation/screens/following_feed_screen.dart",
  "lib/features/community/presentation/widgets/feed_card_registry.dart",
  "test/features/community/presentation/following_feed_test.dart",
  "docs/rounds/e09-r14-feed-ui-cache-and-mindful-use.md",
]
gate_tests = [
  "test/features/community/presentation/following_feed_test.dart"
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Reszponzív, hozzáférhető feed offline cache-sel, végtelen engagement-minták NÉLKÜL — explicit "Továbbiak betöltése", nincs autoplay, van vége (end-of-feed).

## 2. Jelenlegi állapot — mért tények

- A Kör 13 backend feed MA készen áll — ez a kör az első UI-fogyasztója
- A Kör 10 artifact-típusok (hét altípus) MA léteznek — a card-registry ezekre mappelt, ismeretlen típusra fallback-kártyát ad

## 3. Scope

**Benne van:** feed controller state: initial/loading/content/refreshing/paging/offline/error/end · lokális, user-scope-olt, bounded feed cache · pull-to-refresh scroll-pozíció megőrzéssel + új-poszt jelzéssel · explicit "Továbbiak betöltése" (kontrollált pagination) · nincs autoplay; média csak user interactionre indul · end-of-feed nézet + "Gyakorlás indítása" CTA · feed card registry artifact-típusonként, ismeretlen típusra fallback.

**NINCS benne (tilos):**

- Reakció/komment interakció — Kör 15/16.
- Explore feed — külön, jövőbeli feature flag mögötti kör.
- `docs/adr/**`, `tools/**`, `.github/**`, `backend/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/application/controllers/feed_controller.dart` | ÚJ |
| `lib/features/community/data/local/feed_cache.dart` | ÚJ |
| `lib/features/community/presentation/screens/following_feed_screen.dart` | ÚJ |
| `lib/features/community/presentation/widgets/feed_card_registry.dart` | ÚJ |
| `test/features/community/presentation/following_feed_test.dart` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/features/community/domain/**` (csak fogyasztás) · `lib/features/community/application/outbox/**` (Kör 12 lezárt szerződése) · `docs/adr/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs autoplay, nincs kötelező végtelen görgetés

A média user-interactionre indul; a lapozás explicit "Továbbiak betöltése" gombbal vagy egyértelmű kontrollal történik, nem automatikus infinite-scroll triggerrel.

**NEM elfogadható gyengítés:** egy scroll-listener, ami a lista aljához közeledve AUTOMATIKUSAN tölt be több oldalt — ez pontosan a §13.6 SDD-invariáns tiltott mintája.

### 5.2 A cache accountonként izolált, sosem keveredik

A lokális feed-cache kulcsa tartalmazza a profil-azonosítót — account-váltás után a régi cache nem jelenik meg átmenetileg sem.

### 5.3 Ismeretlen artifact-típus fallback-kártyát kap, nem crash-t

A card-registry defenzív: egy jövőbeli, még nem ismert artifact-típus egy generikus "tartalom nem jeleníthető meg" kártyát ad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A feed hálózati hiba esetén sem omlik össze (error state) | `following_feed_test.dart` |
| A2 | A cache nem keveredik accountok között | `following_feed_test.dart` |
| A3 | Nincs automatikus hang- vagy videólejátszás | `following_feed_test.dart` |
| A4 | Duplikált post nem jelenik meg egy session-ben | `following_feed_test.dart` |
| A5 | Ismeretlen artifact-típus fallback-kártyát kap, nem crash-t | `following_feed_test.dart` |
| A6 | Létezik egyértelmű end-of-feed állapot | `following_feed_test.dart` |
| A7 | Pull-to-refresh megőrzi a scroll-pozíciót és jelzi az új posztokat | `following_feed_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A lista automatikusan tölt be a scroll-pozíció alapján | A3 mellett termékinvariáns-sértés (§13.6), review-lelet |
| A cache kulcsa nem tartalmazza a profil-ID-t | A2 |
| Egy videó artifact automatikusan lejátszásra indul betöltéskor | A3 |
| Egy ismeretlen artifact-típus kivételt dob és a feed összeomlik | A5 |
| A pull-to-refresh a lista tetejére ugrik minden alkalommal | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj hozzá egy scroll-listener alapú automatikus lapozást, futtasd a widget-tesztet a "nincs autoplay/autoload" cellára → **A3**-nak PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/following_feed_test.dart
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

1. `feed_cache.dart` — bounded, profil-ID-vel kulcsolt lokális cache.
2. `feed_controller.dart` — a teljes állapotgép.
3. `feed_card_registry.dart` — a hét artifact-típus + fallback.
4. `following_feed_screen.dart` — pull-to-refresh, explicit pagination, end-state, CTA.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az automatikus infinite-scroll kísértése.** Ez a legkönnyebben "visszacsúszó" minta — sok UI-library alapból ezt ajánlja (A3/§13.6).
- **A cache-keveredés account-váltáskor.** Egy másik user korábbi feedje átmenetileg megjelenne (A2).
- **A crash ismeretlen artifact-típuson.** Egy jövőbeli, még be nem vezetett poszt-típus a teljes feedet ledöntené fallback nélkül (A5).

## 10. Implementation handoff

### 10.1 Állapotgép térkép

| Állapot | Melyik esemény váltja ki |
|---|---|
| initial | a `FeedController.build()` hívása (első provider-read a screenről) |
| loading | `load()` meghívása — a cache olvasva, a repository hívás folyamatban |
| content | a repository első oldala sikeresen megérkezett (`_absorbPage`), vagy `loadMore`/`refresh` sikeres lezárult |
| refreshing | `refresh()` meghívása — a lista változatlan, a háttérben új oldalak jönnek (A7) |
| paging | `loadMore()` meghívása — a lista változatlan, a háttérben a következő oldal jön |
| offline | `load`/`refresh` megbukott ÉS a cache-ban volt snapshot — a lista látszik, banner jelzi |
| error | `load`/`refresh`/`loadMore` megbukott ÉS a cache üres — hiba-kártya + retry gomb (A1) |
| end | a repository `CursorPage.haltedAfterRequest()`-ot adott vissza — az "Elérted a feed végét." marker + CTA (A6) |

A controller a nyolc állapotot az `initial` → `loading` → `content` alapgörbén kívül mindenhol explicit őrzi (`if (current.status == loading/refreshing/paging) return;` minden állapotváltó metódus elején), így a duplikált `load`/`refresh`/`loadMore` hívás második alkalma NEM gyújt újabb repository-kérést.

### 10.2 Numerikus bound

| Paraméter | Érték | Indoklás |
|---|---|---|
| feed-cache `maxItems` | **80** | 4 oldalnyi utolsó-látott feed (20-as oldalmérettel = 80) — elég egy offline újra-betöltéshez, és messze a per-document preferencia-plafon alatt marad. A szerveroldali per-page limit (Kör 13, ADR 0406) ettől FÜGGETLEN bound. |
| default page-size | **20** | a Kör 13 szerver-kapuja — a tesztek ezt használják, a `load`/`refresh`/`loadMore` explicit paraméterként is elfogadja. |

### 10.3 Valódi-sértés próba eredménye

A §6.1 szerinti kötelező valódi-sértés próbát lefuttattam: a
`following_feed_screen.dart` `_ContentState`-jéhez ideiglenesen hozzáadtam
egy `_scrollController.addListener(_autoPageOnScroll)` hívást, ahol
`_autoPageOnScroll` a `position.pixels >= maxScrollExtent - 200` esetén
meghívja a `widget.onLoadMore()`-t — pontosan a §5.1 / §13.6 tiltott
minta.

**Próba előtti állapot** (gyári kód, scroll-listener nélkül) —
`flutter test --plain-name "scroll listener"` kimenete:
```
00:00 +0: A3 — no autoplay, no auto-scroll-pagination the rendered widget tree
             never installs a scroll listener that triggers loadMore
00:01 +1: A3 — no autoplay, no auto-scroll-pagination no video / audio widget
             is auto-started — every card is inert on load
00:01 +2: Real-violation probe for A3 a future regression that installs a
             scroll-listener auto-pagination would surface as a second
             repository call after a drag
00:01 +3: All tests passed!
```
A `A3 — no autoplay, no auto-scroll-pagination` cella ZÖLD: a
scroll-listener hiányában a drag nem triggerel `loadMore`-t.

**Próba közbeni állapot** (scroll-listener aktív) — ugyanaz a parancs:
```
00:00 +0: A3 — no autoplay, no auto-scroll-pagination the rendered widget tree
             never installs a scroll listener that triggers loadMore
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: an object with length of <1>
  Actual: [CursorPage:CursorPage.initial, CursorPage:CursorPage.continued(cursor-1)]
   Which: has length of <2>
no auto-scroll-pagination
#4      main.<anonymous closure>.<anonymous closure>
        (file://.../following_feed_test.dart:408:9)
00:01 +0 -1: A3 — no autoplay, no auto-scroll-pagination the rendered widget
              tree never installs a scroll listener that triggers loadMore [E]
  Test failed.
```

A scroll-listenert a próba után ELTÁVOLÍTOTTAM (`initState` és `dispose`
visszaállítva, `_autoPageOnScroll` törölve); a §10 végleges kódjában a
scroll-listener kizárólag a `_rememberScroll` (A7 — scroll-pozíció
megőrzése), nincs auto-paging callback.

A fenti kimenetek a saját, körön belüli futtatásból származnak — a
review-lelet a saját `git diff` alapján ellenőrizheti, hogy a próba
nyoma nincs a végleges kódban.

### 10.4 Lefuttatott parancsok és kimenetük

**Gate (cikk-cakk `flutter analyze && flutter test` lánc NÉLKÜL, a
`tools/round-gate.sh` szétbontva futtatja a `format → analyze → test →
architecture → secrets → l10n` lépéseket):**

```
$ tools/round-gate.sh test/features/community/presentation/following_feed_test.dart
═══ [1] format                                          → ZÖLD
═══ [2] analyze                                         → ZÖLD
═══ [3] test test/features/community/presentation/following_feed_test.dart  → ZÖLD
═══ [4] architecture                                    → ZÖLD
═══ [5] secrets                                         → ZÖLD
═══ [6] l10n                                            → ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test ...following_feed_test.dart                           zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A 13 widget-teszttel lefedett acceptance-cella: A1 × 2, A2 × 2, A3 × 2,
A4 × 2, A5 × 2, A6 × 1, A7 × 1 + 1 valódi-sértés-próba-teszt. Mind a 7
acceptance-cella (A1–A7) ZÖLD, plusz az A3 valódi-sértés próba is ZÖLD.

### 10.5 Fájlszintű scope-check

A `tools/hooks/implementer_guard.py` scope-őr a teljes munkafán
futtatható; a `git diff` a §4 engedélyezett-listán kívüli fájlt NEM
tartalmaz (a 6 új fájl pontosan az allowed_paths hat elemen belül van,
a 2 javító commit csak ezeket a hat fájlt módosítja).

## 11. Review — a Claude tölti ki
