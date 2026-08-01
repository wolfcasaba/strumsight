# ADR 0111 — A Practice V2 négy hiányzó éles providere

- **Státusz:** Elfogadva (2026-08-01)
- **Kör:** E02-R21 — a zárójelentés §3 rendszerszintű résének javítása
- **SDD:** `docs/sdd/epic-02-completion-report.md` §3 (rendszerszintű rés), §5
  (DoD-tábla érintett sorai)
- **Előzmények:** [ADR 0077](0077-practice-session-controller.md) (a
  controller az erőforrás-életciklus tulajdonosa, §10 réteg-tisztaság),
  [ADR 0074](0074-practice-observation-gateway.md) (`LivePracticeObservationGateway`
  megírva, hívó nélkül), [ADR 0084](0084-practice-history-v2-and-coaching.md)
  (`PracticeSessionRecorder` + a write-then-drop védelem, R18 B2)

## Kontextus

Az E02-R20 zárókör mérve rögzítette: a Practice V2 domain, application és
presentation réteg kész és kimerítően tesztelt, de egy valós felhasználó a
Hub → Setup → Session úton **ma nem tud** önálló Practice V2 sessiont
futtatni az élesített (nem-produkciós) buildben. A hiány négy production
provider — `practiceSessionHostProvider` (`null`),
`practicePrepareSinkProvider` (logging placeholder),
`practiceSessionRecorderProvider` (mindig `NoopPracticeSessionRecorder`, a
placeholder mode/source/definitionId kódok miatt) és a
`LivePracticeObservationGateway` hiányzó providere — plusz egy ötödik, ami mind
a négyet összefogja: a `practiceSessionControllerProvider` auto-dispose family
nincs definiálva. Ez a kör ezt a négy (+ötödik) drótot köti be — **új
képesség nélkül**, a meglévő domain/application/presentation viselkedésének
megváltoztatása nélkül.

## Döntés

### 1. A domain és a presentation viselkedése nem változik

A kör kizárólag a Riverpod provider-gráfot köti be a már megírt és tesztelt
rétegek között. Ha egy bekötéshez domain-viselkedés módosítása kellene, az
brief-ütközés — a rés a drótozásban van, nem a motorban.

### 2. A gateway providere külön fájlban él, az ADR 0077 §10 réteg-tisztasági
korlátja miatt

A `practice_session_providers.dart` nem hivatkozhat `AudioSessionCoordinator`,
`audioSessionCoordinatorProvider`, `StrumEngine(`, `BuildContext`, `Navigator`,
`GoRouter`, `SharedPreferences`, `dart:ui`, `DateTime.now(` szimbólumra — ez a
korlát eddig a `practice_session_controller_test.dart` A9 csoportjában csak a
`practice_session_controller.dart` forrására volt gépi mércével kikényszerítve.
A `LivePracticeObservationGateway` viszont `StrumEngine`-t igényel, ezért a
providere a **`lib/features/practice/data/practice_observation_gateway_provider.dart`**
új fájlba kerül — ez a fájl szabadon hivatkozhat a StrumEngine-re és az
audio-session koordinátorra, mert nem az alkalmazás-réteg tiszta magja.

### 3. A providers fájl tisztasága mostantól gépi mérce, nem csak dokumentáció

A pre-flight mérése szerint a `test/features/practice/application/`
könyvtárban **nem létezik** `practice_session_providers_test.dart` — ez a
brief §4 táblájának hibás „meglévő" jelölése, javítva a §0.0 revízióban. A kör
ezt a fájlt **újonnan** hozza létre, és egy, az A9 mintáját követő
forrás-mintaőrt ad hozzá, amely a `practice_session_providers.dart` forrását
(kommentek nélkül) a fenti tiltott szimbólum-listával veti össze. Ez teszi az
A4 acceptance criteriát ("a layer-purity guard zöld marad") ténylegesen
mérhetővé a providers fájlra is, nem csak a nem-érintett controller fájlra.

### 4. A recorder csak valódi, visszaolvasható metaadattal válthat le a no-op ágról

Az R18 B2 write-then-drop csapdájának megismétlését a kör azzal zárja ki, hogy
az A3 acceptance criteria mércéje nem a `record()` sikeres visszatérése, hanem
egy teljes írás→visszaolvasás kör a valódi serializerrel. A
`NoopPracticeSessionRecorder` ág csak akkor tűnhet el, ha a session config
tényleges `mode`/`source`/`definitionId` értékei elérhetők a recorder
providerének — ha nem, a placeholder ág marad, és ez dokumentált korlátozás,
nem hiba.

### 5. A production flag nem mozdul

`practiceEngineV2Enabled` és `migratedLearnEnabled` értéke ebben a körben
változatlan (`nonProd` / `false`). A kör terméke a nem-produkciós build
használhatósága; a production rollout a készülékes teszt utáni, külön
user-döntésű kör.

## Következmények

- A Hub → Setup → Session út a nem-produkciós buildben a kör után valós
  sessiont futtat és perzisztál.
- A `practice_session_providers.dart` tisztasága innentől ugyanolyan gépi
  mércével védett, mint a controlleré.
- A production rollout továbbra is külön, később meghozandó user-döntés.
- A zárójelentés §3 nyitott tétele lezárul; a §2 többi nyitott lelete
  (chord-change `analysis: null`, Free Practice „strum count" csempe,
  `noSignal` szemantika, `AudioOwner.practice`) változatlanul külön körökre
  vár.
