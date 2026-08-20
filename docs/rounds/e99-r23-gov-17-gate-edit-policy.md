# E99-R23 (GOV-17) — Gate-edit policy: a briefben ELŐRE megtervezett mércemódosítás emberi kéz nélkül

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-20, `main @ ecfbde54`)
- **Típus:** **governance-kör** — a lánc saját felhatalmazási rétege
- **Kör-azonosító:** `E99-R23`. Emberi neve **GOV-17**.
- **Előfeltétel:** nincs (a `E99-R21` és `E08-R29` hold-ok EBBŐL a körből oldódnak fel)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** `0372` — az ADR-t
  Claude írja, a `docs/adr/` ebben a körben **TILOS zóna**.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  ".claude/gate-edit-policy",
  ".claude/hooks/protect_factory_files.py",
  "tools/gateguard-scan.py",
  "tools/tests/test_gate_edit_policy.py",
  "tools/tests/test_gateguard_scan.py",
  "docs/rounds/e99-r23-gov-17-gate-edit-policy.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a kör magát az őrt módosítja. Egy elrontott
> escape MINDEN védett útvonalat felold minden sessionnek — ezért a
> `security-reviewer` bevonása KÖTELEZŐ, és a §6.1 mátrix minden cellája
> falszifikációs próbát ír elő.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 0.1 A user álló döntése, amit ez a kör végrehajt

2026-08-19, két kérdésre kifejezett igen (jegyzőkönyv:
`.pipeline/HANDOFF-gate-autonomy-20260819.md` §2): *„legyen ÁLLÓ felhatalmazás,
hogy a mércét érintő körökhöz SOHA többé ne kelljen emberi kéz"* — **de csak
akkor**, ha a mércefájl a kör briefjének `allowed_paths` listáján **névszerint**
szerepel, azaz a szándék előre, emberi olvasásra papírra került.

Amit a döntés kifejezetten NEM enged meg: ad-hoc, terven kívüli mércemódosítás;
titok-útvonal feloldása; a `tools/round-gate.sh` és a CI lépéslistájának
megváltoztatása.

## 0.1 Visszakeresett előzmény (tudás-index, ADR 0312 §4.1)

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "mércefájl védett őr felhatalmazás gate-edit marker emberi engedély hold"`:

- **`lessons/L323`** (E99-R17, H3, 2026-08-19) — a marker megléte önmagában nem
  vitte el a kört. Az utólagos mérés (memória: `gateguard-authorization-mechanism`,
  2026-08-19) pontosította: a marker MŰKÖDIK (payloaddal futtatva exit 0), a
  valódi két ok a **gitignore** (friss munkapéldányba sosem kerül bele) és a
  **dispatch előtti pre-flight hold**. Ez a kör mindkettőt megszünteti: a policy
  KÖVETETT (D1), a pre-flight pedig a névszerinti tervet elfogadja (D3).
- **`lessons/L117`** (GOV-03) — *„az emberi escape-hatch, amit nem lehet
  beállítani, nem escape-hatch"*: a `STRUMSIGHT_GATE_EDIT_OK` env futó
  sessionben nem állítható be, a `settings.local.json` `env` blokkját pedig a
  harness (helyesen) blokkolja. Ezért NEM env-alapú a megoldás, hanem
  **commitolt policy-fájl + a briefből mért szándék**.
- **`ADR 0309 §4.1`** — a hook-réteg ismert rése: két lépés azért maradt nyitva,
  mert a mérce saját zónáját írná. Ez a kör pontosan ezt a rést zárja, a
  hatókör szűkítése nélkül.

## 0.2 Bootstrap — az EGYETLEN emberi lépés (mérve, nem megkerülhető)

`.claude/hooks/*` maga is a `PROTECTED_GLOBS` része
(`.claude/hooks/protect_factory_files.py:56-92`), ezért a **D2** commitot az őr
saját magán blokkolná: tyúk-tojás. Feloldás — a user egyszeri aktusa a kör
INDÍTÁSA előtt, a kör munkapéldányában:

```bash
printf 'E99-R23 GOV-17 bootstrap — a gate-edit-policy beépítése (user-döntés 2026-08-19).\n' \
  > .claude/gate-edit-authorized
```

A marker `.gitignore`-olt, tehát nem utazik a commitokkal. **A kör DoD-ja
tartalmazza a törlését** — a marker hatókör nélkül mindent felold, ezért egy
percig sem maradhat ott a merge után. Ezután a bootstrap véglegesen tárgytalan:
a D1 policy-fájl KÖVETETT, tehát minden munkapéldányba automatikusan bekerül.

## 1. Cél

A mércét érintő kör fusson végig emberi kéz nélkül, **ha és csak ha** a
mércefájlt a kör briefje névszerint nevesíti — a védőháló (scope-audit,
független review, teljes kapu, zöld kapus merge) változatlan marad.

Mérhető végállapot: a `hold`-ban álló `E99-R21` és `E08-R29` a kör merge-e után
pusztán a sor-státusz `pending`-re állításával elindulhat, a pre-flight nem teszi
őket újra hold-ra.

## 2. Jelenlegi állapot — mérve a kódban (2026-08-20)

| mérés | eredmény |
|---|---|
| `.claude/gate-edit-policy` | **nem létezik** |
| `.claude/gate-edit-authorized` | nem létezik (az E99-R17 után törölve) |
| a hook escape-jei | `ESCAPE_VARIABLE="STRUMSIGHT_GATE_EDIT_OK"` (:94), `ESCAPE_MARKER=".claude/gate-edit-authorized"` (:95) — **mindkettő hatókör nélküli**: ha jelen van, MINDEN védett útvonalat felold |
| brief-alapú felhatalmazás | **nincs** — `grep -c '_brief_authorization' .claude/hooks/protect_factory_files.py` → 0 |
| pre-flight hold | `tools/round-pipeline.sh:2261` importálja a `tools/gateguard-scan.py`-t és a kört a sorban `hold`-ra teszi — **a hook escape-jétől függetlenül**, tehát a hook önmagában NEM elég |
| a scan illesztése | `tools/gateguard-scan.py:62-91` három irányban illeszt (fájl, szülő-könyvtár, glob) |
| hold-ban álló körök emiatt | `E99-R21`, `E08-R29` |
| brief-önfelhatalmazás kockázata | **226 / 254** brief listázza saját magát az `allowed_paths`-án, és a `docs/rounds/**` nincs a `PROTECTED_GLOBS`-ban |

## 3. Feladatok

### D1 — `.claude/gate-edit-policy` (KÖVETETT policy-fájl)

Új, **nem gitignore-olt** fájl; a létezése a user álló döntése, a törlése a
visszavonás. Első sora az indok. Tartalma szó szerint a
`.pipeline/HANDOFF-gate-autonomy-20260819.md` §2 D1 blokkja (hatókör: a három
együttes feltétel; ad-hoc módosítás továbbra is blokkolva; titok-útvonal soha).

### D2 — a hook harmadik, SZŰK escape-je

`_brief_authorization(path)` a meglévő `_escape_reason()` mellé, a blokkoló ág
ELŐTT meghívva. Feltételek — mind a három EGYÜTT:

1. `.claude/gate-edit-policy` létezik;
2. `STRUMSIGHT_ROUND_BRIEF` env be van állítva (implementer-körben vagyunk);
3. a cél a brief egyetlen ` ```ai-router ` blokkjának `allowed_paths` listáján
   **PONTOS egyezéssel** szerepel.

**NEM elfogadható gyengítés** (a review ezt méri):
- **prefix/könyvtár-illesztés** pontos egyezés helyett — egy briefbe írt `tool/`
  az egész `tool/ci/*`-ot feloldaná;
- a brief beolvasása a **munkafából**, ha az implementer felül tudja írni:
  a briefet **immutábilis forrásból** kell olvasni (`git show <BÁZIS-SHA>:<brief>`,
  ahol a bázis a kör indulási commitja). Ha ez technikailag nem elérhető,
  az eszköz a megoldás, nem a mérce lazítása: a driver exportáljon
  `STRUMSIGHT_ROUND_BASE_SHA`-t, és a hook azt használja. Munkafából olvasni
  csak akkor szabad, ha bizonyítottan nincs bázis-SHA, és ezt a stderr KIÍRJA;
- a `SECRET_GLOBS` ág elé kerülés — a titok-útvonalra **semmilyen** felhatalmazás
  nem érvényes, ez a sorrend nem cserélhető fel;
- több `ai-router` blokk esetén „az elsőt vesszük" — kettőnél több blokk
  **fail-closed** (nincs felhatalmazás).

Minden feloldás a **stderr-re** kerül az indokkal, hogy a kör átiratában látszódjon.

### D3 — a pre-flight ne tegye hold-ra a névszerint tervezett kört

`tools/gateguard-scan.py`: ha a policy-fájl létezik, a **pontos fájl-egyezés**
NEM ütközés (a szándék papíron van), de a **szülő-könyvtár és glob** találat
TOVÁBBRA IS fel nem oldható ütközés marad — a két réteg így nem tud szétcsúszni
a D2-vel. A `--all` jelentés írja ki, melyik találatot oldotta fel a policy.

### D4 — falszifikációs mérce

`tools/tests/test_gate_edit_policy.py` + a `tools/tests/test_gateguard_scan.py`
kiegészítése. A hook-tesztek a **valódi payloaddal** futtassák a hookot
(alfolyamat, stdin JSON), ne a belső függvényt utánozzák.

## 4. Mérce-mátrix

| eset | policy | brief-env | a cél a listán | elvárt |
|---|---|---|---|---|
| tervezett mércemódosítás | van | van | igen, pontosan | **enged** (exit 0) + stderr indok |
| ad-hoc mércemódosítás | van | van | nincs | **blokkol** (exit 2) |
| policy nélkül | nincs | van | igen | **blokkol** |
| brief-env nélkül (nem kör-session) | van | nincs | igen | **blokkol** |
| szülő-könyvtár a listán (`tool/`) | van | van | csak prefix | **blokkol** |
| titok-útvonal a listán (`.env`) | van | van | igen, pontosan | **blokkol** — a titok-ág erősebb |
| két `ai-router` blokk a briefben | van | van | igen | **blokkol** (fail-closed) |
| a brief a munkafában utólag módosítva | van | van | igen (csak a munkafában) | **blokkol** — a bázis-SHA-ból olvasott lista a mérvadó |
| pre-flight, pontos egyezés | van | — | igen | a scan **nem** tesz hold-ra |
| pre-flight, könyvtár-egyezés | van | — | csak prefix | a scan **hold**-ra tesz |

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `startswith`/prefix illesztés pontos egyezés helyett | „szülő-könyvtár a listán" |
| a titok-ág a felhatalmazási ág UTÁN fut | „titok-útvonal a listán" |
| a brief a munkafából olvasva | „a brief a munkafában utólag módosítva" |
| a policy-fájl létezését nem ellenőrzi | „policy nélkül" |
| `STRUMSIGHT_ROUND_BRIEF` hiányát nem ellenőrzi | „brief-env nélkül" |
| a scan a policy-t glob-találatra is alkalmazza | „pre-flight, könyvtár-egyezés" |
| több `ai-router` blokknál az elsőt veszi | „két `ai-router` blokk" |

**Valódi-sértés próba (kötelező, §10-ben dokumentálva):** a `.claude/gate-edit-policy`
ideiglenes átnevezése után a „tervezett mércemódosítás" cellának PIROSRA kell
váltania; visszaállítás után zöld.

## 5. Tilos zóna

- `tools/round-gate.sh`, `tool/ci/*`, `.github/workflows/*` — a mérce és a CI
  lépéslistája **változatlan** (ADR 0112 §3, ADR 0171 §4);
- `.ai/router.toml`, `tools/model-router.py`, `tools/scope-audit.py` — a router
  biztonsági rétege nem e kör tárgya;
- a `SECRET_GLOBS` bármilyen lazítása;
- `docs/adr/` — az ADR 0372-t Claude írja;
- a `.pipeline/` állapotfájljainak kézi szerkesztése;
- DSP/ML paraméter (AGENTS.md §9).

## 6. Definition of Done

1. D1–D4 kész, a §4 mátrix minden cellája zöld, a valódi-sértés próba
   dokumentálva a §10-ben.
2. `tools/round-gate.sh tools/tests` zöld (külön processzként futó lépések).
3. `security-reviewer` lefutott (risk=high) és APPROVED.
4. **A `.claude/gate-edit-authorized` bootstrap-marker TÖRÖLVE** a merge után
   (`ls .claude/gate-edit-authorized` → nincs ilyen fájl) — a bizonyítékot a
   §10 tartalmazza.
5. A `docs/execution/pipeline-queue.tsv` `E99-R21` és `E08-R29` sora
   `hold` → `pending` (KÜLÖN, ops-PR-ben, a merge UTÁN — a sor-fájl e kör
   `allowed_paths` listáján nincs rajta).

## 7. Gate

```bash
tools/round-gate.sh tools/tests
```

## 8. Kockázatok

- **A legnagyobb: túl tág escape.** Egy prefix-illesztés az egész `tool/ci/*`-ot
  feloldja. Ezt a §6.1 két cellája méri.
- **Brief-önfelhatalmazás.** 226/254 brief listázza magát; ha a hook a munkafából
  olvas, egy kör felveheti magának a mércét. Ezért kötelező a bázis-SHA.
- **A bootstrap-marker ottfelejtése.** A DoD 4. pontja gépi bizonyítékot kér.

## 10. Implementation handoff

(a Codex/Terra tölti)

## 11. Review

(a review linkje)
