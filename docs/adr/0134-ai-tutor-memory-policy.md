# ADR 0134 — AI Tutor memory policy

- **Státusz:** Elfogadva (E04-R01 pre-flight, 2026-08-04)
- **Kör:** E04-R01 — AI Tutor baseline, ADR-ek és feature flagek
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md)
- **Kontext-ADR-ek:** [0132](0132-ai-tutor-privacy-and-consent.md)

## Kontextus

A tutor személyre szabáshoz tanulási adatokat (memory factek, célok,
hangszeradatok, preferenciák) használ (SDD Ch5 §1, §393–397). A felhasználónak
képesnek kell lennie megtekinteni és törölni az AI által használt személyes
adatokat (Ch5 §397, §504, §2466–2470). Ha a memory átláthatatlan vagy
szerver-first lenne, a felhasználó elveszítené a kontrollt a saját adatai
felett.

## Döntés

1. **Local-first:** minden tutor-memory alapértelmezetten a készüléken él.
   Tartós szerveroldali tárolás csak külön consenttel (ADR 0132), és az sem
   automatikus következménye a cloud model-use-nak.
2. **Megtekinthető:** a felhasználó látja a tutor által tárolt memory facteket,
   célokat és a consent-állapotot.
3. **Szerkeszthető / törölhető:** egyes memory factek szerkeszthetők vagy
   törölhetők; a teljes memory törölhető.
4. **Dokumentált retention:** a megőrzési (retention) szabály dokumentált; nincs
   csendes, határozatlan idejű felhalmozás.

## Következmények

- A memory repository (local-first), az inspect/edit/delete UI és a retention
  flow későbbi körök felelőssége; ez a kör csak a policyt rögzíti a
  baseline-dokumentumban — greenfield, még nincs memory-kód.
- A memory-modell nem tartalmazhat nyers audiót (ADR 0132) és nem szivárogtathat
  provider-specifikus típust (ADR 0131).
- Ez a döntés nem lazítható azért, hogy egy teszt zöld legyen.
