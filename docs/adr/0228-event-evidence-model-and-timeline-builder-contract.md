# ADR 0228 — Event evidence modell bővítés és EventId/EventTimelineBuilder szerződés

- **Státusz:** Elfogadva (E06-R10 pre-flight, 2026-08-12)
- **Kör:** E06-R10 — Event evidence modell és onset/strum timeline V2
- **Implementer motor:** Terra (`gpt-5.6-terra`), `.pipeline/engine-override=terra` szerint.
- **Kapcsolódó szerződések:** SDD Ch7 §9.6/§9.7/§13.1–13.2, [ADR 0215](0215-analysis-document-versioning.md)
  4. döntése (additív, hátrafelé kompatibilis mező nem igényel séma-verzió-
  emelést), [ADR 0226](0226-clip-analyzer-stage-boundary-and-fallback-provenance.md)
  (`LegacyEvidence` forrás), a meglévő `lib/features/audio_analysis/domain/
  analysis_event.dart` (E06-R02) és `lib/features/audio_analysis/data/
  legacy_view_adapter.dart` (E06-R09).

## Kontextus

A brief eredetileg (2026-08-07, batch, Epic 6 kickoff ELŐTT, `main@a6e6f3d`)
két ÚJ fájlt írt elő `OnsetEvent`/`StrumEvent` néven — az azóta lezajlott
E06-R02 kör ugyanezt a két nevet már a sealed `AnalysisEvent` család tagjaként
alkotta meg. A H3 önjavító kör (PR #224, 2026-08-12) ezt a fájl-cél-ütközést
zárta (`allowed_paths` retargetelve a meglévő `domain/analysis_event.dart`-ra)
— de a self-heal jogosultsága kizárólag a HALT-olt hibaosztályra szólt, a
tényleges evidence-mezőkészletet, az `EventId` formátumát és a builder
összevonási/elnyomási szabályait nem rögzítette formális döntésként. Ez az
ADR ezt a hátralévő, még nyitott architekturális felületet zárja le, mielőtt
az implementer megkapja a brief-et.

Öt már merge-elt kör fogyasztja a mai `OnsetEvent`/`StrumEvent` konstruktort
allowed_paths-on KÍVÜL (`analysis_document_codec.dart`,
`legacy_analyze_adapter.dart`, `analysis_timeline_test.dart`,
`legacy_analyze_adapter_test.dart`, `analysis_document_codec_test.dart`) — a
bővítésnek ezért additívnak és hátrafelé kompatibilisnek kell maradnia
(ADR 0215 4. pont), és a brief tilos zónája kifejezetten kizárja a sealed
`AnalysisEvent` bázisosztály és a testvér-típusok (`ChordChangeEvent` stb.)
módosítását.

Mérve (pre-flight, 2026-08-12, `main@8c2e43ae`): a `test/features/
audio_analysis/engine/clip_analyzer_parity_test.dart` mind a **kilenc**
fixture-je `sampleRate: 44100`-at használ (nem 48000-et); a
`lib/features/audio_analysis/engine/preprocessing/` (E06-R08, ADR 0225) NEM
resamplel — a rendszerben nincs egyetlen kanonikus/rögzített mintavételi ráta
konstans sem (`rg -n "48000|48_000" lib/features/audio_analysis/` → 0 találat).
A V1 referencia-szűrő (`clip_analyzer.dart:234`, `dt > 0.05`) IDŐN
(másodperc) dönt, nem mintaszámon. A brief §6 acceptance-mátrixa a
minimum-separation határesetet „2399/2400/2401 minta, 48 000 Hz-en" alakban
írja le — ez ÖNMAGÁBAN félreérthető: ha az implementáció egy rögzített
2400-mintás küszöböt hasonlítana össze a `sampleIndex`-különbséggel a
tényleges mintavételi rátától függetlenül, a valódi (44100 Hz-es) bemeneten a
2400 minta ≈ **54,42 ms** lenne, NEM 50 ms — pontosan a §6 első acceptance
pontját (V1-paritás a kilenc R09-fixture-ön) törné néma, rendszerszintű
módon.

## Döntés

1. **Az öt új mező a KÉT LEVÉL-típuson él, nem a bázisosztályon.**
   `attackStrength` (`double`), `localRms` (`double`), `confidenceSource`
   (`String`, ld. 6. pont), `fallbackReason` (`String?`) named, opcionális/
   alapértékes paraméterként **mindkét** `OnsetEvent`-en ÉS `StrumEvent`-en
   külön-külön jelenik meg (duplikálva, nem közös bázis-mezőként) — a sealed
   `AnalysisEvent` bázisosztály és a testvér-típusok (`ChordChangeEvent`/
   `BeatEvent`/`NoteOnsetEvent`/`SilenceRegionEvent`/`ClippingRegionEvent`)
   egyetlen sora sem változik (§3/§4 tilos zóna). `directionConfidence`
   (`double`) KIZÁRÓLAG a `StrumEvent`-en jelenik meg, mert csak ennek van
   `direction` mezője. A bázis `confidence` mező jelentése és típusa
   **változatlan** marad (onset/strum saját, kalibrálatlan confidence-e).
2. **`EventId` egy stateless generátor, nem az `id` mező típusa.**
   `domain/events/event_id.dart` egy determinisztikus stringet épít
   `<runId>:<type>:<sampleIndex>` alakban, és ezt a MEGLÉVŐ `String id` mezőbe
   írja — az `AnalysisEvent.id` típusa `String` marad. `type` a HÍVÓ (builder)
   által átadott, rögzített literál (`'onset'` / `'strum'`), **nem**
   `runtimeType.toString()` — az utóbbi implementációfüggő, és a
   determinizmus-kritérium (§6 „ugyanaz a bemenet kétszer építve azonos
   ID-listát ad") sérülékennyé válna egy refaktortól, aminek semmi köze az
   event tartalmához.
3. **A minimum-separation összehasonlítás `Duration`-alapú, nem
   mintaszám-alapú.** A névvel ellátott konstans `Duration(milliseconds: 50)`
   (OD-02) — a builder KÉT event `.time` mezőjét (nem `.sampleIndex`-ét)
   hasonlítja össze. A §6 acceptance-mátrix „2399/2400/2401 minta, 48 000
   Hz-en" hármasa a PROPERTY/UNIT teszt SAJÁT, önkonzisztens fixture-
   konstrukciója (a teszt egy tetszőlegesen választott 48 kHz-es mintavételi
   rátán számolja ki a 49,98/50,00/50,02 ms-nak megfelelő mintaszámokat, és a
   hozzájuk tartozó `Duration` értéket UGYANEZZEL a rátával származtatja) —
   **nem** azt jelenti, hogy a builder egy rögzített 2400-as mintaszám-
   küszöböt tartalmaz. Ez a döntés zárja a fenti, mért kontextus-részben
   leírt rést: a builder így a kilenc R09-fixture 44100 Hz-es bemenetén is
   pontosan 50 ms-ot (nem 54,42 ms-ot) alkalmaz.
4. **A suppressed event a diagnosztikai ágba kerül, nem tűnik el.** A builder
   egy második, publikus API-n elérhető listát ad vissza (ok + a
   „vesztes" esemény adatai + időpont) minden elnyomott eseményre; a fő
   (nyilvános) timeline listából hiányzik.
5. **`confidenceSource` zárt, ismert értékkészlet** (`'heuristic'` /
   `'crnn'` / `'calibrated'`) — ebben a körben előállított event SOSEM kap
   `'calibrated'`-et (a kalibráció az R19 dolga, SDD §13.2). Az érték a
   `LegacyEvidence.provenance`-ből (E06-R09, ADR 0226 `strumRefinerSource`
   `none`/`heuristic`/`crnn` háromosztása) vezethető le közvetlenül a
   `LegacyEvidence` → V2 event fordításnál; `none` esetén a builder
   `'heuristic'`-et ír (nincs negyedik forrás-kategória az event szinten).
6. **A codec és a `legacy_analyze_adapter.dart` NEM módosul ebben a körben**
   (OD-03) — az öt új mező egyelőre (de)szerializálatlan marad. Ez
   SZÁNDÉKOS, dokumentált rés: a §6 acceptance nem kéri a codec-fidelitást,
   csak a `LegacyViewAdapter` paritást (ami a meglévő `direction`/`time`/
   `confidence` hármast használja, ÚJ mezőt nem).
7. **`StrumEvent.onsetEventId` (nullable `String?`, additív mező) a builder
   SAJÁT szintetizált onsetjére mutat, nem egy független detektor
   kimenetére** (OD-04). Mérve: a `LegacyEvidence` (E06-R09) nem hordoz
   független onset-listát — kizárólag `strums`/`chords`. A builder ezért
   minden `LegacyStrumEvidence`-bejegyzéshez PONTOSAN egy `OnsetEvent`-et
   szintetizál, azonos `time`/`sampleIndex`-szel, mint a belőle épített
   `StrumEvent`; ez a mai V1 szemantikát tükrözi (§2: „az onset és a strum
   azonos fogalom"), nem új onset-detektálási algoritmus (ami a §3 tilos
   zónája). A minimum-separation/suppression a (onset, strum) **párt
   atomikusan** kezeli — ha a strum elnyomásra kerül, a szintetizált onsetje
   is a diagnosztikai ágba kerül, hogy a publikus listában sosem maradjon
   `onsetEventId`, ami nem létező vagy elnyomott eseményre mutat.
8. **A kombinált (onset+strum) kimeneti lista rendezési kulcsa `sampleIndex`
   monoton NEM CSÖKKENŐ, nem szigorúan növekvő** — mérve Terra dispatch #1
   stopped-jelzéséből (2026-08-12 02:21 UTC, §0.0.2): a 7. döntés minden
   szintetizált (onset, strum) párt AZONOS `sampleIndex`-re helyez, ami
   matematikailag kizárja a „szigorúan monoton" (nulla duplikátum,
   típustól függetlenül) invariánst minden legalább egy strumot tartalmazó
   bemeneten. A dedup-kulcs változatlanul `(type, sampleIndex)` (§5 pont 5,
   nem ez az ADR vezette be) — ugyanazon `sampleIndex`-en legfeljebb egy
   `OnsetEvent` ÉS legfeljebb egy `StrumEvent` élhet egyszerre. Holtverseny
   (mindkettő jelen van ugyanazon `sampleIndex`-en): az `OnsetEvent`
   determinisztikusan megelőzi a hozzá `onsetEventId`-vel kapcsolódó
   `StrumEvent`-et a listában.
9. **A §6 suppression/separation acceptance PÁR-szinten számol, nem
   esemény-szinten.** Mérve Terra dispatch #2 stopped-jelzéséből (2026-08-12
   02:29 UTC, §0.0.3, valódi `event_id.dart` commit UTÁN, `d33e3491`): a §6
   eredeti „diagnosztikai lista pontosan 1 bejegyzés / publikus lista 1
   esemény" számozása a párosítás-mentes (H3 self-heal előtti) modellt
   tükrözte. A 7. döntés (atomikus pár-suppression) alatt egy MEGTARTOTT
   vagy ELNYOMOTT logikai egység mindig két fizikai eseményt jelent (1
   `OnsetEvent` + 1 `StrumEvent`) — a minimum-separation teszt bemenete ezért
   KÉT `LegacyStrumEvidence` (két pár), és a diagnosztikai/publikus
   listaszámok 2/2, nem 1/1.

## Elutasított alternatívák

- **Közös mezők felemelése az `AnalysisEvent` bázisosztályba** (DRY-elv): a
  brief tilos zónája kifejezetten kizárja a bázisosztály módosítását ebben a
  körben — a duplikáció (leaf-classonként külön mező) az ELFOGADOTT ár egy
  jövőbeli, dedikált refaktor-körért cserébe.
- **`EventId` mint új value-class, ami lecseréli az `id: String` mezőt**:
  minden allowed_paths-on KÍVÜLI fogyasztót (codec, legacy adapter, három
  teszt) törne — ADR 0215 4. pontjával és a §5 pont 7 „bitre változatlan
  hívók" követelménnyel egyaránt ütközne.
- **`type` diszkriminátor `runtimeType.toString()`-ból**: implementáció-
  függő, és semmilyen szerződés nem garantálja a stabilitását — a
  determinizmus-kritériumnak (§6) egy explicit literál felel meg
  ellenőrizhetően.
- **Mintaszám-alapú minimum-separation rögzített 2400-as küszöbbel**: csak
  48 000 Hz-es bemeneten helyes; a kilenc R09-fixture 44100 Hz-es bemenetén
  ~54,42 ms-ot alkalmazna 50 ms helyett, néma paritás-regressziót okozva
  (mérve, ld. Kontextus).
- **`confidenceSource` négy értékkel (`none` külön kategóriaként)**: az
  event-szintű evidence-nek nincs értelmezhető „nincs forrás" állapota — egy
  event vagy létezik (van forrása), vagy nincs a listában; az R09
  `none`/`heuristic` közötti különbségtétel a `ClipAnalyzer`-hívás
  side-channel-jéé (ADR 0226), nem az event evidence-é.
- **`onsetEventId` opcionálisan üresen hagyva, amikor nincs külön onset-forrás**:
  ez formálisan teljesítené az additivitást, de a §5 pont 1 kötelező
  hivatkozását ("egy strum hivatkozik a saját onsetjére") és a §6.1 mátrix
  „onsetEventId hivatkozás cellát" üresen hagyná, mérhetetlenné téve a
  kötött döntést — a szintetizálás (7. döntés) az egyetlen út, ami a
  kötelező hivatkozást a MAI (onset-mentes) bemeneten is kielégíti.
- **A suppression csak a strumra alkalmazva, az onsetje érintetlenül a
  publikus listán marad**: árva, semmi által nem hivatkozott `OnsetEvent`-et
  hagyna a publikus timeline-ban — ez sértené a „duplikátummentesség és
  hivatkozási integritás" elvet, és megzavarná a jövőbeli hotspot-
  fogyasztókat (ismeretlen eredetű onset egy elnyomott strum mellett).
- **A kombinált lista tényleg szigorúan monoton marad, a `StrumEvent`
  `sampleIndex`-ét mesterségesen +1-gyel eltolva az onsetjéhez képest**:
  megmentené a szigorú monotonitást, de két új, hamis állítást vezetne be —
  a strum `sampleIndex`-e többé nem egyezne a saját `time`-jából számolható
  mintaszámmal (§5 pont 2 sérülne: „a kettő... konzisztens"), és a
  szintetikus eltolás egy KITALÁLT, semmilyen méréssel alá nem támasztott DSP-
  mennyiség lenne. Elutasítva — a rendezési kulcs szemantikáját (nem
  csökkenő, nem szigorúan növekvő) kellett pontosítani, nem az adatot
  torzítani.
- **Az onset és a strum egy KÖZÖS listaelemként jelenne meg (visszatérés az
  `isStrum`-boolean-mintához, csak most „rendezettség miatt")**: ez pontosan
  a §5 pont 1 „NEM elfogadható" tétele — a rendezettségi ütközés feloldása
  nem ok az architekturális alapdöntés visszavonására.
- **A diagnosztikai/publikus szám „1" marad, egy pár egyetlen összevont
  bejegyzésként számolva (`{onset, strum}` tuple, nem két különálló
  `AnalysisEvent`)**: ez a builder KIMENETI TÍPUSÁT változtatná meg (két
  homogén `List<AnalysisEvent>` helyett egy heterogén, tuple-alapú
  szerkezetet) — sem a §3 scope, sem a `LegacyViewAdapter` meglévő
  `document.timeline.events.whereType<StrumEvent>()` mintája nem ezt várja;
  elutasítva, a pár-szintű SZÁMOLÁS (2 fizikai esemény = 1 logikai egység)
  a kisebb, kompatibilis módosítás.

## Visszavonási feltétel

Ha egy jövőbeli kör ténylegesen perzisztálja a builder kimenetét (a codec
bővítése éles útvonalon), a 6. döntés („codec nem módosul") ADR-frissítéssel
felülírandó — a codec bővítése és egy dedikált round-trip teszt akkor
kötelező előfeltétel (a brief §9 már jelzi ezt follow-upként). Ha egy
jövőbeli kör bevezet egy tényleges, rendszerszintű kanonikus mintavételi
rátát (pl. a preprocessing resampler bekapcsolásával), a 3. döntés
`Duration`-alapú indoklása változatlan marad — a döntés maga (Duration, nem
sampleIndex, a helyes összehasonlítási alap) EZEN A PONTON IS érvényes marad,
csak a kontextus-rész „nincs kanonikus ráta" állítása avulna el. Ha egy
jövőbeli kör valódi, strumtól független onset-detektort köt be (a mai
tilos zóna feloldásával), a 7. döntés („a builder minden strumhoz szintetizál
egy onsetet") ADR-frissítéssel felülírandó — attól kezdve a builder a valódi
detektor onset-listáját fogadja bemenetként, és a szintetizálás csak arra a
strumra marad, aminek nincs hozzá tartozó, mért onsetje.

## Következmények

- Az `OnsetEvent`/`StrumEvent` konstruktor bővül, de a típusuk, a bázisosztály
  és a testvér-típusok bitre változatlanok — az öt allowed_paths-on kívüli
  fogyasztó git diff-je üres kell legyen ezekben a fájlokban.
- A minimum-separation helyesen viselkedik minden mintavételi rátán (nem csak
  48 000 Hz-en), mert a builder sosem hasonlít nyers mintaszámot egy rátától
  független konstanshoz.
- Az `EventId` formátuma stabil marad refaktor esetén is, mert a `type`
  literál, nem reflexió.
- A codec-rés nyitva marad — a `AnalysisDocument` perzisztált formája ebben a
  körben NEM hordozza az új mezőket; ez explicit, mért, követett follow-up
  (§9), nem hallgatólagos adatvesztés.
- Minden R10-ben épített `OnsetEvent` egy-az-egyben egy forrás-strumhoz
  kötött (nincs önálló, strumtól független onset ebben a körben) — amikor
  egy jövőbeli kör valódi, független onset-detektort köt be, ez a
  szintetizálási szabály (7. döntés) felülvizsgálandó, mert onnantól a
  `LegacyEvidence`-nél gazdagabb bemenet is elérhető lesz (Visszavonási
  feltétel).
- A „rendezettség" property-teszt (§6) mostantól két külön állítást mér:
  monoton-nem-csökkenő + típusonkénti dedup (property, tetszőleges méretű
  véletlen onset-halmazon) ÉS a holtverseny-sorrend (determinisztikus
  unit-teszt, egyetlen szintetizált párra) — a kettő EGYÜTT adja vissza azt
  a garanciát, amit az eredeti, pontatlan „szigorúan monoton" megfogalmazás
  próbált (de tévesen) kifejezni.
