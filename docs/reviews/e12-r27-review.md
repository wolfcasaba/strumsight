# E12-R27 review — Closed Beta launch és monitoring

- **Kör:** `E12-R27` · **Branch:** `sonnet-impl/e12-r27-closed-beta-launch-and-monitoring`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`) · **Reviewer:** Claude (orchestrátor, read-only)
- **Review-alap:** `6e2bba21..d5c0e7da` (6 fájl, +1211 sor, 0 törlés)
- **Dátum:** 2026-09-02
- **Verdikt (1. kör):** **CHANGES REQUESTED** — 1 MAJOR (mért fail-OPEN), 0 BLOCKER

## 1. Scope-audit

`python3 tools/scope-audit.py --repo … --brief docs/rounds/e12-r27-… --base 6e2bba21`
→ `Legacy scope audit OK (6e2bba21069a..d5c0e7da2189, 6 changed path(s), 0 generated/ignored)`,
exit 0. Mind a hat érintett fájl az `allowed_paths` listáján van; tiltott zóna
(`lib/**`, `.github/**`, `tools/**`, `docs/adr/**`, `docs/release/**`,
`docs/operations/**`, a `docs/beta/` meglévő fájljai) érintetlen.

## 2. Valódi-sértés próbák (izolált klón: `/tmp/review-e12-r27`)

A reviewer SAJÁT próbái, a szállított fán futtatva
(`flutter test test/tooling/beta_profile_test.dart`):

| # | Mutáció | Várt | Mért | Ítélet |
|---|---|---|---|---|
| 0 | nincs (baseline) | zöld | `All tests passed!` (16 cella), exit 0 | ✔ |
| 1 | egy **kipipált** (`- [x]`) ellenőrzőlista-sor NEM létező útvonalra hivatkozik | PIROS | **exit 0 — ZÖLD** | ✘ **MAJOR-1** |
| 2 | ugyanaz a sor **kipipálatlanul** (`- [ ]`) | PIROS | exit 1, A5 cella piros | ✔ (kontroll) |
| 3 | `communityMediaEnabled: false` → `true` a szállított profilban | PIROS | exit 1, **három** cella piros (A1 valódi fa, A3 szállított profil, A4 blokk-egyezés) | ✔ |
| 4 | `--registry /dev/null` (parse-olhatatlan katalógus) | nem-nulla, kimondott üzenet | `registry parse yielded 0 entries, expected >= 40`, exit 2 | ✔ (fail-closed) |

A 3. próba mellékesen azt is megmutatja, hogy az A4 dokumentum-blokk cellája
NEM dísz: a profil bármely változása azonnal elrontja a beágyazott
dry-run-kimenet bájtazonosságát.

## 3. Leletek

### MAJOR-1 — az A5 őr **fail-OPEN** a kipipált (`- [x]`) sorokra (L566 hibaosztály)

**Hol:** `test/tooling/beta_profile_test.dart:384`
(`_splitChecklistItems`, `RegExp(r'^- \[ \] (.*)$')`).

**Mérés (2. szakasz, 1. próba):** a `docs/beta/closed-beta-launch.md` 44.
sorát `- [x] … `docs/beta/NOPE-does-not-exist.md`` alakra írva a célzott gate
**zöld marad** (exit 0), miközben ugyanez a sor kipipálatlanul pirosra vált
(2. próba). A kipipált sor nem „rendben lévő" — a parszer számára **nem
létezik**, pontosan az a fail-OPEN minta, amit a kör saját §0.0.1 P2/P5
revíziója tilt („a fel nem ismert alakú sor → PIROS"), és amit
[L566](../LESSONS.md#l566) mért ki az E12-R19-en.

**Miért MAJOR és nem MINOR:** a dokumentum RENDELTETÉSE, hogy egy ember
indítás előtt kipipálja a sorait (`§5 Human launch field`). Az őr tehát
pontosan abban a pillanatban némul el, amikor a mérésre szükség lenne — a
lista attól a ponttól kezdve tetszőlegesen elsodródhat a fától, hivatkozás
nélküli vagy lógó hivatkozású sorokkal, és a gate ezt zölden hagyja.

**Javítás (a legkisebb elégséges):** a bullet-minta ismerje fel a kipipált
alakot is (`^- \[[ xX]\] (.*)$`), és legyen egy cella, amely ezt MÉRI: egy
kipipált, lógó hivatkozású sorra a `findChecklistReferenceProblems` nem-üres
listát ad. A `docs/beta/closed-beta-launch.md` tartalmán ehhez nem kell
változtatni.

### MINOR-1 — az A3 „szállított profil" cellája szigorúbb YAML-alakot feltételez, mint amit a PyYAML elfogad

**Hol:** `test/tooling/beta_profile_test.dart:128` —
`RegExp('^\\s*$flag:\\s*true\\s*\$', multiLine: true)`.

A `\s*` a kettőspont UTÁN áll, előtte viszont nem: az `accountEnabled : true`
(kettőspont előtti szóköz) érvényes YAML, de ez a regex nem fogná meg. A
lelet **nem** BLOCKER, mert a valódi mércét az A1 „exit 0 a valódi fán" cella
adja (az a tool-t futtatja, tehát a PyYAML-lel parse-olt igazságot méri) — a
regex-cella csak másodlagos, olcsó backstop. Javasolt javítás: a mintát a
kettőspont elé is engedékennyé tenni, VAGY a cella doc-kommentjében kimondani,
hogy ez backstop, és az elsődleges mérés az A1 tool-futás.

### NOTE-1 — az A6 tiltólista természeténél fogva részleges

`beta_profile_test.dart:297-306` fix részstring-lista. Egy parafrázis („we
have started inviting testers") átcsúszna rajta. Ez a megfogalmazás-őrök
inherens korlátja, nem hiba — a pozitív követelmény (`has not launched`,
`human decision` jelenléte) a lista erős fele. Nem kérek javítást.

### NOTE-2 — az A4 read-only cella a temp-könyvtárra mér

`beta_profile_test.dart:139-164` a temp-profil bájtazonosságát és a temp-dir
listáját ellenőrzi. Elvben a tool a repóba is írhatna; a forrás
(`verify_beta_profile.py`) átolvasva egyetlen írási művelet sincs benne
(`open(..., "w")`, `write_text`, `mkdir` nulla találat), tehát az állítás
igaz, csak a cella hatóköre szűkebb, mint a mondat. Nem kérek javítást.

## 4. Ami MÉRTEN rendben van

- **A1/A2** — a fail-closed registry-parse valódi: a csonkolt registry és a
  `/dev/null` egyaránt nem-nulla kilépés, kimondott üzenettel (4. próba). A
  `FeatureFlagDefinition(` előfordulás-szám ↔ sikeresen parse-olt hármasok
  egyenlősége (`verify_beta_profile.py:87`) a néma mezősorrend-drift ellen véd.
- **A3** — mind a 7 mért `high` flag (`accountEnabled`, `diagnosticsEnabled`,
  `aiTutorCloudEnabled`, `visionLabCaptureEnabled`, `communityEnabled`,
  `communityWritesEnabled`, `communityMediaEnabled`) `false` mindkét
  cohortban; a `true`-ra állítás pirosra vált (3. próba).
- **A4** — a dry-run alanya `labModeAvailable` a `closed_beta` cohortban, ami
  MÉRTEN `low` kockázatú ÉS bekapcsolt — a §0.0.1 P4 kikötése teljesül (egy
  `high` flag alapból `false`, azon a próba semmit nem bizonyítana). A
  beágyazott blokk bájtazonosságát a cella újrafuttatással méri.
- **A5** — a dokumentum 14 pontjának MINDEN hivatkozott repó-relatív útvonala
  létezik (reviewer-oldali `existsSync` ellenőrzés is: 8/8 külön mért fájl OK),
  és a markdown-linkek célpontjai is (`../rounds/e12-r19-…`,
  `../../tool/release/…`).
- **A6** — a dokumentum kimondja, hogy a béta NEM indult el, az emberi mező
  üres, és a `§4` őszintén felsorolja, mi NEM volt elvégezhető ezen a boxon.
- **Nem-duplikálás** — az ADR 0446 D7 adat-round-trip cellákat a kör NEM írja
  újra; a hivatkozott csoportnevek MÉRTEN léteznek
  (`rollback_policy_test.dart:86` „A3 — kill switch round-trip",
  `feature_flag_registry_test.dart:216` „A6 — a kill-switched (off)
  resolution never touches stored data").
- **Monitoring-illúzió** — a `closed-beta-launch.md` §2 és a
  `daily-triage-template.md` egyaránt KIMONDJA, hogy telemetria-gyűjtés MA
  nincs, és hogy a csendes nap nem bizonyíték.

## 5. Döntés

**CHANGES REQUESTED.** A MAJOR-1 (és opcionálisan a MINOR-1) javítása után a
kör merge-elhető. Javító kör: ugyanaz a motor (`sonnet-impl`), a fenti
leletlistával, ugyanazon a branchen.

---

## 6. Javító kör (fix1) — újra-ellenőrzés

- **Javító commit:** `a8d99e6b` — „A5 checklist guard recognizes checked
  lines, A3 regex tolerates space before colon". Két fájl
  (`test/tooling/beta_profile_test.dart`, a brief §10 handoffja),
  `scope_audit=ok` (2 changed path).
- **A dokumentum tartalma NEM változott** — a javítás az őrben van, ahogy a
  javító-prompt kérte.

### 6.1 MAJOR-1 — LEZÁRVA

`_splitChecklistItems` bullet-mintája `^- \[[ xX]\] (.*)$`, és két ÚJ cella
méri: kipipált + nem létező útvonal → jelzés; kipipált + létező útvonal →
nincs jelzés.

**Reviewer-oldali újra-mérés** (friss izolált klón, `/tmp/review2-e12-r27`,
HEAD `a8d99e6b`, `flutter test test/tooling/beta_profile_test.dart`):

| # | Mutáció | Várt | Mért | Ítélet |
|---|---|---|---|---|
| 0 | nincs (baseline) | zöld | `All tests passed!` (**18** cella), exit 0 | ✔ |
| 1 | ugyanaz a mutáció, ami az 1. körben ZÖLDEN átment: `- [x]` + nem létező útvonal | PIROS | **exit 1**, az A5 cella piros | ✔ (a fail-OPEN megszűnt) |
| 5 | `- [x]` + LÉTEZŐ útvonal (túllövés-próba) | zöld | exit 0, 18 cella | ✔ (a javítás nem lett túl szigorú) |

### 6.2 MINOR-1 — LEZÁRVA

`RegExp('^\\s*$flag\\s*:\\s*true\\s*\$')` — a kettőspont előtt is enged
szóközt, és a cella fölé került doc-komment kimondja, hogy ez másodlagos
backstop; az elsődleges mérés az A1 tool-futás.

### 6.3 Célzott gate (reviewer, izolált klón, `a8d99e6b`)

```
tools/round-gate.sh test/tooling/beta_profile_test.dart test/core/feature_flags/feature_flag_registry_test.dart
→ gate_exit=0
   format zöld · analyze zöld · test beta_profile_test.dart zöld ·
   test feature_flag_registry_test.dart zöld · architecture zöld ·
   secrets zöld · l10n zöld
```

## 7. VÉGSŐ DÖNTÉS: APPROVED

0 nyitott BLOCKER/MAJOR/MINOR. A két NOTE tudomásul véve, javítást nem
igényel. A kör merge-elhető, amint a teljes CI-kapu (Full Gate + Router CI) a
merge SHA-n zöld.
