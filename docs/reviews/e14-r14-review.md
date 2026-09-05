# E14-R14 — Független review (ADR 0055, `sdd-round-review`)

- **Kör:** `E14-R14` — Automatikus Audio Setup és Accuracy Check
- **Branch:** `sonnet-impl/e14-r14-audio-setup-and-accuracy-check`
- **Reviewelt HEAD:** `6d34fa652986ee7e594eec2408c8fa65bb6d2131`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude (Opus 5), read-only, izolált klónban
- **ADR:** [0519](../adr/0519-audio-setup-profile-as-input-not-calibration.md)
- **Kockázat:** `high` (`privacy`) → a §5 biztonsági szakasz KÖTELEZŐ, elvégezve
- **Dátum:** 2026-09-05

## VÉGSŐ DÖNTÉS: **APPROVED**

Nyitott **BLOCKER: 0**, **MAJOR: 0**. Egy **MINOR** és három **NOTE** rögzítve
— egyik sem merge-blokkoló, mindegyik a következő kör (`E14-R14b`, UI-bekötés)
bemenete.

## 1. Scope-audit

A gépi audit a jelzésfájlban: `scope_audit=ok`,
`scope_audit_base=761baee1`, `scope_audit_changed=8`. Kézzel újramérve, a
brief `allowed_paths` listája ellen:

| Fájl | A listán? |
|---|---|
| `lib/features/onboarding/audio_setup/audio_setup_step.dart` | ✅ |
| `lib/features/onboarding/audio_setup/audio_profile.dart` | ✅ |
| `lib/features/onboarding/audio_setup/audio_profile_store.dart` | ✅ |
| `lib/features/onboarding/audio_setup/audio_setup_controller.dart` | ✅ |
| `lib/features/onboarding/public.dart` | ✅ |
| `test/features/onboarding/audio_setup_controller_test.dart` | ✅ |
| `test/features/onboarding/audio_profile_store_test.dart` | ✅ |
| `docs/rounds/e14-r14-audio-setup-and-accuracy-check.md` | ✅ |

Listán kívüli fájl: **nincs**. A tesztek `test/core/storage/in_memory_key_value_store.dart`-ot
importálnak — ez NEM a kör terméke: mérve `git log --oneline -1 --` →
`9e5bcf351 refactor(storage): introduce injected persistent storage layer (#6)`,
tehát régóta a fán van, a diff nem érinti.

Az ADR 0519-et az orchestrátor írta a pre-flightban; az implementer nem
módosította (`git diff 761baee1..HEAD -- docs/adr/` üres).

## 2. Gate — függetlenül újrafuttatva

Izolált klón: `…/scratchpad/review-e14-r14`, `HEAD = 6d34fa65`, előtte
`tools/prepare-flutter-generated.sh`.

```
tools/round-gate.sh test/features/onboarding/audio_setup_controller_test.dart test/features/onboarding/audio_profile_store_test.dart
```

MÉRT kimenet — **GATE_EXIT=0**, minden lépés zöld:

| Lépés | Eredmény |
|---|---|
| `format` | zöld |
| `analyze` | zöld |
| `test …/audio_setup_controller_test.dart` | zöld (**8/8**) |
| `test …/audio_profile_store_test.dart` | zöld (**9/9**) |
| `architecture` | zöld — `Architecture dependencies OK (12 allowlisted deviation(s))` |
| `secrets` | zöld — `4406 file(s) scanned, 0 finding(s)` |
| `l10n` | zöld — `parity OK (en → hu, 2304 message(s))` |

Az `architecture` deviáció-szám **12**, változatlan: a kör NEM vett fel új
allowlist-bejegyzést (ez volt a §0.0/R3 kockázata).

## 3. Valódi-sértés próbák (eldobható mutációk, egyik sem commitolva)

Minden mutáció után `git checkout --` visszaállítás, `git status --short` üres.

### P1 — a §7.1 falszifikációs próba REPRODUKÁLVA

Az implementer §10 állítását (lépésenkénti mentés → 3. acceptance PIROS) nem
bemondásra fogadtam el: a `recordStep`-be minden lépés után beszúrtam egy
`store.save(...)` hívást. MÉRT:

```
acceptance #2 — … a tooQuiet fixture … [E]
acceptance #3 — … abort() after a few recorded steps leaves the store empty [E]
00:00 +6 -2: Some tests failed.
```

Pontosan a jelentett két cella, pontosan a jelentett okból. Visszaállítva:
zöld. **A §10 falszifikációs állítása igaz.**

### P3 — a `crossFeatureImportsMustUsePublicApi` kapu VALÓDI

Az `audio_profile.dart` importját a mély útra cserélve
(`../../live/domain/recognition/signal_quality_snapshot.dart`):

```
Architecture dependency check failed.
- lib/features/onboarding/audio_setup/audio_profile.dart -> lib/features/live/domain/recognition/signal_quality_snapshot.dart [cross-feature imports must target public.dart]
```

A §0.0/R3 tehát nem papír-előírás: gépi őr méri.

### P5 — az inkluzív felső határ VALÓDI mércét kapott

`total <= kAudioSetupMaxDuration` → `<` mutációval:

```
acceptance #1 — … the boundary is inclusive on the top: 59s accepted, 60s accepted, 61s rejected … [E]
00:00 +7 -1: Some tests failed.
```

A brief §6.1 mátrixának utolsó sora („a hossz-ellenőrzés exkluzív felső
határral") tehát ténylegesen le van fedve.

### P2 / P6 — a D2 osztályozás a TELJES enumra

Eldobható próbateszt: minden `SignalQualityState` értékre (a `good`
kivételével) végigfuttatva a nyolclépéses futást — **mind a hét** nem-`good`
állapot `needsAttention`-t ad, **nem üres** tanáccsal, és **nem ment profilt**
(`store.read() == null`). Kiemelten az `unknown` is: a „nincs elég adat"
sosem csúszik át sikerként (ADR 0519 D2 + 0505 §1). Ezt egyik szállított
teszt sem méri kifejezetten — az implementáció viszont helyes (a
`_firstNonGoodState()` bármely nem-`good` értéket kiszűr), ezért ez **NOTE**,
nem lelet.

### P4 — `schemaVersion` round-trip

Lásd a MINOR-1 leletet lent; a próba MÉRTE, hogy egy nem-current
`schemaVersion`-nel épített profil mentés után `schemaVersion = 1`-gyel jön
vissza, és **nem** value-equal az eredetivel.

## 4. Acceptance criteria — pontonként

| # | Elvárás | Mérce | Verdikt |
|---|---|---|---|
| 1 | SDD lépéssor + 30–60 s, inkluzív felső határ (59/60/61 cella) | `audio_setup_controller_test.dart` 4 teszt; `AudioSetupStep.sequence` = 8 lépés (csend, erős down, up, E/Am/G/C, pozíció-javaslat), tervezett össz 40 s; P5 mutáció | ✅ |
| 2 | `tooQuiet` → `needsAttention`, nem üres tanács | `acceptance #2`; P2/P6 az egész enumra | ✅ |
| 3 | Megszakítás után nincs részleges profil | `acceptance #3` (2 teszt); P1 falszifikáció | ✅ |
| 4 | Route-változás → `stale`, a getter nem adja vissza | `audio_profile_store_test.dart` `acceptance #4` (3 teszt: route ÉS sample-rate) | ✅ |
| 5 | Ismeretlen `schemaVersion` → típusos hiba; a migrált profil mezői egyeznek | `acceptance #5` (3 teszt), mezőnkénti egyezés-mérés (L70) | ✅ |
| 6 | Törlés után nem olvasható vissza | `acceptance #6` — `read() == null` ÉS `backing.contains(storageKey) == false` (valódi `remove`, nem flag) | ✅ |

Az ADR 0519 D1–D8 mindegyike lefedve: D1 (a profil egyetlen `settings`/`live`
konstanst sem ír — mérve: a diff nem importálja őket), D2/D3/D4/D5 a fenti
cellákkal, D6 a P3 próbával, D7 a feature-lokális `storageKey`-jel, D8 azzal,
hogy `screens/**` érintetlen.

## 5. Biztonsági / adatvédelmi review (`risk = "high"`, `privacy`)

MÉRT a teljes kör-diffen (`grep -rnE "dio|http|Uri\.|Socket|logger|appLogger|print\(|debugPrint|Permission|MethodChannel|record"`):

- **Hálózat: nincs.** A négy új `lib/` fájl összes importja: `package:meta/meta.dart`,
  `dart:convert`, `../../live/public.dart`, `../../../core/storage/key_value_store.dart`
  és egymás. Nincs `dio`, `http`, `Uri`, socket.
- **Naplózás: nincs.** A profil egyetlen mezője sem kerül loggerbe, `print`-be
  vagy `debugPrint`-be; a `toString` nincs felülírva, tehát nincs véletlen
  szivárgás sem.
- **Platform-csatorna / engedély / felvétel: nincs.** A kör NEM nyit
  mikrofont, NEM kér engedélyt és NEM rögzít hangot — a jelminőség kívülről,
  `SignalQualitySnapshot` értékként érkezik. A brief „mikrofon-felvételt
  vezérel" kockázat-indoklása ezért ebben a körben **nem realizálódik**; a
  valódi mikrofon-tulajdonlás a UI-kör (`E14-R14b`) kérdése lesz, és ott
  külön mérendő az `AudioOwner`/lease szerződés ellen.
- **Tárolt adat:** `micRouteId` (opak audio-route leíró), `sampleRateHz`,
  `suggestedInputGainDb`, két latency egész, `qualityExpectation` enum,
  `confidenceProfile` arány, `recordedAt` időbélyeg. **Nincs** hangminta,
  felvétel-részlet, azonosító vagy szabadszöveges felhasználói adat. Ez
  helyesen a nem-titkos `KeyValueStore` sávba tartozik (SDD Ch2 §7.4), NEM
  igényel `flutter_secure_storage`-ot.
- **Törölhetőség:** a `clear()` ténylegesen `remove`-ol; a store-teszt a
  backing store `contains`-ét is méri, nem csak a `read()`-et. A felhasználó
  adata így valóban törölhető, nem csak elrejthető.
- **Titok-szkennelés:** `secrets` gate zöld, 0 lelet.

**Biztonsági verdikt: nincs lelet.**

## 6. Leletek

### MINOR-1 — a `schemaVersion` mező silent felülíródik mentéskor

`lib/features/onboarding/audio_setup/audio_profile.dart:78-88` — a `toJson()`
a **`currentSchemaVersion`** konstanst szerializálja, nem a példány
`schemaVersion` mezőjét, miközben a mező a konstruktorban `required`.

**Mért hibaforgatókönyv (P4):** `AudioProfile(schemaVersion: 0, …)` →
`store.save(…)` → `store.read()` a profilt `schemaVersion: 1`-gyel adja
vissza, és `back == legacyShaped` **hamis** — a mentett blob csendben mást
állít, mint amit a hívó átadott.

**Ma nem shipping-hiba:** az egyetlen két producer (`_decodeCurrent` és a
controller `_finish()`) mindkettő `currentSchemaVersion`-t ad át, tehát
eltérő érték a jelenlegi kódból nem keletkezhet. A csapda a JÖVŐ hívójáé.

**Javasolt feloldás (`E14-R14b` vagy egy migrációs kör):** vagy a
`schemaVersion` kikerül a publikus konstruktorból (mindig `currentSchemaVersion`),
vagy a `toJson()` a példány mezőjét írja ki és a `decode` fail-closed
ellenőrzi. Nem merge-blokkoló.

### NOTE-1 — sérült JSON-blob `FormatException`-t ad, nem `ArgumentError`-t

`audio_profile_store.dart:28` — a `jsonDecode(raw)` egy nem-JSON tárolt
értéken `FormatException`-t dob, mielőtt a fail-closed `AudioProfile.decode`
egyáltalán lefutna. A viselkedés továbbra is **fail-closed** (nincs default
profil, nincs csendes `null`), tehát a D5 nem sérül; a doc-comment „throws"
szava igaz. Csak a hívó oldali `catch` típusa lesz kettős, amikor egy jövőbeli
UI-kör hibát jelenít meg.

### NOTE-2 — a `confidenceProfile` ma mindig pontosan `1.0`

`audio_setup_controller.dart:198-204` a `good` lépések arányát számolja, de a
D2 miatt `success` csak akkor születik, ha MINDEN lépés `good` — és profil
csak `success` esetén mentődik. A perzisztált `confidenceProfile` tehát ma
információt nem hordoz. Ez nem hiba (a mező a D1 szerinti „személyes
confidence-profil" helye), de a `E14-R14b` vagy egy későbbi kör vagy
értelmes tartalmat ad neki (pl. lépésenkénti confidence-értékek), vagy
kimondja, hogy konstans.

### NOTE-3 — a `schemaVersion: 0` legacy alak feltételezett

A §10 ezt **kimondja**, nem hallgatja el: ez vadonatúj feature, valós régi
mentés nem létezik. A migrációs út így az 5. acceptance-pont demonstrációja.
Ez elfogadható — a migrációs gépezet és a tesztje akkor is valódi, ha a v0
alakot soha nem írta eszköz —, de a jövő olvasójának tudnia kell, hogy a v0
ág törölhető, ha sosem kerül élesbe.

## 7. Amit külön ellenőriztem, és rendben van

- **A §10 handoff állításai reprodukálhatók** (8/8 + 9/9, falszifikáció, gate)
  — egyik sem bemondás.
- **Nincs generált-barrel staleness-kockázat:** az `architecture` lépés zöld,
  és `lib/features/onboarding/public/` fragmentum-könyvtár nem jött létre, így
  a `_checkGeneratedBarrels` őr nem is fut erre a feature-re (§0.0/R2 mérése
  helyes).
- **`OnboardingStep` érintetlen:** a kipinnelt
  `test/features/onboarding/onboarding_resume_test.dart` enum-szekvenciájához
  a kör nem nyúlt (a diff nem tartalmazza az `onboarding_provider.dart`-ot).
- **A `recordStep` nem éleszt újra halott futást:** `abort()` után
  `StateError` — mérve.
- **A `AudioSetupStep` assertje** (`expectedChord` akkor és csak akkor, ha
  `chordCheck`) a `const` szekvencián fordítási időben is kiértékelődik.
