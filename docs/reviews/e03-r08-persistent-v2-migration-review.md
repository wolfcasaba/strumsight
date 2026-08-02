# E03-R08 — Review

Brief: `docs/rounds/e03-r08-persistent-v2-migration.md`  
Diff: `git diff origin/main...codex/e03-r08-persistent-v2-migration`  
Reviewer: Codex / GPT-5.6 Terra · Date: 2026-08-02  
Verdict: CHANGES REQUIRED

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Üres, egy- és többdalos storage migrálható | ❌ | Az egyrekordos happy path `needsResume` státuszt ad: `song_storage_migrator_test.dart:205`; a normál provider-wiring is ugyanígy bukik: `song_storage_migrator_wiring_test.dart:141`. |
| 2 | N-edik write/read-back hiba után restart folytatható | ❌ | A teszt ellenőrzőpontig sem jut el: `song_storage_migrator_test.dart:277`, `:338`. |
| 3 | Corrupt rekord redacted recoveryval kezelhető | ❌ | Az első jó rekord sem checkpointolható: `song_storage_migrator_test.dart:417`. |
| 4 | Setlist csak teljes song-mapping után indul | ❌ | A hibátlan songbooknál is `needsResume`: `song_storage_migrator_test.dart:471`, `:491`. |
| 5 | Production wiring friss példányból visszaolvasható | ❌ | Izolált provider-wiring teszt `readBackMiss` loggal és `needsResume` eredménnyel bukik. |

## Scope-audit

Az E03-R08 funkcionális diff kizárólag a brief §4-ben engedélyezett hét fájlt érinti. A branch a review előtt `origin/main`-nel merge-elve lett; annak örökölt self-heal fájljai nem a kör funkcionális diffjei.

## Megállapítások

### F1 — BLOCKER — A sikeres fájltárolás után minden normál migráció read-back parity hibára fut

- **Fájl:** `lib/features/song_trainer/application/migration/song_storage_migrator.dart:427-453`
- **Probléma:** A migrátor a frissen megnyitott repositoryból kiolvasott dokumentumot teljes `SongDocument` value equalityval hasonlítja az adapter által készített dokumentumhoz. A valós `FileSongRepository` + codec útvonalon ez a feltétel már egy normál, egyrekordos mentésnél hamis, ezért a kód `songMigration.song.readBackMiss` logot ad, nem checkpointol, és `needsResume`-mal tér vissza. Ez nem szintetikus fake-probléma: a production-wiring teszt ugyanezt mutatja.
- **Hatás:** A termék egyetlen érvényes legacy dalt sem tud befejezetten V2-be migrálni. Minden indítás ugyanazt a rekordot próbálja újra, a completion marker sosem íródik ki; a kör fő célja és az összes sikerágas acceptance kritérium sérül.
- **Kötelező javítás:** A R06 fidelity szerződésnek megfelelő, pontosan definiált read-back parityt vezess be: az adapter által megőrzendő szerkezeti/forrásadatokat hasonlítsa, de csak olyan eltérést fogadjon el, amelyet a R07 repository/codec bizonyíthatóan legitim módon normalizál. Ne a parityt kapcsold ki, és maradjon olyan regressziós teszt, amely egy szerkezeti eltérést (például section vagy track módosítása) ténylegesen `readBackMiss`-re visz. A happy-path és fresh-provider wiring teszteknek javítás után `completed`-del kell zárulniuk.
- **Ellenőrzés:** `tools/round-gate.sh test/features/song_trainer/application/migration test/features/song_trainer/data/migration test/features/songs` teljesen zöld; az imént bukott hét teszt, különösen a `song_storage_migrator_wiring_test.dart:141`, zöld.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format | ✅ — 706 fájl, 0 módosítás |
| analyze | ✅ — `flutter analyze lib/ test/ tool/`: No issues found |
| célzott tesztek | ❌ — `flutter test test/features/song_trainer/application/migration`: 7 bukó, 3 zöld, 1 skip |
| architecture | ❌ — a gate a célzott tesztfázis első hibáján megállt |
| CI (teljes suite + property + APK) | ❌ — kódhibás lokális gate mellett dispatch tiltott |

## Merge-döntés

Az ADR 0052 szerint merge tilos: F1 BLOCKER nyitott és a kötelező lokális gate piros.
