# ADR 0182 — Vision audio-priority degradation

- **Státusz:** Elfogadva (E05-R01 pre-flight, 2026-08-06)
- **Kör:** E05-R01 — Vision baseline, alapozó ADR-ek
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  örökölt kézi override, `codex-round.sh`) — az ADR-eket az orchestrátor (Claude)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.3, §5.4
- **Kontext-ADR-ek:** [0056](0056-exclusive-microphone-session.md) (audio lifecycle
  owner), [0178](0178-vision-privacy-by-default.md)

## Kontextus

A StrumSight elsődleges érzékelője az audio (akkord-/ritmus-/note-detektálás);
a vision opcionális, kiegészítő érzékelő (SDD Ch6 §2.3). A kamera + inference
pipeline CPU/GPU/thermal terhelése veszélyeztetheti az audio realtime
deadline-ját. Az SDD §5.3 latest-frame feldolgozást, a §5.4 fokozatos
degradációs láncot ír elő. Az AGENTS.md §9 tiltja a DSP audio ablak/hop
paraméterek felállítását nem-DSP okból.

## Döntés

1. **Audio-elsőbbség.** Ha az audio-feldolgozás deadline-ja romlik, a **vision**
   degradálódik, sosem az audio. Az audio a saját exkluzív session-owneréé
   marad ([ADR 0056](0056-exclusive-microphone-session.md)).
2. **Latest-frame, korlátlan queue nélkül.** Ha az inference lassabb a kameránál,
   a legfrissebb frame marad meg, a köztes frame-ek eldobhatók, a timestamp-
   folytonosság megmarad, és a dropped-frame count mérendő (SDD §5.3).
3. **Fokozatos degradációs lánc** (SDD §5.4 sorrendje): overlay-frekvencia ↓ →
   pose-pipeline ritkítás → hand-pipeline FPS ↓ → model-input felbontás ↓ → egy
   kéz követése → csak quality-monitor → vision leállítása, audio megtartása.

**NEM elfogadható:** az audio feldolgozási ablak, hop vagy bármely DSP-paraméter
módosítása a vision-teljesítmény javítása érdekében (AGENTS.md §9) — a vision
sosem nyerhet erőforrást az audio realtime-garanciájának rovására.

## Következmények

- A degradációs vezérlő és a dropped-frame metrika külön kör; a baseline a
  metrika-listában (experimental oszlop) rögzíti az observability-előfeltételt.
- A vision pipeline nem birtokolhatja az audio session lease-t; az audio owner
  változatlan (ADR 0056), a vision nem szerez audio-erőforrást.
- A latest-frame szabály a privacy-frame-élettartammal
  ([ADR 0178](0178-vision-privacy-by-default.md)) konzisztens: nincs korlátlan
  frame-history.

## Elutasított alternatívák

- **Szimmetrikus erőforrás-megosztás audio és vision között.** Elvetve: az audio
  a termék magja; a vision degradációja mindig olcsóbb, mint az audio akadása.
- **Frame-queue a simább vision-ért.** Elvetve: késleltetést és memórianyomást
  okoz, és sérti a latest-frame elvet (SDD §5.3).
- **DSP-ablak tágítása a vision terhelés kompenzálására.** Elvetve: AGENTS.md §9
  tiltja; a DSP-paraméter csak DSP-okból, mért baseline mellett változhat.
