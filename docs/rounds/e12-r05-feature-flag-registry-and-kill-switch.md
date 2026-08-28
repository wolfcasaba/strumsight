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

**R1 — A mért számok (a ⚠ jegyzet egy száma HIBÁS volt).**
`lib/app/config/feature_flags.dart` = 451 sor, **37** `final bool` mező:
**3** kötelező konstruktor-paraméter (`accountEnabled`, `diagnosticsEnabled`,
`labModeAvailable`) + **34** `= false` alapértelmezésű. A ⚠ jegyzet „5 kötelező
konstruktor-paraméter" állítása téves; a §2 „3 kötelező" állítása helyes.
`bool.fromEnvironment` **5** helyen. **Az A1 teljesség-követelmény mind a 37
mezőre vonatkozik**, nem csak a 34-re. Az E13/E14 sáv nem vett fel újat.

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

## 11. Review — a Claude tölti ki
