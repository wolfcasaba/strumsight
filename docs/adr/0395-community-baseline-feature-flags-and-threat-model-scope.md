# ADR 0395 — Community baseline: feature flag kill switch mechanizmus, backend readiness placeholder és threat-model scope

- **Státusz:** Elfogadva (E09-R01 pre-flight, 2026-08-22)
- **Kör:** E09-R01 — Community baseline, threat model és feature flag
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 1 (a 32 kör közül az első)
- **Kontext-ADR-ek:** [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)
  (a repó precedense egy teljes építő-epic flag-jeinek hardcode-false
  lezárására — ez az ADR EGY MÁS mechanizmust választ, lásd [Elutasított
  alternatívák]), a `lib/app/config/feature_flags.dart` `accountEnabled`
  dart-define mintája (E01-R03) és a `backend/app/config.py` `tutor_enabled`
  env-var mintája (ADR 0131).
- **Sorszám-jegyzet:** a szám a `tools/round-slots.py reserve-adr --round
  E09-R01` foglalótól jött (Epic 9 batch-tartomány 0395–0419).

## Kontextus

**Mért 2026-08-22-én:**

1. A kör briefje (`docs/rounds/e09-r01-community-baseline-and-feature-flags.md`
   §5.3) már rögzíti a döntés IRÁNYÁT: "A dart-define/env override minta
   megegyezik a meglévő `accountEnabled`/`tutorEnabled` mintával." Ez az ADR
   ezt a döntést formalizálja PONTOS mechanizmus-szinten, mert a brief §5 ezt
   nem specifikálja kódszinten, és a MiniMax implementer mért gyengéje
   (`docs/execution/engine-registry.tsv` — "invariánst lazít") pontosan az
   ilyen alulspecifikált pontokon üt be.
2. **Kritikus korlát, amit a brief `allowed_paths`-a ró ki:** az `accountEnabled`
   ÉLŐ mintája a dart-define-t (`STRUMSIGHT_ACCOUNT`) NEM a
   `feature_flags.dart`-ban olvassa, hanem a `lib/app/config/app_config.dart`
   `rawAccountEnabled = bool.fromEnvironment(accountDefine)` statikus mezőjében,
   és ezt adja át `FeatureFlags.forEnvironment`-nek kötelező paraméterként. Az
   E09-R01 `allowed_paths`-a **nem** tartalmazza `app_config.dart`-ot — tehát
   az implementer NEM követheti szó szerint ezt a huzalozást. A `bool.fromEnvironment`
   viszont nyelvi szinten bárhol const kifejezés, tehát a mechanizmus
   önmagában, `app_config.dart` nélkül is megvalósítható a `feature_flags.dart`
   fájlon belül.
3. **A repó ELLENTÉTES precedense is létezik** (ADR 0220, Epic 6): egy teljes
   építő-epic minden flagje `false` MINDEN környezetben (a `nonProd`
   számítástól is függetlenül), dart-define override NÉLKÜL, amíg egy külön,
   jövőbeli GOV-rollout-kör másképp nem dönt — ott a "dart-define override
   hozzáadása" kifejezetten **elutasított alternatíva** volt. Ez az ADR emiatt
   explicit indoklással tér el ettől a precedenstől (lásd [Elutasított
   alternatívák]).
4. A backend oldalon a `Settings` (`backend/app/config.py`) két mért mintát
   kínál: (a) `diagnostics_enabled`/`apk_download_enabled` — a
   `_default_lab_flags_for_environment` model_validator KÖRNYEZET-alapján
   (nem-prod ⇒ true) állítja be az alapértéket; (b) `tutor_enabled` — sima
   `bool = False` mező, KÖRNYEZETTŐL FÜGGETLENÜL mindig off, amíg egy env-var
   explicit be nem kapcsolja. A brief §5.3 a `tutorEnabled` mintát nevezi meg
   — ez a (b) minta, nem az (a).
5. A brief A5 kritériuma ("A backend `Settings` readiness placeholder-je
   dokumentálja a SQLite-vs-PostgreSQL éles döntést") kódszinten
   alulspecifikált — a `database_url` mező és a mai SQLite-dev-default MÁR
   létezik (`allow_sqlite_in_prod: bool = False`), de nincs semmi, ami a
   Community-modul jövőbeli Postgres-igényét a mai SQLite-állapothoz kötné.

## Döntés

1. **Öt új Flutter flag a `FeatureFlags` osztályon** (`communityEnabled`,
   `communityWritesEnabled`, `communityMediaEnabled`,
   `communityLeaderboardEnabled`, `communityClubsEnabled`): a const
   konstruktorban **opcionális named paraméter, `false` literál alapértékkel**
   — ugyanaz a minta, mint minden `accountEnabled`/`diagnosticsEnabled`/
   `labModeAvailable` UTÁNI flag (pl. `practiceGeneratorEnabled = false`).
   `==`/`hashCode`/`toString()` bővül mind az öttel, a meglévő
   `additionalBits`/`legacyHash` mintát követve (a hashCode-ág NE törje meg a
   régi flag-kombinációk hash-stabilitását — `additionalBits` bővítése a
   helyes hely, nem a `legacyHash` Object.hash-lista).
2. **A dart-define kill switch a `FeatureFlags.forEnvironment` TÖRZSÉBEN
   olvasódik, `app_config.dart` érintése NÉLKÜL** (a [Kontextus] 2. pontja
   miatt kötelező eltérés az `accountEnabled` szó szerinti huzalozásától):
   ```dart
   factory FeatureFlags.forEnvironment(
     AppEnvironment environment, {
     required bool accountEnabled,
   }) {
     final nonProd = environment != AppEnvironment.production;
     const communityEnabled =
         bool.fromEnvironment('STRUMSIGHT_COMMUNITY');
     const communityWritesEnabled =
         bool.fromEnvironment('STRUMSIGHT_COMMUNITY_WRITES');
     const communityMediaEnabled =
         bool.fromEnvironment('STRUMSIGHT_COMMUNITY_MEDIA');
     const communityLeaderboardEnabled =
         bool.fromEnvironment('STRUMSIGHT_COMMUNITY_LEADERBOARD');
     const communityClubsEnabled =
         bool.fromEnvironment('STRUMSIGHT_COMMUNITY_CLUBS');
     return FeatureFlags(
       // ... meglévő mezők változatlanul ...
       communityEnabled: communityEnabled,
       communityWritesEnabled: communityWritesEnabled,
       communityMediaEnabled: communityMediaEnabled,
       communityLeaderboardEnabled: communityLeaderboardEnabled,
       communityClubsEnabled: communityClubsEnabled,
     );
   }
   ```
   `bool.fromEnvironment(name)` `defaultValue` nélkül **mindig `false`**, ha a
   define hiányzik — ez ad production-fail-closedet (A1) explicit
   `--dart-define` nélkül, MINDEN környezetben (dev/lab/prod egyaránt), az
   `accountEnabled` viselkedésének pontos analógjaként. Az "elérhető
   development/lab környezetben" (A2) tehát **operábilis** (a define
   átadásával bekapcsolható), NEM "alapból bekapcsolt" — ugyanúgy, ahogy az
   `accountEnabled` sem `nonProd`-on alapból igaz.
3. **A négy alkapcsoló (`communityWritesEnabled` stb.) SAJÁT, KÜLÖN
   define-nal** — nem `communityEnabled`-ből származtatva. Ez teszi
   mérhetővé az A2 mérce-mátrix sorát ("Csak egy flag kap production-off
   védelmet, a többi négy nem"): mind az öt define egymástól függetlenül,
   explicit `bool.fromEnvironment` hívással olvasódik, egyik sem örökli a
   másik alapértékét.
4. **Backend: öt új `Settings` mező, a `tutor_enabled` mintáját követve**
   (KÖRNYEZETTŐL FÜGGETLEN sima `bool = False`, NEM a
   `_default_lab_flags_for_environment` validator ága):
   ```python
   community_enabled: bool = False
   community_writes_enabled: bool = False
   community_media_enabled: bool = False
   community_leaderboard_enabled: bool = False
   community_clubs_enabled: bool = False
   ```
   Env-override a `pydantic-settings` alap névképzésével (`env_prefix=
   "STRUMSIGHT_"` + mezőnév uppercase): `STRUMSIGHT_COMMUNITY_ENABLED`,
   `STRUMSIGHT_COMMUNITY_WRITES_ENABLED`, `STRUMSIGHT_COMMUNITY_MEDIA_ENABLED`,
   `STRUMSIGHT_COMMUNITY_LEADERBOARD_ENABLED`,
   `STRUMSIGHT_COMMUNITY_CLUBS_ENABLED` — külön env-var kulcs mindegyiknek, a
   2. pont indoklásával azonos okból.
5. **Backend readiness placeholder (A5):** egy új, dokumentált, csak-olvasható
   property a `Settings`-en:
   ```python
   @property
   def community_postgres_ready(self) -> bool:
       """Epic 9 (Community) SDD-terve PostgreSQL-t feltételez; a mai dev/prod
       default SQLite (`database_url`). Ez a property dokumentációs
       placeholder a Kör 2 (`E09-R02`) éles migrációs döntéséhez — MA nem
       kapcsol semmilyen viselkedést `community_enabled`-hez. `False`, amíg
       a `database_url` sqlite-ra mutat."""
       return not self.database_url.startswith("sqlite")
   ```
   Ez a property **nem** gate-eli a `community_enabled`-et (a kör briefje
   szerint ez a kör alkalmazáskódot nem ír, csak dokumentál) — a Kör 2 dolga
   eldönteni, hogy egy jövőbeli readiness-ellenőrzés éles gate legyen-e.
6. **A négy alkapcsoló szemantikája (dokumentációs, ADR-szintű rögzítés,
   hogy a Kör 5+ ne találja ki újra):** `communityEnabled` a modul
   LÁTHATÓSÁGÁT vezérli (route-ok, UI belépési pontok — ha ez `false`, a
   többi négy irreleváns); `communityWritesEnabled` az írási útvonalakat
   (poszt, komment, reakció, follow-request) `communityEnabled=true` mellett;
   `communityMediaEnabled` a média-feltöltést; `communityLeaderboardEnabled`
   a versenyzési/leaderboard felületet; `communityClubsEnabled` a klub-domain
   elérhetőségét. A négy alkapcsoló egymástól és `communityEnabled`-től
   FÜGGETLENÜL olvasódik be (2-3. pont) — a jövőbeli hívó kódnak (Kör 5+) kell
   majd az AND-kapcsolást (`communityEnabled && communityWritesEnabled` stb.)
   megvalósítania, ez a kör csak a nyers flag-eket vezeti be.

**NEM elfogadható gyengítés:** bármelyik öt flag `nonProd`-alapon (a
`diagnosticsEnabled`/`labModeAvailable` mintája szerint) automatikusan
igazra állítása dev/lab buildben — ez a Community modult (amely MÉG nem
létezik, `lib/features/community/` üres) élesítené fejlesztői buildekben egy
UI/domain nélkül, és ellentmond az A1/A2 explicit "engedély nélkül false"
elvárásának; a `communityEnabled`-ből származtatott al-flag alapérték (pl.
`communityWritesEnabled` csak akkor olvasódjon, ha `communityEnabled` igaz) —
ez törné az A2 mérce-mátrix független-mérési képességét; a readiness
property gate-ként bekötése ebbe a körbe (a §3 kifejezetten "alkalmazáskód-
változtatás nélkül" kört ír elő).

## Elutasított alternatívák

- **Az ADR 0220 (Epic 6) mintájának másolása: mind az öt flag `false` MINDEN
  környezetben, dart-define NÉLKÜL, a teljes Epic 9 építő-fázisa alatt.**
  Elvetve: az ADR 0220 explicit indoka (Kontextus 2. pont, "songTrainerV2Enabled
  KÉTFÁZISÚ precedense") egy néma, hívó nélküli V2-shadow-utat védett egy
  ÉLŐ, elsődleges V1 út MELLETT — ott a korai kapcsolgatás egy félkész UI-t
  tenne láthatóvá. A Community domain jelenleg **nem létezik**
  (`lib/features/community/` üres), tehát nincs V1/V2 párhuzamos-út
  kockázat, amit védeni kellene; a brief §5.3 pedig kifejezetten a
  `accountEnabled`/`tutorEnabled` operábilis-kill-switch mintát nevezte meg
  már a brief-írás pillanatában. A két precedens NEM ugyanarra a helyzetre
  vonatkozik — ez az ADR ezért tudatosan tér el, nem véletlenül.
- **`app_config.dart` felvétele az `allowed_paths`-ra, hogy az `accountEnabled`
  huzalozását szó szerint követhesse.** Elvetve: a brief `allowed_paths`-a
  előre, írásban rögzített, és a bővítés MOST, ad hoc, a pre-flightban H3
  határsértés lenne (ADR 0087 §2) egy olyan fájlra, ami nem is szükséges —
  a `bool.fromEnvironment` nyelvi szinten helyben is működik.
- **Egyetlen `communityEnabled` flag, a négy alkapcsoló `communityEnabled`-ből
  származtatva (pl. `communityWritesEnabled => communityEnabled && ...`).**
  Elvetve: az A2 mérce-mátrix sora explicit egy olyan hibás implementációt ír
  elő pirosra ("csak egy flag kap védelmet, a másik négy nem"), ami csak
  akkor mérhető, ha mind az öt flag TÉNYLEGESEN független bemenetről olvas.

## Következmények

- A Kör 5+ (`lib/features/community/**` első valódi kódja) a négy alkapcsoló
  AND-szemantikáját (Döntés 6. pont) implementálja a hívó oldalon — ez az ADR
  csak a nyers flageket vezeti be, a kapcsolási logikát nem.
- A Kör 2 (`backend/app/community/**`, migráció) a `community_postgres_ready`
  placeholdert vagy éles gate-té alakítja, vagy dokumentáltan elveti — a
  döntés Kör 2 saját ADR-jének dolga.
- Minden jövőbeli Epic 9 kör, amíg `communityEnabled` production-ben `false`
  marad, a `lib/features/community/**`-t és a `backend/app/community/**`-t
  hívó nélkül vagy flag-mögötti hívóval építheti — a production viselkedés
  bitre azonos marad, amíg egy külön, jövőbeli GOV-rollout-kör másképp nem
  dönt (ugyanaz az elv, mint ADR 0220 Következmények szakasza, csak itt a
  MECHANIZMUS eltér: itt van dart-define/env kill switch a build alatt is
  tesztelhetőség miatt, ott nincs).

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli Epic 9 kör mérten azt találja, hogy az
operábilis kill switch (dart-define/env mindig felülírható) tényleges
kockázatot jelentett — pl. egy CI vagy dev build véletlenül a define-nal
készült és élesbe került. Ekkor a váltás az ADR 0220 mintájára (hardcode-false
a build teljes hátralévő részére) egy dedikált, dokumentált GOV-mikro-kör
dolga, nem egyetlen építő-kör csendes döntése.
