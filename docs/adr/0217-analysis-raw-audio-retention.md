# ADR 0217 — Analysis raw audio retention

- **Státusz:** Elfogadva (E06-R01 pre-flight, 2026-08-11)
- **Kör:** E06-R01 — Analyze V1 baseline, mérés és ADR-ek
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 1; §24.4 (Nyers audio retention), §24.5 (Törlés), §28.1-28.3
  (Privacy — nyers audio, temp fájl, fájlnév)
- **Kontext-ADR-ek:** [0183](0183-vision-no-raw-frame-persistence.md)
  (a raw-frame no-persistence precedens a Vision oldalon, E05-R01 —
  szerkezetileg azonos döntés, más médiumra), [0178](0178-vision-privacy-by-default.md)
  (privacy-by-default elv, amiből ez a döntés az audio oldalra öröklődik)
- **Sorszám-jegyzet:** lásd [ADR 0215](0215-analysis-document-versioning.md)
  fejléce — a teljes hatos blokk 0200–0205-ről 0215–0220-ra tolódott.

## Kontextus

**Mért 2026-08-11-én:**

1. A jelenlegi `ClipRecorder` (`lib/features/analyze/engine/clip_recorder.dart:11-24`)
   egy egyszerű, növekvő `final List<double> _buffer = []` — **nincs
   maximum hossz**, és a rögzített PCM az elemzés után a Dart GC-re van
   bízva (nincs explicit törlés/nullázás). A `computeClipAnalysis`
   (`providers/analyze_providers.dart:108-121`) a PCM-et egy `compute()`
   isolate-hopon adja át; az elemzés után a hívó (`AnalyzeController._analyze`)
   nem tartja meg a nyers mintákat az `AnalyzeResult`-on kívül.
2. A `docs/rag/chunks/`-ban (DSP-igazság, AGENTS.md §9) és a Lab
   diagnostics úton (`lib/features/diagnostics/`) **rövid audio explicit,
   opt-in feltöltésre kerül** — ez a meglévő, szándékos kivétel, nem
   alapértelmezés (`memory: lab-mode-diagnostics` — cloudflared tunnel,
   `visionLabCaptureEnabled` audio-analóg útja).
3. A Vision feature már megoldotta ugyanezt a problémát a képi oldalon:
   [ADR 0183](0183-vision-no-raw-frame-persistence.md) — alapértelmezetten
   nincs raw-frame persistence, a tárolt egység egy aggregátum (insight +
   capability + confidence + model-verzió), a raw adat kizárólag a
   consentelt Lab capture flag mögött rögzíthető. Ugyanaz a szerkezet,
   más médium (audio vs. kép) — ez az ADR ezt a mintát viszi át.
4. Az SDD §24.4 explicit `AudioRetentionPolicy { keepOriginal,
   autoDeleteAfter }` típust ír elő, `keepOriginal = false`
   alapértelmezéssel; preview waveform tárolható, a felhasználó explicit
   dönthet később (opt-in, nem opt-out).
5. Az SDD §28.1 (Nyers audio) öt tilalmat sorol: nem kerül logba, crash
   reportba, Tutor contextbe, backupba explicit policy nélkül; §28.2
   (Temp fájl) app-private directory, random név, cleanup cancel/crash
   esetén is; §28.3 (Fájlnév) a importált fájlnév logban redaktálandó,
   share-ben alapból nem jelenik meg, Tutorhoz consent nélkül nem
   továbbítható.
6. A HANDOFF §2 „Detektálás (100% on-device)" és a `CLAUDE.md` „detection
   stays 100% on-device" elve azt is jelenti, hogy a nyers audio **soha
   nem hagyja el az eszközt** hálózaton — ez már ma is igaz (nincs
   audio-upload a normál Analyze úton), ez az ADR a **tárolási** (nem
   hálózati) oldalt rögzíti.

## Döntés

1. **`AudioRetentionPolicy { keepOriginal, autoDeleteAfter }` külön
   entitás** (SDD §24.4), **`keepOriginal = false` alapértelmezés minden
   AnalysisDocument-hez.** A nyers PCM/WAV az elemzés után nem kerül
   tartós tárba, csak egy opcionális, kis méretű preview waveform
   (letömörített amplitúdó-burkoló, nem a teljes mintasor).
2. **Kivétel kizárólag a consentelt Lab capture** — ugyanaz a mechanizmus,
   mint a Vision oldalon ([ADR 0183](0183-vision-no-raw-frame-persistence.md)
   Döntés 3): explicit flag + explicit consent, a normál production
   persistence útja ettől érintetlen.
3. **Nyers audio soha nem kerül logba, crash reportba, Tutor-kontextusba
   vagy exportba** — sem ideiglenesen, sem „majd egy későbbi kör törli"
   indoklással. A `AnalysisProvenance` ([ADR 0215](0215-analysis-document-versioning.md))
   `inputFingerprint` mezője (SDD §10.4) a nyers audióból **nem
   rekonstruálható** hash-alapú azonosító, nem maga az audio.
4. **A temp fájl kezelés** (ha a feldolgozás átmenetileg lemezre ír, pl.
   nagy import esetén) app-private directory, random fájlnév, és
   cancel/crash esetén is garantált cleanup (SDD §28.2) — ez a
   `AtomicFileWriter`/`FileSongRepository` (E03-R07) staging-mintájának
   audio-analóg alkalmazása.
5. **A törlés (SDD §24.5) teljeskörű:** session törlésekor a document, az
   index-bejegyzés, az opcionális megtartott audio és a cache mind
   törlődik egy műveletben — részleges törlés (pl. csak a document, az
   audio megmarad) nem elfogadható végállapot.

**NEM elfogadható:** „ideiglenesen elmentjük, majd egy későbbi kör törli" —
sem a nyers audióra, sem a temp fájlra; nyers audio bármilyen formában
logban, crash reportban vagy Tutor-promptban; `keepOriginal` alapértelmezett
`true`-ként bevezetése „hogy a debug egyszerűbb legyen" indoklással.

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; a shadow diff-riport nem tartalmaz nyers audioadatot.

- A V2 storage-réteg (E06-R21) az `AudioRetentionPolicy`-t a `FileSongRepository`
  (E03-R07) atomikus-írás mintájára építi: a nyers audio soha nem kerül a
  tartós document mellé alapértelmezésben.
- A Lab diagnostics út (meglévő, E06-R99-en kívüli) audio-analóg
  kiterjesztése egy jövőbeli kör dolga, ha egyáltalán szükséges — ez az ADR
  csak azt rögzíti, hogy MARADJON explicit opt-in.
- A `docs/manual-testing/analysis-eval-matrix.md` (ez a kör hozza létre)
  egy PENDING sort kap a temp-fájl cleanup valós-eszközös ellenőrzésére.
- A V1 `ClipRecorder` viselkedése (in-memory buffer, GC-re bízott törlés)
  **érintetlen marad** ebben a körben — ez a döntés a V2 storage-szerződést
  rögzíti, alkalmazáskód-változás nélkül
  ([ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)).

## Elutasított alternatívák

- **A nyers audio alapértelmezett megtartása, opt-out mechanizmussal.**
  Elvetve: opt-out alapértelmezés ellentmond a projekt privacy-by-default
  elvének ([ADR 0178](0178-vision-privacy-by-default.md)) és az SDD §24.4
  explicit `keepOriginal = false` előírásának.
  Egy felhasználó, aki sosem nyit Settings-et, sosem tudná, hogy a
  felvételei tárolva vannak.
- **Egy „reprezentatív" tömörített audio-klip mentése minden analízishez**
  (a preview waveformnál részletesebb). Elvetve: ugyanaz az érvelés, mint
  [ADR 0183](0183-vision-no-raw-frame-persistence.md) Elutasított
  alternatívák 1. pontja — egyetlen érzékeny audio-részlet is túl sok
  alapértelmezésben; az aggregált metrika + insight elegendő a
  termékértékhez.
- **A temp-fájl retention-t erre a körre bővíteni valós implementációval.**
  Elvetve: docs-only kör, `lib/`/`test/` diff nulla — ez az ADR a
  szerződést rögzíti, az implementáció a storage-kör (E06-R21) dolga.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli, explicit user-döntés cloud-backupot vagy
audio-megosztást vezet be a felvételekhez (ma nincs ilyen terv) — ekkor
`keepOriginal` egy ÚJ, explicit user-vezérelt Settings-kapcsolóként
bevezethető, de az alapértelmezés akkor is `false` marad, és a döntést
külön ADR rögzíti, nem ennek a döntésnek a csendes felülírása.
