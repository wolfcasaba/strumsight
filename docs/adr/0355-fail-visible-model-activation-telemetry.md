# ADR 0355 — A modellaktiváció fail-visible: típusos eredmény, zárt hibakód, mért hash

- **Státusz:** elfogadva
- **Dátum:** 2026-09-04
- **Kör:** `E14-R03` (Chapter 14, Kör 3)
- **Kapcsolódó:** [`0271`](0271-recovery-kickoff-and-release-guard.md),
  [`0292`](0292-model-activation-requires-verified-integrity.md);
  `0355` az `E14-R02` `0354`-es baseline-manifest ADR-jével PÁRHUZAMOS kör,
  ezért annak fájljára szándékosan nem hivatkozik linkkel
- **Előzmény:** `docs/LESSONS.md` L06 (az elnyelt hiba néma no-op),
  L260 (a kulcsnév-listás redakciós teszt vakon zöld), L28

## Kontextus

A Live felismerő út ma **némán** esik vissza a heurisztikus irányosztályozóra,
ha a CRNN-súly nem tölthető be. Mért állapot a `main @ 4f293403` fán:

- `lib/features/live/engine/ml/strum_crnn.dart:26-36` — `StrumCrnn.tryLoad`:
  `try { … } catch (_) { return null; }`. Az OK **sehol nem marad meg**.
- `lib/features/live/engine/dsp/live_pipeline.dart:21-31` — `_tryLiveCrnn`:
  ugyanez a minta, a `StrumAnalyzer` `classifier:` mezője (`:60`) `null` lesz.
- A `LiveFrame` 11 mezője közül **egy sem** mondja meg, melyik osztályozó adta a
  verdiktet.

Ebből az következik, hogy egy futó buildről **nem eldönthető, mit mértünk**: a
heurisztikus és a CRNN-es verdikt kívülről megkülönböztethetetlen. A Chapter 14
egész felismerési helyreállítása erre a megkülönböztetésre épül — az `ADR 0271`
aktivációs szerződése és az `ADR 0354` baseline-manifestje egyaránt azt kívánja,
hogy a kiértékelt konfiguráció **azonosítható** legyen.

A `docs/LESSONS.md` L06 ezt a hibaosztályt már megmérte a beállítás-szinkronon:
az elnyelt kivétel + optimista felület a felhasználó felől megkülönböztethetetlen
a sikertől. A felismerő oldalán ugyanez a minta él, csak itt nem adat vész el,
hanem a **mérés hitele**.

Az `ADR 0292` a szomszédos, szigorúbb kérdést dönti el (hamisított modell nem
aktiválható). Ez az ADR nem lazítja: itt a modell **hiánya vagy sérülése** a
tárgy, és a válasz továbbra is „nem aktiválunk" — csak mostantól **ki is
mondjuk**.

## Döntés

1. **A betöltés eredménye típusos, nem `null`.** A `ModelActivation` két állapota
   `activated(model, info)` és `fallback(reason, info)`. A `null` visszatérés
   megszűnik mint a „nem tudni, mi történt" hordozója.

2. **A `fallbackReason` ZÁRT, gépi kódhalmaz**, nem szöveg:
   `assetMissing`, `assetUnreadable`, `parseFailed`, `shapeMismatch`,
   `disabledByFlag`. Kivétel `toString()`-je **nem** kerülhet a kódba, a
   modellbe, a naplóba vagy az exportba — platform- és lokalizáció-függő, és
   fájlrendszer-utat szivárogtat.

3. **A fail-visible NEM fail-fast.** A modell hiánya vagy sérülése után
   változatlanul a heurisztika fut, kivétel nélkül; a felhasználó élménye bitre
   azonos. Kizárólag a *diagnosztika* javul. A fallback ág dobásra cserélése
   ennek az ADR-nek a megsértése, nem a szigorítása.

4. **A modellazonosság MÉRT, nem átvett.** A `strumModelSha256` a ténylegesen
   betöltött bájtokból számolt hash. A manifestből (`assets/ml/model_manifest.json`)
   átmásolt érték nem elfogadható: pontosan azt az esetet nem fogná meg, amiért
   a mező létezik (a manifest és az asset szétcsúszása). Ez az `ADR 0292`
   integritás-elvének mérési oldala.

5. **A production Live felület ebben a körben változatlan.** A runtime-információ
   a Labban és a lokális kiértékelésben látszik; technikai hibaszöveget a
   production felhasználó nem kap.

6. **A `RecognitionRuntimeInfo` kizárólag modell-metaadatot hordoz** — nincs
   benne PII, token, audio, sem abszolút fájlrendszer-út. A redakciót
   **kanári-próba** méri (L260): a tesztnek egy olyan úton kell betöltést
   provokálnia, amelynek egyedi útszegmense a kivétel szövegében szerepel, és
   azt kell mérnie, hogy a szerializált **érték** ezt a szegmenst nem
   tartalmazza. Kulcsnév-listás tiltás önmagában nem mérce: fix kulcskészletű
   DTO ellen konstrukció szerint mindig zöld.

## Következmények

**Pozitív.** Egy futó buildről eldönthető, melyik felismerő adta a verdiktet, és
ha fallback fut, annak stabil, gépi oka van. A Chapter 14 kiértékelési körei
(`E14-R06`…`E14-R09`) így tudják a mérésüket a *ténylegesen aktív* modellhez
kötni, nem a feltételezetthez.

**Negatív / ár.** A hibaokot a betöltő oldalnak **osztályoznia** kell (magic,
verzió, hiányzó tömb), ami a bináris fejléc-szerződés apró duplikációja a
`strum_crnn.dart`-ban. Ezt vállaljuk: az alternatíva a `FormatException`
szövegére illesztés lenne, ami törékeny és a 2. pontot sértené.

**Amit ez a döntés TILT.**

- A `catch (_) { return null; }` mintát a modellbetöltés körül.
- A kivétel-szöveg továbbadását hibaokként.
- A fallback ág fail-fast dobássá alakítását.
- A hash manifestből másolását.
- A `RecognitionRuntimeInfo` bővítését audióval, tokennel vagy abszolút úttal.

**Hatókör-korlát (mért).** A `LivePipeline` a **DSP-izolátumban** él
(`lib/features/live/engine/real_strum_engine.dart:167` `_DspInit`, `:220`
`_dspEntry`), a `StrumEngine` seam pedig ma nem hordoz runtime-információt. Az
izolátum → UI átvitel ezért **nem** ennek a körnek a dolga: a `LiveLabState`
additív mezőt és belépőt kap, a tényleges bekötés a `LiveFrame` szerződését
átszabó `E14-R04` köre. Ez az ADR a szerződést rögzíti, nem a szállítást.
