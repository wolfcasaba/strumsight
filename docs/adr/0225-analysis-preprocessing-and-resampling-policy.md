# ADR 0225 — Analysis preprocessing és resampling policy

- **Státusz:** Elfogadva (E06-R08 pre-flight, 2026-08-11)
- **Kör:** E06-R08 — Preprocessing context és resampling policy
- **Implementer motor:** Terra (`gpt-5.6-terra`), az aktív
  `.pipeline/engine-override=terra` szerint.
- **Kapcsolódó szerződések:** SDD Ch7 §12.1–12.4, ADR 0215, ADR 0220 és az
  E06-R04 `AnalysisStage<I, O>` contract.

## Kontextus

Az Analyze V1 chord-útja a bemenet natív sample rate-jén fut.
`DspConfig.nnlsWindow` (16384) és `DspConfig.nnlsHop` (4096) mintában
megadott értékek, ezért a frame-középpontok ideje közvetlenül függ a sample
rate-től. A `PcmAnalysisInput` a V2 határon már mono, immutable PCM-et hordoz:
a WAV core codec a csatornákat dekódoláskor átlagolja, az R05 adapter csak az
eredeti csatornaszám metaadatát tartja meg.

Az E06-R08-nak explicit, reprodukálható preprocessing contextet kell adnia,
amely megőrzi a dynamics számára az eredeti amplitúdóarányokat, és nem tesz
hallgatólagos sample-index/idő konverziót a hívókra. Nincs olyan V2
production-wiring ebben a körben, amely a legacy Analyze vagy Live útvonalat
módosíthatná.

## Döntés

1. A V1 preprocessing stage **nem resampol**. Minden input a saját, natív
   sample rate-jén marad, és a sample-index/idő mapping a
   `PreprocessedAudio` explicit contractja.
2. A preprocessing context két reprezentációt tart: az érintetlen
   `originalSamples` a dynamics fogyasztók számára, valamint a feature
   extractionre szolgáló `canonicalSamples`. Alapkonfigurációban a két mező
   ugyanarra a listára referál; másolat csak aktív transzformáció esetén
   megengedett.
3. DC-offset eltávolítás és peak-normalization csak az additív,
   alapértelmezetten kikapcsolt preprocessing flag mellett érhető el. Sem a
   flag, sem a stage nem módosíthatja az input PCM-et.
4. A `MonoDownmix.v1` a csatornaátlag determinisztikus, verziózott policy
   szerződése. A jelen, már mono `PcmAnalysisInput`-ot fogadó stage nem
   alkalmazza újra; ezzel elkerüli a core WAV codec downmixének duplikálását.
   A többcsatornás nyers bemenet bekötése külön kör döntése.

## Elutasított alternatívák

- **44.1 kHz vagy 22.05 kHz kötelező kanonikus rate:** megváltoztatná a
  mintában rögzített V1 ablakok időtartamát, ezért azonnali, nem mért
  onset/chord parity-kockázat.
- **Polyphase resampler most:** minőségi irány, de anti-alias, latency,
  több-rate fixture és valós audio evaluation nélkül nem bizonyítható.
- **Nearest-neighbor resampling:** SDD Ch7 §12.3 kifejezetten tiltja.
- **Normalizált egyetlen puffer:** a dynamics amplitúdóarányait csak
  visszaosztással próbálná helyreállítani, ami nem megengedett contract.
- **A core WAV codec átírása a policy használatához:** a kör tiltott zónája;
  a már shipping decoder szerződését nem szabad a V2-előkészítés részeként
  módosítani.

## Visszavonási feltétel

Resampler csak egy későbbi, külön scoped körben vezethető be, ha mind teljesül:

1. 44.1 kHz és 48 kHz fixture-ön az onset- és chord-timeline parity a
   dokumentált, inkluzív 5 ms határon belül marad;
2. anti-alias fixture igazolja, hogy a Nyquist feletti bemenet nem aliasol
   hallható/evidence-szintű komponenssé;
3. a sample-index/idő mapping minden támogatott rate-en determinisztikus és
   oda-vissza tesztelt;
4. valós készülékes, több natív sample-rate-es evaluation rögzíti a latency és
   minőségi hatást, mielőtt a production pathra kerül.

## Következmények

- Az E06-R08 explicit provenance- és mapping-contractot ad anélkül, hogy
  megváltoztatná a V1 Analyze vagy Live hangfeldolgozását.
- Különböző eszközök natív sample rate-je továbbra is eltérő lehet; ez ismert,
  mérendő follow-up, nem rejtett resampling.
- A future multi-channel input pathnak a `MonoDownmix` policy valódi bekötését
  és a core decoder/adapter határát külön ADR-rel kell kezelnie.
