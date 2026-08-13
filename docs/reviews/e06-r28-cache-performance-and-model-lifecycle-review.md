# E06-R28 — Review

Brief: docs/rounds/e06-r28-cache-performance-and-model-lifecycle.md
Diff: `git diff 0efa1906..adbe8eee` (pre-flight commit → implementer commit)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-13
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 2 · NOTE: 0

Gate ÚJRAFUTTATVA saját kézzel, izolált `/tmp/review-e06-r28` klónban
(GitHub-ról klónozva, NEM a megosztott munkafáról) — mind a 8 lépés zöld.
Scope-audit OK, 15 fájl, mind engedélyezett. Egy explicit valódi-sértés próbát
saját kézzel megismételtem (analyzerVersion komponens ideiglenes kivétele a
kulcsból) — a megfelelő cella pontosan PIROSRA vált, majd visszaállítva.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Kulcs-mátrix — hét cella (1 hit + 6 miss) | ✅ | `analysis_cache_key_test.dart:8-19`, saját futtatással zöld; a `analyzerVersion` ág valódi-sértés próbával is igazolva (lásd Megállapítások előtti bekezdés) |
| 2 | Fingerprint-tulajdonságok (100 futás azonos, 1 minta eltér, névfüggetlen, fix 64 hex) | ✅ | `audio_fingerprint_test.dart` mind a 4 teszt zöld; a "névfüggetlen" teszt gyenge, ld. F1 (MINOR) |
| 3 | Cap-hármas darabra (19/20/21, LRU nem FIFO) | ✅ | `analysis_cache_test.dart:62-95` — a "LRU retains an old entry that was accessed between writes" teszt explicit a köztes-olvasás cellát méri, nem csak darabszámot |
| 4 | Cap-hármas méretre (52428799/52428800/52428801) | ✅ | `analysis_cache_test.dart:97-124` — a pontos konstansokat külön `expect`-tel igazolja (`AnalysisCache.defaultMaxBytes == 52428800`), a boundary-viselkedést kicsinyített cap-pal (arányos, elfogadható mintázat) |
| 5 | Sérült bejegyzés → miss, nem hiba | ✅ | `analysis_cache_test.dart:126-134`, saját futtatással zöld |
| 6 | Mentett session védettsége cache-ürítés után | ✅ | `analysis_cache_test.dart:136-162` — a VALÓDI R21 `FileAnalysisRepository`-t használja (nem stub), `purge()` után `list()`/`getById()` változatlan |
| 7 | Single-flight (`== 1` hívás) | ✅ | `analysis_cache_test.dart:164-183` — genuin egyidejűség `Completer`-rel, mindkét hívó ugyanazt kapja |
| 8 | Modell-betöltés (`== 1` bundle-olvasás és parse, 3 hívó) | ✅ | `analysis_cache_test.dart:185-206` — `Future.wait` három egyidejű `load()` hívással |
| 9 | Benchmark-artefaktum (futtatott kimenet, R01-gyel azonos fixture, determinisztikus) | ✅ | `docs/baseline/epic-06-analysis-performance.md` — a DETERMINISM_SHA256 (`071925bc…5f1d7b6`) BITRE EGYEZIK az R01 `epic-06-audio-analysis-start.md` saját hash-ével — ezt magam kereszt-ellenőriztem, ez erős bizonyíték a valódi (nem kitalált) futtatásra |
| 10 | Nincs wall-clock assert a tesztben | ✅ | `analysis_cache_property_test.dart` — forrásolvasó teszt, saját futtatással zöld; a `tool/audio_analysis_benchmark.dart` jogosan használ `Stopwatch`-ot (nem gate-elt artefaktum, nincs `expect(...lessThan...)`) |
| 11 | Eval-mátrix PENDING sor, felelőssel, mérendő számmal | ✅ | `docs/manual-testing/analysis-eval-matrix.md` — EVAL-27 sor, "Performance owner", négy konkrét mérendő szám |
| 12 | ADR 0248 tartalma (hat komponens, cap, halasztási feltétel) | ✅ | a pre-flight már megírta; az implementer nem módosította (nincs a diffben) — indokolt, mert nem volt implementációs eltérés |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e06-r28 \
  --brief docs/rounds/e06-r28-cache-performance-and-model-lifecycle.md --base 0efa1906
→ Legacy scope audit OK (0efa1906..adbe8eee, 15 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs.** A 15 megváltozott fájl
pontosan lefedi a brief §4 listáját (az `docs/adr/0248-…md` kivételével, amit
az implementer nem módosított — jogosan, ld. #12).

## Megállapítások

### F1 — MINOR — a "névfüggetlen fingerprint" teszt nem azt bizonyítja, amit állít

- **Fájl:** `test/features/audio_analysis/data/audio_fingerprint_test.dart:57-73`
  ("content fingerprint has no filename input")
- **Probléma:** a teszt `AudioFingerprint.compute(...)`-ot KÉTSZER hívja
  BYTE-AZONOS argumentumokkal (`first` és `renamed` — nincs köztük semmilyen
  eltérés), majd egyenlőséget vár. Mivel `AudioFingerprint.compute()`
  szignatúrájában EGYÁLTALÁN NINCS fájlnév/path paraméter, ez a teszt valójában
  a determinizmust ismétli (amit a fájl első tesztje, 100 futással, már
  szigorúbban bizonyít) — a névfüggetlenség ÁLLÍTÁSÁT nem egy VALÓDI
  ellenpélda-kísérlettel (két eltérő "fájlnév" bemenettel) igazolja, mert
  ilyen bemenet nincs is a függvényen.
- **Hatás:** a mai kódra nulla — a tulajdonság (nincs fájlnév a hash
  bemenetében) a függvény SZIGNATÚRÁJÁBÓL következik, saját olvasással
  igazolva (`audio_fingerprint.dart:19-24`, a `compute()` paraméterlistája:
  `samples`/`sampleRate`/`channelCount`/`preprocessingVersion`, semmi más). A
  teszt viszont NEM nyújt védelmet egy jövőbeli regresszió ellen, ha valaki
  később fájlnév-paramétert adna a függvényhez és belekeverné a hashbe — a
  teszt akkor is zöld maradna, hacsak nem a hívási helyét is módosítják.
- **Kötelező javítás:** nem kötelező ebben a körben (nem hizlalja érdemben a
  diffet, de nem is BLOCKER/MAJOR). Javasolt jövőbeli finomítás: vagy törölni
  ezt a redundáns tesztet, vagy átnevezni úgy, hogy a szignatúra-hiányt
  dokumentálja (`'AudioFingerprint.compute has no filename/path parameter by
  design'`), esetleg egy statikus típusvizsgáló megjegyzéssel kiegészítve.
- **Ellenőrzés:** nincs futtatható ellenőrzés a mai állapotra (nincs mit
  pirosra buktatni) — ez dokumentációs/precizitási megjegyzés.
- **Státusz:** OPEN (nem blokkoló, follow-up jegyzetként hagyva)

### F2 — MINOR — a §10 handoff "16 zöld teszt" állítása félrevezetően van egy fájlhoz kötve

- **Fájl:** `docs/rounds/e06-r28-cache-performance-and-model-lifecycle.md`,
  §10 "Acceptance evidence" bekezdés, "LRU/cap/korrupció/…" sor
- **Probléma:** a mondat szó szerint ezt állítja: „LRU/cap/korrupció/session/
  single-flight/model: `analysis_cache_test.dart` (**16 zöld teszt** a
  célzott futásban)". Saját futtatással (`flutter test --reporter compact
  test/features/audio_analysis/data/analysis_cache_test.dart`) igazoltan ez a
  fájl **8** tesztet tartalmaz, mind zöld ("All tests passed!", 8/8). A 16-os
  szám a NÉGY új tesztfájl (8+4+3+1 = `analysis_cache_test.dart` +
  `audio_fingerprint_test.dart` + `analysis_cache_key_test.dart` +
  `analysis_cache_property_test.dart`) ÖSSZESEN vett tesztszáma — az állítás
  önmagában igaz, csak a mondatszerkezet egyetlen fájlnak tulajdonítja.
- **Hatás:** nulla a kódra; a tényleges teszteredmény (mind zöld) helyes és
  saját kézzel újra-igazolt. Csak a handoff-dokumentum pontossága sérül —
  ami jövőbeli olvasónak (self-heal session, jövőbeli audit) téves képet
  adhat arról, mennyi teszt fedi konkrétan az LRU/cap/korrupció logikát.
- **Kötelező javítás:** nem kötelező (a tényadat a merge szempontjából
  irreleváns, a kód és a gate a valódi bizonyíték). Egy jövőbeli
  dokumentum-simítás javíthatja a mondatot négy külön számra.
- **Ellenőrzés:** `flutter test --reporter compact
  test/features/audio_analysis/data/analysis_cache_test.dart` → 8/8 zöld (a
  reviewer saját futtatása, izolált klónban).
- **Státusz:** OPEN (dokumentációs pontosítás, nem blokkoló)

## Valódi-sértés próba (a brief §6.1 utolsó sora, saját kézzel megismételve)

`analysis_cache_key.dart:_canonicalJson()`-ban ideiglenesen kivettem az
`analyzerVersion` kulcsot a kanonikus JSON-ból, majd lefuttattam
`analysis_cache_key_test.dart`-ot: pontosan az „analyzerVersion" miss-cella
(`expect(_key(analyzerVersion: 'analyzer-v2'), isNot(baseline))`, 12. sor)
vált PIROSRA (`Expected: not <Instance…> / Actual: <Instance…>`), a másik két
teszt zöld maradt. Visszaállítva, `git diff --stat` üres — a próba nem hagyott
nyomot.

## Architektúra + termékhatárok

- **Domain-purity:** `domain/cache/analysis_cache_key.dart` importjai:
  `dart:convert`, `package:crypto`, két relatív domain-import — nincs
  Flutter/Riverpod. `architecture` gate lépés zöld (saját futtatással).
- **`public.dart` barrel:** additív export, a három új osztály a megfelelő
  domain/data szekcióban.
- **Cache/repository fájlrendszeri elkülönülés:** `analysisCacheRootDirectoryName
  = 'analysis_cache'` vs. `analysisRepositoryRootDirectoryName = 'analysis'` —
  külön app-support alkönyvtár, testvér-viszonyban, nem beágyazva egymásba
  (`analysis_providers.dart:46-48,66-101`).
- **`storage_keys.dart`:** kizárólag additív — egy új kulcs (`analysisCache`),
  a `all` listába felvéve; egyetlen meglévő kulcs sem módosult/törölt.
- **Nincs rejtett hálózati hívás:** a négy új production fájl importjai
  kizárólag `dart:*`/`crypto`/belső domain — nincs `dio`/`http`/plugin.
- **R27 `AnalysisCachePort` érintetlen:** `delete_analysis_use_case.dart`
  NINCS a diffben (scope-audit is igazolja) — a pre-flight §0.0-jában
  dokumentált korlátozás betartva.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futtatás, izolált klón |
| analyze | zöld | ✅ saját futtatás, izolált klón |
| test test/features/audio_analysis | zöld | ✅ saját futtatás, izolált klón |
| test test/property | zöld | ✅ saját futtatás, izolált klón |
| test test/core | zöld | ✅ saját futtatás, izolált klón |
| architecture | zöld | ✅ saját futtatás, izolált klón |
| secrets | zöld | ✅ saját futtatás, izolált klón |
| l10n | zöld | ✅ saját futtatás, izolált klón |
| CI (teljes suite + property + APK) | — | ⏳ dispatch a review után, exact-SHA a merge előtt |

**A jelzésfájl `gate_shape=VIOLATION`/`dirty_files=1` mezőiről:** mindkettőt
kivizsgáltam pre-review lépésben. A `gate_shape=VIOLATION` a naplóban a brief/
implementer-prompt SAJÁT szövegének (a `round-gate.sh test/core` parancs,
közel utána a „NE fűzd `&&`-fel" tiltó mondat) egy heurisztikus regex-találata
volt — nem tényleges csonkított gate-hívás; a §10 handoff kizárólag a helyes,
csonkítatlan parancsot idézi bizonyítékként, és a saját, izolált
újrafuttatásom mind a 8 lépésen zöldet adott. A `dirty_files=1` egy 9
másodperces, a végleges commit UTÁNI tranzitív állapot volt (feltehetően a
benchmark saját, önmagát takarító temp-könyvtárának egy pillanatnyi
metszéspontja a jelzés-írással) — a munkapéldány jelenleg (és a review-klón
eleve) tisztán jött át, nincs elveszett munka.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Ez a feltétel teljesül (0 BLOCKER, 0 MAJOR, 2 dokumentált MINOR, egyik sem
blokkoló). **A kötelező dedikált security review (risk=high) külön fut,
independens agent-tel — annak verdiktje a végső merge-döntés
előfeltétele**, ezt a jelentést önmagában nem elegendő elfogadni.
