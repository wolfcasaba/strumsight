# E08-R25 — Song Trainer és setlist integráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`) — **pre-flight revízió 2026-08-22, kód mérve `main @ fec594c6`**
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 25
- **Kör-azonosító:** `E08-R25`
- **Branch:** `<motor>/e08-r25-song-trainer-and-setlist-integration`
- **Előfeltétel:** `E08-R24` merge-elve (practice/learn integráció)
- **Brief szerzője:** Claude (Opus 5); **§0.0 pre-flight revízió: Claude Sonnet 5 (orchestrátor)**
- **ADR:** [`0391`](../adr/0391-song-gamification-adapter-standalone-bonus-and-hashed-song-id.md) — a
  2026-08-18-i brief két állítását a pre-flight mérés megcáfolta (lásd §0.0);
  az ADR a javított mechanizmust rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/songs/` és `lib/features/song_trainer/` TÉNYLEGES public szerződését (szakasz, hurok, teljes dal, setlist eredmények), és ellenőrizd, hogyan azonosítja az importált dalokat — a privacy-safe azonosító ebből származik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (2026-08-22, Claude Sonnet 5, ADR 0391)

**Visszakeresett előzmény (ADR 0312, §4.9 kötelező, szűkített korpuszon):**
- `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "dal-esemény jutalom dedup szülő-gyermek gamification adapter"` →
  legjobb találat **ADR 0390** (`bm25#2 emb#3`, Practice/Learn adapter-határ:
  meglévő event-típus, outbox, caller-fed kettős írás — az adapter
  three-step sorrendjének mintája) és **lessons/L404** (`bm25#14 emb#5`,
  E08-R24: „egy session/próbálkozás-szintű eseményazonosítót SOSE
  származtass egy statikus katalógus-id-ből, és minden adapter kapjon SAJÁT
  teljes tesztmátrixot" — ez alapozza meg alább a stabil, session-eredetű
  `eventId` szabályt).
- `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "privacy-safe azonosító főkönyv nem tartalmazhat dalcímet"` →
  nincs korábbi StrumSight-lecke pontosan erre (a legjobb találatok — L260,
  L180, L190, L169, L196 — más feature-ök redakciós/allowlist csapdái,
  analóg tanulság: egy név/kulcs-alapú szűrő vakon zöld marad, ha az ÉRTÉK-
  oldalon szivárog a nyers adat). **Nincs releváns közvetlen előzmény** — a
  lenti mérés a saját, ebben a pre-flightban végzett feltárás.

**Mért ellentmondás #1 — a §5.1 (2026-08-18-i alak) `parentEventId`-t (R06,
ADR 0341) jelölt meg a szakasz/teljes-dal bónusz mechanizmusaként. Ez
megcáfolva:** `lib/features/gamification/infrastructure/default_reward_policy.dart`
`_dedup()` és ADR 0341 §Döntés 2 („gyermek nulla XP-t kap, ha a parent már
jutalmazott; parent nulla XP-t, ha korábbi gyermek már hivatkozott rá") —
**bináris, mind-vagy-semmi** összeomlás. A reális sorrendben (szakaszok
előbb, teljes dal utóbb) ez a teljes dal bónuszát **nullára**, nem
csökkentett, nemnulla értékre ejtené — ellentmondva a §6.1 „rajta" cellának.
Részletes indoklás és elutasított alternatívák: **ADR 0391**.

**Mért ellentmondás #2 — a §5.3 (2026-08-18-i alak) feltételezte, hogy a
`SongId` ma tartalom-semleges.** Megcáfolva:
`grep -n "SongId(" lib/features/song_trainer/data/importers/*.dart` →
`SongId('musicxml-${_slug(title)}')` / `SongId('midi-${_slug(title)}')` — a
`SongId.value` a dal címének kisbetűs, kötőjelezett szelete. A
`lib/features/song_trainer/application/progress/song_progress_aggregator.dart`
`PracticeSessionSongCreditRecorder` már ma is `lessonId: 'song-${record.
songId.value}'` mintát használ — ez a minta **NEM** másolható a gamification
főkönyvbe, mert nyers/felismerhető cím-szeletet vinne be. Részletek: ADR
0391 §Döntés 4.

**A §5.1, §5.3 és §6.1 alábbi szövege a fentiek szerint frissült — ez a
hatályos szerződés, nem a fejléc alatti eredeti verzió.**

**Kockázat = high, indoklás:** az `allowed_paths` egyik útvonala sem egyezik
szó szerint a router `high_risk_path_fragments` listájával (auth, camera,
credential, crypto, encryption, migration, payment, **privacy**, secret,
share, upload, vision), de a kör tartalmilag privacy-döntés: §5.3 és A5 azt
követeli, hogy a felhasználó által importált dal címe/előadója/fájlneve SOHA
ne kerüljön a szinkronizálható (Kör 28) főkönyvbe — a mért #2 ellentmondás
(fent) pontosan azt mutatta, hogy a naiv implementáció (a meglévő
`songId.value` közvetlen felhasználása) ezt megsértené. A `risk = "high"`
tehát indokolt annak ellenére, hogy a fájlnév-egyezés nem talál rá.

**S6 (brief-méret) ellenőrizve:** `python3 tools/brief-merge-plan.py` a teljes
queue-n **nem** ajánl E08-R25-öt érintő összevonást (az egyetlen javasolt pár
E14-R15/E14-R16, más feature-gyökér). A kör önállóan marad — nincs
diszjunkt-de-szomszédos testvér brief, amivel érdemes lenne egyesíteni.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/application/gamification_song_adapter.dart",
  "test/features/gamification/integration/song_reward_flow_test.dart",
  "docs/rounds/e08-r25-song-trainer-and-setlist-integration.md",
]
gate_tests = [
  "test/features/gamification/integration/song_reward_flow_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Jutalmazd a dalgyakorlást **session-bookkeeping alapú bónusz-méretezéssel**
(ADR 0391 — NEM az R06 `parentEventId` dedupjával, lásd §0.0) és személyes
rekord mérföldkövekkel — jutalom-infláció nélkül, és **privacy-safe**
(hashelt) dal-azonosítóval.

## 2. Jelenlegi állapot — mért tények

- **A R06 `parentEventId` (ADR 0341) bináris mind-vagy-semmi dedup — NEM
  alkalmas a szakasz/teljes-dal bónusz-splitre** (§0.0, ADR 0391). A kör az
  adapter saját, session-hatókörű könyvelését használja a bónusz
  méretezésére; a `parentEventId` mezőt egyetlen kérés sem állítja be.
- A `lib/features/songs/` és `lib/features/song_trainer/` (Epic 3) szakasz-, hurok-, teljes dal- és setlist-eredményeket ad.
- Az importált dal címe és a fájl neve **felhasználói tartalom** — nem kerülhet azonosítóként a főkönyvbe. A `SongId.value` MA is cím-szeletet hordoz
  (`SongId('musicxml-${_slug(title)}')`) — nem semleges (§0.0 #2).
- `test/features/songs/` MA zöld — elbukása `blocked`.

## 3. Scope

**Benne van:** szakasz, hurok, teljes dal és setlist befejezés esemény · a gyermek események
összekötése szülő session-azonosítóval · a teljes dal bónusza NEM duplikálja a szakaszok
alap-jutalmát · tempó-mérföldkő és tiszta felvétel esemény · ugyanazon felvétel újrajátszása
NEM ad második jutalmat · importált dalnál **privacy-safe** azonosító.

**NINCS benne (tilos):**

- A `lib/features/song_trainer/**` és a `lib/features/songs/` többi fájljának módosítása.
- A dal-haladás (`song progress`) logikájának átvétele — az a `songs` feature saját mérőszáma.
- A gamification belső fájljainak importálása (csak `public.dart`).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/songs/application/gamification_song_adapter.dart` | **ÚJ** — a dal-adapter |
| `test/features/gamification/integration/song_reward_flow_test.dart` | a §6 cellái |
| `docs/rounds/e08-r25-song-trainer-and-setlist-integration.md` | a §10 handoff |

**Tilos zóna:** `lib/features/songs/` MINDEN más fájlja · `lib/features/song_trainer/**` · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/gamification/` belső (nem `public.dart`) fájljai

## 5. Kötött architekturális döntések

### 5.1 A TELJES DAL BÓNUSZ, NEM ÖSSZEG (mechanizmus: ADR 0391 §Döntés 1–3)

Ha a felhasználó végigjátssza a dalt, a teljes dal esemény **bónuszt** ad — nem
kapja meg újra a szakaszok alap-jutalmát. **A mechanizmus NEM az R06
`parentEventId` dedupja** (az mérve bináris — lásd §0.0; szó szerinti
használata a reális sorrendben NULLÁRA, nem csökkentett bónuszra ejtené a
teljes dal jutalmát). Helyette:

1. Minden `RewardPolicyRequest`, amit az adapter küld (szakasz, hurok, teljes
   dal, setlist-tétel), **önálló** — `parentEventId: null`. A R06 dedup
   rétege így soha nem omlik össze a szakasz↔dal kapcsolatra.
2. Az adapter a rákapott `SongTrainerResult`/`SetlistResult` bemenetből
   (amit a hívó ad át — a `songs`/`song_trainer` public szerződésen
   keresztül, NEM a gamification belsejéből) eldönti, hogy **ugyanabban a
   sessionben** már küldött-e szakasz-eseményt ehhez a dalhoz:
   - ha IGEN → a teljes dal eseménye **csökkentett** (bónusz-méretű)
     `validDuration`/`qualityScore` jelet kap;
   - ha NEM (a felhasználó szakaszok nélkül, közvetlenül a teljes dalt
     játszotta végig) → a teljes dal eseménye a **természetes, teljes**
     (alap + bónusz) jelet kapja.
3. A gyermek↔szülő session-hovatartozás (A2) az `eventId` session-be
   ágyazott, determinisztikus namespace-eléséből adódik (pl.
   `'song-section/<sessionId>/<sectionId>'`, `'song-full/<sessionId>'`) —
   NEM a `RewardPolicyRequest.parentEventId` mezőből.

**NEM elfogadható gyengítés:** a szakasz-jutalmak összeadása és a bónusz hozzáadása
(kétszeres fizetés); VAGY a `parentEventId` szó szerinti bevezetése a
szakasz↔dal kapcsolatra (ez a mért bináris dedup miatt NULLÁZNÁ a bónuszt,
ami az A1 „rajta" cellája szerint szintén hibás).

### 5.2 AZ ÚJRAJÁTSZÁS UGYANAZZAL AZ EREDMÉNNYEL NEM AD ÚJ JUTALMAT

A felvétel (take) azonosítója stabil; ugyanazt az eredményt újra megnyitva vagy
újrajátszva a főkönyv `append-if-absent` művelete blokkol. Az ÚJ felvétel természetesen
új esemény.

### 5.3 PRIVACY-SAFE dal-azonosító (mechanizmus: ADR 0391 §Döntés 4)

Az importált dal címe, előadója vagy fájlneve **nem** kerül a főkönyvbe. **A
mai `SongId.value` NEM alkalmas nyers felhasználásra** — mérve, hogy
importált daloknál a cím kisbetűs, kötőjelezett szeletét hordozza
(`SongId('musicxml-${_slug(title)}')`, §0.0 #2). Az adapter a `songId.value`-ból
egy stabil, determinisztikus, **egyirányú** digestet származtat (pl. SHA-256
hex, rögzített hosszra csonkolva) minden ledgerbe kerülő `eventId`/
`practiceKey` komponenshez — a nyers `songId.value` SOHA nem kerül a
`RewardPolicyRequest`-be vagy az eseménybe.

**NEM elfogadható gyengítés:** „csak a cím, hogy a felületen ki tudjuk írni”
(a főkönyv szinkronizálható — Kör 28 — a felhasználó dallistája nem mehet
fel); VAGY a `songId.value` közvetlen (hash nélküli) felhasználása — az még
mindig a cím felismerhető szeletét vinné be, még ha `song-` előtaggal
kombinálva is (ez a `PracticeSessionSongCreditRecorder` mai, MÁS hídra
jóváhagyott mintája — 1:1 átvétele itt éppen a §5.3-at sértené).

### 5.4 A SZEMÉLYES REKORD MAGYARÁZHATÓ

A tempó-mérföldkő megmondja, mihez képest rekord (előző legjobb, mikor). A
puszta „Új rekord!” üzenet nem ellenőrizhető.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az összes szakasz + a teljes dal együtt NEM ad kétszeres alap-jutalmat | `song_reward_flow_test.dart` — infláció-cella |
| A2 | A gyermek események szülő session-azonosítót hordoznak | `song_reward_flow_test.dart` |
| A3 | Ugyanazon felvétel újrajátszása NEM ad második jutalmat | `song_reward_flow_test.dart` |
| A4 | Új felvétel ÚJ jutalmat ad (a dedup nem zárja ki a valódi új gyakorlást) | `song_reward_flow_test.dart` |
| A5 | A főkönyvben NEM szerepel dalcím, előadó vagy fájlnév | `song_reward_flow_test.dart` — privacy-cella |
| A6 | A tempó-mérföldkő megadja az előző legjobbat és annak idejét | `song_reward_flow_test.dart` |
| A7 | A dal-haladás (`songs` feature) VÁLTOZATLAN | a `test/features/songs` suite a §7 gate-ben |
| A8 | A folyamat offline teljes | `song_reward_flow_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A szakasz-jutalmak összeadódnak a teljes dal bónuszához (a teljes dal esemény MINDIG a teljes, nem csökkentett jelet küldi, session-bookkeeping nélkül) | **A1** |
| A teljes dal eseménye `parentEventId`-t állít be a szakasz-relációra (a mért bináris dedup miatt ez NULLÁRA, nem bónuszra ejtené) | **A1** |
| Az újrajátszás új eseményt generál | **A3** |
| A dalcím vagy a nyers `songId.value` bekerül a főkönyvbe (hash nélkül) | **A5** |
| A rekord nem adja meg az előző legjobbat | **A6** |
| Az adapter átveszi a dal-haladás számítását | **A7** |
| A gyermek esemény `eventId`-je nem tartalmazza a session-azonosítót | **A2** |

**A küszöb három kötelező cellája** (az adapter session-bookkeeping-alapú bónusz-méretezése — ADR 0391 §Döntés 2 — a szakaszok alap-jutalmához képest):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | csak szakaszok játszva (nincs teljes dal esemény) | a szakaszok **alap-jutalma** jár, bónusz nincs |
| **rajta** (a küszöbön) | minden szakasz + a teljes dal ugyanabban a sessionben | a szakaszok alap-jutalma **EGYSZER** + a teljes dal **csökkentett, bónusz-méretű** jele (a session-bookkeeping ezt detektálja) — összesen NEM a kétszerese, és a bónusz NEM nulla |
| a küszöb **fölött** | teljes dal szakasz-gyakorlás nélkül ugyanabban a sessionben | a teljes dal **természetes, teljes** (alap + bónusz) jele; a nem játszott szakaszokért nem jár semmi |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva, KETTŐ cella):**
1. Kapcsold ki a session-bookkeeping ágat úgy, hogy a teljes dal eseménye
   MINDIG a természetes (teljes) jelet küldje, függetlenül attól, hogy a
   session már tartalmazott-e szakasz-eseményt → futtasd a gate-et → az
   **A1** infláció-cellának PIROSNAK kell lennie → állítsd vissza.
2. Állíts be `parentEventId`-t a teljes dal eseményén a hozzá tartozó
   valamelyik szakasz `eventId`-jére → futtasd a gate-et → az **A1** „rajta"
   cellájának PIROSNAK kell lennie (a mért bináris dedup nullázza a
   bónuszt) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/integration/song_reward_flow_test.dart test/features/songs
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `gamification_song_adapter.dart` — a négy eseménytípus a `songs` public szerződéséből.
2. Session-be ágyazott, namespace-elt `eventId` minden eseménytípuson (A2) — NEM `parentEventId`.
3. Session-scope bookkeeping: a teljes dal eseménye csökkentett (bónusz) vagy teljes jelet kap aszerint, hogy a session tartalmazott-e már szakasz-eseményt (ADR 0391 §Döntés 2) — minden kérés `parentEventId: null`.
4. Stabil felvétel-azonosító az újrajátszás dedupjához (a `rewardedEventIds` plain re-submission dedupja, A3/A4).
5. Privacy-safe dal-azonosító: `songId.value` egyirányú hash-e (ADR 0391 §Döntés 4), sosem a nyers érték.
6. Magyarázható tempó-mérföldkő.
7. A KÉT valódi-sértés próba §10-be (§6.1); `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A jutalom-infláció.** A szakasz+teljes dal összeadása a legkézenfekvőbb implementáció, és ugyanazt a gyakorlást kétszer fizeti (A1).
- **A dalcím a főkönyvben.** Kényelmes a felület számára, és a Kör 28 szinkronjával a felhasználó dallistája elhagyná az eszközt (A5).
- **A dal-haladás átvétele.** A `songs` feature saját mérőszáma; az átvétel scope-sértés és regresszió (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
