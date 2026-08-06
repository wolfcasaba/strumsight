# ADR 0183 — Vision no-raw-frame persistence

- **Státusz:** Elfogadva (E05-R01 pre-flight, 2026-08-06)
- **Kör:** E05-R01 — Vision baseline, alapozó ADR-ek
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  örökölt kézi override, `codex-round.sh`) — az ADR-eket az orchestrátor (Claude)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.1, §9.8
- **Kontext-ADR-ek:** [0178](0178-vision-privacy-by-default.md),
  [0179](0179-vision-capability-aware-feedback.md)

## Kontextus

A privacy-by-default ([ADR 0178](0178-vision-privacy-by-default.md)) kimondja,
hogy raw frame nem kerül tartós tárba. A vision-session mégis termékértéket
hordoz: a felhasználó fejlődését aggregált eredményben kell rögzíteni. Az SDD
Ch6 §9.8 a `VisionSessionResult` aggregátumot definiálja mint a persistence
egységét. Kérdés: mit szabad a persistence rétegnek tárolnia.

## Döntés

1. **A persistence rétegben raw kép és teljes landmark-idősor alapértelmezetten
   nem tárolható.** A tárolt egység a `VisionSessionResult` aggregátum: insight +
   capability + confidence + model-verzió (a mérés reprodukálható eredetéhez), a
   nyers frame és a képkockánkénti teljes landmark-stream nélkül.
2. **A model-verzió a résznek eredetet ad.** Minden tárolt eredmény hordozza a
   generáló model-verziót (SDD §30 manifest-lánc), hogy egy későbbi modellváltás
   után is értelmezhető maradjon.
3. **Kivétel csak a consentelt Lab capture.** A raw frame kizárólag a
   `visionLabCaptureEnabled` flag mögött, explicit consenttel rögzíthető
   ([ADR 0178](0178-vision-privacy-by-default.md)) — a production persistence útja
   ettől érintetlen marad.

**NEM elfogadható:** a raw frame, egy „reprezentatív" kimentett kép vagy a
teljes képkockánkénti landmark-idősor tartós tárba írása a
`VisionSessionResult` aggregátum részeként, még „a coaching javításához" vagy
„debug célra" indoklással sem — a Lab-flagen kívül nincs raw-persistence.

## Következmények

- A `VisionSessionResult` domainmodell és a persistence-adapter külön kör; ez az
  ADR a tárolható mezőkészletet rögzíti.
- A privacy-teszt (E05 későbbi kör) property/unit szinten őrzi, hogy a
  persistence útján raw frame vagy teljes landmark-stream nem hagyja el a
  memóriát a Lab-flagen kívül.
- Konzisztens a latest-frame szabállyal
  ([ADR 0182](0182-vision-audio-priority-degradation.md)): nincs korlátlan
  frame-history sem futásidőben, sem tárban.

## Elutasított alternatívák

- **Egy reprezentatív frame mentése session-enként.** Elvetve: egyetlen raw kép
  is a legérzékenyebb adat; az aggregátum + insight elegendő a termékértékhez.
- **Teljes landmark-idősor tárolása a jövőbeli elemzéshez.** Elvetve: gyakorlatilag
  rekonstruálható belőle a mozgás/kép; a §5.1 privacy-elvet sértené.
- **Model-verzió elhagyása a helytakarékosságért.** Elvetve: eredet nélkül a
  tárolt eredmény egy modellváltás után értelmezhetetlenné válik (SDD §30).
