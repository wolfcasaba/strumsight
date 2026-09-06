# Javítási terv — „minden eddigi fejlesztés fusson az APK-ban" (2026-09-06)

Alap: `docs/ui/remaining-work.md` (2026-09-05) + a mai mérés. Ág:
`ops/community-data-layer`, PR #594. Minden szám futtatott mérésből van.

## A mai mérés: KÉT kompozíciós hibaosztály, nem egy

A `lib/main.dart` felülírás-listája NYOLC providert köt be (config, kv-store,
song repo, song asset repo, tutor ×3, onboarding, diag). A fában viszont
**tizenhét** olyan éles provider van, ami override nélkül dob. A hiányzók:

| Terület | Provider (dob) | Fogyasztó a szállított felületen |
|---|---|---|
| audio_analysis V2 | `analysisRepositoryProvider` | **Library fül** (`UnifiedLibraryScreen` → `libraryV2SourcesProvider`), `LibraryItemDetailScreen` |
| audio_analysis V2 | `analysisCacheProvider`, `analysisMigrationVersionStoreProvider`, `legacyLibraryMigratorProvider` | analysis V2 folyamat |
| song_trainer | `setlistRepositoryProvider` | **Library fül** (`SetlistItemSource`), setlist képernyők |
| song_trainer | `songProgressRepositoryProvider` | dal-haladás |
| community | `feedCacheProvider`, `communityPostRepositoryProvider`, `communityKeyValueStoreProvider`, `communityLoggerProvider` | feed, szerkesztő, kommentek |
| community | `communityClubRepositoryProvider`, `clubFeedProvider`, `clubPinnedProvider`, `clubChallengesProvider` | 3 klub-képernyő |
| community | `communityChallengeResultRepositoryProvider` | kihívás-eredmény beküldés |

A boot-providerek (`*BootProvider`) MEGVANNAK mindegyikhez az analysis és a
song_trainer oldalon — **semmi nem hívja őket** (`grep` a definíciós fájlon
kívül: 0 találat). A Library fül tehát a fejlesztői buildben is a
`StateError`-t kapja a forrás-listája helyett.

## Munkacsomagok (fájl-diszjunkt, párhuzamosan futtatható)

### WP-A — Bootstrap-kompozíció (analysis + song_trainer)
- `lib/main.dart`: a boot-providerekből előállt példányok felülírása
  (`analysisRepository`, `analysisCache`, `analysisMigrationVersionStore`,
  `legacyLibraryMigrator` + `legacyLibrarySupplier` a legacy library
  repóból; `setlistRepository`, `songProgressRepository`). Egy külön
  `lib/app/production_overrides.dart` a lista otthona, hogy tesztelhető legyen.
- Őr: `test/app/production_composition_test.dart` — a bootstrap override-listát
  (temp könyvtárral) betöltve MINDEN „must be overridden" provider felold.
- Mérce: a Library fül valós forrásokat mutat; a cella piros az override
  bármelyikének elhagyásakor.

### WP-B — Community adatréteg + kompozíció
- `feedCacheProvider` → `FeedCache.open(store: keyValueStoreProvider, logger:
  appLoggerProvider, userId: auth user id)`; `communityKeyValueStoreProvider`
  → `keyValueStoreProvider`; `communityLoggerProvider` → `appLoggerProvider`.
- `HttpCommunityPostRepository` (`data/repositories/post_repository_impl.dart`,
  10 metódus a `/community/posts`, `/community/posts/{id}/comments`,
  `/community/comments/{id}`, `/community/posts/{id}/reaction`,
  `/community/bookmarks/{id}` végpontokra) + EGY provider-definíció, a
  controller re-exportál.
- `HttpCommunityClubRepository` (`club_repository_impl.dart`, 9 metódus a
  `/community/clubs*` végpontokra) + a provider átköltözik a data-rétegbe;
  `clubFeedProvider`/`clubPinnedProvider` a feed-repository `clubFeed`/
  `clubPinned` hívására; `clubChallengesProvider` őszinte „nincs végpont".
- `communityChallengeResultRepositoryProvider` → a Kör 21 impl re-exportja.
- Őr: `production_repository_wiring_test.dart` bővítése az összes fenti
  providerre (override nélkül, `Disabled*`/valós példány, sosem kivétel).
- Ismert rés marad: klub-poszt írás (belső `club_id`), `profilePosts`.

### WP-C — Community navigáció
- A kapu `ready` állapota HUB: feed, szerkesztő, klubok, értesítések,
  keresés, könyvjelzők, kihívások, biztonság, profil-szerkesztés.
- Feed-kártya → kommentek (`/community/posts/:id/comments`); feed → szerkesztő
  (FAB); klub-lista → klub-részlet; kihívás → ranglista.
- Új ARB-kulcsok CSAK a `lib/l10n/base/app_{en,hu}.arb`-ban (a
  `lib/l10n/app_*.arb` generált).
- Őr: `community_routing_test.dart` új cellái + a `check_screen_reachability`
  BEJÖVŐ-hivatkozás cellája (a 39 hivatkozatlan útvonal-konstans mérése).

### WP-D — A többi belépési pont (WP-C után, ARB-ütközés miatt)
- `/analysis/capture` az Analyze kezdőlapról; `/practice/generator/weekly`
  és `/privacy` a tervező „ma" képernyőjéről; `SetlistListScreenV2` bekötése.
- A gamification/tutor útvonal-konstansok bejövő hivatkozásainak mérése; ahol
  a hub `Navigator.push`-sal ér el képernyőt, az nem hiba.

### WP-E — „Minden bekapcsolva" build-oldal
- `FeatureFlags.forEnvironment`: `STRUMSIGHT_PREVIEW_ALL` define nem-production
  környezetben bekapcsolja a hardkódolt `false` UI-flageket; `lab_build.json`
  felveszi. Production alapérték változatlan.

### Kész: WP-F — a CI titok-szkenner két teszt-fixture találata jelölve (04e3b44).

## Sorrend és kapu
1. A, B, C párhuzamosan (fájl-diszjunkt) → 2. D, E → 3. `build-apk.yml` +
`lab-apk.yml` zöld → 4. valós-gitár APK-teszt (a felhasználó kapuja).
