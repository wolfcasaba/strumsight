# ADR 0179 — Vision capability-aware feedback

- **Státusz:** Elfogadva (E05-R01 pre-flight, 2026-08-06)
- **Kör:** E05-R01 — Vision baseline, alapozó ADR-ek
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  örökölt kézi override, `codex-round.sh`) — az ADR-eket az orchestrátor (Claude)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.2, §5.5, §7
- **Kontext-ADR-ek:** [0178](0178-vision-privacy-by-default.md),
  [0181](0181-vision-manual-calibration-fallback.md)

## Kontextus

A vision-visszajelzés minősége eszközfüggő: a kamera, a fényviszonyok, a
kalibráció és a modellképesség együtt döntik el, mit lehet megbízhatóan mérni.
Az SDD Ch6 §5.2 szerint a rendszer **nem** használhat egyetlen
`visionAvailable` booleant; képességenként kell státuszt vezetni (§5.2 lista:
`unavailable`, `initializing`, `available`, `availableDegraded`, `experimental`,
`blockedByPermission`, `blockedBySetup`, `blockedByDevice`, `failed`). A §5.5
alapelv: *no feedback is better than false feedback* — bizonytalan mérésnél nem
adunk technikai ítéletet.

## Döntés

1. **Minden vision insight kötelező mezői:** `requiredCapability` (a minimális
   képesség, ami az insightot méréssel alátámasztja), `confidence` (a mérés
   megbízhatósága) és `observability` (megfigyelhető-e egyáltalán ez a jelenség
   az adott capability-vel).
2. **Hiányzó megfigyelhetőség ⇒ `notObservable`, nem gyengébb ítélet.** Ha a
   szükséges capability nincs meg, vagy a confidence/visibility a küszöb alatt
   van, az insight `notObservable` státuszú, setup-javaslattal — nem pontszám-
   csökkentés és nem hosszú távú skill-evidence.
3. **A capability-státusz a domainé.** A `requiredCapability` és az insight
   observability determinisztikusan dől el a mért evidenciából, a generatív
   szöveg (AI Tutor) előtt (SDD §5.6); a Tutor megfogalmazhatja, de új vision
   claimet nem találhat ki.

**NEM elfogadható:** „ha nincs elég adat, adjunk általános technikai tanácsot"
vagy „becsüljük meg a legvalószínűbb hibát" — hiányzó megfigyelhetőség esetén az
egyetlen helyes kimenet a `notObservable` + setup-javaslat, sosem egy alább
alátámasztatlan negatív feedback vagy pontlevonás.

## Következmények

- A metrika-lista kétoszlopos (production-supported vs experimental),
  metrikánként `requiredCapability` + minimum observability-előfeltétellel; a
  baseline dokumentum ezt rögzíti.
- A `VisionInsight`/`VisionEvidence` domainmodell (SDD §9.6–9.7) e három mezőt
  kötelezővé teszi; a modell implementációja későbbi kör.
- A confidence-küszöbök és a `notObservable` UX külön körben, property teszttel
  védve készülnek.

## Elutasított alternatívák

- **Egyetlen `visionAvailable` boolean.** Elvetve: elrejti a degradált és a
  „megfigyelhetetlen" eseteket, és false feedbackhez vezet (SDD §5.2, §5.5).
- **Általános tanács fallbackként.** Elvetve: a mérhetetlen jelenségről adott
  „valószínű" ítélet pontosan az a false feedback, amit a §5.5 tilt.
- **Capability-státusz a generatív rétegben.** Elvetve: a determinisztikus policy
  a generatív szöveg előtt dönt (SDD §5.6), különben a Tutor kitalálhatna
  méréssel nem alátámasztott vision claimet.
