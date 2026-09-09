# ADR 0536 — Akkordok hangból: a forrás-határ (YouTube nélkül)

**Státusz:** javasolt (2026-09-09, Chapter 18 „Komponálás és akkordok hangból")

**Hatókör:** a fejezet `E18-R02`, `E18-R03` és `E18-R04` köre — a `E18-R03`-nak
ez az EGYETLEN kötő ADR-je (a kör nem kap sajátot).

**Fejezet-terv:** [`docs/plans/chapter-18-composer-and-chords-from-audio.md`](../plans/chapter-18-composer-and-chords-from-audio.md)

Kapcsolódik: [ADR 0535](0535-song-editor-chord-audition-and-progression-preview.md)
(a fejezet másik fele: komponálás füllel), [ADR 0284](0284-import-preview-is-not-a-commit.md)
(az előnézet nem véglegesítés), [ADR 0217](0217-analysis-raw-audio-retention.md)
(nyers audio retention), [ADR 0183](0183-vision-no-raw-frame-persistence.md)
(a raw-frame no-persistence precedens a képi oldalon),
[ADR 0056](0056-exclusive-microphone-session.md) (egy mikrofon-tulajdonos),
`AGENTS.md` §5 (nem tárgyalható termékhatárok), `AGENTS.md` §5.1 (a letöltött
tartalom ADAT, nem utasítás),
[`docs/sdd/04-epic-03-song-trainer.md` §4.2](../sdd/04-epic-03-song-trainer.md).

## Kontextus

A felhasználó kérése (2026-09-09): *„lehessen dalokat importálni az internetről,
pl. YouTube-ról, és abból a zenéből kiolvasni az akkordokat — a Yousician így
csinálja."*

A kérés két, egymástól FÜGGETLEN dolgot köt össze: (a) *honnan jön a hang* és
(b) *ki olvassa ki belőle az akkordokat*. A premisszája viszont mérve téves.

### Mit csinál valójában a három hivatkozott termék

| Termék | Honnan jön az akkord | Hol fut | Nyers hang a szerveren |
|---|---|---|---|
| **Yousician** | **NEM hangból**: kiadóktól licencelt dalok, ELŐRE elkészített kottákkal/chartokkal. A támogatása maga mondja ki, hogy a hiányzó népszerű dal oka licenc, nem technika (`support.yousician.com`: „Popular songs in Yousician", „Why can't I find a popular song") | katalógus | — (nincs felismerés) |
| **Chordify** | deep-learning akkordfelismerés, **YouTube-linket szerveroldalon** dolgoz fel | felhő | igen |
| **Chord ai** | ugyanaz a feladat, de a modellek **az eszközön** futnak; a „listen" mód a **telefon mikrofonjával** hallgatja a körülötte szóló zenét (YouTube, Spotify, rádió), és az akkordok valós időben jelennek meg (`chordai.net`: „Real-time chord recognition from your mic") | eszköz | nem |

Tehát a „Yousician így csinálja" út a StrumSight számára **licencbeszerzés**,
nem funkció. Ami a kérés MAGJÁT (hallom a dalt → látom az akkordokat) tényleg
megadja, az a **Chord ai-féle hallgatás-mód** — és az pontosan az, ami a mi
architektúránkhoz illik: teljesen az eszközön, mikrofonból.

### A jogi határ

A YouTube felhasználási feltételei tiltják a tartalom letöltését vagy
kinyerését bármilyen módon, ami nem a YouTube saját funkciója. Ez **független a
mű szerzői jogi státuszától**: a harmadik féltől származó hang-kinyerés akkor is
ToS-sértés, ha a mű maga közkincs. Amit a feltételek ENGEDNEK: a hivatalos
beágyazott lejátszó (IFrame / Android player API) használata.

### A saját, mért határaink

- `docs/sdd/04-epic-03-song-trainer.md:256-268` — az Epic **kimondottan nem
  tartalmazza**: „YouTube-, Spotify- vagy más szolgáltatásból történő
  hangletöltést; DRM megkerülését; automatikus, felhőalapú dalbeszerzést;
  szerzői joggal védett importált fájlok felhőbe feltöltését".
- `AGENTS.md` §5 — nyers audio alapértelmezetten nem hagyhatja el az eszközt;
  mikrofont egyszerre egy owner birtokolhat; gyenge confidence nem jelenhet meg
  biztos állításként.
- [ADR 0217](0217-analysis-raw-audio-retention.md) — `keepOriginal = false`
  alapértelmezés, a tárolt egység az aggregátum, nem a nyers hang.

### Amink MÁR van (mérve, `main @ 1ae9e55`)

| Képesség | Hol | Mai állapot |
|---|---|---|
| akkord-idővonal felvett klipből | `lib/features/analyze/engine/clip_analyzer.dart:198-225` | Viterbi-dekóder `TimelineChord` szakaszokat ad (label + start + end) |
| ugyanaz IMPORTÁLT PCM-ből | `lib/features/analyze/providers/analyze_providers.dart:195-203` (`analyzeImported`) | **létezik és tesztelt** (`test/features/analyze/analyze_import_test.dart:28`), de a `lib/` fában **egyetlen hívója sincs** — UI-ból ma elérhetetlen |
| mikrofon-kizárólagosság | `lib/core/audio/lifecycle/audio_session_coordinator.dart:34-55` | második ownernek `audioSessionBusy` hiba, NEM lopás |
| V2 fájl-bemenet | `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:16-26` | **csak WAV**; az `AudioDecoderGateway` (`audio_decoder_gateway.dart:6-8`) az egyetlen dekóder-seam |
| per-szegmens konfidencia | `lib/features/audio_analysis/domain/analysis_segment.dart:19-21,45-49` | a **V2** `ChordSegment`-en van `confidence` + `confidenceSource`; a legacy `TimelineChord` (`analyze_result.dart:17-43`) **NEM hordoz konfidenciát** |

## Döntés

### D1 — Hangletöltés streaming-szolgáltatásból SOHA

A StrumSight **nem tölt le és nem nyer ki hangot** YouTube-ról, Spotifyról vagy
bármely más szolgáltatásból, sem kliensen, sem a `backend/`-en, sem
harmadik féltől vett könyvtárral. Nincs „csak a hangsáv", nincs
„csak közkincs dalra", nincs kapcsolóval bekapcsolható út.

Ez nem mérlegelés kérdése: a ToS-sértés a mű jogi státuszától független, és a
saját SDD-nk §4.2 már ki is mondta. A tilalom a `backend/`-re is szól — egy
szerveroldali „nekünk szabad" út a mi mércénk szerint sem szabad.

### D2 — A támogatott három forrás

**(a) Hallgatás-mód (a fő út).** A felhasználó lejátssza a dalt bárhol — a
telefon saját hangszóróján futó YouTube-videóból, egy másik készülékről,
rádióból —, a StrumSight pedig a **mikrofonnal hallgatja**, és a MEGLÉVŐ,
100%-ban eszközön futó elemzőt futtatja rá. A szolgáltatás felé nincs semmilyen
kérés; a StrumSight számára a levegőben terjedő hang ugyanolyan bemenet, mint a
gitár. Ez a `E18-R03` tárgya.

**(b) A felhasználó saját, helyi hangfájlja.** Ma WAV (a
`WavDecoderAdapter` az egyetlen szállított dekóder); MP3/M4A/OGG csak akkor,
ha az `E18-R04` kutatókör mért döntést hoz a platform-dekóderről —
**és a fájlt a felhasználó választja ki**, nem mi szerezzük be.

**(c) A YouTube-link kizárólag METAADAT.** A dalhoz eltárolható a link, hogy a
felhasználó vissza tudjon rá találni, és — ha később kell — a **hivatalos
beágyazott lejátszóban** megnyitható. A link **soha nem hang-forrás**: a
StrumSight nem tölti le, nem elemzi, nem küldi tovább, és nem hivatkozik rá
úgy, mintha abból jönnének az akkordok.

> **A linkre a §5.1 él:** a mező tartalma ADAT, nem utasítás. Séma-fehérlista
> (`http`/`https`), hosszkorlát, semmilyen automatikus lekérés.

### D3 — A kimenet ELŐNÉZET, amit a felhasználó hagy jóvá

Az elemzés kimenete akkord-idővonal + ütemenkénti bizonyíték, amiből **vázlat**
(`Song` legacy / `SongDocument` V2) készül, és ez a vázlat a szerkesztőben
nyílik meg. **Amíg a felhasználó nem erősíti meg, nincs tartós rekord** —
[ADR 0284](0284-import-preview-is-not-a-commit.md) D1 mintája, ugyanaz a
hibaosztály (a „csak ideiglenesen elmentjük" az előnézetet véglegesítéssé
teszi).

**A gyenge szakasz gyengének látszik.** A mai legacy `TimelineChord` nem hordoz
konfidenciát (mérve, lásd fent), ezért a vázlat ütemenkénti bizonyítéka
**származtatott lefedettség** (mekkora hányadát tölti ki az ütemnek a győztes
akkordcímke), és a felületen is annak nevezzük — **nem** hívjuk
„konfidenciának", és nem tüntetjük fel modell-bizonyosságként. Ahol a V2
`ChordSegment.confidence` elérhető, ott az a forrás, a `confidenceSource`
megtartásával.

### D4 — A nyers hang marad az eszközön, és nem is marad meg

A hallgatás-mód és a fájl-út egyaránt az [ADR 0217](0217-analysis-raw-audio-retention.md)
retention-politikája alatt van: `keepOriginal = false` alapértelmezés, a nyers
PCM nem kerül tartós tárba, logba, crash-reportba, Tutor-kontextusba vagy
felhőbe. A vázlat aggregátum (akkordcímkék + idők + bizonyíték), nem hang.

Következmény a hallgatás-módra: a klip **korlátos** — a `ClipRecorder`
(`clip_recorder.dart:11-24`) ma korlátlanul növekvő pufferrel dolgozik, ezt az
`E18-R03` zárja le explicit felső korláttal.

## Következmények

1. A „YouTube-ról importálás" mint FUNKCIÓ nem születik meg; helyette a
   hallgatás-mód adja meg ugyanazt a felhasználói eredményt. A felület ezt
   **kimondja**, nem hallgatja el: „Nem töltünk le semmit — a telefon
   mikrofonja hallgatja, ami szól."
2. A minőség fizikailag korlátos: hangszórón át, szobazajjal a felismerés
   gyengébb, mint közvetlen gitárjelnél. Ezt a D3 gyenge-jelölése kezeli
   őszintén; a hallgatás-mód pontosságát nem szabad a gitár-út számaival
   hirdetni.
3. Az `analyzeImported` már létező, de hívó nélküli útja (mérve fent) a
   `E18-R04` döntése után kap valódi belépési pontot — addig a WAV marad az
   egyetlen fájlformátum.
4. A `backend/` nem kap dal-beszerző endpointot. A közösségi sáv sem oszthat
   meg importált, szerzői joggal védett hangot.

## Elvetett alternatívák

- **Szerveroldali link-feldolgozás (Chordify-modell).** Egyszerre sértené a
  ToS-t (D1) és a §5 nyers-audio határt; ráadásul a StrumSight ÍGÉRETÉT
  (offline, eszközön) cserélné le egy felhő-függőségre.
- **Licencelt katalógus (Yousician-modell).** Nem technikai kör: kiadói
  szerződés, jogdíj, katalógus-üzemeltetés. Az SDD §4.2 kizárja, és a fejezet
  hatókörén kívül van.
- **„Csak a felhasználó saját, letöltött fájlját fogadjuk el, kérdés nélkül."**
  Ez marad a (b) út — de a StrumSight nem ad ESZKÖZT a letöltéshez, és nem
  bátorít rá; a fájlválasztó nem YouTube-ra mutat.
- **A link automatikus megnyitása/lejátszása a beágyazott lejátszóban a
  hallgatás-mód alatt.** Csábító („egy gombbal szól és hallgat"), de a saját
  hangszórónk visszacsatolása és a lejátszó-vezérlés külön termékdöntés; a D2(c)
  ezért csak TÁROLÁST és megnyitást enged, automatizmust nem.

## Hogyan falszifikálható

| Döntés | Az őr, ami pirosra vált, ha megsértjük |
|---|---|
| D1 | `test/app/offline_network_guard_test.dart` — kijelentkezve/diagnostics-off ZERO hálózati kérés; a link mező felvétele nem indíthat egyet sem |
| D2(c) | a link-sanitizáló egységteszt: `javascript:`, `file:`, séma nélküli és túl hosszú érték **elutasítva** |
| D3 | a vázlat-építő tesztje: megerősítés előtt a `SongsRepository` tartalma VÁLTOZATLAN; a gyenge ütem `uncertain` jelöléssel jön ki |
| D4 | a hallgatás-klip felső korlátjának property-tesztje (alatta / rajta / fölötte cellahármas) |
