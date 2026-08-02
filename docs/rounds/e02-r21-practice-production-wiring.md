# E02-R21 — A Practice V2 éles drótozása (a zárójelentés §3 rendszerszintű rése)

- **Státusz:** **PLANNING** (írva 2026-08-01, kód mérve: `main` @ `6d61e23`)
- **SDD-kör:** utókör az Epic 2-höz — a `docs/sdd/epic-02-completion-report.md`
  **§3 rendszerszintű rése** és a §2 nyitott leletek közül az R11 §11.4/4 és az
  R18 B2 residual.
- **Branch:** `codex/e02-r21-practice-production-wiring`
- **Előfeltétel:** E02-R20 merge-elve (`4616aed`), a router merge-elve (`6d61e23`).
- **ADR:** **0111** — `docs/adr/0111-practice-production-wiring.md`, az
  orchestrátor írja a pre-flightban. **0089–0110 FOGLALT** (Epic 3 kör-ADR-ek,
  `docs/execution/pipeline-queue.tsv`) — azokat NE oszd ki.
- **Implementer motor:** `auto` — ez a **MiniMax-first router első éles köre**
  (ADR 0088). Kicsi, jól körülhatárolt kör, ezért alkalmas első próbának.

## 0.0 Pre-flight revízió (orchestrátor, 2026-08-01)

Kötelező grep-ellenőrzés futott a brief minden hivatkozott szimbólumára és
fájlnevére (a pipeline-prompt §1 két mérési szabálya) — az alábbi egy pont
javításra szorult, minden más állítás mérve stimmelt:

- **A §4 táblázat tévesen "meglévő" (`—`) jelöléssel sorolja fel a
  `test/features/practice/application/practice_session_providers_test.dart`
  fájlt.** Mérve (`ls`/`grep -rl`): ez a fájl **nem létezik** — a
  `practice_session_providers.dart`-nak ma nincs dedikált tesztje. A kör ezt
  **újonnan** hozza létre (jelölése a §4-ben mostantól ÚJ).
- Ehhez kapcsolódóan: az A9 "layer-purity guard" ma **kizárólag**
  `practice_session_controller.dart` forrását vizsgálja
  (`practice_session_controller_test.dart` A9 csoportja) — nem
  `practice_session_providers.dart`-ot. Az A4 acceptance criteria ("a
  layer-purity guard zöld marad") ezért csak akkor mérhető ténylegesen a
  providers fájlra, ha az új `practice_session_providers_test.dart` egy, az
  A9 mintáját követő forrás-mintaőrt is tartalmaz a §2-ben felsorolt tiltott
  szimbólum-listával. Ld. [ADR 0111](../adr/0111-practice-production-wiring.md)
  §2/§3. Ez **kiegészíti** az A4-et, nem tágítja a scope-ot: a §4 engedélyezett
  fájllistája változatlan (a fájl már szerepelt rajta).
- Minden más mért állítás (a négy hiányzó provider pontos helye és mai értéke,
  a feature-flag állapot, a réteg-tisztasági korlát szimbólum-listája a
  controller fájlon, a három terminal állapot) grep-pel igazolva, változtatás
  nélkül.
- **Hiányzó `ai-router` metadata-blokk (a router első futtatási kísérlete
  fedte fel, exit 50, `"brief must contain exactly one ai-router block"`).**
  Ez a brief a router (ADR 0088) merge-je ELŐTT íródott, ezért nincs benne a
  géppel olvasott TOML-blokk, amit `tools/ai_router/brief.py` megkövetel — az
  Epic 3 briefek (ugyanaz a PR, amely a routert hozta) ezt már tartalmazzák.
  A blokk alant, a §4 engedélyezett-fájllistával és a §9 záró gate-parancs
  útvonalaival bitre egyező tartalommal pótolva:

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/adr/0111-practice-production-wiring.md",
  "lib/features/practice/application/practice_session_providers.dart",
  "lib/features/practice/application/practice_setup_controller.dart",
  "lib/features/practice/presentation/practice_effect_listener.dart",
  "lib/features/practice/data/practice_observation_gateway_provider.dart",
  "lib/features/practice/public.dart",
  "test/features/practice/application/practice_production_wiring_test.dart",
  "test/features/practice/application/practice_session_providers_test.dart",
  "test/features/practice/presentation/practice_effect_listener_test.dart",
  "docs/rounds/e02-r21-practice-production-wiring.md",
]
gate_tests = [
  "test/features/practice",
  "test/features/learn",
  "test/core",
  "test/app",
  "test/property",
]
native_gate = false
```

  `risk = "normal"`: a kör provider-drótozás már megírt/tesztelt rétegek
  között, nem érint autót/tokent/titkot/kriptót/fizetést, nem tárolómigráció
  és nem publikus interfészt tör (ADR 0088 §2 magas-kockázat listája egyik
  pontjának sem felel meg) — a mikrofon-lease életciklus kockázatát a §5/§6
  A6 leak-számlálói mérik, nem a Terra-eszkaláció.

## 0. Kör-jelzés

`engine=auto`: a kör-jelzést az **orchestrátor** képezi le a router
strukturált eredményéből (orchestrátor-prompt §1.1) — a router modelljei
**nem commitolnak** és nem hívnak `gh`-t.

**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `STOPPED`.
**A §7 a terved.**

## 1. Cél

A Practice Engine V2 **elérhetővé tétele** a nem-produkciós buildben: a
Hub → Setup → Session úton egy valódi felhasználó **valóban le tudjon futtatni**
egy önálló Practice V2 sessiont, és az **perzisztálódjon** is.

Ez a kör **nem ad új képességet** — a domain, application és presentation réteg
kész és tesztelt. A kör azt a **négy hiányzó providert** köti be, ami miatt a
kész motor élesben soha nem indul el.

## 2. Jelenlegi állapot — MÉRVE (`main` @ `6d61e23`)

A zárójelentés §3-a szerint *„egy valós felhasználó a Practice Hub → Setup →
Session úton ma NEM tud önálló Practice V2 sessiont futtatni az élesített
appban"*. A mért ok **négy** hiányzó drót:

| # | Provider | Mai éles érték | Hol |
|---|---|---|---|
| 1 | `practiceSessionHostProvider` | **`null`** | `presentation/practice_effect_listener.dart:64` |
| 2 | `practicePrepareSinkProvider` | placeholder **logging sink** (`_loggingPrepareSink`) | `application/practice_setup_controller.dart:33-57` |
| 3 | `practiceSessionRecorderProvider` | **`NoopPracticeSessionRecorder`** — a placeholder `mode/source/definitionId` kódok miatt szándékosan (write-then-drop csapda elkerülése, R18 B2) | `application/practice_session_providers.dart:74-94` |
| 4 | **observation gateway provider** | **NEM LÉTEZIK** — a `LivePracticeObservationGateway` (`data/live_practice_observation_gateway.dart:29`) meg van írva, de **sehol nincs providere**, tehát élesben soha nem jön létre (mérve: `grep -rn "LivePracticeObservationGateway" lib/` → csak a definíció és egy doc-komment) | — |

Ehhez jön az ötödik, ami mind a négyet fogja: **`practiceSessionControllerProvider`
nincs definiálva.** A `practice_session_providers.dart:182-186` záró
megjegyzése ma is ezt mondja: *„The Kör 13 pre-flight will define the
auto-dispose `family` with the configuration parameters wired in. Stay tuned."*

**Flag-állapot (mérve, `app/config/feature_flags.dart:36-44`):**
`practiceEngineV2Enabled: nonProd` — a V2 **nem-produkciós buildben MA is
elérhető lenne**, csak a production van kikapcsolva. Ezért ez a kör a
production flaghez **nem nyúl**: a drótozás után a lab/dev build azonnal
használható, és a production rollout külön kör, a valódi eszközös teszt UTÁN
(user-döntés 2026-08-01).

**Réteg-tisztasági korlát (ADR 0077 §10, mérve a fájl fejlécében):** a
`practice_session_providers.dart` **NEM hivatkozhat** `AudioSessionCoordinator`,
`audioSessionCoordinatorProvider`, `StrumEngine(`, `BuildContext`, `Navigator`,
`GoRouter`, `SharedPreferences`, `dart:ui`, `DateTime.now(` szimbólumra — az A9
layer-purity guard ezt állítja. A `LivePracticeObservationGateway` viszont
`StrumEngine`-t vár. **Ezért a gateway providere NEM kerülhet ebbe a fájlba** —
ez a §4 lista `data/practice_observation_gateway_provider.dart` új fájljának az
indoka. Ha az implementer más elrendezést talál helyesnek, az **brief-ütközés →
`STOPPED`**, nem néma áthelyezés.

## 3. Scope

**Benne:** a négy provider + a controller-family bekötése, a hozzájuk tartozó
metaadat-átvezetés, és a **valódi piros→zöld** integrációs teszt.

**Kívül (ebben a körben TILOS):**

- **A production flag átállítása.** `practiceEngineV2Enabled` és
  `migratedLearnEnabled` élesre kapcsolása **külön kör**, a készülékes teszt
  után. A `lib/app/config/**` **tilos zóna**.
- **Új képesség, új képernyő, új mód.**
- **A zárójelentés többi nyitott lelete** — az R15 NOTE-1 (chord-change
  `analysis: null` a session-screenen), az R18 n1 (Free Practice „strum count"
  csempe `attemptsCount`-ot mutat), az R11 §11.4/1 (`noSignal` szemantika), az
  R11 §11.4/3 (nincs `AudioOwner.practice`). Ezek **külön körök**; ha az
  implementáció közben útba esnek, **ne javítsd** — a §10-ben említsd.
- DSP/ML paraméter és modell-bináris (AGENTS.md §9).

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `docs/adr/0111-practice-production-wiring.md` | **ÚJ** | a kör ADR-je (az orchestrátor írja) |
| `lib/features/practice/application/practice_session_providers.dart` | — | controller-family (A1), recorder-metaadat (A3) |
| `lib/features/practice/application/practice_setup_controller.dart` | — | **CSAK** a `practicePrepareSinkProvider` valódi bekötése (A2) |
| `lib/features/practice/presentation/practice_effect_listener.dart` | — | **CSAK** a `practiceSessionHostProvider` valódi bekötése (A2) |
| `lib/features/practice/data/practice_observation_gateway_provider.dart` | **ÚJ** | a gateway providere — a réteg-tisztasági korlát miatt NEM mehet a providers fájlba (§2) |
| `lib/features/practice/public.dart` | — | **CSAK** ha egy bekötött típus exportja hiányzik |
| `test/features/practice/application/practice_production_wiring_test.dart` | **ÚJ** | A5 — a valódi piros→zöld cella |
| `test/features/practice/application/practice_session_providers_test.dart` | — | a meglévő provider-tesztek kiegészítése |
| `test/features/practice/presentation/practice_effect_listener_test.dart` | — | a host-provider cellái |
| `docs/rounds/e02-r21-practice-production-wiring.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más. Nevezetesen `lib/app/config/**` (a flagek),
`lib/features/practice/domain/**` (a domain kész és tesztelt — viselkedése nem
változhat), `lib/features/learn/**`, `.github/**`, `tools/**`,
`docs/rag/chunks/**`, és minden `docs/adr/0089`–`0110`.

**Új fájl a listán kívül = scope-sértés** → `STOPPED`.

## 5. Kötött döntések (NEM tárgyalhatók)

1. **A domain viselkedése nem változhat.** Ha egy bekötéshez domain-változás
   kellene, az `STOPPED` — a rés a drótozásban van, nem a motorban.
2. **A recorder ne írjon olvashatatlan rekordot.** Az R18 B2 tanulsága kötött:
   a `NoopPracticeSessionRecorder`-ág **csak akkor** cserélhető valódi
   recorderre, ha a `mode/source/definitionId` **valódi** értéket kap a session
   configból, és a mapper által írt rekordot a **serializer vissza is tudja
   olvasni**. A write-then-drop visszavezetése BLOCKER.
3. **Nincs néma no-op.** Egyetlen bekötött provider sem nyelhet el hibát
   `try/catch`-csel úgy, hogy sikert jelez. Ahol a művelet elbukhat,
   `AppResult` a válasz (mért tanulság: a settings-sync csapdája, CLAUDE.md).
4. **Az erőforrás-életciklus mérendő, nem feltételezendő.** A mikrofon-lease,
   a ticker és a subscription a terminal ág UTÁN nulla aktív erőforrást
   hagyjon — mind a három terminal ágon (az R11/R13 leak-számlálói a mérce).
5. **A production flag nem mozdul.** (§3)

## 6. Acceptance criteria

### A1 — `practiceSessionControllerProvider` létezik és auto-dispose

Autodispose `family`, a session-inputokkal paraméterezve. A kör **mérje ki**, mi
a tényleges paraméter-halmaz a `PracticeSessionController` konstruktorából —
a `practice_session_providers.dart:182-186` megjegyzése *terv*, nem szerződés.

***Pirosra fogja:*** a nem-autodispose (globális) provider — egy befejezett
session állapota nem szivároghat a következőbe.

### A2 — A host és a prepare-sink valódi

- `practiceSessionHostProvider` éles értéke **nem `null`**, és a controllerre
  mutat.
- `practicePrepareSinkProvider` a valódi előkészítő utat hívja, nem
  `_loggingPrepareSink`-et.
- A „session unavailable" képernyő-állapot **továbbra is elérhető** marad arra
  az esetre, amikor a host tényleg hiányzik (a flag OFF ága) — ezt cella
  igazolja.

### A3 — A recorder valódi metaadatot kap, és a rekord VISSZAOLVASHATÓ

- A `mode`, `source`, `definitionId` a session tényleges configjából jön; a
  `practice.*.unknown` placeholderek eltűnnek.
- **A mérce nem az írás, hanem a kör-út:** a teszt írjon egy rekordot a valódi
  recorderrel, majd **olvassa vissza a serializerrel**, és állítsa, hogy a
  visszaolvasott rekord a kiírttal egyenértékű. Egy „record() Success-t adott"
  állítás önmagában NEM elfogadható (R18 B2).

***Pirosra fogja:*** minden olyan implementáció, amely a mappert nem a valódi
enum-kódokkal hívja — a serializer `JsonRecordException`-nel dobja el.

### A4 — Az observation gateway élesben létrejön

Provider a `LivePracticeObservationGateway`-hez, a `StrumEngine`, a
mikrofon-engedély-gateway, az idővonal és a logger valódi forrásaival.
A layer-purity guard (A9) **zöld marad** — ha nem hozható zöldre a §2 szerinti
elrendezéssel, az `STOPPED`, nem a guard lazítása. **§0.0 revízió:** ez a
guard a `practice_session_providers.dart`-ra ÚJ (ebben a körben írt) —
ld. §0.0 és ADR 0111 §3.

### A5 — A valódi piros→zöld cella

`practice_production_wiring_test.dart`: a **provider-gráfon keresztül** (nem a
konstruktorba injektált fake-ekkel) indítson egy sessiont a Setup által
összeállított configgal, futtassa terminal állapotig, és állítsa, hogy

1. a host **nem `null`**, a state-stream valódi állapotokat ad;
2. a session terminal állapotba jut;
3. a history-repóban **ott van** a rekord, és **visszaolvasható**;
4. terminal után **nulla** aktív erőforrás (lease, ticker, subscription).

**Kötelező bizonyíték a §10-ben:** ez a teszt a kör ELSŐ commitja előtti fán
**PIROS** (a mai `null` host miatt), utána **ZÖLD**. A §10-be a piros futás
kimenete is bekerül — bizonyíték nélküli „valódi piros→zöld" állítás a
jelentés hibája (mért tanulság: `docs/LESSONS.md` L24, L31).

### A6 — Nincs leak és nincs offline-sértés

Az R11/R13 leak-számlálói zöldek mind a három terminal ágon; az
`offline_network_guard_test.dart` zöld (a session alatt **nulla** hálózati kérés).

### A7 — A flagek nem mozdultak

`git diff` a `lib/app/config/` alatt **üres**. A §10 mondja ki, hogy a
production rollout külön körre marad.

## 7. Implementációs sorrend (ez a TERVED)

1. Mérd ki a `PracticeSessionController` konstruktorának tényleges
   paraméter-halmazát és a `PracticeSessionConfig` mezőit — az A1/A3 ebből él.
2. Írd meg az **A5 tesztet ELŐSZÖR**, és futtasd: **pirosnak kell lennie**.
   A piros kimenetet tedd félre a §10-nek.
3. A4 — gateway provider (a §2 réteg-korláttal).
4. A1 — controller-family.
5. A2 — host + prepare sink.
6. A3 — recorder-metaadat + a visszaolvasási cella.
7. A5 újra: **zöld**. Aztán A6, A7.
8. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A layer-purity guard.** A gateway `StrumEngine`-t vár, a providers fájl nem
  hivatkozhat rá. Ez a kör legfőbb szerkezeti kényszere — a §2 adja a megoldást,
  eltérés esetén `STOPPED`.
- **A write-then-drop visszavezetése.** Az R18 B2 pontosan ezen bukott el
  egyszer; az A3 visszaolvasási cellája a védelem.
- **Scope-tágulás.** A §2 nyitott leletei (chord-change null, strum count
  csempe) útba esnek, és csábítóan kicsinek látszanak. **Nem ebben a körben.**
- **Erőforrás-szivárgás.** Az önálló session az első út, ahol a lease-t nem a
  Learn-migrációs ág szerzi meg — a terminal ágak mindegyikét mérd.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/features/learn/ test/core/ test/app/ test/property/
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + randomizált
property gate + APK a CI-ban fut (ADR 0053); a **zöld CI-futás linkje**
kötelező része a §10-nek.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · **az A5 teszt PIROS futásának kimenete a javítás
előtt** · a záró gate TÉNYLEGES, teljes kimenete · az A1–A7 teljesülése
bizonyítékkal · a nem futtatott ellenőrzések és okuk · a §3-ban kívül hagyott,
útba esett leletek felsorolása.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r21-review.md`

Kiemelt figyelem: az **A5 piros→zöld bizonyítéka** (tényleg piros volt-e a
javítás előtt, vagy a teszt eleve zöldre íródott), az **A3 visszaolvasási
cellája** (nem elég a `Success`), a **layer-purity guard** valódi zöldsége, és
hogy a `lib/app/config/` diffje tényleg üres-e.
