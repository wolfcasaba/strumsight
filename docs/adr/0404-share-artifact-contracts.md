# ADR 0404 — Share artifact szerződések

- **Státusz:** Elfogadva (E09-R10 pre-flight, 2026-08-23)
- **Kör:** E09-R10 — Share artifact szerződések
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 10 (a 32 kör közül a tizedik)
- **Kontext-ADR-ek:** [0399](0399-flutter-community-domain-and-public-api.md)
  (Kör 5 — `CommunityPost`/`content_id` value objectek), [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — a legutóbb kiosztott Epic 9 ADR-szám, innen derül ki a foglalási
  ütközés, lásd a sorszám-jegyzetet).
- **Sorszám-jegyzet:** a `docs/execution/pipeline-queue.tsv` E09-R10 sora és
  a brief fejléce `0402`-t adott előre kiosztott ADR-ként, de ez a szám MÁR
  foglalt — a Kör 8 (`E09-R08`, "Block, mute és safety kapcsolatkezelés")
  ADR-je, `docs/adr/0402-block-mute-and-safety-relationships.md`. A
  `tools/round-slots.py reserve-adr --round E09-R10` friss számot adott
  (`0404` — `0403` egy másik, még nem indult kör előjegyzett foglalása,
  `.pipeline/inflight/adr/0403`). Ez a pontosan a `docs/execution/08-round-brief.md`
  §1 és a driver §1.0.1 által előre jelzett hiba-osztály: az `ls docs/adr |
  tail` alakú, nem a foglalóval mért szám-választás elavul, ha közben más kör
  ADR-t ír.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban (ez a szakasz a teljes
tényellenőrzést hordozza — a brief §0.0-jában is megismételve):**

1. `lib/features/share/widgets/strum_card.dart` és `wrapped_card.dart` a
   RENDERELŐ réteg, ahogy a brief §2 állítja — `StrumCard` az `analyze/
   public.dart` `AnalyzeResult`-jából épül (chords/strums/bpm/duration),
   `WrappedCard` a `share/model/weekly_recap.dart` `WeeklyRecap`-jából
   (percek, streak, pontosság). Egyik widget sem importál nyers audio/
   landmark/DSP-belső típust — ez a precedens a "minimalizált nézet" szint,
   amit az artifact modellnek követnie kell, NEM a widgetek maguk a forrásai
   a Community mappereknek (azok a §4 négy forrás-feature `public.dart`-ján
   keresztül épülnek, a brief §5.1 szerint).
2. **Az `analysis_share_mapper.dart` forrása `lib/features/audio_analysis/**`
   (a brief `allowed_paths`/tilos-zóna szerint), NEM a `lib/features/analyze/**`**
   — ez a két különböző feature (`analyze` = az eredeti klip-szintű chord/
   strum DSP-detektor, amit a `StrumCard` fogyaszt; `audio_analysis` = a V2,
   gazdagabb elemzés-feature timeline/insight/comparison/export réteggel,
   ADR 0247-ben lezárt export-szerződéssel). Az `audio_analysis/public.dart`
   exportálja a `domain/comparison/analysis_comparison.dart` és
   `analysis_trend.dart` típusokat — ezek adják az "analysis improvement"
   artifact természetes forrását (két elemzés közti javulás), nem az
   `AnalyzeResult` egyetlen klip-pillanatfelvétele.
3. **A gamifikáció `verified`/`unverified` megkülönböztetése (§5.3) a
   `LedgerEntrySyncStatus` enum** (`lib/features/gamification/data/sync/
   gamification_sync_contract.dart:28`, `{ unverified, verified }`), a
   `SyncReceipt.status` mezőn, E08-R28-ban (ADR 0394) vezetve be — NEM az
   `EvidenceTrust` enum (`domain/activity/evidence_trust.dart`, öt fokozatú:
   `unverified, userConfirmed, deviceObserved, scored, verified`), ami egy
   másik, korábbi (aktivitás-bizonyíték) tengely. A challenge-artifact a
   `LedgerEntrySyncStatus`-t képezi le, mindkettő exportált a `gamification/
   public.dart`-on.
4. **Hét artifact-típus, négy mapper-fájl** (§3 scope vs. §4 allowed_paths) —
   a brief nem írja le explicit módon, melyik altípust melyik mapper adja.
   Mérve: `lib/features/songs/model/song.dart` `Song` modellje (chord-per-bar
   progresszió + strum pattern + tempó) egyben hordozza a "song result",
   "plan template" és "original progression" artifact-tartalmát — mindhárom
   ugyanabból az egy domain-típusból vezethető le (a Song feature nem tart
   külön "terv sablon" vagy "eredeti progresszió" entitást). Az
   `achievement_share_mapper.dart` mindkét gamifikációs típust adja
   (achievement ÉS challenge) — a challenge a gamifikáció ugyanazon
   `public.dart`-jából (`ChallengeDefinition`, `RewardLedgerEntry`+
   `LedgerEntrySyncStatus`) épül, mint az achievement, tehát nem indokolt
   egy ötödik mapper-fájl (ami a `allowed_paths`-on kívülre esne, H3).
5. `docs/contracts/` könyvtár még nem létezik — a
   `community-share-artifacts.md` az első fájl benne, nincs meglévő
   konvenció, amit sértene.
6. A backendben nincs élő Pydantic discriminated-union minta
   (`grep -rln "Discriminator\|discriminator=" backend/app/` → 0 találat) —
   ez az első ilyen kör; a `backend/app/community/schemas/artifacts.py`
   szabadon választhatja a Pydantic v2 `Field(discriminator=...)` +
   `Annotated[Union[...], ...]` mintát, nincs visszamenőleges kompatibilitási
   kényszer.

## Döntés

### D1 — Négy mapper, hét artifact-altípus: a leképezés rögzítve

| Artifact altípus | Mapper | Forrás `public.dart` típus |
|---|---|---|
| Practice summary | `practice_share_mapper.dart` | `PracticeSessionResult` (`practice/public.dart`) |
| Song result | `song_share_mapper.dart` | `Song` (`songs/public.dart`) |
| Original progression | `song_share_mapper.dart` | `Song` (ugyanaz a típus, más artifact-kind) |
| Plan template | `song_share_mapper.dart` | `Song` (ugyanaz a típus, más artifact-kind) |
| Analysis improvement | `analysis_share_mapper.dart` | `AnalysisComparison`/`AnalysisTrend` (`audio_analysis/public.dart`) |
| Achievement | `achievement_share_mapper.dart` | `AchievementDefinition`+`AchievementProgress` (`gamification/public.dart`) |
| Challenge | `achievement_share_mapper.dart` | `ChallengeDefinition`+`RewardLedgerEntry`+`LedgerEntrySyncStatus` (`gamification/public.dart`) |

Egyetlen mapper-fájl SEM importálhat a listázott `public.dart`-on kívüli
fájlt a saját forrás-feature-jéből (§5.1, A1/A5 mérce-cella). A `song_share_mapper.dart`
egy fájlban, három külön factory-metódussal (pl. `SongShareMapper.songResult`,
`.originalProgression`, `.planTemplate`) adja a három altípust — nem három
külön fájllal (ami az `allowed_paths`-on kívülre esne).

### D2 — Az artifact MINIMÁLIS, immutable és verziózott (brief §5.1 megerősítve)

Minden `ShareArtifact` altípus explicit mezőkkel rendelkezik, `schemaVersion`
+ `sourceId` + `createdAt` kötelező mezőket hordoz. A `share_artifact.dart`
sealed hierarchia — a JSON round-trip (A4) a `type` discriminator mezőből
dönt típust, NEM a jelenlévő mezők halmazából (§6.1 mérce-cella).

### D3 — Ismeretlen/manipulált verzió elutasítva (brief §5.2 megerősítve)

A Pydantic discriminated union (`artifacts.py`) `Literal[...]` típus-
diszkriminátorral dolgozik; ismeretlen `type` vagy `schemaVersion` `pydantic.ValidationError`-t
dob, amit a router 422-re képez le — nincs csendes best-effort parse vagy
"ismeretlen mezők eldobása" fallback.

### D4 — A challenge-artifact a `LedgerEntrySyncStatus`-t hordozza (brief §5.3 pontosítva, ld. Kontextus/3)

`ChallengeShareArtifact.rewardStatus` (vagy ezzel ekvivalens mezőnév, az
implementer választja) típusa a gamifikáció `LedgerEntrySyncStatus`
enumjának Community-oldali, saját (importált típust nem visszaadó) tükre —
a Community domain nem importálhatja magát a gamifikációs enumot a saját
sealed hierarchiájába (A1), de a KÉT ÉRTÉK (verified/unverified) 1:1
leképeződik, harmadik érték nélkül.

### D5 — Field-level share-kapcsolók alapértelmezetten `false` (brief §5.1/§9.3 megerősítve)

A share-preview modell minden opcionális mezőjének (pl. audio-klip
csatolása, ha egy jövőbeli kör bevezetné) alapértéke KI — a felhasználónak
explicit be kell kapcsolnia bármely extra adatot, mielőtt megosztásra kerül.

## Elutasított alternatívák

- **Hét külön mapper-fájl (egy artifact-altípusonként).** Elvetve: a brief
  `allowed_paths`-a négyet sorol fel; hét fájl tilos-zóna-sértés (H3) lenne.
  A D1 leképezés a meglévő négy fájllal teljes lefedettséget ad.
- **Az `analyze` feature (nem `audio_analysis`) mint az analysis-mapper
  forrása.** Elvetve: a brief `allowed_paths`/tilos-zóna explicit
  `audio_analysis/**`-t nevez meg, és az "improvement" szemantika (két
  mérés közti javulás) az `audio_analysis` comparison/trend típusaihoz
  illik, nem az `analyze` egyetlen klip-pillanatfelvételéhez.
- **Az `EvidenceTrust` enum újrahasznosítása a challenge-artifact
  hitelesség-mezőjeként.** Elvetve: az `EvidenceTrust` öt fokozatú
  aktivitás-bizonyíték tengely, nem a reward-ledger szinkron-állapota; a
  brief §5.3 kifejezetten a "reward-ledger verified/unverified" fogalmára
  hivatkozik, ami a `LedgerEntrySyncStatus`.

## Következmények

- A Community domain négy ÚJ mapper-fájlt kap, mindegyik pontosan egy
  forrás-feature `public.dart`-ját fogyasztja — egy jövőbeli ötödik
  forrás-feature (pl. Vision/Tutor, a brief §1 célja szerint később) saját
  ÚJ mapper-fájlt igényel majd, külön kör `allowed_paths`-ában.
- A `docs/contracts/community-share-artifacts.md` a jövőbeli deprecation-
  szabályok referenciapontja — egy jövőbeli schema-bővítés ide ír, nem egy
  szétszórt kód-kommentbe.
- A `song_share_mapper.dart` három factory-metódusa közös kódot oszthat meg
  (pl. a `Song`→artifact mezőleképezés törzse) — ez a fájlon belüli
  refaktor-szabadság, nem külön fájl.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör (Vision/Tutor share-integráció) új
forrás-feature-t von be — ekkor a D1 táblázat egy sorral bővül, saját ADR-ben.
