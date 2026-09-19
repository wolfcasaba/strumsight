# ADR 0538 — Chord-korpusz manifest-szerződés és a szintetikus generátor határa

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R25 · **Precedens:** ADR 0354 (baseline manifest, kézi validátor, „no raw audio”), ADR 0509 (grouped split), Ch14 §7.1, §12/2

## Kontextus (mért)

- A Ch14 §7.1 korpusza (8 gitáros / 6 telefon / 4 gitár / 4 szoba / 24
  kiegyensúlyozott osztály / hard-negatívok) **egyetlen elérhető korpuszban
  sem teljesül**. A Klangio 82 felvétel / 3 gitáros, egy elrendezés.
- A `chord-train.yml` letölti a **GuitarSet**-et (valós gitár, valós
  akkordcímke, gitáros-szintű LOGO) — ezen az osztály-support és a
  gitáros-split **ténylegesen mérhető**, telefon-mikrofon, szoba, capo és
  pick/finger viszont nincs benne.
- Korpusz-manifest szerződés a chord-sávra **nem létezett**; a
  `baseline_manifest_schema.json` a legacy DSP baseline-t írja le, nem egy
  felveendő korpuszt.

## Döntés

### D1 — A szerződés ELŐBB van, mint az adat

`evaluation/recognition/chord_corpus_manifest_schema.json` +
`domain/evaluation/chord_corpus_manifest.dart`. Ez nem adatot pótol: azt
rögzíti, hogy a felvételi munka **milyen alakban válik használhatóvá**, mielőtt
bárki felvenne 500 fájlt. Kézi validátor, séma-könyvtár nélkül (ADR 0354 D8).

### D2 — Minden felvételi körülmény KÖTELEZŐ

`voicing`, `capo`, `pickStyle`, `loudness`, `room`, `distanceCm`, `guitar`,
`player`, `device`, `durationMs`, `tempoBpm`. Nincs opcionális metaadat: egy
mező, ami hiányozhat, pontosan ott fog hiányozni, ahol az elemzés kérné. A
hiba tipizált, a pontos JSON útvonallal.

### D3 — Zárt címke-szótár, gépi tükörrel

A `label` a 24 támogatott maj/min osztály valamelyike vagy a fenntartott
`noChord`. A 24-es lista (`chordCorpusMajMin24Labels`) a
`assets/ml/model_manifest.json` `output_classes` listája mínusz az `N.C.`, és
egy teszt **gépi tükörként** ezt ellenőrzi — a szótár nem sodródhat el egyik
oldalon sem. Egy `Csus4` elutasítás: a nyílt halmazú akkord az open-set
korpuszba tartozik (ADR 0540), nem egy kiegyensúlyozott maj/min korpuszba.

### D4 — Egy split-implementáció, nem kettő

`ChordCorpusManifest.buildFolds` a tételeket `RecognitionCase`-ekké vetíti, és
a SHIPPED `RecognitionSplitBuilder` + `LeakageDetector` fut rajtuk (ADR 0509
D1/D2). Így „egy játékos nem lépi át a train/eval határt” egyetlen helyen van
definiálva, és a hiányzó csoportkulcs itt is tipizált hiba, nem `unknown`
gyűjtő.

### D5 — Az osztály-egyensúly riport NEVEZ, nem osztályoz

`classBalance(minimumSupport:)` visszaadja az osztályonkénti supportot, a
hiányzó és a minimum alatti osztályok **listáját**, az N.C./hard-negatív
darabszámot és a hard-negatív arányt (`null` üres korpuszon, sosem `0`). Egy
`bool unbalanced` semmit nem mondana arról, mit kell felvenni.

### D6 — A szintetikus korpusz első osztályú, MEGJELÖLT és kapu-képtelen

`ChordCorpusKind.synthetic` valódi állapot, nem hack; a
`gateEvidenceRefusal` egy **megnevezett indok** (nem dobott kivétel), így a
generált korpusz továbbra is legitim módon hajtja a validátort és a dekóder
plumbingot, de release-bizonyítékként visszautasított (Ch14 §12/2).

### D7 — A generátor seedelt, determinisztikus, és teszt-oldalon él

`test/features/live/evaluation/support/synthetic_chord_corpus.dart`:
Karplus–Strong pengetés + lecsengő harmonikus sorozat, minden támogatott
címke × voicing × tempó, `math.Random(seed + index)` gerjesztéssel. Nem
`lib/`-ben van, mert **soha nem szabad terméktermékké válnia**; a
`test/support/synth.dart` (más csomagok közös fájlja) érintetlen maradt.

## Ami MÉRVE van és ami NINCS

**Mérve:** a séma és a validátor viselkedése, a generátor determinizmusa és
seed-érzékenysége, a szintetikus korpusz kapu-visszautasítása, a
szótár-tükör, a grouped-split jólformáltsága.

**NINCS mérve:** minden, ami valós hangot igényel — osztályonkénti valós
support, telefon/szoba/távolság variancia, a §7.4/§7.5 chord-számok. Az út:
`gh workflow run chord-train.yml` (GuitarSet) a mérhető részre, és a
felhasználó felvételei a §7.1 többi dimenziójára
(`docs/eval/chord-corpus-plan.md`).
