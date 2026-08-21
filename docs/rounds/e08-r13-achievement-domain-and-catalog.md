# E08-R13 — Achievement domain és katalógus

- **Státusz:** READY (pre-flight revízió 2026-08-20, mérve: `main @ 7267fe6d`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 13
- **Kör-azonosító:** `E08-R13`
- **Branch:** `<motor>/e08-r13-achievement-domain-and-catalog`
- **Előfeltétel:** `E08-R12` merge-elve (streak UI V2)
- **Brief szerzője:** Claude (Opus 5)
- **Pre-flight ADR:** `ADR 0374` — az atomi foglaló adta. Az ADR-t az orchestrátor írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02 esemény-altípusait és az R06 XP-komponenseit — az objective-ek ezekre a metrikákra hivatkoznak; és ellenőrizd a `lib/l10n/features/gamification_en.arb` meglévő kulcs-konvencióját. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/achievements/achievement_definition.dart",
  "lib/features/gamification/domain/achievements/achievement_progress.dart",
  "lib/features/gamification/domain/achievements/achievement_catalog.dart",
  "lib/features/gamification/infrastructure/default_achievement_catalog.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/domain/achievement_catalog_test.dart",
  "docs/rounds/e08-r13-achievement-domain-and-catalog.md",
]
gate_tests = [
  "test/features/gamification/domain/achievement_catalog_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revíziók — 2026-08-20

### 0.0.1 H3 self-heal scope-revízió

A megállt pre-flight az `ecfbde54` HEAD-en mérte, hogy az E99-R17 óta a
`lib/l10n/app_{en,hu}.arb` két **generált aggregátum**, miközben a brief az
achievement-fordításokhoz csak ezeket engedte. A kötelező elsődleges
`lib/l10n/features/gamification_{en,hu}.arb` forrásszegmensek hiányoztak az
allowlistből, ezért a kör a jóváhagyott scope-on belül nem volt
megvalósítható.

Feloldás: az új kulcsok kizárólag a gamification forrásszegmensekbe
kerülnek. A generált aggregátum közvetlenül nem szerkeszthető; a
`lib/l10n/app_{en,hu}.arb` csak kimenet. A szegmensek módosítása után
kötelező a determinisztikus
`dart run tool/gen_l10n_segments.dart --write`, és annak két kimenete marad
név szerint az allowlistben. Ez az aggregate-freshness mércét nem lazítja.
Regressziós őr: `tools/tests/test_e08_r13_l10n_scope.py`.

### 0.0.2 Aktuális kódmérés, visszakeresés és ADR-szám

A dispatch előtti újramérés az aktuális `main @ 7267fe6d` állapoton a
következő, végrehajtható input-szerződést találta:

- az R02 hat konkrét esemény-altípusa és stabil `typeCode` értéke:
  `practice`, `song`, `analysis`, `plan`, `tutor`, `vision`; mindegyik a közös
  `duration` és `score` mezőt hordozza;
- az R06 receipt pontos öt komponense: `baseXp`, `durationXp`, `qualityXp`,
  `improvementXp`, `diversityXp`, valamint a származtatott `totalXp`;
- a gamification ARB-szegmens meglévő kulcsai lowerCamelCase alakúak, és a
  felolvasási szöveg külön `...Semantics` kulcsot használ;
- nincs ma `domain/achievements/` könyvtár, achievement-katalógus vagy
  erőforrás-acquire/lifecycle owner ezen az útvonalon.

Ezért az objective-vokabulár kötött: a hat fenti eseményfajta; a numerikus
`eventCount`, `durationSeconds`, `score` és a hat R06 XP-metrika; distinct
esetben kizárólag a ma ténylegesen mért `activitySource`. Nem vezethető be
fantom `songId`, `skillId` vagy technique-metrika. Az ismeretlen objective-et
egy explicit `UnknownAchievementObjective` forward-compatibility sentinel
reprezentálja, amelyet a katalógus-validáció mindig hibának vesz; ez őrzi a
sealed típusrendszert és a fail-closed ágat egyszerre.

Az előre írt `0310` foglalás elavult: a marker ma
`.pipeline/inflight/adr/0310 = round=E99-R14`. A kötelező
`tools/round-slots.py reserve-adr --round E08-R13` futás `0374`-et adott,
ezért a kör döntési artefaktuma
`docs/adr/0374-achievement-domain-and-catalog-contract.md`. A brief minden
korábbi `0310` hivatkozását ez a dokumentált revízió írja felül.

A kötelező RAG-sorrend lefutott. A szűkített keresések releváns előzményei:
`lessons/L365` és `lessons/L369` (feature-szegmens az elsődleges l10n-forrás,
az aggregátum csak generált kimenet), továbbá `adr/0328` (mért baseline) és
`adr/0344` (a katalógus-verzió későbbi perzisztálási határa). A teljes
korpuszos keresés az R13/R14/R15 briefeket hozta vissza. Az index
`6371aa36` állapotú, három committal elavult; az ADR 0312 szerinti szabály
alapján ezt a kör nem reindexeli.

A katalógusméret cellái `python3 -c`-vel számolva:
`19 / 20 / 21` és `29 / 30 / 31`; a 20 és 30 határ inkluzív.

### 0.0.3 Visszakeresett előzmény és kockázati indoklás

A `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5
"E08-R13 achievement katalógus generált l10n aggregátum gamification
forrásszegmens"` keresés releváns találata L365: ugyanennek a generált
aggregate / hiányzó source-segment hibának az E08-R12-n mért előzménye. Az
ADR 0328 a mért gamification-baseline-t, az ADR 0344 pedig a későbbi
katalógus-verzió perzisztálási határát erősíti meg; egyik sem változtatja
meg e kör szűk domain- és l10n-scope-ját.

**Kockázat = high, indoklás:** a stabil achievement-azonosítók és a
deprecation-szerződés később tartós felhasználói eredményre hivatkozik;
egy címből képzett vagy utólag eltűnő azonosító megszerzett haladást
veszíthet el. A magas kockázat ezért indokolt, a high-risk független review
kötelező marad.

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

Típusos, validálható és lokalizálható eredmény-rendszer: 20–30 gondozott
achievement stabil azonosítókkal, típusos objective-ekkel és **körmentes** tier-gráffal.

## 2. Jelenlegi állapot — mért tények

- Az R02 hat esemény-altípust ad; az R06 komponensenként bontott XP-t — az objective-ek ezekre a metrikákra hivatkozhatnak.
- `lib/features/gamification/domain/achievements/` **nem létezik**.
- i18n konvenció: az új kulcsok elsődleges forrása a
  `lib/l10n/features/gamification_{en,hu}.arb`; a
  `lib/l10n/app_{en,hu}.arb` determinisztikusan generált aggregátum, a
  `app_localizations*.dart` pedig gitignore-olt Flutter-kimenet.
- Az `ADR 0289`: az elsajátítottság mért teljesítményből származik — az achievement **feltétele** mérhető metrika, nem puszta XP.

## 3. Scope

**Benne van:** az objective-típusok (count, threshold, distinct, sequence, compound) · a gondozott
katalógus 20–30 elemmel · stabil azonosítók és ARB-kulcsok · tier-függőségek és rejtett
(hidden) státusz · tartalom-verzió és elavulás (deprecation) mező · a katalógus
**validálhatósága** (körmentes gráf, hiányzó kulcs, ismeretlen metrika).

**NINCS benne (tilos):**

- A kiértékelés (Kör 14), a felület (Kör 15).
- `tool/` alatti validátor script — a Kör 29 dolga; ITT a validáció a domain-oldali, tesztelt függvény.
- Beégetett UI-szöveg: minden cím és leírás ARB-kulcs.
- `docs/adr/**` — az ADR 0374-et az orchestrátor írja a pre-flightban.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/achievements/achievement_definition.dart` | **ÚJ** — a definíció (azonosító, objective, tier, hidden, verzió) |
| `lib/features/gamification/domain/achievements/achievement_progress.dart` | **ÚJ** — a haladás típusa |
| `lib/features/gamification/domain/achievements/achievement_catalog.dart` | **ÚJ** — a katalógus + validáció |
| `lib/features/gamification/infrastructure/default_achievement_catalog.dart` | **ÚJ** — a gondozott 20–30 elem |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/features/gamification_en.arb` | elsődleges forrásszegmens — az ÚJ angol kulcsok; meglévő kulcs NEM módosítható |
| `lib/l10n/features/gamification_hu.arb` | elsődleges forrásszegmens — az ÚJ magyar kulcspárok |
| `lib/l10n/app_en.arb` | **GENERÁLT** — csak a `gen_l10n_segments.dart --write` determinisztikus kimenete |
| `lib/l10n/app_hu.arb` | **GENERÁLT** — csak a `gen_l10n_segments.dart --write` determinisztikus kimenete |
| `test/features/gamification/domain/achievement_catalog_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0374)

### 5.1 Az azonosító STABIL és soha nem változik

Az achievement azonosítója a főkönyvbe és a felhasználó profiljába kerül. Az
átnevezés visszamenőleg elveszi a megszerzett eredményt, ezért az azonosító **nem** a címből
származik, és nem is sorszám.

**NEM elfogadható gyengítés:** az azonosító generálása a lokalizált címből — a fordítás
megváltoztatása így elvenné az eredményt.

### 5.2 Az objective TÍPUSOS, nem szabad szöveg vagy kifejezés-string

Az objective sealed típusok halmaza (count / threshold / distinct / sequence /
compound), amelyek típusosan hivatkoznak esemény-típusra és metrikára. Az ismeretlen
objective **fail-closed**: a katalógus-validáció hibát ad, nem hagyja figyelmen kívül.

**NEM elfogadható gyengítés:** „feltétel-kifejezés” string, amit futásidőben értelmezünk.
Az nem validálható CI-ben, és a Kör 14 indexelése lehetetlenné válna.

### 5.3 A tier-gráf KÖRMENTES, és ezt a validáció bizonyítja

A tier-függőségek irányított gráfot alkotnak; a kör a katalógus-validáció hibája.
Egy kör a kiértékelőt végtelen ciklusba vinné.

### 5.4 Minden szöveg ARB-KULCS; a katalógus nem tartalmaz emberi szöveget

A definíció cím- és leírás-mezője lokalizációs kulcs. A validáció ellenőrzi,
hogy minden hivatkozott kulcs LÉTEZIK mindkét ARB-ban — a hiányzó fordítás a felületen
nyers kulcsként jelenne meg.

### 5.5 Tartalom-verzió és elavulás — az achievementek NEM törlődnek

Egy achievement kivezetése `deprecated` jelöléssel történik, nem törléssel: a
már megszerzett eredmény a felhasználó profiljában marad. A katalógus `contentVersion`-je
teszi követhetővé, melyik build melyik halmazzal dolgozott.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A katalógus 20–30 elemet tartalmaz, mind stabil, nem cím-alapú azonosítóval | `achievement_catalog_test.dart` |
| A2 | Minden objective típusos; ismeretlen objective a validációban HIBÁT ad (fail-closed) | `achievement_catalog_test.dart` |
| A3 | A tier-gráf körmentes; beszúrt kör esetén a validáció hibát ad | `achievement_catalog_test.dart` — kör-cella |
| A4 | Minden hivatkozott ARB-kulcs létezik MINDKÉT nyelvi fájlban | `achievement_catalog_test.dart` — kulcs-lefedettség |
| A5 | A katalógus NEM tartalmaz beégetett emberi szöveget | `achievement_catalog_test.dart` + review |
| A6 | A `deprecated` achievement a katalógusban marad, és a validáció elfogadja | `achievement_catalog_test.dart` |
| A7 | A katalógusnak van `contentVersion`-je, és az elemszám VÁLTOZÁSA verziót igényel | `achievement_catalog_test.dart` |
| A8 | Minden definícióhoz tartozik akadálymentességi (rövid, felolvasható) leírás-kulcs | `achievement_catalog_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az azonosító a címből generálva | **A1** (a stabilitás-cella) |
| Az objective kifejezés-string | **A2** |
| A tier-gráfban kör van | **A3** |
| Egy kulcs csak az angol ARB-ban létezik | **A4** |
| Az elavult achievement törölve | **A6** |
| Beégetett angol cím a katalógusban | **A5** |
| Az elemszám változik, de a `contentVersion` nem nő | **A7** |
| Egy definíció accessibility-kulcsa hiányzik | **A8** |

**A két inkluzív határ kötelező cellái** (a katalógus mérete, azaz a
gondozott elemek száma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alsó határ **alatt** | 19 elem | a validáció **HIBÁT ad** |
| alsó határon | 20 elem | **ELFOGADVA** |
| alsó határ **fölött** | 21 elem | **ELFOGADVA** |
| felső határ **alatt** | 29 elem | **ELFOGADVA** |
| felső határon | 30 elem | **ELFOGADVA** |
| felső határ **fölött** | 31 elem | a validáció **HIBÁT ad** |

A két határ inkluzív: `20 <= elemszám <= 30`. A cellákat a §0.0.2-ben
dokumentált `python3 -c` számítás adta, nem fejben választottuk.
Az alsó küszöbhármas tömören: **alatta** 19 (hiba), **rajta** 20
(elfogadva), **fölötte** 21 (elfogadva). A felső küszöbhármas: **alatta** 29
(elfogadva), **rajta** 30 (elfogadva), **fölötte** 31 (hiba).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** szúrj be egy kört a tier-gráfba (A → B → A), futtasd a gate-et → az **A3**
kör-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
dart run tool/gen_l10n_segments.dart --write
tools/round-gate.sh test/features/gamification/domain/achievement_catalog_test.dart
```

Az első parancs a forrásszegmensekből regenerálja a két aggregátumot;
kézi aggregate-szerkesztés tilos. A gate ezután a freshness-t is ellenőrzi.

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `achievement_definition.dart` — stabil azonosító, típusos objective, tier, hidden, verzió, deprecation.
2. Az objective sealed típusok (count / threshold / distinct / sequence / compound).
3. `achievement_catalog.dart` — a katalógus + a validáló függvény (kör, hiányzó kulcs, ismeretlen objective).
4. `achievement_progress.dart` — a haladás típusa.
5. `default_achievement_catalog.dart` — a gondozott 20–30 elem.
6. Az ARB-kulcsok felvétele a
   `lib/l10n/features/gamification_{en,hu}.arb` forrásszegmensekbe, majd
   `dart run tool/gen_l10n_segments.dart --write`; az aggregátumokat
   közvetlenül szerkeszteni tilos.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A cím-alapú azonosító.** Kényelmes és olvasható, és az első fordítás-javításnál elveszi a felhasználó eredményét (A1).
- **A kifejezés-string objective.** Rugalmasnak tűnik, és CI-ben validálhatatlan, a Kör 14 indexelését pedig ellehetetleníti (A2).
- **A hiányzó magyar kulcs.** Csak a magyar nyelvű felületen látszik, nyers kulcsként — a kulcs-lefedettségi cella nélkül a review sem fogja meg (A4).

## 10. Implementation handoff — az implementer tölti ki

### E08-R13 implementation (Terra, 2026-08-20)

| Fájl | Változás |
|---|---|
| `achievement_definition.dart` | Stabil lower-snake-case ID, immutable definíció, a zárt count/threshold/distinct/sequence/compound objective-vokabulár és fail-closed unknown sentinel. |
| `achievement_catalog.dart` | Immutable katalógus, stabil típusos validációs report, méret-, locale-kulcs-, tier-gráf- és content-version ellenőrzés. |
| `achievement_progress.dart` | Verziózott, nem csökkenő, mellékhatásmentes progress értéktípus. |
| `default_achievement_catalog.dart` | 22 gondozott, stabil azonosítójú achievement; egy retained `legacy_first_step` elem deprecated jelöléssel. |
| `public.dart` | Csak achievement domain- és default-catalog exportok. |
| `gamification_{en,hu}.arb` | Az új title/description/semantics kulcsok elsődleges feature-szegmensei. |
| `app_{en,hu}.arb` | Kizárólag `gen_l10n_segments.dart --write` determinisztikus generált kimenete. |
| `achievement_catalog_test.dart` | A1–A8 célzott cellák, 19/20/21 és 29/30/31 inkluzív méretcellák, unknown sentinel, A→B→A tier-kör és objective-vokabulár. |

#### Futott parancsok és tényleges eredmények

- `flutter test test/features/gamification/domain/achievement_catalog_test.dart` a még hiányzó domain API-val: **PIROS**, a várt hiányzó achievement típusok compile-hibájával (TDD RED).
- `dart format ...achievement_definition.dart ...achievement_progress.dart ...achievement_catalog.dart ...default_achievement_catalog.dart ...public.dart ...achievement_catalog_test.dart`: **ZÖLD**, 6 fájlból 4 formázott módosítás.
- `dart run tool/gen_l10n_segments.dart --write`: **ZÖLD**, `en` és `hu` aggregátum írva.
- `flutter test test/features/gamification/domain/achievement_catalog_test.dart`: **ZÖLD**, 16 teszt.
- Valódi A3 sértéspróba: az A→B→A fixture elutasítási elvárását ideiglenesen `isTrue`-ra fordítottam; `flutter test ... --plain-name 'A3: rejects an A to B to A tier cycle'`: **PIROS** (`Expected: true`, `Actual: <false>`), majd az elvárást tisztán `isFalse`-ra visszaállítottam.

#### Eltérések és nem futtatott ellenőrzések

- Nincs funkcionális eltérés a brieftől.
- `tools/round-gate.sh test/features/gamification/domain/achievement_catalog_test.dart`: **ZÖLD** — format, analyze, a 16 célzott teszt, architecture, secrets és l10n mind zöld; a l10n parity 1503 üzenetet mért.
- A teljes suite, randomizált property gate, CI-dispatch, PR és merge implementer-scope-on kívül van.

### E08-R13 F1/F2 repair (Terra, 2026-08-21)

| Fájl | Változás |
|---|---|
| `achievement_catalog.dart` | A `previousCatalog` minden korábbi ID-jának jelenlétét ellenőrzi elemszámtól és verzióemeléstől függetlenül; a hiányt a stabil `previousAchievementMissing` kóddal jelzi. |
| `achievement_definition.dart` | A count/distinct pozitív célja és a threshold véges, nem negatív minimuma runtime `ArgumentError`-ral őrzött. |
| `achievement_progress.dart` | A kezdeti és `advanceTo` progress véges, nem negatív és nem csökkenő runtime-invariáns. |
| `default_achievement_catalog.dart` | A runtime-validált objective-konstruktorokhoz igazított hívások. |
| `achievement_catalog_test.dart` | Azonos elemszámú replacement-ID regressziós cella, valamint zero/negative/infinity/NaN objective- és progress-határmátrix. |

#### Futott parancsok és tényleges eredmények

- `flutter test test/features/gamification/domain/achievement_catalog_test.dart` az új F1 validation code nélkül: **PIROS**, várt compile-hibával (`previousAchievementMissing` nem létezett).
- `flutter test test/features/gamification/domain/achievement_catalog_test.dart`: **ZÖLD**, 20 teszt.
- `dart format lib/features/gamification/domain/achievements/achievement_definition.dart lib/features/gamification/domain/achievements/achievement_catalog.dart lib/features/gamification/domain/achievements/achievement_progress.dart lib/features/gamification/infrastructure/default_achievement_catalog.dart test/features/gamification/domain/achievement_catalog_test.dart`: **ZÖLD**, 5 fájl ellenőrizve, 2 formázott változás.
- `tools/round-gate.sh test/features/gamification/domain/achievement_catalog_test.dart`: **ZÖLD** — format, analyze, 20 célzott teszt, architecture, secrets és l10n gate lefutott.

#### Eltérések és nem futtatott ellenőrzések

- L10n-forrásszegmens nem változott, ezért `dart run tool/gen_l10n_segments.dart --write` nem futott.
- N1 completion-timestamp megfigyelés változatlanul R14 pre-flightjára marad.
- A teljes suite, randomizált property gate, CI-dispatch, PR és merge implementer-scope-on kívül van.

## 11. Review — a Claude tölti ki

Correctness: [`docs/reviews/e08-r13-achievement-domain-and-catalog-review.md`](../reviews/e08-r13-achievement-domain-and-catalog-review.md)
— **APPROVED** (`c088c26c`, két MAJOR javítva).
Security: [`docs/reviews/e08-r13-achievement-domain-and-catalog-security.md`](../reviews/e08-r13-achievement-domain-and-catalog-security.md)
— **PASS**, nincs nyitott security BLOCKER/MAJOR.
