# ADR 0318 — Song goal public boundary és caller-fed bemenet

**Státusz:** elfogadva (2026-08-18). Az Epic 7 Song goal integrációs döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 24. Épít: [ADR 0262](0262-catalog-snapshot-revisions-and-capability-truth.md), [ADR 0264](0264-explainable-priority-and-versioned-policy.md) és [ADR 0268](0268-technical-failure-is-not-skill-failure.md).

## Kontextus

A Song goal tervezőnek szakaszra, asset-referenciára és revízióra van szüksége. A pre-flight mérése szerint a Song Trainer feature felső `public.dart`-ja csak presentation screeneket exportál; a `domain/public.dart` a `SongDocument`-et és strukturális modelljeit exportálja, de repositoryt nem. Hotspot- és `SongSessionResult`-szerződés nincs a publikus felületen; a tényleges `SongTrainerResult` application-internal típus.

## Döntés

1. A Practice Generator kizárólag a `package:strumsight/features/song_trainer/domain/public.dart` publikus contractját importálhatja. A Song goal reader bemenete a hívó által átadott `SongDocument`; nem nyit Song Trainer repositoryt vagy controllert.
2. A tervező a document `sections`, `tracks`, `assets` és `revision` mezőjét használhatja. Fizikai asset-létezést nem állíthat: a hiányzó, használható publikus asset-referencia explicit `unavailable` eredmény, nem csendes kihagyás.
3. A Song Trainer terminális eredménye nincs ma publikus contractban. A kör saját, caller-fed song-goal outcome típust normalizálhat, de nem nevezheti ezt a Song Trainer tényleges resultjának. Technikai vagy unavailable kimenet nem learner-evidence, összhangban az ADR 0268-cal.
4. Hotspot-alapú kiválasztás és a valódi Song Trainer outcome-wiring csak egy későbbi, Song Trainer-oldali, additív public-contract kör után valósulhat meg.

## Következmények

- A jelen kör offline és dependency-safe: nincs cross-feature belső import, plugin, storage vagy hálózati olvasás.
- A caller a documentot és a terminális tényt explicit módon adja át; az adapter nem talál ki hiányzó adatot.
- A jövőbeli public felület bővítésének külön teszttel kell bizonyítania az új Song Trainer contractot, mielőtt a Practice Generator fogyasztja.

## Mérce

Az E07-R24 A5/A6/A7/A8 cellái: a hiányzó asset-referencia explicit eredményt ad; a revízió megmarad; a gyártási adapter csak a domain public barrelből importál; és a technikai/unavailable caller-fed outcome nem válik learner-evidence-szé. A reviewer a cross-feature import őrrel és egy valódi belső-import sértéspróbával ellenőrzi a boundaryt.
