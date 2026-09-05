# E14-R12 review — Provisional → confirmed stabilizátor állapotgép

- **Kör:** `E14-R12`, branch `sonnet-impl/e14-r12-recognition-stabilizer`
- **Reviewer:** Claude (Opus 5), orchestrátor-szék, **read-only** (a kód
  javítását a javító kör végzi; a kör SAJÁT, még nem merge-elt ADR-jét és
  briefjét az orchestrátor módosítja — ADR 0087 §2)
- **Reviewelt HEAD:** `50dcca56` (pre-flight alap: `0f7069fd`)
- **Dátum:** 2026-09-05
- **Verdikt (1. menet):** **CHANGES REQUESTED** — 0 BLOCKER, 1 MAJOR,
  2 MINOR, 2 NOTE

## 0. Amit MÉRTEM (nem olvastam, hanem futtattam)

| Mérés | Eredmény |
|---|---|
| `scope_audit` a `0f7069fd` alapon | `ok`, 7 fájl — mind az `allowed_paths`-on |
| Munkafa a jelzéskor | tiszta (`git status --short` üres a `50dcca56`-on) |
| `reduceChordTimeline` diff | a tiszta reducer törzse **érintetlen**; csak a `ChordTimelineController.build()` változott (ADR 0518 D5 teljesül) |
| Cold-start próbateszt (lásd MAJOR-1) | izolált `/tmp/e14r12-verify` klón, a `_confirmedLabel == null` ág törölve → `+13 -3`, pontosan a §10.2-ben megnevezett 3 cella piros |

## MAJOR-1 — A cold-start kivétel a kör szerződésén KÍVÜL született, és nincs saját gépi mércéje

**Mit találtam.** A `RecognitionStabilizer.stabilize`
(`lib/features/live/engine/recognition_stabilizer.dart:88-94`) a legelső
valaha látott eldöntött címkét **ránézésre** megerősíti, miközben az ADR 0518
D1/D3 szövege szó szerint egységes `agreeFrames >= minAgreeFrames` küszöböt
írt elő MINDEN címkére. Az implementer ezt a §10.2-ben becsületesen jelezte,
és nem próbálta elrejteni — a lelet nem a titkolás, hanem hogy (a) a kör
normatív szövege nem mondta ki, és (b) **egyetlen cella sem pinneli**: a
matrix-cellák `bootstrapped()` segédfüggvénye HASZNÁLJA a kivételt, de nem
méri; egy jövőbeli refaktor kiterjeszthetné az elmozdításra is anélkül, hogy
bármi pirosra menne (a 3b cella egy MÁR megerősített A ellen mér, tehát nem
fogná meg a „minden ÚJ címke ránézésre megerősül" hibát… kivéve az
első blip esetét — de ez nem szándékolt őr, hanem véletlen fedés).

**Miért NEM a kód visszaállítása a javítás.** Függetlenül reprodukáltam: a
kivétel nélkül a kör `allowed_paths`-án KÍVÜLI három cella pirosra megy
(`live_screen_test.dart` „Live renders the current chord + its strum on the
timeline hero", `live_stage_test.dart` A1 és A2) — mindhárom EGYETLEN keretet
emittál és azonnali timeline-visszajelzést vár. Ezek átírása H3 volna. A
kivétel maga védhető: a küszöb tárgya az **elmozdítás**, üres timeline mellett
nincs mit elmozdítani, és az a keret a pipeline saját kapuját (ADR 0516) már
megjárta.

**A feloldás (megtörtént / kért):**
1. *(orchestrátor, kész)* **ADR 0518 D11** — a cold-start kivétel kimondva, a
   MÉRT indoklással, a reprodukáló paranccsal és az árával együtt; a brief
   §5.2 + §6 pt.8 + §6.1 mátrix ehhez igazítva.
2. *(javító kör)* **saját cella** a `recognition_stabilizer_test.dart`-ban:
   (a) friss stabilizátor `chordState == RecognitionDecision.candidate` még
   egyetlen keret előtt; (b) az első eldöntött címke ránézésre `confirmed` és
   a keret átmegy; (c) a kivétel **csak egyszer** tüzel — a MÁSODIK, ELTÉRŐ
   címke 2 kereten `null` + `provisional`, és csak a 3.-on megy át.

## MINOR-1 — A `candidate` állapotot a D1 kimondja, de egyetlen cella sem méri

`RecognitionDecision.candidate` a `_chordState` kezdőértéke
(`recognition_stabilizer.dart:39`), de a tesztfa sehol nem állítja. A D1
háromállapotú szerződéséből ma kettő van pinnelve. A MAJOR-1 (a) alpontja
ezt lefedi — a javításnak ott a helye.

## MINOR-2 — A `flipRate` a cold-start megerősítést is flipnek számolja, a getter doksija nem mondja ki

`_confirmedFlips++` a cold-start ágon is fut
(`recognition_stabilizer.dart:90`), így a §10.4 mért `GUIDED flipRate =
1/13` valójában „0 elmozdítás + 1 alapállapot-felvétel". A metrikát az R09
release gate fogja olvasni; a jelentés akkor honest, ha a getter doksija
kimondja, hogy a **nulláról felvett** alapállapot is beleszámít. Egy sor
doc-comment, viselkedés-változás nélkül.

## NOTE-1 — Az üres (idle) keret nem szakítja meg a futó egyezés-sorozatot

`current == null` esetén a `stabilize` átengedi a keretet a számláló
érintése nélkül (`:72-73`), tehát `B, [idle ×100], B, B` megerősíti B-t, és a
latency a 100 üres keretet is számolja. Ez konzisztens a
`confirmationLatencyFrames` doksijával („includes any interleaved idle
frames") és a reducer 1. szabályával (idle → változatlan puffer). Nem kérek
változtatást; a jövőbeli R13/R09 tudjon róla.

## NOTE-2 — Az azonos `strumSeq`-ű, ellentétes irányú keret a TELJES keretet ejti

`_admitStrum == false` → a keret akkord-evidenciája is elveszik arra a
keretre (`:70`). Ez az ADR 0518 D7 tudatos ára, és ma nincs ilyen termelő a
fában (a pipeline eseményenként egyszer állítja a `latestStrum`-ot, a
`strumSeq` eseményenként nő) — előre-védő szerződés marad.

## Amit KÜLÖN ellenőriztem és RENDBEN van

- **Nincs második szótár:** az állapot a merge-elt `RecognitionDecision`; a
  fájl nem deklarál új állapot-enumot (`StabilizerProfile` küszöb-hordozó,
  nem döntési állapot) — ADR 0518 D1.
- **Nincs második megerősítési kapu:** a stabilizátor nem olvas
  konfidenciát, tonalness-t, jel-minőséget; bemenete a MÁR eldöntött keret
  (`frame.current != null`) — ADR 0518 D2, az ADR 0516 döntési helye
  érintetlen (a `live_pipeline.dart` nincs a diffben).
- **Nincs időzítő:** `grep -n "Future\|Timer\|DateTime" recognition_stabilizer.dart`
  → nulla találat; a mérce a keret-számláló — ADR 0518 D3.
- **A profil paraméter:** egyetlen állapotgép, `enum StabilizerProfile` a
  küszöbbel; nincs `if (guided)` ág — ADR 0518 D4.
- **A reducer bit-azonos:** a `test/property/chord_timeline_property_test.dart`
  módosítatlan és zöld (9/9) — ADR 0518 D5, L593.
- **Felépülési út:** eltérésre nullázódó számláló + a 6. pont cellája
  (16 keretnyi váltakozó zaj után is megerősít) — ADR 0518 D6, L165.
- **`autoDispose` provider**, a UI-fájlok érintetlenek — D9/D10.

## Verdikt

**CHANGES REQUESTED** — a MAJOR-1 (b) pontja (a cold-start cella) a javító
kör feladata; az (a) pont és a normatív szöveg (ADR D11 + brief) már kész.
