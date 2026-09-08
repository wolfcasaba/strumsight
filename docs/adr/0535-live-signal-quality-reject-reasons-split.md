# ADR 0535 — A Live jel-minőségi elutasítási ok SZÉTVÁLASZTÁSA: hat tipizált ok a merge-elt `signalQuality` gyűjtő helyett

**Státusz:** elfogadva (2026-09-08) · **Kör:** E17-R15 · **Felülírja részben:** ADR 0516 D4 táblázat 2. sora, ADR 0520 D1 „hatelemű" megfogalmazása

## Kontextus (mért)

- A motor (`lib/features/live/engine/quality/live_signal_quality_analyzer.dart`,
  ADR 0507) HAT nem-`good` állapotot különböztet meg — `tooQuiet`, `tooLoud`,
  `clipping`, `tooNoisy`, `speechLike`, `unstable` — saját küszöbbel és
  prioritás-sorrenddel (`_classify`).
- A döntési pont (`lib/features/live/engine/dsp/live_pipeline.dart`,
  `debugDeriveChordDecision`, ~L334) MIND A HATOT egyetlen
  `RecognitionRejectReason.signalQuality` okba gyúrja.
- A banner (`lib/features/live/widgets/uncertainty_reason_banner.dart`, ADR 0520)
  ebből EGY szöveget mutat: *„Signal too weak to tell — move closer to the mic"*.
  Túl hangos vagy túlvezérelt (clipping) jelnél ez a tanács a helyzetet
  RONTJA; zaj/beszéd/ingadozás esetén irreleváns. Ez a „confidently wrong"
  osztály (ADR 0271 §1), csak most a tanácsban, nem a verdiktben.
- Az onboarding audio-setup (`audio_setup_controller.dart::_adviceFor`) már
  állapotonként ad tanácsot — a Live ettől elmaradt.

## Döntés

### D1 — A szótár a domain rétegben bővül, nem a UI-ban (ADR 0520 D1 szellemében)

`RecognitionRejectReason`-ból a `signalQuality` tag **törlődik**, helyére HAT
tag lép, pontosan ebben a névvel:

| `SignalQualityState` | `RecognitionRejectReason` |
|---|---|
| `tooQuiet` | `signalTooQuiet` |
| `tooLoud` | `signalTooLoud` |
| `clipping` | `signalClipping` |
| `tooNoisy` | `signalTooNoisy` |
| `speechLike` | `signalSpeechLike` |
| `unstable` | `signalUnstable` |

A `signal` előtag kötelező: a meglévő `unstable` (akkord-szintű: „tartsd
stabilan az akkordot") és a jel-szintű `signalUnstable` (hangerő ingadozik)
KÜLÖNBÖZŐ jelentés, nem vonható össze. Gyűjtő/„egyéb" tag TILOS — pont ez volt a
hiba. A szótár tagszáma 6 → 11.

### D2 — A leképezés a motorban, kimerítő `switch`-csel, `default` NÉLKÜL

`debugDeriveChordDecision` a `SignalQualityState` felett kimerítő `switch`
kifejezéssel ad okot; `good` és `unknown` esetén NEM ad jel-minőségi okot (ez
a mai viselkedés, változatlan). A prioritás változatlan (ADR 0516 D4): a
jel-minőség ELŐBB dönt, mint a `noChord`/`lowConfidence`. Új küszöb, új DSP
paraméter NINCS — a `docs/rag/chunks/live-signal-quality.md` csak a leképezést
dokumentálja.

### D3 — Hat új szöveg, mindkét locale-ban, páronként különböző, és SOHA nem káros

A `liveRejectSignalQuality` kulcs törlődik; hat új kulcs
(`liveRejectSignalTooQuiet`, `liveRejectSignalTooLoud`,
`liveRejectSignalClipping`, `liveRejectSignalTooNoisy`,
`liveRejectSignalSpeechLike`, `liveRejectSignalUnstable`) a
`lib/l10n/base/app_{en,hu}.arb` FORRÁS-szegmensbe kerül (ADR 0520 D7), és az
aggregátumot a `tool/gen_l10n_segments.dart` sorrendje szerint kell frissíteni.
Tartalmi őr (gépi teszt): a `tooLoud`/`clipping` szöveg NEM tartalmazhat
„közelebb"/„closer" tanácsot; a `tooQuiet` NEM tartalmazhat
„távolabb"/„back"/„further" tanácsot.

### D4 — Wire-kompatibilitás: a `signalQuality` névérték eltűnik

`RecognitionRejectReason.fromJson('signalQuality')` ezentúl tipizált hibát dob
(ADR 0505 D6: nincs „biztonságos" visszaesés). Mért tény: a `lib/` alatt
NINCS olyan hely, ahol `ChordPrediction`/`RecognitionFrame` JSON-t
perzisztálnak és visszaolvasnak (csak in-memory és teszt-fixture), tehát
migráció nem szükséges. Ha a jövőben Lab-felvétel perzisztál ilyen JSON-t, az
a kör felel a migrációért.

### D5 — A képernyő továbbra sem hoz döntést (ADR 0520 D4–D6 érintetlen)

A `live_screen.dart` nem változik: a banner a `chordRejectReason` egyetlen
mezőjéből dolgozik, a heurisztikus gyenge-jel figyelmeztetés (`isWeakSignal`)
a „nincs döntés" esetre marad.

## Következmények

- A `recognition_frame_contract_test.dart` „exactly six" cellája a 11-tagú
  halmazra frissül — ez a spec változása, nem gyengítés.
- A banner kimerítő `switch`-e fordítási hibával kényszeríti ki mind a hat
  új ágat (ADR 0520 D2).
- Az onboarding `_adviceFor` és a Live banner tanácsai tartalmilag
  összhangban vannak (a szövegek eltérnek, a tanács iránya azonos).
