# E08-R13 — Achievement domain és katalógus

- **Státusz:** READY (H3 scope-revízió 2026-08-20, mérve: `main @ ecfbde54`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 13
- **Kör-azonosító:** `E08-R13`
- **Branch:** `<motor>/e08-r13-achievement-domain-and-catalog`
- **Előfeltétel:** `E08-R12` merge-elve (streak UI V2)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0310` — a szám FOGLALT. Az ADR-t a Claude írja meg a
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

## 0.0 H3 self-heal scope-revízió — 2026-08-20

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

### 0.0.1 Visszakeresett előzmény és kockázati indoklás

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
- `docs/adr/**` — az ADR 0310-et a Claude írja.

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

## 5. Kötött architekturális döntések (ADR 0310)

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

**A küszöb három kötelező cellája** (a katalógus mérete (a gondozott elemek száma)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | 19 elem | a validáció **HIBÁT ad** — a katalógus a specifikált 20–30 sávon kívül van |
| **rajta** (a küszöbön) | pontosan 20 elem (az alsó határ) | **ELFOGADVA** — a sáv INKLUZÍV mindkét végén |
| a küszöb **fölött** | 31 elem | a validáció **HIBÁT ad** — a felső határ is inkluzív, 30-ig elfogadott |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

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

## 11. Review — a Claude tölti ki
