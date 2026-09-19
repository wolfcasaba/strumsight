# ADR 0539 — Live felismerés-stabilitás: stabilizált hős-címke és onset-tranziens őr

**Státusz:** javasolt (2026-09-09, az E18-R01 emulátor-jelentés javító köre)

**Hatókör:** `lib/features/live/screens/live_screen.dart` (a Stage hős
címkéje), `lib/features/live/engine/recognition_stabilizer.dart` (őr-ablak),
`lib/features/live/widgets/chord_timeline.dart` + `providers/chord_timeline_provider.dart`
(a kártya lejárata — az E18-R01 F2/F3 lelet). **Nem** nyúl a
`engine/dsp/**` egyetlen konstansához sem (AGENTS.md §9).

Kapcsolódik: [ADR 0518](0518-recognition-stabilizer.md) (a stabilizátor —
ezt bővíti, a D1–D11 döntései érvényben maradnak), [ADR 0516](0516-chord-decision-merge.md)
(a keret-döntés egyetlen helye), [ADR 0520](0520-chord-uncertainty-reasons.md)
(a „miért nem” bannerek), `AGENTS.md` §5 („gyenge confidence nem jelenhet meg
biztos állításként"), `docs/rag/chunks/016-pitch-chord-sota.md` (rec #2: onset-
igazított frissítés — AS BUILT r138), a kutatási jegyzet:
[`docs/research/chord-recognition-stability-and-engines-2026-09.md`](../research/chord-recognition-stability-and-engines-2026-09.md).

## Kontextus — a MÉRT tünet (2026-09-09, a felhasználó gépén)

1. **„Egy leütött C-akkordnál más hangokra ugrál: egyszer jól mutatja, a
   következő C-nél elugrik más akkordra, majd vissza C-re — nem magabiztos.
   Mindegyik akkordnál, nem csak a C-vel."** (felhasználói jelentés)
2. Az E18-R01 emulátor-jelentés F2/F3: a Live időszalag hős-kártyája kint
   maradt a 87 %-os konfidencia-sávval, miközben a banner „No chord detected
   yet"-et mondott.

### A mechanizmus, amit a kód alapján azonosítottunk (hipotézis, valós
gitárral MÉG NEM mérve)

- A `ViterbiChordDecoder` minden pengetés-onset után **2 akkord-keretre
  (~186 ms) negyedére csökkenti az önátmenet-bónuszt** (chunk 016 rec #2,
  r138) — ez a „váltson gyorsan a pengetésen” funkció. Pont ez az ablak az,
  ahol a pengetés **attack-tranziense** a kromát a legkevésbé megbízhatóvá
  teszi (szélessávú energia + az előző akkord lecsengése a 370 ms-os NNLS
  ablakban). A chunk 016 r142 auditja ezt „onset-boost × transition-noise
  latch” kockázatként rögzítette, szintetikus reprodukció nélkül.
- A `RecognitionStabilizer` (ADR 0518) **3 egybehangzó, ~15 Hz-es keretet**
  kér az elmozdításhoz (≈200 ms). A 186 ms-os boost-ablak téves címkéje
  2–3 emittált keretet fed le → a 3. keretnél **megerősítődik**, a kártya
  átvált, majd a lecsengő C ismét 3 keret alatt visszaveszi. Ez pontosan a
  „C → más → C" tünet, minden akkordra.
- A Stage **hős** (`SsChordHero`) ráadásul a **nyers** `frame.current`
  címkét mutatta, nem a stabilizáltat (ADR 0518 D10: „a UI-oldal nincs
  benne") — vagyis a nagy akkord-felirat MINDEN egy-keretes blipet
  megmutatott, a stabilizátor csak az időszalagot védte.

## Döntés

### D1 — A Stage hős a STABILIZÁLT címkét mutatja

A hős címkéje az időszalag legújabb kártyájának akkordja (`timeline.last.chord`)
— kártya csak a stabilizátoron átment címkéből születik, tehát ez a
megerősített címke. A **jelenlétet** továbbra is a nyers keret dönti
(`hasChord = frame.current != null`): a kapu elengedésekor a hős azonnal
eltűnik; a nyers címke csak a hidegindítás tartaléka (üres időszalag).
Következmény: egy valódi akkordváltásnál a hős a megerősítésig (≈ D2 őr +
3 keret) az előző megerősített akkordot mutatja — ez a „tartsd az utolsó
értéket” viselkedés, nem hamis állítás (a kapu nyitva, a címke a legutóbb
megerősített). **Az akadálymentes bejelentés (ADR 0280 §2) is a stabilizált
címkét mondja** — a képernyőolvasó nem hallhat olyan egy-keretes blipet,
amit a látó felhasználó már nem lát; az E13-R18 A5 throttle-cellái ezért
megerősített (3 keretes) váltásokat küldenek.

### D2 — Onset-tranziens őr a stabilizátorban

A `RecognitionStabilizer` kap egy `onsetTransientGuardSec` paramétert
(alapértelmezés **0.2 s** = a dekóder 2 × 93 ms-os boost-ablaka + onset-
késés). Egy elmozdítási jelölt keretei, amelyek az utolsó onsethez
(`frame.latestStrumTime`) ennél közelebb vannak, **nem számítanak** az
egyezés-számlálóba: a jelölt címke megmarad, az állapot `provisional`, a
keret eldobva. A számláló az attack után indul. Ha a keretnek nincs onset-
ideje (`latestStrumTime < 0` vagy `engineTimeSec < 0` — mockok, régi
tesztek), a számolás a régi (ADR 0518 D3). `0` kikapcsolja.

- **Ára:** egy valódi váltás megerősítése ~200 ms-ról ~400 ms-ra nő
  (0.2 s őr + 3 keret). A felhasználó kérése kifejezetten a stabilitás.
- **Nem időzítő:** az őr a keret SAJÁT `engineTimeSec`/`latestStrumTime`
  mezőiből számol, fal-óra nélkül — ADR 0518 D3 szellemében determinisztikus.
- **Felépülési út (ADR 0518 D6) érvényben:** egy tartósan megváltozott
  akkord az őr-ablak utáni `minAgreeFrames` kereten MINDIG megerősítődik
  (property-cella őrzi).

### D3 — A kártya lejár a kapuval (E18-R01 F2/F3)

- `ChordTimeline.hasCurrent`: ha a keret szerint nem szól akkord, a legújabb
  kártya a történetbe hátrál, a hős-helyen az „Play a chord…” prompt áll —
  konfidencia-szám nélkül.
- `reduceChordTimeline` 2. szabály: ha a keretből **eltűnt** a pengetés
  (a motor 2 s után ejti a `latestStrum`-ot) és a kártya még mutat irányt,
  a kártya helyben törli az irányt és a konfidenciát (`ChordEvent.withoutStrum`).
  A tétel a property-kapuban is mérve (randomizált invariáns).

### D4 — A dekóder attack-ablaka NEM változik ebben a körben

A legvalószínűbb gyökérok (a boost-ablak az attack-on) dekóder-oldali
javítása — a bónusz-csökkentést az onset utáni **második és harmadik**
akkord-keretre tolni (a sustain-en váltson, ne az attack-on) — DSP-döntési
paraméter (AGENTS.md §9): fixture + property + **valós gitáros mérés** nélkül
tilos. A remote konténerben nincs Flutter SDK és nincs mikrofon; a javaslat és
a mérési protokoll a kutatási jegyzet §4-ében van, az E18-R01 emulátor-
jelentés loopback-módszerével (64 kbps MP3 helyett WAV). Ez a következő kör
(E18-R05 javaslat) tárgya, a felhasználó boxán.

## Mérce

- `test/features/live/recognition_stabilizer_onset_guard_test.dart` — az őr
  hármas cellája (blip nem vált; valódi váltás megerősítődik; őr nélkül a
  régi számolás) + randomizált property (`PROPERTY_SEED`).
- `test/features/live/live_stage_test.dart` A2b/A2c — a kártya lejárata és a
  stabilizált hős, a valódi `LiveScreen`-en, `FakeStrumEngine`-nel.
- `test/property/chord_timeline_property_test.dart` — a 2. szabály bővítése
  (pengetés-lejárat helyben töröl) a randomizált invariánsokban.
- `test/features/live/recognition_stabilizer_test.dart` — az ADR 0518 mátrix
  VÁLTOZATLANUL zöld kell legyen (a keretek onset-idő nélkül jönnek → az őr
  inert).
- **A végső mérce a valós gitár** (HORIZON): a szintetikus zöld nem „kész".

## Következmények

- A Live hős és az időszalag mostantól UGYANAZT a megerősített címkét
  mutatja; a „miért nem” bannerek száma nem nő (sőt az F2 miatt kevesebb
  magyarázat kell — E18-R01 F13 megjegyzés).
- Az onset-ablak dekóder-oldali kérdése nyitott; a valós mérés dönt
  (E18-R05).
