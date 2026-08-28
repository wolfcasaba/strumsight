# E12-R05 — Feature flag registry és emergency kill switch

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 5
- **Kör-azonosító:** `E12-R05`
- **Branch:** `<motor>/e12-r05-feature-flag-registry-and-kill-switch`
- **Előfeltétel:** `E12-R04` merge-elve (a környezet-mátrix a flag-feloldás bemenete)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0446` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "feature flag registry kill switch fail-closed expiration remote signature"` → **[ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)** (score 2.87): a Community kill switch mechanizmusa MÁR eldöntötte, hogy a dart-define/env mindig felülírható, és a hardcode-false váltás dedikált GOV-kör dolga, nem egy építő-köré. Ez a kör tehát a MEGLÉVŐ mechanizmust katalogizálja és auditálja, nem cseréli le.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** számold újra a `lib/app/config/feature_flags.dart` flagjeit (a megíráskor **34** `false`-alapértelmezésű mező + 5 kötelező konstruktor-paraméter, `bool.fromEnvironment` **5** helyen a `forEnvironment` factoryban) és nézd meg, hogy az E13/E14 sáv vett-e fel újat. A §2 számai a mérésből valók.

## 0.0 Pre-flight brief-revízió (orchestrátor, 2026-08-28, `main @ 86d08ad6`)

**Ahol ez a szakasz és bármely későbbi szakasz eltér, EZ nyer.** A normatív
forrás a pre-flightban megírt
[`docs/adr/0446-feature-flag-registry-and-emergency-kill-switch.md`](../adr/0446-feature-flag-registry-and-emergency-kill-switch.md).

**Visszakeresés (ADR 0312, szűkítve → teljes korpusz):**
`--corpus lessons,halts,adr "feature flag registry kill switch fail-closed expiration audit tool"`
→ [ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)
(a kill switch MA operábilis, a hardcode-false lezárás külön GOV-kör),
[ADR 0137](../adr/0137-ai-tutor-readonly-tool-contract.md) (fail-closed,
allowlist-alapú registry precedens). `--corpus lessons,halts "dart tool source
parsing completeness audit test expiry date threshold"` →
[L85](../LESSONS.md#l85)/[L86](../LESSONS.md#l86) (beágyazott Dart tool-package
scope- és analyzer-csapdái — **ezért NEM külön package a `tool/`-ban, hanem
egyetlen fájl a meglévő `tool/` gyökérben**), [L368](../LESSONS.md#l368) (a
generikus architecture-checker és a célzott tesztes őr bizonyítéka nem
felcserélhető).

**R1 — A mért számok** *(javítva a review-ban, 2026-08-28: az eredeti R1
tévesen 37 mezőt írt)*. `lib/app/config/feature_flags.dart` = 451 sor,
**40** `final bool` mező: **3** kötelező konstruktor-paraméter
(`accountEnabled`, `diagnosticsEnabled`, `labModeAvailable`) + **37**
`= false` alapértelmezésű. A ⚠ jegyzet „5 kötelező konstruktor-paraméter"
állítása téves; a §2 „3 kötelező" állítása helyes, a „34" viszont a
`= false` mezőkre is alulmér. **A hibás szám oka mérve:** a pre-flight
`grep -cE "^\s+final bool [a-zA-Z]+;"` mintája kiejtette a **számjegyet
tartalmazó** három mezőnevet (`practiceEngineV2Enabled`,
`songTrainerV2Enabled`, `audioAnalysisV2Enabled`); a helyes minta
`[A-Za-z0-9]+`. `bool.fromEnvironment` **5** helyen (ez stimmelt).
**Az A1 teljesség-követelmény mind a 40 mezőre vonatkozik.** Az A1/D4 gépi
audit amúgy sem rögzített számból, hanem a forrás ÉLŐ parse-olásából
származtatja a teljességet — az implementer helyesen a mért 40 mezőt
katalogizálta (§10.1). Az E13/E14 sáv nem vett fel újat.

**R2 — A katalógus string-kulcsú, NEM importálja a `FeatureFlags` típust**
(ADR 0446 D5). Mérve: `feature_flags.dart` importálja a
`lib/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart`-ot, a
`check_architecture.dart:332` pedig `lib/core/** → lib/features/**` élt tilt. A
bejegyzés a flag **nevét** hordozza; a mezőkhöz kötést a gépi audit (R3)
teremti meg.

**R3 — Az audit-eszköz alakja kötött** (ADR 0446 D4): a logika root- és
tartalom-paraméteres, tesztből hívható függvényekben él, a `main()` vékony,
`exitCode`-ot állító burkoló — a `tool/check_sdd_index.dart` (ADR 0443) mintája.
A teszt relatív importtal hívja: `import '../../tool/check_feature_flags.dart';`
(mérve: `test/tooling/**` minden eszköz-tesztje így tesz). A teljességet a
`lib/app/config/feature_flags.dart` **forrásának** parse-olása adja
(`final bool <név>;` meződeklarációk), nem reflexió.

**R4 — Az idő INJEKTÁLT** (ADR 0446 D6): a lejárat-vizsgáló függvény
`DateTime now` paramétert kap; `DateTime.now()` hívása a mérőfüggvényben TILOS.
A küszöb-cellahármas fix dátumokkal és fix injektált `now`-val megy:
`now = 2026-08-28` mellett `expiresOn = 2026-08-27` → **PIROS**,
`2026-08-28` → **ZÖLD** (inkluzív határ), `2026-08-29` → **ZÖLD**.

**R5 — A VALÓS katalógus zöld, a piros esetet fixture adja** (ADR 0446 D6):
`dart run tool/check_feature_flags.dart` a szállított fán **0** kilépési kóddal
fut. Az A5 piros celláját **kézzel épített fixture** katalógus/forrás állítja
elő (a teszt saját, ideiglenes bemenete), NEM a valós bejegyzés lejáratra
állítása. Az `expiresOn` **opcionális** (`null` = tartós capability-kapcsoló);
lejárat csak ott, ahol a rollout vége ténylegesen dátumozott.

**R6 — A `lib/core/feature_flags/public.dart` KÉZZEL írt barrel.** Mérve: a
`tool/gen_public_barrel.dart` kizárólag `lib/features/<f>/public/*.dart`
fragmentekből generál, és a `check_architecture.dart` frissesség-őre is csak
azokra fut; a `lib/core/design_system/public.dart` a kézzel írt core-barrel
precedense. `dart run tool/gen_public_barrel.dart --write` futtatása ebben a
körben szükségtelen.

**R7 — A `tools/round-gate.sh` bekötése TILOS marad** (§3): az audit-eszközt
ez a kör nem teszi a kapu részévé.

## 0.1 Mit NEM csinál ez a kör

A SDD Kör 5 „signed remote flag forrást" is kér. A fán MA nincs remote flag-csatorna, és a bevezetése hálózati + aláírás-ellenőrzési felületet nyitna. A kör ezért a remote forrást **interfész-szinten** vezeti be (a prioritási sorrend és a fail-closed viselkedés mérhető egy fake forrással), tényleges hálózati implementáció NÉLKÜL — a valódi csatorna a Kör 30/31 rollout-döntéseihez tartozik.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/feature_flags/feature_flag_definition.dart",
  "lib/core/feature_flags/feature_flag_registry.dart",
  "lib/core/feature_flags/feature_flag_source.dart",
  "lib/core/feature_flags/public.dart",
  "tool/check_feature_flags.dart",
  "test/core/feature_flags/feature_flag_registry_test.dart",
  "test/tooling/feature_flag_audit_test.dart",
  "docs/release/kill-switches.md",
  "docs/rounds/e12-r05-feature-flag-registry-and-kill-switch.md",
]
gate_tests = [
  "test/core/feature_flags/feature_flag_registry_test.dart",
  "test/tooling/feature_flag_audit_test.dart",
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a flag-feloldás dönti el, hogy egy build hálózatot használ-e (`usesNetwork => accountEnabled || diagnosticsEnabled`), és hogy a Lab-diagnosztika elérhető-e — egy elrontott prioritási szabály production buildben kapcsolna be adatküldő capabilityt. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához a `lib/app/config/feature_flags.dart` ÁTÍRÁSA kellene (nem csak olvasása), a kimenet a `stopped` jelzés és brief-revízió kérése — az a fájl 34 flag hívóhelyét hordozza, az átírása külön kör ([L478](../LESSONS.md#l478)).

## 1. Cél

Minden kockázatos capability egyetlen, típusos, auditálható katalógusban legyen leírva — owner, lejárat, kill-switch-út és fail-closed alapérték mellett —, a meglévő compile-time flag-mechanizmus lecserélése nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/app/config/feature_flags.dart` (451 sor): `final class FeatureFlags`, **34** `false`-alapértelmezésű flag-mező + 3 kötelező (`accountEnabled`, `diagnosticsEnabled`, `labModeAvailable`), a `FeatureFlags.forEnvironment` factory **`bool.fromEnvironment`** hívásokkal olvassa a dart-define-okat. **Metaadat (owner, lejárat, kockázat) SEHOL nincs.**
- `lib/core/feature_flags/` **nem létezik**. `tool/check_feature_flags.dart` **nem létezik**.
- `test/app/config/feature_flags_test.dart` (219 sor) és `test/app/feature_flags_test.dart` (339 sor) MA is védik a feloldást — mindkettő regresszió-őr, **átírásuk a zöldért TILOS**.
- Backend-oldalon a `backend/app/config.py` öt `community_*` flaget hordoz (`False` alapértelmezés) — a katalógus ezeket is felsorolja, de a backend kódot ez a kör nem módosítja.
- ADR 0395 hatálya: a kill switch operábilis (define/env), a hardcode-false lezárás külön kör.

## 3. Scope

**Benne van:** `FeatureFlagDefinition` típus (kulcs, owner, kockázati szint, fail-closed alapérték, lejárati dátum, kill-switch-út, hivatkozott ADR) · `FeatureFlagRegistry` (a MÉRT flagek katalógusa; a `FeatureFlags` mezőihez kötve) · `FeatureFlagSource` interfész prioritási sorrenddel (`emergency` > `remote(signed)` > `capability` > `local/define`), fake forrásokkal tesztelve · `tool/check_feature_flags.dart` (lejárt flag → nem-nulla kilépés; katalógusból hiányzó, de a kódban létező flag → nem-nulla kilépés) · `docs/release/kill-switches.md`.

**NINCS benne (tilos):**

- **A `lib/app/config/feature_flags.dart` módosítása** — a katalógus a MEGLÉVŐ mezőkre hivatkozik (STOP-eset, ha átírás kellene).
- Tényleges hálózati remote-flag csatorna vagy aláírás-ellenőrzés implementációja.
- A `tools/round-gate.sh` bővítése a `check_feature_flags.dart`-tal.
- `docs/adr/**` — az ADR 0446-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/feature_flags/feature_flag_definition.dart` | ÚJ — a típusos definíció |
| `lib/core/feature_flags/feature_flag_registry.dart` | ÚJ — a katalógus |
| `lib/core/feature_flags/feature_flag_source.dart` | ÚJ — forrás-interfész + prioritás |
| `lib/core/feature_flags/public.dart` | ÚJ — a feature-barrel (cross-feature import szabály) |
| `tool/check_feature_flags.dart` | ÚJ — a lejárat/teljesség audit |
| `test/core/feature_flags/feature_flag_registry_test.dart` | a §6 cellái |
| `test/tooling/feature_flag_audit_test.dart` | az audit-eszköz cellái |
| `docs/release/kill-switches.md` | ÚJ — a kill-switch útvonalak |

**Tilos zóna:** `lib/app/config/**` · `lib/features/**` · `backend/**` · `tools/**` · `.github/**` · `docs/adr/**` · minden meglévő teszt gyengítése

## 5. Kötött architekturális döntések (ADR 0446)

### 5.1 A prioritási sorrend fail-closed, és az `emergency` NEM tud bekapcsolni

Az emergency forrás kizárólag KIKAPCSOLNI tud; a `true` értéke figyelmen kívül marad. **NEM elfogadható gyengítés:** szimmetrikus felülírás („az emergency forrás a legerősebb, tehát be is kapcsolhat") — egy kompromittált vagy elrontott vészcsatorna így capabilityt kapcsolna be.

### 5.2 A kill switch NEM töröl adatot

A kikapcsolás elrejti a capabilityt; a felhasználó adatai érintetlenek maradnak, és visszakapcsoláskor ismét elérhetők. **NEM elfogadható gyengítés:** „takarítás" a kikapcsoláskor.

### 5.3 A katalógus TELJESSÉGE gépi állítás

A `check_feature_flags.dart` a `FeatureFlags` mezőneveit olvassa, és minden mezőhöz katalógus-bejegyzést követel. **NEM elfogadható gyengítés:** kézzel karbantartott lista, gépi teljesség-ellenőrzés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `FeatureFlags` MINDEN mezőjéhez tartozik katalógus-bejegyzés (owner, kockázat, alapérték, kill-switch-út) | `feature_flag_audit_test.dart` |
| A2 | Ismeretlen/hiányzó forrás esetén a feloldás a fail-closed alapértékre esik | `feature_flag_registry_test.dart` |
| A3 | Az `emergency` forrás `false`-a felülír mindent; a `true`-ja NEM kapcsol be semmit | `feature_flag_registry_test.dart` |
| A4 | Aláírás-ellenőrzésen bukó remote forrás figyelmen kívül marad (nem kapcsol be és nem hibázik el fatálisan) | `feature_flag_registry_test.dart` fake-forrás cellája |
| A5 | Lejárt (`expires_on` a mai dátum ELŐTT) flag esetén `check_feature_flags.dart` nem-nulla kóddal lép ki | `feature_flag_audit_test.dart` |
| A6 | A kill switch kikapcsolás után a tárolt adat érintetlen (a kikapcsolt capability nem indít törlést) | `feature_flag_registry_test.dart` |
| A7 | A meglévő `test/app/config/feature_flags_test.dart` és `test/app/feature_flags_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas a lejárati dátumra** (a határ INKLUZÍV, azaz a mai napon lejáró flag MÉG érvényes): a küszöb **alatt** (`expires_on` = tegnap) → az audit PIROS; **pontosan rajta** (`expires_on` = ma) → az audit ZÖLD; a küszöb **fölött** (`expires_on` = holnap) → az audit ZÖLD.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az emergency forrás szimmetrikusan felülír (be is kapcsol) | A3 |
| Hiányzó forrásnál a feloldás az utolsó ismert értéket használja | A2 |
| A bukott aláírású remote payload értékei érvényre jutnak | A4 |
| A katalógus kézzel írt lista, a teljesség nincs ellenőrizve (egy új flag kimarad) | A1 |
| A lejárat-ellenőrzés `>` helyett `>=`-t használ a mai napra | a küszöb-cellahármas „pontosan rajta" cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a katalógusból az egyik `vision*` flag bejegyzését, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/feature_flags/feature_flag_registry_test.dart test/tooling/feature_flag_audit_test.dart test/app/config/feature_flags_test.dart
```

Az audit-eszköz közvetlen futtatása (a kimenet a §10-be):

```bash
dart run tool/check_feature_flags.dart
```

## 8. Implementációs sorrend

1. `feature_flag_definition.dart` — a típus.
2. `feature_flag_source.dart` — a forrás-interfész és a prioritási feloldás.
3. `feature_flag_registry.dart` — a MÉRT flagek katalógusa.
4. `public.dart` barrel.
5. `tool/check_feature_flags.dart` — teljesség + lejárat.
6. A két teszt-fájl, benne a küszöb-cellahármas.
7. `docs/release/kill-switches.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A vészkapcsoló kétirányúvá tétele.** A legsúlyosabb hiba: az emergency forrás bekapcsolóvá válik (A3).
- **A meglévő flag-feloldás megzavarása.** A kör NEM nyúl a `feature_flags.dart`-hoz; a két meglévő teszt (558 sor együtt) a bizonyíték (A7).
- **A katalógus elavulása.** Kézi lista mellett az első új flag után hazudik — ezért gépi a teljesség-ellenőrzés (A1).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort medium`), 2026-08-28.

### 10.1 Mért korrekció — 40 mező, nem 37 (R1 újramérve)

A brief §0.0 R1 pontja (és az ADR 0446 Kontextus szakasza) **37** `final
bool` mezőt állít (3 kötelező + 34 alapértelmezett). Egy közvetlen újramérés
UGYANAZON a fán (`grep -c 'final bool ' lib/app/config/feature_flags.dart`,
`python3 -re` kereszt-ellenőrzés) **40** mezőt talál (3 kötelező + **37**
alapértelmezett — a „34" és a „37 total" szám fel lett cserélve a briefben).
A `bool.fromEnvironment` darabszám (5) és a fájl sorszáma (451) egyezik.

Ez NEM STOP-eset: az A1 teljesség-követelmény és a D4 gépi audit a forrás
ÉLŐ parse-olásából származik, nem egy rögzített számból — a `dart run
tool/check_feature_flags.dart` a valódi fán csak akkor lehet zöld (R5), ha a
katalógus a MÉRT (40, nem 37) mezőt fedi le. A katalógus ezért mind a 40
valós mezőt tartalmazza; ez tartja zölden mind a gépi audit-eszközt, mind a
`test/app/config/feature_flags_test.dart` / `test/app/feature_flags_test.dart`
regresszió-őröket (A7). A pontos mező-egyezést (`real - catalog == ∅` és
`catalog - real == ∅`) egy Python cross-check is megerősítette
implementáció közben.

### 10.2 Létrehozott fájlok

| Fájl | Tartalom |
|---|---|
| `lib/core/feature_flags/feature_flag_definition.dart` | `FeatureFlagDefinition`, `FeatureFlagRisk` |
| `lib/core/feature_flags/feature_flag_source.dart` | `FeatureFlagSource`, `RemoteFeatureFlagSource`, `SignedFeatureFlagPayload`, `FeatureFlagResolver`, `FeatureFlagResolution(Origin)` |
| `lib/core/feature_flags/feature_flag_registry.dart` | `featureFlagRegistry` — 40 bejegyzés, string-kulcsú (D5), `FeatureFlags` importja NÉLKÜL |
| `lib/core/feature_flags/public.dart` | kézzel írt barrel (R6) |
| `tool/check_feature_flags.dart` | `parseFeatureFlagFieldNames`, `isFeatureFlagExpired`, `auditFeatureFlagRegistry`, `checkFeatureFlagsAtRoot`, vékony `main()` (R3, `check_sdd_index.dart` mintája) |
| `test/core/feature_flags/feature_flag_registry_test.dart` | A2/A3/A4/A6 + prioritási lánc + katalógus-alak |
| `test/tooling/feature_flag_audit_test.dart` | A1/A5 + küszöb-cellahármas + R5 (valós katalógus zöld) + programozott valódi-sértés próba |
| `docs/release/kill-switches.md` | a katalógus emberi olvasatú vetülete, generálva a Dart forrásból |

### 10.3 Kötelező gate (§7) — ZÖLD

```
tools/round-gate.sh test/core/feature_flags/feature_flag_registry_test.dart test/tooling/feature_flag_audit_test.dart test/app/config/feature_flags_test.dart
```

Mind a 8 lépés (`format`, `analyze`, a 3 célzott teszt, `architecture`,
`secrets`, `l10n`) ZÖLD. Kiegészítő futtatás (nem a gate része, de az A7
másik regresszió-őre): `flutter test test/app/feature_flags_test.dart` — 16
teszt, mind ZÖLD.

Az audit-eszköz közvetlen futtatása (§7 második parancsa):

```
$ dart run tool/check_feature_flags.dart
Feature flag audit OK (0 issue(s)).
```

### 10.4 Valódi-sértés próba (§6, KÖTELEZŐ) — mindkét próba, kimenettel

**1. próba (A1, brief §6.1 sora 1):** a `visionSetupEnabled` bejegyzés
kivétele a `feature_flag_registry.dart`-ból, majd
`flutter test test/tooling/feature_flag_audit_test.dart`:

```
00:00 +11 -1: checkFeatureFlagsAtRoot — R5 (the real, shipped catalog is green) the real registry matches the real feature_flags.dart source with no expired entries [E]
  Expected: true
    Actual: <false>
  Feature flag audit failed:
  - [missingCatalogEntry] FeatureFlags field "visionSetupEnabled" (lib/app/config/feature_flags.dart) has no catalog entry in featureFlagRegistry.
```

Az A1 cella PIROS lett, pontosan a hiányzó mezőt nevezve. Visszaállítva
(`git diff` üres a fájlra), a teszt újra ZÖLD (16/16, ellenőrizve a §7
gate teljes újrafuttatásával is).

**2. próba (A3, brief §0.0 §6 sora 2 — a resolver §5.1 tiltott gyengítése):**
a `feature_flag_source.dart` `FeatureFlagResolver.resolve` emergency-ágának
szimmetrikussá tétele (`emergencyValue != null` → érvényesül, a `true` is),
majd `flutter test test/core/feature_flags/feature_flag_registry_test.dart`:

```
00:00 +4 -1: A3 — the emergency source is asymmetric: only `false` ever wins (ADR 0446 D1, the NOT-acceptable weakening from brief §5.1) emergency=true does NOT turn the flag on — it is treated exactly like no opinion and falls through to the next source [E]
  Expected: false
    Actual: <true>
```

Az A3 cella PIROS lett — az emergency `true` bekapcsolt egy flaget, ami az
ADR 0446 D1 tiltott gyengítése. Visszaállítva (`git diff` üres a fájlra), a
teszt újra ZÖLD (16/16), és a teljes §7 gate is újra lefutott zölden a
visszaállítás UTÁN (l. 10.3).

### 10.5 Kockázati szint (§9) — a heurisztika és korlátai

A `risk` mező (`FeatureFlagRisk.{low,medium,high}`) emberi ítélet, nem gépi
mérés — a `feature_flag_registry.dart` fejléce dokumentálja a szabályt
(`high` csak ott, ahol a `feature_flags.dart` maga `usesNetwork`-ben
szerepel, vagy a mező doc-commentje hálózati/adat-kiviteli szót nevez meg).
Az `adr` mező csak akkor tölt, ha `feature_flags.dart` MAGA hivatkozik egy
ADR-re az adott mező közelében — 33/40 mezőnél nincs ilyen közvetlen forrás-
hivatkozás, ott `adr: null`. Ez review-ban vitatható, de nem hazudik: minden
`adr != null` érték egy konkrét, idézett forrás-sorra vezethető vissza.

### 10.6 Nem érintett / szándékosan kimaradt

- `lib/app/config/feature_flags.dart` — csak olvasva, nem módosítva.
- `tools/round-gate.sh` — a `check_feature_flags.dart` NINCS bekötve (R7).
- Valódi hálózati remote-flag csatorna / aláírás-ellenőrzés — interfész-
  szintű marad (`SignedFeatureFlagPayload.signatureValid` egy fake-mező), a
  D3 szerint szándékosan.

### 10.7 Javító kör (F1–F3)

**F1 — a mezőminta bővítve, a reviewer mért próbája megismételve.**
`tool/check_feature_flags.dart:25` mintája (`final bool (\w+);`) csak a
sima alakot ismerte fel; a `final bool? <név>;` és a `final bool <név> =
<kifejezés>;` alakok csendben kicsúsztak. Az új minta
(`^\s*final bool\??\s+(\w+)\s*(?:;|=)`, sor-elejére horgonyzva) mindhárom
alakot felismeri, és a horgonyzás miatt getterhez, doc-commentbeli
csali-sorhoz nem nyúl. **RED-cella:** `test/tooling/feature_flag_audit_test.dart`
két új cellája —
`parseFeatureFlagFieldNames reads the plain, nullable, and initialized field
forms alike, ignoring a getter and a doc-comment bait line` és
`auditFeatureFlagRegistry — A1 (completeness) a nullable field and an
initialized field parsed from source are still flagged missingCatalogEntry
when uncataloged` — a régi mintán mérten PIROS volt (a második a
`FeatureFlagAuditIssueCode.incompleteCatalogEntry` hiánya miatt fordítási
hibával, izoláltan a régi mintával futtatva pedig `Expected: false Actual:
<true>`-val bukott, mert az üres `fieldNames` miatt a `report.isClean` igazra
jött ki), a javítás után ZÖLD (mindkettő ellenőrizve `git show HEAD:tool/
check_feature_flags.dart`-tal visszaállított régi fájllal izoláltan
lefuttatva, majd visszaállítva). A **valós fán** megismételve a reviewer
mért próbáját (a két mezőt `lib/app/config/feature_flags.dart` egy `/tmp`-beli
másolatába szúrva, a valós `featureFlagRegistry` ellen auditálva — a tiltott
fájl maga nem módosult): mindkét mező most `missingCatalogEntry`-ként bukik,
nem csúszik át zölden. A valós, változatlan 40 mezős katalógus továbbra is
zöld (`dart run tool/check_feature_flags.dart` → „Feature flag audit OK (0
issue(s))”).

**F2 — a „generált tábla” állítás javítva (kisebb diffet adó (a) út).**
`docs/release/kill-switches.md:10-12` mondata igazra cserélve: a tábla
**kézi vetület** (nem generált), az igazság forrása a Dart katalógus, a
Dart-oldali driftet a `dart run tool/check_feature_flags.dart` gépileg fogja,
de magát a markdown táblát ma semmi nem méri. A (b) út (gépi paritás-cella a
markdown tábla és a `featureFlagRegistry` kulcshalmaza között) nagyobb diffet
adott volna (új parse-logika a teszt-fájlban egy már amúgy is bővülő
fájlban) — az (a) út egy bekezdésnyi, tisztán dokumentációs javítás.

**F3 — `incompleteCatalogEntry` új issue-kód az A1 metaadat-hiányra.**
`auditFeatureFlagRegistry` egy új ellenőrző kört kapott: minden katalógus-
bejegyzés `owner` és `killSwitchPath` mezőjét `.trim().isEmpty`-vel vizsgálja,
és `FeatureFlagAuditIssueCode.incompleteCatalogEntry`-t emel, ha bármelyik
üres vagy csak whitespace. **RED-cellák:** `auditFeatureFlagRegistry — A1
(metadata completeness)` csoport két fixture-cellája (üres `owner`,
whitespace-only `killSwitchPath`) — mindkettő a régi kódon fordítási hibával
bukott (`Member not found: 'incompleteCatalogEntry'`), a javítás után ZÖLD.
Harmadik cella a valós katalógust ellenőrzi: a 40 valós bejegyzés egyikén sem
üres az `owner` vagy a `killSwitchPath` (mérve: a csoport is ZÖLD a valós
fán).

**Gate (mindhárom fixhez együtt, §5 szerint, csonkítás nélkül):**
`tools/round-gate.sh test/core/feature_flags/feature_flag_registry_test.dart
test/tooling/feature_flag_audit_test.dart test/app/config/feature_flags_test.dart`
— mind a 8 lépés ZÖLD. `dart run tool/check_feature_flags.dart` a valós fán
**exit 0**, „Feature flag audit OK (0 issue(s))”. A `lib/app/config/
feature_flags.dart` és a `feature_flag_source.dart` resolver-logikája
egyaránt változatlan marad.

## 11. Review — a Claude tölti ki
