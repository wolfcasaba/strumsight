# E14-R40 — Belső Alpha field study: protokoll és gépi beiratkozás (a study maga NEM FUT)

- **Kör-azonosító:** `E14-R40` (Chapter 14, Kör 40)
- **ADR:** nincs saját szám — a kód-oldali döntés az
  [ADR 0542 D7](../adr/0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md)
  (a field-session tag zárt kohorsz + forgó pszeudonim). A terv §4 PKG-D
  sora ehhez a körhöz csak briefet ír elő.
- **Dátum:** 2026-09-09
- **Implementer:** Claude (Opus 5), PKG-D
- **Terv:** [`epic-14-completion-plan.md`](epic-14-completion-plan.md) §2 R40

## 1. Cél

A field study **protokollját** és a **gépi beiratkozási felületét** szállítani,
hogy amikor a 8 gitáros rendelkezésre áll, a nyolc session összehasonlítható
legyen — és hogy egy NEGATÍV eredmény (még nem elég jó) használható kimenet
legyen, ne utólag átkeretezett kellemetlenség.

**A study maga BLOCKED:** 8 tesztelő, több telefon, több gitár, zajos szoba
kell hozzá. Ez a kör ezt kimondja, nem kerüli meg.

## 2. Mért állapot

| Tény | Bizonyíték |
|---|---|
| A `docs/accessibility/known-exceptions.yaml` bevált fail-closed registry-minta létezik | a fájl + a hozzá tartozó olvasó teszt |
| A Lab-felvétel consentje típussal kényszerített | `lib/features/accuracy_lab/domain/lab_consent.dart` (ADR 0358): a writer csak `LabConsentGranted`-et fogad |
| A diagnosztikai felvételnek ma nincs study-címkéje | `lib/features/diagnostics/model/diagnostics_session.dart` — `surface` egy szabad `String`, study-mező nincs |
| A mért baseline korpuszban NULLA telefon-mikrofonos diverzitás van | `evaluation/recognition/baseline_manifest.json` (Klangio, 82 felvétel) |

## 3. Scope

**Benne:** `docs/release/ch14-r40-field-study.md` (feladatlista, mérendők,
consent-szabály, fail-closed findings-registry alak, üres eredmény-tábla);
`FieldSessionTag` típus + `FieldStudyCohort` / `FieldStudyTask` zárt enumok;
`fieldStudyEnrolmentProvider` (opt-in, default OFF);
`recognitionFieldSessionTaggingEnabled` zászló (OFF minden környezetben).

**Kívül:** a study lefuttatása; a `lab-apk.yml` (tilos zóna); a
`lib/features/diagnostics/**` bekötése (más csomag tulajdona — a javasolt
patch a PKG-D jelentésében van); a `docs/release/ch14-field-study-findings.yaml`
létrehozása (az ELSŐ valódi session hozza létre — egy létező üres registry
azt olvasná, hogy „lefutott és nem talált semmit").

## 4. Fájlok

**Új:** `docs/release/ch14-r40-field-study.md`,
`lib/core/telemetry/field_session_tag.dart`.
**Módosított:** `lib/app/config/feature_flags.dart` +
`lib/core/feature_flags/feature_flag_registry.dart` (a
`recognitionFieldSessionTaggingEnabled` zászló),
`lib/features/settings/providers/telemetry_consent_provider.dart`
(`fieldStudyEnrolmentProvider`, `resolveFieldSessionTag`).
**Teszt:** `test/features/settings/telemetry_consent_center_test.dart`
(Kör 40 csoport).

## 6. Elfogadási feltételek

| # | Feltétel | Státusz |
|---|---|---|
| A1 | A tag zárt kohorszt, zárt feladatot és a forgó pszeudonimet hordozza, semmi mást | **PINNED-BY-TEST** — `telemetry_consent_center_test.dart` (`headerKeys` egyezés) |
| A2 | A tag `null`, ha a zászló, a beiratkozás vagy a pszeudonim hiányzik (fail-closed) | **PINNED-BY-TEST** — ugyanott, három külön cella |
| A3 | A beiratkozás külön opt-in a telemetria-consenttől, default OFF | **PINNED-BY-TEST** — ugyanott |
| A4 | A protokoll kimondja: nyers audio CSAK külön consenttel | **DOKUMENTUM** — `ch14-r40-field-study.md` §4, a `LabConsentGranted` típus-kapura hivatkozva |
| A5 | A false-confident hiba kényszerítetten P0/P1 | **DOKUMENTUM** — §5; gépi őrré akkor válik, amikor az első session létrehozza a registry-fájlt |
| A6 | A study eredményei | **NEEDS-MEASUREMENT** — 8 gitáros + `lab-apk.yml` build; a §6 tábla szándékosan ÜRES |

## 10. Handoff

- **A diagnosztikai bekötés nem történt meg.** A `lib/features/diagnostics/**`
  más csomag tulajdona; a javasolt patch (a `DiagnosticsSession`-höz egy
  opcionális `fieldSessionTag` fejléc-blokk, a `resolveFieldSessionTag`-ből
  töltve, a `settings/public.dart` barrelen át importálva) a PKG-D
  jelentésében van szó szerint.
- **A study futtatásának lépései** a `ch14-r40-field-study.md` §8-ban vannak.
  Az 1. lépés egy szándékos forrásmódosítás
  (`recognitionFieldSessionTaggingEnabled` → `true`), amit a protokollal
  együtt kell reviewzni.
